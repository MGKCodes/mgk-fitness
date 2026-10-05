import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_auth/mgk_auth.dart';
import 'package:mgk_lift/src/core/database/app_database.dart';
import 'package:mgk_lift/src/features/auth/data/fake_auth.dart';
import 'package:mgk_lift/src/features/auth/data/phone_training_data.dart';
import 'package:mgk_lift/src/features/auth/domain/account.dart';
import 'package:mgk_lift/src/features/home/presentation/lift_shell.dart';
import 'package:mgk_lift/src/features/legal/data/account_deletion_service.dart';
import 'package:mgk_lift/src/features/sync/domain/sync_status.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// Counts the runs, so a test can say backup did not move.
class _CountingBackup implements BackupService {
  int runs = 0;

  @override
  Future<SyncPending> pending() async =>
      const SyncPending(workouts: 0, lastSyncedAt: null);

  @override
  Future<SyncReport> run() async {
    runs++;
    return const SyncReport(outcome: SyncOutcome.upToDate);
  }
}

/// Training that is there until it is erased.
class _Training implements LocalTrainingData {
  _Training({this.empty = false});

  bool empty;
  int erasures = 0;

  @override
  Future<bool> isEmpty() async => empty;

  @override
  Future<void> eraseAll() async {
    erasures++;
    empty = true;
  }
}

void main() {
  group('the shell, when somebody signs in', () {
    late FakeAuth auth;
    late _CountingBackup backup;
    late _Training training;
    late InMemoryLocalDataOwner owner;

    Future<void> pumpShell(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: LiftShell(
            auth: auth,
            sync: backup,
            localData: LocalDataGuard(owner: owner, data: training),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    setUp(() {
      auth = FakeAuth();
      backup = _CountingBackup();
      training = _Training();
      owner = InMemoryLocalDataOwner('first-lifter');
    });
    tearDown(() => auth.dispose());

    testWidgets('as another account, is asked before anything backs up', (
      tester,
    ) async {
      await pumpShell(tester);
      final before = backup.runs;

      auth.arrive('second@example.com');
      await tester.pumpAndSettle();

      expect(find.byType(AnotherAccountScreen), findsOneWidget);
      expect(find.textContaining('second@example.com'), findsWidgets);
      expect(
        find.textContaining('The sessions, workouts and photos'),
        findsOneWidget,
      );
      // The leak itself: nothing pushed into the new account, nothing of
      // theirs pulled down beside the first lifter's.
      expect(backup.runs, before);
      expect(training.erasures, 0);
    });

    testWidgets('erasing hands the phone over, then backs up', (tester) async {
      await pumpShell(tester);
      auth.arrive('second@example.com');
      await tester.pumpAndSettle();
      final before = backup.runs;

      await tester.tap(find.byType(DestructiveButton));
      await tester.pumpAndSettle();

      expect(find.byType(AnotherAccountScreen), findsNothing);
      expect(training.erasures, 1);
      expect(await owner.read(), 'fake-user');
      expect(backup.runs, greaterThan(before));
    });

    testWidgets('signing out leaves the training exactly as it was', (
      tester,
    ) async {
      await pumpShell(tester);
      auth.arrive('second@example.com');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(find.byType(AnotherAccountScreen), findsNothing);
      expect(auth.current, isNull);
      expect(training.erasures, 0);
      expect(await owner.read(), 'first-lifter');
    });

    testWidgets('the owner signing back in is not asked', (tester) async {
      owner = InMemoryLocalDataOwner('fake-user');
      await pumpShell(tester);
      final before = backup.runs;

      auth.arrive('me@example.com');
      await tester.pumpAndSettle();

      expect(find.byType(AnotherAccountScreen), findsNothing);
      expect(backup.runs, greaterThan(before));
    });

    testWidgets('an emptied phone changes hands without a question', (
      tester,
    ) async {
      // The last lifter's training is gone; what is left of them (the pull
      // watermark) goes too, quietly, and the new account owns the phone.
      training = _Training(empty: true);
      await pumpShell(tester);

      auth.arrive('second@example.com');
      await tester.pumpAndSettle();

      expect(find.byType(AnotherAccountScreen), findsNothing);
      expect(await owner.read(), 'fake-user');
      expect(training.erasures, 1);
    });

    testWidgets('a phone with no owner is claimed by the first sign-in', (
      tester,
    ) async {
      // Weeks of training with no account, then an account: it is theirs.
      owner = InMemoryLocalDataOwner();
      await pumpShell(tester);

      auth.arrive('new@example.com');
      await tester.pumpAndSettle();

      expect(find.byType(AnotherAccountScreen), findsNothing);
      expect(await owner.read(), 'fake-user');
      expect(training.erasures, 0);
    });
  });

  group('the shell, when the account is deleted', () {
    testWidgets("erasing the phone's copy erases it and leaves it unclaimed", (
      tester,
    ) async {
      // The eraser is the shell's, threaded through Settings and Account to
      // the delete screen: this is the test that it arrives.
      tester.view.physicalSize = const Size(1080, 4200);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      final auth = FakeAuth(
        account: const Account(id: 'u1', email: 'lifter@example.com'),
      );
      addTearDown(auth.dispose);
      final training = _Training();
      final owner = InMemoryLocalDataOwner('u1');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: LiftShell(
            auth: auth,
            deleter: FakeAccountDeleter(),
            localData: LocalDataGuard(owner: owner, data: training),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('lifter@example.com'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(DestructiveButton, 'Delete account'),
      );
      await tester.pumpAndSettle();

      // On by default.
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DestructiveButton));
      await tester.pumpAndSettle();

      expect(training.erasures, 1);
      expect(await owner.read(), isNull);
      expect(
        find.text("This phone's copy has been erased too."),
        findsOneWidget,
      );
    });
  });

  group("Lift's own training", () {
    late AppDatabase db;
    late PhoneTrainingData data;

    setUp(() {
      db = AppDatabase.memory();
      data = PhoneTrainingData(db);
    });
    tearDown(() => db.close());

    Future<void> aSession() => db
        .into(db.workouts)
        .insert(
          WorkoutsCompanion.insert(
            id: 'w1',
            name: 'Push',
            startedAt: DateTime(2026, 9, 1),
          ),
        );

    test('an untouched phone is empty', () async {
      expect(await data.isEmpty(), isTrue);
    });

    test('where the last pull got to is not training', () async {
      await db
          .into(db.syncMeta)
          .insert(
            SyncMetaCompanion.insert(
              key: 'lift.workouts.pulledAt',
              value: Value(DateTime(2026, 9, 1)),
            ),
          );
      expect(await data.isEmpty(), isTrue);
    });

    test('a session is training, and erasing takes all of it', () async {
      await aSession();
      await db
          .into(db.syncMeta)
          .insert(
            SyncMetaCompanion.insert(
              key: 'lift.workouts.pulledAt',
              value: Value(DateTime(2026, 9, 1)),
            ),
          );
      expect(await data.isEmpty(), isFalse);

      await data.eraseAll();

      expect(await data.isEmpty(), isTrue);
      // The watermark too: left behind, the next account's first pull would
      // only ask for what changed since the last lifter's.
      expect(await db.select(db.syncMeta).get(), isEmpty);
    });

    test('erasing removes the photographs themselves', () async {
      final dir = await Directory.systemTemp.createTemp('lift-photos');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/front.jpg')..writeAsBytesSync(<int>[1]);
      await db
          .into(db.progressPhotos)
          .insert(
            ProgressPhotosCompanion.insert(
              id: 'p1',
              weekStart: DateTime(2026, 8, 31),
              poseType: 'front',
              path: file.path,
              takenAt: DateTime(2026, 9, 1),
            ),
          );
      expect(await data.isEmpty(), isFalse);

      await data.eraseAll();

      expect(file.existsSync(), isFalse);
      expect(await data.isEmpty(), isTrue);
    });
  });
}
