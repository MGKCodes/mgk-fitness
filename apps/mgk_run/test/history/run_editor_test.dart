import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/history/data/run_backup.dart';
import 'package:mgk_run/src/features/history/data/run_editor.dart';
import 'package:mgk_run/src/features/history/domain/run_draft.dart';
import 'package:mgk_run/src/features/history/domain/run_writer.dart';

/// A backup that records what it was asked to remove, and can be unreachable.
class _Backup implements RunBackup {
  _Backup({this.dead = false});

  final bool dead;
  final List<String> deleted = <String>[];

  @override
  Future<void> deleteRun(String runId) async {
    if (dead) throw Exception('no network');
    deleted.add(runId);
  }

  @override
  Future<bool> pushRun(String runId) async => true;

  @override
  Future<void> pushTrace(String runId) async {}

  @override
  Future<int> backfill() async => 0;
}

/// Against a real in-memory database, because the guarantee worth testing is
/// what survives in the rows — particularly the one about the trace.
void main() {
  late AppDatabase db;
  late RunEditor editor;
  var seq = 0;

  final now = DateTime(2026, 7, 28, 12);
  final ranAt = now.subtract(const Duration(hours: 3));

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    seq = 0;
    editor = RunEditor(db: db, now: () => now, newId: () => 'run-${++seq}');
  });

  tearDown(() => db.close());

  RunDraft draft({
    Duration duration = const Duration(minutes: 26),
    double distance = 5000,
    String type = kTypeTreadmill,
    String? notes,
    int? rpe,
  }) => RunDraft(
    startedAt: ranAt,
    duration: duration,
    distanceMeters: distance,
    type: type,
    notes: notes,
    rpe: rpe,
  );

  /// A recorded run with a trace, standing in for something the device saw.
  Future<String> aRecordedRun() async {
    await db.upsertRun(
      RunsCompanion.insert(
        id: 'gps-1',
        startedAt: ranAt,
        durationS: 1800,
        distanceM: 6000,
        source: kSourceGps,
        type: kTypeOutdoor,
      ),
    );
    await db.addRunPoint(
      RunPointsCompanion.insert(
        runId: 'gps-1',
        seq: 0,
        lat: 51.5,
        lng: -0.12,
        accuracyM: 5,
        timestamp: ranAt,
      ),
    );
    return 'gps-1';
  }

  // ---- adding --------------------------------------------------------------

  test('a treadmill run is written with its pace derived', () async {
    final id = await editor.add(draft());
    final row = await db.runById(id);

    expect(row, isNotNull);
    expect(row!.distanceM, 5000);
    expect(row.durationS, 26 * 60);
    expect(row.type, kTypeTreadmill);
    // Provenance, not a guess: this run was typed, and says so for ever.
    expect(row.source, kSourceManual);
    expect(row.avgPaceSPerKm, closeTo(312, 0.5));
    // Ended is derived rather than asked for — one less field to get wrong.
    expect(row.endedAt, ranAt.add(const Duration(minutes: 26)));
  });

  test('an invalid draft is refused rather than repaired', () async {
    // Silently fixing it would make the confirmation the runner tapped a
    // description of something other than what got written.
    expect(
      () => editor.add(draft(distance: 0)),
      throwsA(isA<RunDraftInvalid>()),
    );
    expect(await db.allRuns(), isEmpty);
  });

  test('the refusal carries the fields, so a form can point at them', () async {
    try {
      await editor.add(const RunDraft());
      fail('should have thrown');
    } on RunDraftInvalid catch (e) {
      expect(
        e.issues.map((i) => i.field),
        containsAll(<String>['started_at', 'distance', 'duration']),
      );
    }
  });

  // ---- editing -------------------------------------------------------------

  test('editing a run rewrites its numbers and its pace together', () async {
    final id = await editor.add(draft());
    await editor.edit(
      id,
      draft(distance: 10000, duration: const Duration(minutes: 50)),
    );

    final row = await db.runById(id);
    expect(row!.distanceM, 10000);
    expect(row.durationS, 50 * 60);
    // Recomputed, not left stale — a run and its pace cannot disagree.
    expect(row.avgPaceSPerKm, closeTo(300, 0.5));
  });

  test('editing a recorded run leaves the trace alone', () async {
    // The load-bearing one. "A tracked run is a tracked run": the summary is
    // the runner's account, the trace is the evidence, and correcting the first
    // must never quietly rewrite the second.
    final id = await aRecordedRun();
    final before = await db.pointsForRun(id);
    expect(before, hasLength(1));

    await editor.edit(id, draft(distance: 6500));

    final after = await db.pointsForRun(id);
    expect(after, hasLength(1));
    expect(after.single.lat, before.single.lat);
    expect(after.single.lng, before.single.lng);

    final row = await db.runById(id);
    expect(row!.distanceM, 6500);
    // Provenance survives the edit: this is still a run the device recorded.
    expect(row.source, kSourceGps);
  });

  test('editing cannot invent a run that was never there', () async {
    // A typo in an id would otherwise become a duplicate entry in the log.
    expect(
      () => editor.edit('no-such-run', draft()),
      throwsA(isA<StateError>()),
    );
    expect(await db.allRuns(), isEmpty);
  });

  test('an invalid edit leaves the stored run untouched', () async {
    final id = await editor.add(draft());
    expect(
      () => editor.edit(id, draft(duration: const Duration(minutes: 1))),
      throwsA(isA<RunDraftInvalid>()),
    );
    final row = await db.runById(id);
    expect(row!.durationS, 26 * 60, reason: 'the original must survive');
  });

  // ---- round trip ----------------------------------------------------------

  test('a stored run reads back as the draft that wrote it', () async {
    // What a form or a coach confirmation opens with, so an edit starts from
    // what is actually there rather than from blank fields.
    final id = await editor.add(
      draft(notes: 'legs heavy', rpe: 7, type: kTypeTreadmill),
    );
    final back = await editor.draftOf(id);

    expect(back, isNotNull);
    expect(back!.distanceMeters, 5000);
    expect(back.duration, const Duration(minutes: 26));
    expect(back.notes, 'legs heavy');
    expect(back.rpe, 7);
    expect(back.type, kTypeTreadmill);
    expect(back.isValid(now), isTrue);
  });

  test('draftOf a run that does not exist is null, not an error', () async {
    expect(await editor.draftOf('nope'), isNull);
  });

  // ---- delete --------------------------------------------------------------

  // There was no way to remove a run. The log is restored from the backup
  // every time the app opens, so the order here is the whole design: a run
  // removed only from the phone would be back the next morning.
  group('deleting a run', () {
    RunEditor withBackup(RunBackup backup) => RunEditor(
      db: db,
      backup: backup,
      now: () => now,
      newId: () => 'run-${++seq}',
    );

    test('removes it from the backup and from the phone', () async {
      final backup = _Backup();
      final e = withBackup(backup);
      final id = await e.add(draft());

      await e.delete(id);

      expect(backup.deleted, <String>[id]);
      expect(await db.runById(id), isNull);
    });

    test('removes nothing when the backup cannot be reached', () async {
      final e = withBackup(_Backup(dead: true));
      final id = await e.add(draft());

      await expectLater(e.delete(id), throwsA(isA<RunDeleteFailed>()));

      expect(
        await db.runById(id),
        isNotNull,
        reason: 'gone from the phone only, it would come back on restore',
      );
    });

    test('needs no backup at all on a phone that has none', () async {
      final id = await editor.add(draft());
      await editor.delete(id);
      expect(await db.allRuns(), isEmpty);
    });

    test('leaves every other run alone', () async {
      final keep = await editor.add(draft());
      final gone = await editor.add(draft(distance: 8000));

      await editor.delete(gone);

      expect((await db.allRuns()).map((r) => r.id), <String>[keep]);
    });
  });
}
