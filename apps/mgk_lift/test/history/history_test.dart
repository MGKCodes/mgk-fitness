import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/core/database/app_database.dart';
import 'package:mgk_lift/src/features/home/presentation/lift_shell.dart';
import 'package:mgk_lift/src/features/stats/data/drift_session_history.dart';
import 'package:mgk_lift/src/features/stats/presentation/history_screen.dart';
import 'package:mgk_lift/src/features/sync/data/sync_queue.dart';
import 'package:mgk_lift/src/features/tracking/data/drift_session_recorder.dart';
import 'package:mgk_lift/src/features/tracking/domain/session.dart';
import 'package:mgk_lift/src/features/tracking/domain/session_recorder.dart';
import 'package:mgk_lift/src/features/tracking/presentation/session_summary_screen.dart';

/// Phase 6 — history you can fix: every session, each one openable, editable
/// with the session screen's own rules, and deletable with Undo.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.memory());
  tearDown(() async => db.close());

  /// A finished session: one movement, [ticked] of [rows] sets done.
  Future<String> finished(
    String id, {
    String name = 'Push',
    int rows = 2,
    int ticked = 2,
    DateTime? at,
  }) async {
    final started = at ?? DateTime(2026, 9, 23, 18);
    await db
        .into(db.workouts)
        .insert(
          WorkoutsCompanion.insert(
            id: id,
            name: name,
            startedAt: started,
            endedAt: Value(started.add(const Duration(minutes: 55))),
            durationS: const Value(3300),
            updatedAt: Value(started.add(const Duration(minutes: 55))),
            syncedAt: Value(started.add(const Duration(hours: 1))),
          ),
        );
    await db
        .into(db.exercises)
        .insert(
          ExercisesCompanion.insert(
            id: '$id-e',
            workoutId: id,
            name: 'Barbell Bench Press',
          ),
        );
    for (var n = 1; n <= rows; n++) {
      await db
          .into(db.exerciseSets)
          .insert(
            ExerciseSetsCompanion.insert(
              id: '$id-s$n',
              exerciseId: '$id-e',
              setNumber: Value(n),
              reps: const Value(5),
              weightKg: const Value(100),
              isCompleted: Value(n <= ticked),
            ),
          );
    }
    return id;
  }

  group('the editing recorder', () {
    test('changes the finished session it is aimed at', () async {
      await finished('past');
      final editor = DriftSessionRecorder.editing(db, 'past');

      final session = (await editor.current())!;
      expect(session.id, 'past');
      expect(session.isInProgress, isFalse);

      await editor.updateSet('past-s1', reps: 8);
      final after = (await editor.current())!;
      expect(after.exercises.single.sets.first.reps, 8);
    });

    test('saving drops unticked sets, keeps the date, and marks it for '
        'backup', () async {
      await finished('past', rows: 3, ticked: 2);
      final before = await (db.select(
        db.workouts,
      )..where((w) => w.id.equals('past'))).getSingle();
      final editor = DriftSessionRecorder.editing(db, 'past');

      final saved = await editor.finish(at: DateTime(2026, 9, 29, 9));

      expect(saved.exercises.single.sets, hasLength(2));
      final row = await (db.select(
        db.workouts,
      )..where((w) => w.id.equals('past'))).getSingle();
      // Fixing Tuesday on Monday does not move it to Monday.
      expect(row.endedAt, before.endedAt);
      expect(row.durationS, before.durationS);
      expect(
        (await SyncQueue(db).dirtyWorkouts()).map((w) => w.id),
        contains('past'),
      );
    });

    test('never touches the session in progress', () async {
      await finished('past');
      final live = DriftSessionRecorder(
        db,
        idFactory: () => 'live-${DateTime.now().microsecondsSinceEpoch}',
      );
      final open = await live.start(name: 'Today');
      final editor = DriftSessionRecorder.editing(db, 'past');

      await editor.addExercise('Cable Fly');

      expect((await live.current())!.id, open.id);
      expect((await live.current())!.exercises, isEmpty);
      expect((await editor.current())!.exercises, hasLength(2));
    });

    test('does not start or discard sessions', () async {
      await finished('past');
      final editor = DriftSessionRecorder.editing(db, 'past');
      expect(editor.start, throwsStateError);
      await editor.discard();
      expect(
        await editor.current(),
        isNotNull,
        reason: 'a no-op, not a delete',
      );
    });
  });

  group('deleting a past session', () {
    test('is soft: it leaves the log, and goes up as a tombstone', () async {
      await finished('a');
      await finished('b', at: DateTime(2026, 9, 24, 18));
      final history = DriftSessionHistory(db);

      await history.remove('a');

      expect((await history.all()).map((s) => s.id), <String>['b']);
      final row = await (db.select(
        db.workouts,
      )..where((w) => w.id.equals('a'))).getSingle();
      expect(row.deletedAt, isNotNull);
      expect(
        (await SyncQueue(db).dirtyWorkouts()).map((w) => w.id),
        contains('a'),
      );
    });

    test('and Undo puts it back', () async {
      await finished('a');
      final history = DriftSessionHistory(db);
      await history.remove('a');
      await history.restore('a');
      expect((await history.all()).single.id, 'a');
    });

    test('never reaches a session in progress', () async {
      final live = DriftSessionRecorder(db, idFactory: () => 'open');
      await live.start();
      await DriftSessionHistory(db).remove('open');
      expect(await live.current(), isNotNull);
    });
  });

  group('the history screen', () {
    Session s(String id, DateTime at) => Session(
      id: id,
      name: 'Session $id',
      startedAt: at,
      endedAt: at.add(const Duration(hours: 1)),
    );

    testWidgets('every session, grouped by week, newest first', (tester) async {
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: HistoryScreen(
            now: DateTime(2026, 9, 29, 12), // a Tuesday
            log: <Session>[
              s('a', DateTime(2026, 9, 28, 18)),
              s('b', DateTime(2026, 9, 23, 18)),
              s('c', DateTime(2026, 9, 9, 18)),
            ],
            onOpen: (session) => opened.add(session.id),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('THIS WEEK'), findsOneWidget);
      expect(find.text('LAST WEEK'), findsOneWidget);
      expect(find.text('WEEK OF 7 SEP'), findsOneWidget);

      await tester.tap(find.text('Session b'));
      expect(opened, <String>['b']);
    });

    testWidgets('the first week starts below the glass bar, not under it', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HistoryScreen(
            now: DateTime(2026, 9, 29, 12),
            log: <Session>[s('a', DateTime(2026, 9, 28, 18))],
            onOpen: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('THIS WEEK')).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.byType(AppBar)).dy),
      );
    });
  });

  group('a past session\'s page', () {
    testWidgets('reads like the summary, with Edit and Delete instead of '
        "Finish's actions", (tester) async {
      var edits = 0;
      var deletes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SessionSummaryScreen(
            session: Session(
              id: 'x',
              name: 'Push',
              startedAt: DateTime(2026, 9, 23, 18),
              endedAt: DateTime(2026, 9, 23, 19),
            ),
            onEdit: () => edits++,
            onDelete: () => deletes++,
            onOpenCoach: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('WEDNESDAY 23 SEP'), findsOneWidget);
      expect(find.text('Back to Track'), findsNothing);
      expect(find.text('Talk it over with your coach'), findsNothing);
      await tester.tap(find.text('Edit session'));
      await tester.tap(find.text('Delete session'));
      expect(edits, 1);
      expect(deletes, 1);
    });
  });

  group('through the shell', () {
    Future<void> openFromProfile(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(1080, 4000)
        ..devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      var n = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LiftShell(
            recorder: DriftSessionRecorder(db, idFactory: () => 'n-${++n}'),
            editorFor: (id) => DriftSessionRecorder.editing(
              db,
              id,
              idFactory: () => 'e-${++n}',
            ),
            history: DriftSessionHistory(db),
            initialTab: 2,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Push'));
      await tester.pumpAndSettle();
    }

    testWidgets('delete asks, then offers Undo', (tester) async {
      await finished('past');
      await openFromProfile(tester);

      await tester.tap(find.text('Delete session'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(await DriftSessionHistory(db).all(), isEmpty);
      expect(find.text('Push deleted.'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Undo'));
      await tester.pumpAndSettle();
      expect(await DriftSessionHistory(db).all(), hasLength(1));
    });

    testWidgets('edit uses the session screen, and saves on Done', (
      tester,
    ) async {
      await finished('past', rows: 2, ticked: 1);
      await openFromProfile(tester);

      await tester.tap(find.text('Edit session'));
      await tester.pumpAndSettle();

      expect(find.text('EDITING'), findsOneWidget);
      expect(find.text('Discard session'), findsNothing);
      // Tick the second set: no rest timer while editing.
      await tester.tap(find.byTooltip('Mark done').first);
      await tester.pumpAndSettle();
      expect(find.text('RESTING'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();

      // Back on the session's page, as it now is.
      expect(find.text('Edit session'), findsOneWidget);
      final log = await DriftSessionHistory(db).all();
      expect(log.single.completedSets, 2);
    });
  });

  test('SessionRecorder has the editing contract', () {
    // Compile-time: the editing recorder is a SessionRecorder like any other,
    // which is what lets the session screen take it unchanged.
    final SessionRecorder r = DriftSessionRecorder.editing(db, 'x');
    expect(r, isA<SessionRecorder>());
  });
}
