import 'dart:async';

import 'package:drift/drift.dart' show Value;

import '../../../core/database/app_database.dart';
import '../../../core/ids.dart';
import '../../health/data/health_kit_run_metrics.dart';
import '../../health/domain/run_health_metrics.dart';
import '../../history/data/run_backup.dart';
import '../domain/best_effort.dart';
import '../domain/live_metrics.dart';
import '../domain/route_metrics.dart';
import '../domain/run_point.dart';
import '../domain/run_recorder.dart';
import 'location_source.dart';

/// The production [RunRecorder]: wires a [LocationSource] to the local database.
///
/// Contract (see docs/architecture/run-recording.md):
/// - every fix is **persisted before** it is emitted on [points], so a crash
///   mid-run never loses the run (the run row is created on [start], and
///   `endedAt` stays null until [stop] — that null is the recovery marker);
/// - fixes worse than [recordAccuracyMeters] never happened as far as the app
///   is concerned; fixes worse than [distanceAccuracyMeters] are recorded and
///   drawn but do not move the distance.
class RecordingRunRecorder implements RunRecorder {
  RecordingRunRecorder({
    required LocationSource source,
    required AppDatabase db,
    RunBackup? backup,
    RunHealthSource? health,
    String Function()? newId,
    DateTime Function()? now,
    double recordAccuracyMeters = kMaxRecordableAccuracyMeters,
    double distanceAccuracyMeters = kMaxHorizontalAccuracyMeters,
  }) : _source = source,
       _db = db,
       _runBackup = backup,
       _health = health ?? HealthKitRunMetrics(),
       _newId = newId ?? _defaultId,
       _now = now ?? DateTime.now,
       _recordAccuracyM = recordAccuracyMeters,
       _distanceAccuracyM = distanceAccuracyMeters;

  final LocationSource _source;
  final AppDatabase _db;

  /// Where a finished run is mirrored. Null keeps it local, which is what the
  /// preview harness and a dev persona want — invented runs must never reach
  /// the shared project.
  final RunBackup? _runBackup;

  /// What the phone noticed while the run was happening, which the GPS trace
  /// cannot answer — steps, today.
  ///
  /// **Not nullable, unlike the backup**, and the asymmetry is the point. A
  /// null backup means "this run must never leave the device", which a dev
  /// persona genuinely needs. There is no equivalent hazard in *reading*: the
  /// default implementation answers nothing on any platform without Health, so
  /// a test host and a preview get the same absence a runner who declined does,
  /// with no wiring required at the composition root to make that true.
  final RunHealthSource _health;
  final String Function() _newId;
  final DateTime Function() _now;

  /// Worse than this and the fix is discarded outright — see
  /// [kMaxRecordableAccuracyMeters] for why this is not the same number as
  /// [_distanceAccuracyM].
  final double _recordAccuracyM;

  /// Worse than this and the fix is kept and drawn, but does not move the
  /// distance. The number on screen stays trustworthy; the map stays alive.
  final double _distanceAccuracyM;

  /// Runs [push] only when there is a backup, and never lets it fail the
  /// caller: the run has already committed locally.
  ///
  /// The catch is deliberate and always was, but for a while it was the *only*
  /// thing that happened to a failed push, which is how a backup that had been
  /// broken for weeks could look exactly like one that was working. Finishing a
  /// run must not fail because a server was unreachable; it must also not be
  /// the last anybody hears of it. The reporting is done by the wrapper the
  /// backup is built with (`ReportedRunBackup` in `main.dart`) rather than
  /// here, so the recorder keeps knowing nothing about backups beyond this
  /// seam — and so the editor and the backfill get it too.
  Future<void> _backup(Future<void> Function(RunBackup) push) async {
    final backup = _runBackup;
    if (backup == null) return;
    try {
      await push(backup);
    } catch (_) {
      // Deliberate — a lost push is a run on the phone and not yet in the
      // backup, which the next push repairs. Recorded on the way past; see
      // above.
    }
  }

  /// Asks Health what it counted over the run's window and stores it, or does
  /// nothing at all.
  ///
  /// **Three ways to end with no steps written, and all three are correct.**
  /// The runner declined the Health read; the phone counted nothing because it
  /// spent the hour on a table; the store was slow enough to hit the deadline.
  /// iOS cannot tell them apart and neither can this — so none of them is an
  /// error, none of them is a zero, and none of them touches the column. A run
  /// with no steps stored shows no STEPS tile, which is the honest rendering of
  /// "not recorded" (CLAUDE.md rule 6).
  ///
  /// **Wall-clock window, not moving time.** A pause takes time off the run's
  /// clock but the runner is still standing on the road, and HealthKit indexes
  /// by the calendar. Asking `startedAt..endedAt` counts the steps taken during
  /// a coffee stop, which is a slight over-count and the honest direction to be
  /// wrong in — the alternative is stitching one query per unpaused segment,
  /// which costs a platform round trip per pause to correct a rounding error in
  /// a figure nobody trains off.
  ///
  /// Known and unfixable from here: iOS writes pedometer samples with a lag, so
  /// a run finished the instant the last step lands can be asked before the
  /// store has it. That under-counts slightly on the finish screen and is why
  /// this is a write that repeats safely rather than a one-shot — re-reading a
  /// run's steps later is a change this method's shape already allows.
  Future<void> _recordSteps({
    required String runId,
    required DateTime from,
    required DateTime to,
  }) async {
    final RunHealthMetrics metrics = await _health.forInterval(
      start: from,
      end: to,
    );
    final steps = metrics.steps;
    if (steps == null) return;
    await _db.recordRunSteps(runId: runId, steps: steps);
  }

  final StreamController<RunPoint> _points =
      StreamController<RunPoint>.broadcast();
  final StreamController<RecorderStatus> _statuses =
      StreamController<RecorderStatus>.broadcast();
  final StreamController<RecorderProblem?> _problems =
      StreamController<RecorderProblem?>.broadcast();

  RecorderStatus _status = RecorderStatus.idle;
  RecorderProblem? _problem;
  String? _runId;
  DateTime? _startedAt;
  int _seq = 0;

  /// The last fix that moved the distance. Cleared on pause so the first fix
  /// after resuming is an anchor rather than the far end of a long segment.
  RunPoint? _lastMeasured;
  RunPoint? _lastFix;

  /// When the newest fix arrived — see [RunRecorder.sinceLastFix].
  DateTime? _lastFixAt;
  double _distanceM = 0;

  /// Time not counted so far, and when the current not-counting began.
  Duration _pausedTotal = Duration.zero;
  DateTime? _notCountingSince;

  /// Set once the run is finished, so both clocks stop at the line rather than
  /// running on while the summary is open.
  DateTime? _endedAt;

  StreamSubscription<RunPoint>? _sub;

  @override
  Stream<RunPoint> get points => _points.stream;

  @override
  Stream<RecorderStatus> get statusChanges => _statuses.stream;

  @override
  RecorderStatus get status => _status;

  @override
  RecorderProblem? get problem => _problem;

  @override
  Stream<RecorderProblem?> get problems => _problems.stream;

  @override
  RunPoint? get lastFix => _lastFix;

  @override
  Duration? get sinceLastFix {
    final at = _lastFixAt;
    if (at == null) return null;
    final age = _now().difference(at);
    // A fix timestamped fractionally ahead of the clock is a rounding artefact,
    // not time travel; report it as fresh rather than negative.
    return age.isNegative ? Duration.zero : age;
  }

  /// Time on the run's clock: wall time since the start, minus anything the
  /// runner explicitly paused.
  ///
  /// **Only the runner stops this clock, and only by pressing Pause.** That is
  /// the whole rule, and both halves matter:
  ///
  ///  * A pause is a deliberate act. Someone who presses it means "this next
  ///    bit is not my run", and the clock owes them that.
  ///  * Merely stopping running is not a pause. Waiting at a crossing is part
  ///    of your 10k the way it is part of a race — the gun clock does not care
  ///    that you stopped. An autopause heuristic was built and removed for
  ///    exactly this: a guess that stops the clock is a guess quietly editing
  ///    somebody's time, and when it latched it also stopped the writing.
  ///
  /// Derived from the wall clock rather than accumulated from a ticker: iOS
  /// throttles and then suspends timers behind a locked screen, so a run with
  /// the screen locked came back having lost the minutes it was away.
  ///
  /// This is also exactly what [stop] stores, so the summary can never
  /// contradict the number the runner watched.
  @override
  Duration get elapsed {
    final started = _startedAt;
    if (started == null) return Duration.zero;
    // Frozen at the moment the clock stopped — a pause now, or the finish —
    // and otherwise running to now. Past pauses come off either way, so a
    // pause is never charged twice.
    final until = _notCountingSince ?? _endedAt ?? _now();
    final total = until.difference(started) - _pausedTotal;
    return total.isNegative ? Duration.zero : total;
  }

  /// Whether time and distance should currently be accruing.
  ///
  /// Deliberately reads nothing but lifecycle state. It briefly consulted an
  /// autopause heuristic, which is how a wrong guess froze the clock and
  /// stopped the run recording. Nothing but Pause gets that authority.
  bool get _counting => _status == RecorderStatus.recording && _runId != null;

  /// Folds every reason the run might not be counting into one clock.
  ///
  /// Called after anything that could change [_counting]. Idempotent, so it is
  /// safe to call on a transition that turns out not to be one.
  void _syncCounting() {
    if (_counting) {
      final since = _notCountingSince;
      if (since != null) {
        _pausedTotal += _now().difference(since);
        _notCountingSince = null;
      }
    } else {
      _notCountingSince ??= _now();
      // Drop the anchor, so whatever happens next starts a fresh segment
      // instead of measuring back to wherever the runner stopped.
      _lastMeasured = null;
    }
  }

  /// The id of the run currently being recorded, or null.
  String? get currentRunId => _runId;

  /// Distance in meters accumulated so far this run.
  double get distanceMeters => _distanceM;

  void _setStatus(RecorderStatus next) {
    _status = next;
    _statuses.add(next);
  }

  void _setProblem(RecorderProblem? next) {
    if (_problem == next) return;
    _problem = next;
    _problems.add(next);
  }

  RecorderProblem _problemFor(LocationUnavailable e) => switch (e.reason) {
    LocationUnavailableReason.servicesDisabled =>
      RecorderProblem.locationServicesOff,
    LocationUnavailableReason.permissionDenied =>
      RecorderProblem.permissionDenied,
    LocationUnavailableReason.permissionDeniedForever =>
      RecorderProblem.permissionDeniedForever,
    LocationUnavailableReason.reducedAccuracy =>
      RecorderProblem.reducedAccuracy,
    LocationUnavailableReason.failed => RecorderProblem.locationFailed,
  };

  @override
  Future<void> start() async {
    if (_status == RecorderStatus.recording) return;
    // Mid-run, not a fresh start. This is what the "Allow location" button
    // on a mid-run problem calls (`RecordingScreen._askAgain`): the runner
    // paused after a permission error and is retrying, not beginning a new
    // run. The guard used to check only for `recording`, so calling this
    // from `paused` — exactly the state that retry happens in — fell
    // through to the fresh-start path below: a new id, a new row, the clock
    // reset to zero, and a second subscription to the same broadcast fixes
    // stream, so every fix that arrived after landed twice.
    if (_status == RecorderStatus.paused && _runId != null) {
      await _restartSourceMidRun();
      return;
    }
    final id = _newId();
    final started = _now();
    _runId = id;
    _startedAt = started;
    _seq = 0;
    _lastMeasured = null;
    _lastFix = null;
    _lastFixAt = null;
    _distanceM = 0;
    _pausedTotal = Duration.zero;
    _notCountingSince = null;
    _endedAt = null;
    _setProblem(null);

    await _db.upsertRun(
      RunsCompanion.insert(
        id: id,
        startedAt: started,
        durationS: 0,
        distanceM: 0,
        source: 'gps',
        type: 'outdoor',
      ),
    );

    // Subscribe BEFORE starting the source. `fixes` is a broadcast stream, and
    // a broadcast stream drops whatever it emits with nobody listening — so
    // subscribing afterwards threw away every fix that arrived in the gap.
    // On a warm GPS that is the first second or two of the run.
    _sub = _source.fixes.listen(_onFix, onError: _onSourceError);
    _setStatus(RecorderStatus.recording);

    try {
      await _source.start();
    } on LocationUnavailable catch (e) {
      // Deliberately not rethrown: `start` is called from `initState`, so a
      // throw here has nobody to catch it and becomes an unhandled async error
      // — which is exactly how a refused permission used to turn into a screen
      // that pulsed "Recording" over zeroes forever. The problem is a value the
      // screen can render instead.
      await _abandonUnstartedRun();
      _setProblem(_problemFor(e));
      _setStatus(RecorderStatus.idle);
    }
  }

  /// Re-requests permission and restarts the location source on the run
  /// already in progress, instead of beginning a new one. See [start].
  ///
  /// No new id, no new row, no second subscription: [_sub] from the run's
  /// original [start] is still listening throughout a pause (nothing
  /// cancels it), so resuming needs only the source itself restarted and
  /// the status flipped back — the same two things [resume] does, with a
  /// platform call in between that can fail.
  Future<void> _restartSourceMidRun() async {
    _setProblem(null);
    _setStatus(RecorderStatus.recording);
    _syncCounting();
    try {
      await _source.start();
    } on LocationUnavailable catch (e) {
      // Refused again — back to paused, not idle: the run is still there,
      // only the retry failed.
      _setProblem(_problemFor(e));
      _setStatus(RecorderStatus.paused);
      _syncCounting();
    }
  }

  /// Removes the run row created for a run that never began.
  ///
  /// Without this a refused permission leaves a row with a null `endedAt`,
  /// which is the recovery marker — so the next launch would offer to resume a
  /// run that has no points and never happened.
  Future<void> _abandonUnstartedRun() async {
    final runId = _runId;
    await _sub?.cancel();
    _sub = null;
    if (runId != null) await _db.deleteRun(runId);
    _runId = null;
    _startedAt = null;
  }

  void _onSourceError(Object error, StackTrace stack) {
    if (error is LocationUnavailable) {
      _setProblem(_problemFor(error));
    } else {
      _setProblem(RecorderProblem.locationFailed);
    }
  }

  Future<void> _onFix(RunPoint fix) async {
    if (_status != RecorderStatus.recording) return; // ignore while paused
    if (fix.accuracyMeters > _recordAccuracyM) return; // unusable at any price
    final runId = _runId;
    if (runId == null) return;

    // A fix arriving is proof location is working, whatever went wrong before.
    _setProblem(null);
    _lastFix = fix;
    _lastFixAt = _now();

    // Nothing between here and the write below may decide not to persist. A
    // fix that reached this point is going on disk: that is rule 1, and the
    // whole of this class's reason to exist.

    final seq = _seq++;
    // Persist FIRST — an emitted point must already be on disk.
    await _db.addRunPoint(
      RunPointsCompanion.insert(
        runId: runId,
        seq: seq,
        lat: fix.latitude,
        lng: fix.longitude,
        accuracyM: fix.accuracyMeters,
        timestamp: fix.timestamp,
        altitudeM: Value(fix.altitudeMeters),
      ),
    );

    // Recorded and drawn either way; only good fixes move the number. This is
    // the whole point of the two gates — a 35 m fix still says where you are,
    // it just isn't precise enough to measure with.
    if (fix.accuracyMeters <= _distanceAccuracyM) {
      final prev = _lastMeasured;
      if (prev != null) {
        _distanceM += haversineMeters(
          prev.latitude,
          prev.longitude,
          fix.latitude,
          fix.longitude,
        );
      }
      _lastMeasured = fix;
    }

    _points.add(fix);
  }

  @override
  Future<void> pause() async {
    if (_status != RecorderStatus.recording) return;
    _setStatus(RecorderStatus.paused);
    // Drop the anchor. Without this the first fix after resuming measured all
    // the way back to wherever the runner stood when they paused, so a coffee
    // stop two streets away was silently added to the run.
    _syncCounting();
    await _persistPauseState();
  }

  @override
  Future<void> resume() async {
    if (_status != RecorderStatus.paused) return;
    _setStatus(RecorderStatus.recording);
    _syncCounting();
    await _persistPauseState();
  }

  /// Mirrors [_pausedTotal] and [_notCountingSince] onto the run row.
  ///
  /// Called from [pause] and [resume] rather than only at [stop]: a run
  /// recovered after the process died mid-run has no [stop] call to compute
  /// a duration from, so whatever the recovered duration excludes has to
  /// already be on disk (see `run_recovery.dart`). Both write the same two
  /// columns, so the run row always answers "how much of this run's wall
  /// time doesn't count" exactly as of the last pause boundary — which, for a
  /// run killed while paused, is precisely the moment it was killed at.
  Future<void> _persistPauseState() async {
    final runId = _runId;
    if (runId == null) return;
    await _db.updateRunPauseState(
      runId: runId,
      pausedTotalS: _pausedTotal.inSeconds,
      notCountingSince: _notCountingSince,
    );
  }

  /// The in-flight [stop] call, so a second one arriving before the first
  /// finishes waits on the same work instead of repeating it.
  ///
  /// Without this, a double tap on Finish read `_runId` as a run still in
  /// progress on its second call — nothing here ever cleared it — and ran
  /// the whole finalize sequence again: a second walk over the trace, a
  /// second write of the summary, the splits and the records, and a second
  /// backup push. The local writes are each individually idempotent, but
  /// the run's own life cycle is not something a second `stop()` should be
  /// allowed to repeat.
  Future<void>? _stopping;

  @override
  Future<void> stop() {
    final runId = _runId;
    if (runId == null) return _stopping ?? Future<void>.value();
    return _stopping ??= _finishRun(runId).whenComplete(() => _stopping = null);
  }

  /// How long the backup push gets, detached, before it is abandoned.
  ///
  /// Generous against a marathon's several-thousand-point trace sent in
  /// [SupabaseRunBackup]'s 500-point batches over an ordinary connection —
  /// this is a bound, not a target — but finite: this must not be the thing
  /// still running when the runner has moved on to another app.
  static const Duration _backupPushTimeout = Duration(seconds: 30);

  Future<void> _finishRun(String runId) async {
    await _sub?.cancel();
    _sub = null;
    await _source.stop();
    // Recompute the authoritative distance from the persisted trace with the
    // smoother, so the stored total matches what the screen displayed and isn't
    // inflated by jitter (the live [_distanceM] is a raw running estimate).
    final rows = await _db.pointsForRun(runId);
    final trace = <RunPoint>[for (final row in rows) _rowToPoint(row)];
    final distanceM = processedDistanceMeters(
      trace,
      maxAccuracyM: _distanceAccuracyM,
    );
    final ended = _now();
    _endedAt = ended;
    // The same number the screen showed. Storing anything else means the
    // summary disagrees with the run — which it did, in both directions,
    // within a day: first wall time against a moving-time display, then
    // moving time against a wall-clock one.
    final durationS = elapsed.inSeconds;
    final avgPace = distanceM > 0 ? durationS / (distanceM / 1000) : null;
    await _db.finalizeRun(
      runId: runId,
      endedAt: ended,
      durationS: durationS,
      distanceM: distanceM,
      avgPaceSPerKm: avgPace,
      // **Elevation goes down with the run**, from the same walk over the same
      // trace as the distance and the splits below — so the three can never
      // disagree about which fixes they were derived from.
      //
      // Climb had the splits' bug: computed on every fix for the in-run readout
      // and stored nowhere, so an hour of watching it tick up ended with a
      // summary that had no column to read it back from. The maximum is new
      // beside it because it answers a different question — hill repeats are
      // huge gain and an unremarkable high point, one long drag is the reverse.
      //
      // Both are null on a trace with no barometric altitude, which today is
      // every trace this app records: `GeolocatorLocationSource` supplies no
      // altitude at all and GPS altitude is deliberately never substituted (see
      // ADR-0024). That is absence, not failure, and it renders as an absent
      // tile — but it does mean these two stay empty until a barometer source
      // exists, and no amount of wiring on this side changes that.
      elevationGainM: climbMeters(trace),
      elevationMaxM: maxElevationMeters(trace),
    );
    // **The splits go down with the run**, from the same walk over the same
    // persisted trace the distance just came from.
    //
    // They were computed on every fix for the in-run readout and then dropped
    // on the floor: `run_splits` was written only by a restore, so the ten
    // splits a runner watched turn over disappeared the moment the screen did,
    // and the summary they were sent to could only ever show an empty list.
    // Points have always been persisted as they arrive (rule 1); this is the
    // derived half of the same run finally being kept.
    //
    // Written before the mirror, because `pushTrace` reads the splits back out
    // of the database — pushing first would mirror a run with none.
    await _db.replaceRunSplits(runId, <RunSplitsCompanion>[
      for (final split in splitsFor(trace))
        RunSplitsCompanion.insert(
          runId: runId,
          seq: split.index,
          distanceM: split.distanceMeters,
          durationS: split.duration.inSeconds,
        ),
    ]);
    // **The records go down with the run too, and for the same reason the
    // splits do: this is the only moment the trace is cheap to read.**
    //
    // A record is the fastest continuous stretch of 5 km, 10 km, a half or a
    // full *inside* this run — searched for over the trace, never read off the
    // summary. The 23 Aug run covered 10.18 km in 58:28 and its actual 10K was
    // about 57:25; reporting the whole run's time as a 10K best understates the
    // runner's own record by a minute and says nothing about doing so
    // (ADR-0026).
    //
    // Computed here rather than when Profile opens, which is the same argument
    // ADR-0023 makes about reads: the alternative is loading every point of
    // every run in the log on every visit to a tab, over a log that only grows.
    // Four numbers per run, written once, is the whole cost.
    //
    // Usually empty, and that is not a gap: most runs are shorter than 5 km.
    await _db.replaceRunBestEfforts(runId, <RunBestEffortsCompanion>[
      for (final effort in bestEffortsFor(trace))
        RunBestEffortsCompanion.insert(
          runId: runId,
          distanceM: effort.distanceMeters,
          durationS: effort.duration.inSeconds,
        ),
    ]);
    // **What the phone counted while the GPS was watching the road.**
    //
    // Last of the local writes and deliberately so: it is the only one that
    // depends on anything outside this app, and the run is already complete and
    // correct without it. A Health store that is slow, locked or refusing costs
    // a bounded pause on the Finish button and nothing else — every one of
    // those outcomes reaches [_recordSteps] as an absence rather than as a
    // throw, and none of them can delay the run being in the log.
    //
    // Before the mirror rather than after, so that the day the Postgres columns
    // exist the push carries the figure instead of a stale null. Today it does
    // not: `pushRun` enumerates its columns and `run.runs` has no `steps`, so
    // steps are local-only and a restore onto a new phone will not bring them
    // back. That is a `db/` change and out of this lane; see ADR-0024.
    //
    // `_startedAt` is non-null wherever `_runId` is — they are set and cleared
    // together — so the fallback is unreachable, and it collapses the window to
    // nothing rather than inventing one if that ever stops being true.
    await _recordSteps(runId: runId, from: _startedAt ?? ended, to: ended);
    // The run is safe on the phone at this point, and that is now the whole of
    // what "safe" requires (rule 1): the log is read from Drift, so the run is
    // in it the moment the line above returns. Mirroring is a mirror.
    //
    // Cleared here rather than left set: a `stop()` arriving after this one
    // resolves must see no run in progress, the same as it would after
    // `discard()`. `_startedAt` stays — [elapsed] still reads it, and the
    // summary screen keeps asking this object's `elapsed` until it is
    // itself torn down.
    _runId = null;
    _setStatus(RecorderStatus.stopped);
    // Detached rather than awaited, and this is the change that matters.
    // It used to be more than a mirror — the log was read from Supabase, so
    // this push was what made a run appear at all, and awaiting it here is
    // a leftover from that (ADR-0023 covers the read side; this is the
    // write side of the same history). Today the run is already complete
    // and in the log two lines up, so the only thing waiting on this push
    // bought was the Finish button staying busy for as long as a
    // several-thousand-point trace took to upload — long enough, on a
    // marathon over a slow signal, that a runner who tapped twice believing
    // nothing had happened yet was not wrong to think so.
    unawaited(_pushBackup(runId));
  }

  /// Mirrors the finished run, bounded by [_backupPushTimeout] and never
  /// awaited by [stop] — see [_finishRun].
  Future<void> _pushBackup(String runId) async {
    try {
      await _backup((backup) async {
        await backup.pushRun(runId);
        await backup.pushTrace(runId);
      }).timeout(_backupPushTimeout);
    } catch (_) {
      // Silently, on purpose, for the same reason [_backup]'s own catch is:
      // a lost or slow push is a run on the phone and not yet in the
      // backup, which the next push repairs. This layer adds only the
      // timeout; it must not become a second way to fail loudly, and it
      // must never log what it failed to send (CLAUDE.md rule 6).
    }
  }

  @override
  Future<void> discard() async {
    final runId = _runId;
    await _sub?.cancel();
    _sub = null;
    await _source.stop();
    if (runId != null) {
      await _db.deleteRun(runId);
      // A discarded run must not survive in the backup, or the next read of
      // the log would bring it back.
      await _backup((backup) => backup.deleteRun(runId));
    }
    _runId = null;
    _setStatus(RecorderStatus.stopped);
  }

  RunPoint _rowToPoint(RunPointRow row) => RunPoint(
    latitude: row.lat,
    longitude: row.lng,
    accuracyMeters: row.accuracyM,
    altitudeMeters: row.altitudeM,
    timestamp: row.timestamp,
  );
}

/// A recorded run's identity. Not the clock — see [newLocalId].
///
/// Starting two runs inside one microsecond is not a thing a person does, so
/// this generator was the safer of the two that shared the bug. It is fixed
/// anyway: "the caller happens not to race" is a property of today's callers,
/// and the recorder already writes from a stream.
String _defaultId() => newLocalId();
