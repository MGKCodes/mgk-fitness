import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/core/database/app_database.dart';
import 'package:mgk_lift/src/features/home/presentation/lift_shell.dart';
import 'package:mgk_lift/src/features/stats/data/drift_session_history.dart';
import 'package:mgk_lift/src/features/sync/domain/sync_status.dart';
import 'package:mgk_lift/src/features/sync/presentation/backup_messages.dart';
import 'package:mgk_lift/src/features/sync/presentation/backup_scheduler.dart';
import 'package:mgk_lift/src/features/tracking/data/drift_session_recorder.dart';
import 'package:mgk_lift/src/features/tracking/data/exercise_lookup.dart';
import 'package:mgk_lift/src/features/tracking/domain/exercise.dart';
import 'package:mgk_lift/src/features/tracking/domain/session.dart';
import 'package:mgk_lift/src/features/tracking/domain/workout_library.dart';
import 'package:mgk_lift/src/features/tracking/presentation/finish_sheet.dart';
import 'package:mgk_lift/src/features/tracking/presentation/session_summary_screen.dart';
import 'package:mgk_lift/src/features/tracking/presentation/track_surface.dart';
import 'package:mgk_lift/src/features/tracking/presentation/workout_library_screen.dart';

/// Counts runs, and answers what it is told to.
class CountingBackup implements BackupService {
  int runs = 0;
  SyncReport next = const SyncReport(outcome: SyncOutcome.upToDate);
  SyncPending waiting = const SyncPending(workouts: 0, lastSyncedAt: null);

  @override
  Future<SyncPending> pending() async => waiting;

  @override
  Future<SyncReport> run() async {
    runs++;
    return next;
  }
}

void main() {
  final finished = Session(
    id: 's',
    name: 'Push',
    startedAt: DateTime(2026, 9, 29, 18),
    endedAt: DateTime(2026, 9, 29, 19),
    exercises: const <SessionExercise>[
      SessionExercise(
        id: 'e',
        name: 'Barbell Bench Press',
        orderIndex: 0,
        sets: <SessionSet>[
          SessionSet(
            id: 'x',
            setNumber: 1,
            reps: 5,
            weightKg: 100,
            isCompleted: true,
          ),
        ],
      ),
    ],
  );

  group("Track's pill", () {
    Future<void> pump(
      WidgetTester tester,
      BackupStatus status,
      ValueChanged<BackupAction> onAction,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrackSurface(
              today: DateTime(2026, 9, 29),
              backup: status,
              onBackupAction: onAction,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('appears when something needs the lifter, and acts', (
      tester,
    ) async {
      final actions = <BackupAction>[];
      await pump(
        tester,
        const BackupStatus(
          state: BackupState.failed,
          pending: SyncPending(workouts: 2, lastSyncedAt: null),
        ),
        actions.add,
      );

      expect(find.text('Backup failed'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(actions, <BackupAction>[BackupAction.retry]);
    });

    testWidgets('is not there when all is well', (tester) async {
      await pump(tester, const BackupStatus(), (_) {});
      expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);
    });
  });

  group('the summary', () {
    testWidgets('says saved at once, then backed up, live', (tester) async {
      final status = ValueNotifier<BackupStatus>(
        const BackupStatus(
          state: BackupState.running,
          pending: SyncPending(
            workouts: 1,
            lastSyncedAt: null,
            waitingIds: <String>{'s'},
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            session: finished,
            backup: BackupHooks(status: status),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Saved on this phone. Backing up…'), findsOneWidget);

      // The run that Finish started lands a moment later.
      status.value = BackupStatus(
        pending: SyncPending(
          workouts: 0,
          lastSyncedAt: finished.endedAt!.add(const Duration(seconds: 3)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Backed up.'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
    });

    testWidgets('a failure offers a retry', (tester) async {
      var retried = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            session: finished,
            backup: BackupHooks(
              status: ValueNotifier<BackupStatus>(
                const BackupStatus(
                  state: BackupState.failed,
                  pending: SyncPending(
                    workouts: 1,
                    lastSyncedAt: null,
                    waitingIds: <String>{'s'},
                  ),
                ),
              ),
              onRetry: () => retried++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      expect(retried, 1);
    });

    testWidgets('with no server, says nothing about backup', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: SessionSummaryScreen(session: finished)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('on this phone'), findsNothing);
    });
  });

  group("the library's rows", () {
    testWidgets('mark the one not backed up, and only when signed in', (
      tester,
    ) async {
      final library = InMemoryWorkoutLibrary();
      final push = await library.save(
        name: 'Push',
        movements: const <TemplateMovement>[TemplateMovement('Bench')],
      );
      await library.save(
        name: 'Pull',
        movements: const <TemplateMovement>[TemplateMovement('Row')],
      );
      final status = ValueNotifier<BackupStatus>(
        BackupStatus(
          pending: SyncPending(
            workouts: 0,
            savedWorkouts: 1,
            lastSyncedAt: null,
            waitingIds: <String>{push.id},
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: WorkoutLibraryScreen(
            library: library,
            lookup: ExerciseLookup(const <Exercise>[]),
            backup: status,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Not backed up yet'), findsOneWidget);

      status.value = BackupStatus(
        state: BackupState.signedOut,
        pending: status.value.pending,
      );
      await tester.pump();
      expect(find.byTooltip('Not backed up yet'), findsNothing);
    });
  });

  group('the shell runs backup at checkpoints', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.memory());
    tearDown(() async => db.close());

    testWidgets('on launch, once it settles', (tester) async {
      final backup = CountingBackup();
      await tester.pumpWidget(MaterialApp(home: LiftShell(sync: backup)));
      await tester.pump();
      expect(backup.runs, 0);
      await tester.pump(const Duration(seconds: 3));
      expect(backup.runs, 1);
    });

    testWidgets('after a saved workout changes', (tester) async {
      final backup = CountingBackup();
      final library = InMemoryWorkoutLibrary();
      await tester.pumpWidget(
        MaterialApp(
          home: LiftShell(sync: backup, library: library),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      final before = backup.runs;

      await library.save(
        name: 'Push',
        movements: const <TemplateMovement>[TemplateMovement('Bench')],
      );
      await tester.pump(const Duration(seconds: 3));
      expect(backup.runs, before + 1);
    });

    testWidgets('after Finish — and never while the session is logged', (
      tester,
    ) async {
      final backup = CountingBackup();
      var n = 0;
      final recorder = DriftSessionRecorder(db, idFactory: () => 'r-${++n}');
      await recorder.start();
      await recorder.addExercise('Barbell Bench Press');
      await recorder.addSet('r-2', reps: 5, weightKg: 100);

      await tester.pumpWidget(
        MaterialApp(
          home: LiftShell(
            sync: backup,
            recorder: recorder,
            history: DriftSessionHistory(db),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      final atLaunch = backup.runs;

      // Resume the open session and log a set: nothing goes up.
      await tester.tap(find.widgetWithText(FilledButton, 'Resume session'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Mark done').first);
      await tester.pump(const Duration(seconds: 5));
      expect(backup.runs, atLaunch, reason: 'logging never touches backup');

      await tester.tap(find.widgetWithText(FilledButton, 'Finish').first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(FinishSheet),
          matching: find.widgetWithText(FilledButton, 'Finish'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));

      expect(backup.runs, atLaunch + 1);
      expect(find.byType(SessionSummaryScreen), findsOneWidget);
    });
  });
}
