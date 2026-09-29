import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/onboarding/data/file_intro_store.dart';
import 'package:mgk_run/src/features/settings/data/file_backup_consent.dart';
import 'package:mgk_run/src/features/settings/data/file_backup_health.dart';
import 'package:mgk_run/src/features/settings/data/file_profile_photo.dart';
import 'package:mgk_run/src/features/settings/data/phone_runner_data.dart';
import 'package:mgk_run/src/features/settings/domain/backup_consent.dart';
import 'package:mgk_run/src/features/settings/domain/backup_health.dart';

/// **Erasing the phone has to reach everything a runner left on it.**
///
/// Handing a phone to another account, signing out with "also remove my data",
/// and deleting the account all end here -- and anything this misses is one
/// runner's data greeting the next. So every store is filled first and checked
/// after, and the database is checked table by table: the eraser clears every
/// table it has rather than a list, and this is what proves the list would not
/// have been shorter.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late AppDatabase db;
  late FileProfilePhoto photo;
  late FileIntroStore intro;
  late FileBackupConsent consent;
  late FileBackupHealth health;
  late PhoneRunnerData phone;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('phone');
    db = AppDatabase(NativeDatabase.memory());
    photo = FileProfilePhoto(directory: dir);
    intro = FileIntroStore(directory: () async => dir);
    consent = FileBackupConsent(
      directory: () async => dir,
      signedInUserId: () => 'alex',
    );
    health = FileBackupHealth(directory: () async => dir);
    phone = PhoneRunnerData(
      db: db,
      photo: photo,
      intro: intro,
      consent: consent,
      backupHealth: health,
    );
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<int> rowsIn(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
          .read<int>('n');

  /// One of everything a runner leaves on the phone.
  Future<void> fill() async {
    final at = DateTime.utc(2026, 9, 1, 7);
    await db.restoreRuns(<RunsCompanion>[
      RunsCompanion.insert(
        id: 'run-1',
        startedAt: at,
        durationS: 1800,
        distanceM: 5000,
        source: 'gps',
        type: 'outdoor',
      ),
    ]);
    await db.restoreRunPoints(<RunPointsCompanion>[
      RunPointsCompanion.insert(
        runId: 'run-1',
        seq: 0,
        lat: 51.5,
        lng: -0.12,
        accuracyM: 5,
        timestamp: at,
      ),
    ]);
    await db.restoreRunSplits(<RunSplitsCompanion>[
      RunSplitsCompanion.insert(
        runId: 'run-1',
        seq: 0,
        distanceM: 1000,
        durationS: 360,
      ),
    ]);
    await db.replaceRunBestEfforts('run-1', <RunBestEffortsCompanion>[
      RunBestEffortsCompanion.insert(
        runId: 'run-1',
        distanceM: 5000,
        durationS: 1800,
      ),
    ]);
    await db.restorePlan(
      plan: PlansCompanion.insert(
        id: 'plan-1',
        startDate: at,
        weeks: 8,
        currentWeeklyM: 20000,
        longestRecentM: 10000,
        daysPerWeek: 3,
        availableWeekdays: '2,4,7',
      ),
      weeks: <PlanWeeksCompanion>[
        PlanWeeksCompanion.insert(
          planId: 'plan-1',
          weekNumber: 1,
          phase: 'base',
          targetVolumeM: 20000,
          longRunM: 8000,
        ),
      ],
      sessions: <PlanSessionsCompanion>[
        PlanSessionsCompanion.insert(
          planId: 'plan-1',
          weekNumber: 1,
          weekday: 2,
          scheduledDate: at,
          kind: 'easy',
        ),
      ],
    );
    await db.restoreCoachMemory(
      conversations: <CoachConversationsCompanion>[
        CoachConversationsCompanion.insert(id: 'convo-1'),
      ],
      turns: <CoachTurnsCompanion>[
        CoachTurnsCompanion.insert(
          conversationId: 'convo-1',
          seq: 0,
          role: 'user',
          body: 'My left calf has been tight since the half.',
        ),
      ],
    );
    await db.restoreCoachSummary(
      CoachSummariesCompanion.insert(summary: 'Tight left calf.'),
    );

    final source = File('${dir.path}${Platform.pathSeparator}picked.jpg');
    await source.writeAsBytes(<int>[0xFF, 0xD8, 0xFF]);
    await photo.write(source);
    await intro.markDone(name: 'Alex');
    await consent.write(BackupConsent.granted);
    await health.write(BackupHealth(lastSucceededAt: at));
  }

  test('every table, the photo, the name and the backup answer go', () async {
    await fill();

    // Filled, table by table -- so an empty table afterwards is the erase and
    // not the fixture.
    for (final table in db.allTables) {
      expect(
        await rowsIn(table.actualTableName),
        1,
        reason: table.actualTableName,
      );
    }
    expect(await phone.isEmpty(), isFalse);

    await phone.eraseAll();

    for (final table in db.allTables) {
      expect(
        await rowsIn(table.actualTableName),
        0,
        reason: '${table.actualTableName} kept a runner\'s rows',
      );
    }
    expect(await photo.read(), isNull);
    expect(await intro.readName(), isNull);
    expect(await consent.read(), BackupConsent.unknown);
    final after = await health.read();
    expect(after.lastSucceededAt, isNull);
    expect(after.lastFailedAt, isNull);
    expect(await phone.isEmpty(), isTrue);
  });

  test('what describes the install rather than the runner stays', () async {
    await fill();
    await phone.eraseAll();

    // The intro marker records that this install asked for its permissions,
    // which the OS still remembers; erasing it would replay a conversation
    // about permissions already granted.
    expect(await intro.isDone(), isTrue);
  });

  group('the phone counts as holding something', () {
    test('with only a run on it', () async {
      await db.restoreRuns(<RunsCompanion>[
        RunsCompanion.insert(
          id: 'run-1',
          startedAt: DateTime.utc(2026, 9, 1),
          durationS: 60,
          distanceM: 100,
          source: 'manual',
          type: 'outdoor',
        ),
      ]);
      expect(await phone.isEmpty(), isFalse);
    });

    test('with only a name on it', () async {
      await intro.markDone(name: 'Alex');
      expect(await phone.isEmpty(), isFalse);
    });

    test('with only a photo on it', () async {
      final source = File('${dir.path}${Platform.pathSeparator}picked.jpg');
      await source.writeAsBytes(<int>[1, 2, 3]);
      await photo.write(source);
      expect(await phone.isEmpty(), isFalse);
    });

    test('and not with nothing', () async {
      expect(await phone.isEmpty(), isTrue);
    });
  });
}
