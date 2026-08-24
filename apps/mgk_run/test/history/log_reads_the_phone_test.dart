import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/history/data/consented_run_backup.dart';
import 'package:mgk_run/src/features/history/data/drift_run_repository.dart';
import 'package:mgk_run/src/features/history/data/reported_run_backup.dart';
import 'package:mgk_run/src/features/history/data/run_backup.dart';
import 'package:mgk_run/src/features/history/data/run_editor.dart';
import 'package:mgk_run/src/features/history/domain/run_draft.dart';
import 'package:mgk_run/src/features/recording/data/location_source.dart';
import 'package:mgk_run/src/features/recording/data/recording_run_recorder.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';
import 'package:mgk_run/src/features/settings/domain/backup_consent.dart';
import 'package:mgk_run/src/features/settings/domain/backup_health.dart';

class _FakeLocationSource implements LocationSource {
  final StreamController<RunPoint> _controller =
      StreamController<RunPoint>.broadcast();

  @override
  Stream<RunPoint> get fixes => _controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  void emit(RunPoint point) => _controller.add(point);

  Future<void> dispose() => _controller.close();
}

/// A backup with no network behind it. Every push throws, the way one does on
/// a phone at the far end of a trail run.
class _OfflineBackup implements RunBackup {
  int attempts = 0;

  Never _offline() {
    attempts++;
    throw const SocketException('Network is unreachable');
  }

  @override
  Future<bool> pushRun(String runId) async => _offline();

  @override
  Future<void> pushTrace(String runId) async => _offline();

  @override
  Future<void> deleteRun(String runId) async => _offline();

  @override
  Future<int> backfill() async => _offline();
}

RunPoint _fix(double lng, DateTime at) =>
    RunPoint(latitude: 0, longitude: lng, accuracyMeters: 5, timestamp: at);

/// **The test that the field had to supply, because nothing here did.**
///
/// A 10 km run was recorded on 23 August 2026, displayed for an hour, and then
/// vanished: the log said "No runs yet" the next morning while the run sat
/// complete and correct in the on-device database. It vanished because History
/// was read from Supabase, so a run existed as far as the app was concerned
/// only if it had been successfully mirrored — and mirroring is consented
/// (ADR-0012) and best-effort (`catch (_)`), which gave three independent ways
/// for a recorded run to become invisible with nobody told. ADR-0023 reverses
/// that; this is what would have caught it first.
///
/// Every test here runs the write path **with the backup disabled and the
/// network down**, which is the combination the old read path could not survive
/// and the new one must not notice. Nothing is stubbed between the recorder and
/// the log: a real Drift database, the real recorder, the real consent gate,
/// and a backup that fails the way a backup on a hillside fails.
void main() {
  late AppDatabase db;
  late _FakeLocationSource source;
  late _OfflineBackup offline;
  late InMemoryBackupConsent consent;
  late InMemoryBackupHealth health;
  late DateTime clock;

  /// The production wiring from `main.dart`: the reporter inside the consent
  /// gate, so a push consent refused is never reported as a failure.
  RunBackup backup() => ConsentedRunBackup(
    inner: ReportedRunBackup(inner: offline, health: health, now: () => clock),
    consent: consent,
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    source = _FakeLocationSource();
    offline = _OfflineBackup();
    consent = InMemoryBackupConsent(BackupConsent.declined);
    health = InMemoryBackupHealth();
    clock = DateTime(2026, 8, 23, 9);
  });

  tearDown(() async {
    await source.dispose();
    await db.close();
  });

  /// Records a short run end to end, exactly as the recording screen does.
  Future<void> recordARun() async {
    final recorder = RecordingRunRecorder(
      source: source,
      db: db,
      backup: backup(),
      newId: () => 'run-23-aug',
      now: () => clock,
    );
    final start = clock;
    await recorder.start();
    source.emit(_fix(0, start));
    source.emit(_fix(0.001, start.add(const Duration(seconds: 30))));
    source.emit(_fix(0.002, start.add(const Duration(seconds: 60))));
    await pumpEventQueue();
    clock = clock.add(const Duration(minutes: 1));
    await recorder.stop();
  }

  test('a recorded run is in the log with backup off and no signal', () async {
    // The 23 August run, reproduced. Both of the conditions that hid it are in
    // force: the runner has declined backup, and there is no network behind the
    // mirror anyway.
    await recordARun();

    final log = await DriftRunRepository(db).fetchRuns();

    expect(log, hasLength(1));
    expect(log.single.id, 'run-23-aug');
    expect(log.single.distanceMeters, greaterThan(150));
    expect(log.single.duration, const Duration(minutes: 1));
  });

  test('and nothing was sent anywhere to make that true', () async {
    // The point of the fix, rather than a side effect of it: the log is not
    // showing the run because a push happened to succeed. Nothing was pushed.
    await recordARun();

    expect(offline.attempts, 0, reason: 'consent was declined');
    expect(await DriftRunRepository(db).fetchRuns(), hasLength(1));
  });

  test('a declined backup is not reported as a failed one', () async {
    // The switch is doing what it was asked. Reporting that as a failure would
    // put a warning in Settings for a runner whose only crime was saying no.
    await recordARun();

    final record = await health.read();
    expect(record.isFailing, isFalse);
    expect(record.lastFailedAt, isNull);
    expect(record.lastSucceededAt, isNull);
  });

  test(
    'a run recorded with consent on but no signal is still in the log',
    () async {
      // The other half of the old bug, and the half a runner could not have
      // avoided by changing a setting. The push fails; the run is still theirs.
      consent = InMemoryBackupConsent(BackupConsent.granted);

      await recordARun();

      expect(offline.attempts, greaterThan(0));
      expect(await DriftRunRepository(db).fetchRuns(), hasLength(1));
    },
  );

  test('but the failed push is written down rather than swallowed', () async {
    // `catch (_) {}` in the recorder is deliberate — finishing a run must not
    // fail because a server was unreachable — and for a while it was the only
    // thing that happened to a failed push. A backup that has been broken for
    // a month must not look identical to one that is working.
    consent = InMemoryBackupConsent(BackupConsent.granted);

    await recordARun();

    final record = await health.read();
    expect(record.isFailing, isTrue);
    expect(record.lastFailedAt, isNotNull);
  });

  test('a hand-entered run lands in the log the same way', () async {
    // The second witness from the field test: a run logged through the chat a
    // week earlier was missing too, and it went in through RunEditor rather
    // than the recorder. One read path, so one fix.
    final editor = RunEditor(
      db: db,
      backup: backup(),
      now: () => clock,
      newId: () => 'manual-1',
    );

    await editor.add(
      RunDraft(
        startedAt: clock.subtract(const Duration(days: 7)),
        duration: const Duration(minutes: 26),
        distanceMeters: 5000,
        type: kTypeTreadmill,
      ),
    );

    final log = await DriftRunRepository(db).fetchRuns();
    expect(log.single.id, 'manual-1');
    expect(log.single.distanceMeters, 5000);
  });

  test('a run still being recorded is not in the log yet', () async {
    // A null `endedAt` is the recorder's marker for a run in progress, and the
    // row carries a zero distance until `stop()` writes the real one. Supabase
    // never showed these because nothing pushed a run until it finished;
    // reading locally, the log has to exclude them itself or a runner mid-run
    // sees a 0.00 km run sitting at the top of their own history.
    final recorder = RecordingRunRecorder(
      source: source,
      db: db,
      backup: backup(),
      newId: () => 'in-progress',
      now: () => clock,
    );
    await recorder.start();
    source.emit(_fix(0, clock));
    await pumpEventQueue();

    expect(await db.runById('in-progress'), isNotNull);
    expect(await DriftRunRepository(db).fetchRuns(), isEmpty);
  });

  test('the log is newest first', () async {
    for (final days in <int>[1, 9, 4]) {
      // An id per run rather than the editor's default, which is built from
      // the wall clock: three writes inside one of Windows' millisecond ticks
      // share a microsecond, and the upsert quietly folds them into one row.
      final editor = RunEditor(
        db: db,
        backup: null,
        now: () => clock,
        newId: () => 'manual-$days',
      );
      await editor.add(
        RunDraft(
          startedAt: clock.subtract(Duration(days: days)),
          duration: const Duration(minutes: 30),
          distanceMeters: 6000,
          type: kTypeTreadmill,
        ),
      );
    }

    final log = await DriftRunRepository(db).fetchRuns();
    expect(log.map((r) => clock.difference(r.startedAt).inDays), <int>[
      1,
      4,
      9,
    ]);
  });
}
