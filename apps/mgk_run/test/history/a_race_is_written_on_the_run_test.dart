import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/history/data/drift_run_repository.dart';
import 'package:mgk_run/src/features/history/data/run_backup.dart';
import 'package:mgk_run/src/features/history/data/run_editor.dart';
import 'package:mgk_run/src/features/history/domain/run_draft.dart';
import 'package:mgk_run/src/features/recording/domain/run_race.dart';

class _Backup implements RunBackup {
  final List<String> pushed = <String>[];

  @override
  Future<bool> pushRun(String runId) async {
    pushed.add(runId);
    return true;
  }

  @override
  Future<void> pushTrace(String runId) async {}

  @override
  Future<int> backfill() async => 0;

  @override
  Future<void> deleteRun(String runId) async {}
}

/// The race is written on the run, read back off it, and backed up with it
/// (ADR-0049) — and nothing the phone measured is touched on the way.
void main() {
  late AppDatabase db;
  late RunEditor editor;
  late _Backup backup;
  final now = DateTime(2026, 10, 13, 12);
  const half = 21097.5;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    backup = _Backup();
    editor = RunEditor(
      db: db,
      backup: backup,
      now: () => now,
      newId: () => 'sunday',
    );
    await editor.add(
      RunDraft(
        startedAt: DateTime(2026, 10, 11, 9, 31),
        duration: const Duration(hours: 2, minutes: 0, seconds: 47),
        distanceMeters: 21685.8,
        type: kTypeOutdoor,
      ),
    );
    backup.pushed.clear();
  });

  tearDown(() => db.close());

  Future<RunRace?> read() async =>
      (await DriftRunRepository(db).runDetail('sunday'))?.race;

  test(
    'a race is stored with its official time and name, and pushed',
    () async {
      await editor.markRace(
        'sunday',
        const RunRace(
          distanceMeters: half,
          officialTime: Duration(hours: 2, minutes: 0, seconds: 30),
          name: '  Royal Parks Half ',
        ),
      );

      expect(
        await read(),
        const RunRace(
          distanceMeters: half,
          officialTime: Duration(hours: 2, minutes: 0, seconds: 30),
          name: 'Royal Parks Half',
        ),
      );
      expect(backup.pushed, <String>['sunday']);
    },
  );

  test('marking a race leaves the measured run alone', () async {
    await editor.markRace('sunday', const RunRace(distanceMeters: half));
    final row = (await db.runById('sunday'))!;

    expect(row.distanceM, 21685.8);
    expect(row.durationS, 7247);
  });

  test('clearing a race clears the time and name with it', () async {
    await editor.markRace(
      'sunday',
      const RunRace(
        distanceMeters: half,
        officialTime: Duration(hours: 2),
        name: 'Royal Parks Half',
      ),
    );
    await editor.markRace('sunday', null);
    final row = (await db.runById('sunday'))!;

    expect(await read(), isNull);
    expect(row.raceTimeS, isNull);
    expect(row.raceName, isNull);
  });

  test('a race no runner could have run is refused, not repaired', () async {
    expect(
      () => editor.markRace('sunday', const RunRace(distanceMeters: 0)),
      throwsArgumentError,
    );
    expect(
      () => editor.markRace(
        'sunday',
        const RunRace(distanceMeters: half, officialTime: Duration.zero),
      ),
      throwsArgumentError,
    );
    expect(
      () => editor.markRace(
        'sunday',
        RunRace(distanceMeters: half, name: 'x' * 81),
      ),
      throwsArgumentError,
    );
    expect(await read(), isNull);
  });

  test('a run that is not there is an error, not a new row', () async {
    expect(
      () => editor.markRace('nope', const RunRace(distanceMeters: half)),
      throwsStateError,
    );
  });

  test('correcting the run afterwards keeps the race', () async {
    await editor.markRace('sunday', const RunRace(distanceMeters: half));
    final draft = (await editor.draftOf('sunday'))!;
    await editor.edit('sunday', draft.copyWith(notes: 'Windy at the end'));

    expect((await read())?.distanceMeters, half);
  });
}
