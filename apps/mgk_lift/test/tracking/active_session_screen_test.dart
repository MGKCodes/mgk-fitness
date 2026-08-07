import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/core/database/app_database.dart';
import 'package:mgk_lift/src/features/tracking/data/drift_session_recorder.dart';
import 'package:mgk_lift/src/features/tracking/domain/session.dart';
import 'package:mgk_lift/src/features/tracking/presentation/active_session_screen.dart';
// Prefixed: drift generates its own `SetRow` for the sets table, which collides
// with the widget of the same name.
import 'package:mgk_lift/src/features/tracking/presentation/exercise_card.dart'
    as card;
import 'package:mgk_units/mgk_units.dart';

void main() {
  late AppDatabase db;
  late DriftSessionRecorder recorder;
  var counter = 0;

  setUp(() {
    counter = 0;
    db = AppDatabase.memory();
    recorder = DriftSessionRecorder(db, idFactory: () => 'id-${++counter}');
  });

  tearDown(() async => db.close());

  Future<Widget> screen({MassUnit unit = MassUnit.kilograms}) async {
    final session = await recorder.current() ?? await recorder.start();
    return MaterialApp(
      home: ActiveSessionScreen(
        recorder: recorder,
        session: session,
        massUnit: unit,
      ),
    );
  }

  testWidgets('a weight typed in pounds is stored in kilograms', (
    WidgetTester tester,
  ) async {
    // The whole point of the units work. What the lifter types is theirs; what
    // reaches the database is always metric.
    await recorder.start();
    await recorder.addExercise('Bench press');
    await recorder.addSet('id-2');

    await tester.pumpWidget(await screen(unit: MassUnit.pounds));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '225');
    await tester.pumpAndSettle();

    final stored = await db.select(db.exerciseSets).getSingle();
    expect(stored.weightKg, closeTo(102.058, 0.001));
  });

  testWidgets('a stored kilogram weight renders as a loadable pound value', (
    WidgetTester tester,
  ) async {
    await recorder.start();
    await recorder.addExercise('Squat');
    await recorder.addSet('id-2');
    // 225 lb exactly, stored canonically.
    await recorder.updateSet('id-3', weightKg: 102.058283, reps: 5);

    await tester.pumpWidget(await screen(unit: MassUnit.pounds));
    await tester.pumpAndSettle();

    // Not 220.5 — plates are discrete and the conversion is not.
    expect(find.widgetWithText(TextField, '225'), findsOneWidget);
  });

  testWidgets('the same weight renders in kilograms when that is the choice', (
    WidgetTester tester,
  ) async {
    await recorder.start();
    await recorder.addExercise('Squat');
    await recorder.addSet('id-2');
    await recorder.updateSet('id-3', weightKg: 100, reps: 5);

    await tester.pumpWidget(await screen());
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '100'), findsOneWidget);
  });

  testWidgets('finish is unavailable until a set is actually completed', (
    WidgetTester tester,
  ) async {
    await recorder.start();
    await recorder.addExercise('Row');
    await recorder.addSet('id-2');

    await tester.pumpWidget(await screen());
    await tester.pumpAndSettle();

    // A row exists but nothing was ticked. Finishing would write an empty
    // session to the log and an empty card to the cross-app feed.
    //
    // Finish lives in the header now rather than as a full-width slab at the
    // bottom: that slab read as the screen's purpose, when it is the thing you
    // press once, at the end.
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Finish'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('an empty set row says which column is which', (
    WidgetTester tester,
  ) async {
    // Found on device: Flutter renders suffixText only once a field has
    // content, so a fresh row was two identical boxes with nothing to say which
    // was weight and which was reps. The fix moved the unit out of the field
    // into a column header, which also lets the rows be bare numbers.
    await recorder.start();
    await recorder.addExercise('Press');
    await recorder.addSet('id-2');

    await tester.pumpWidget(await screen());
    await tester.pumpAndSettle();

    // SectionLabel uppercases.
    expect(find.text('SET'), findsOneWidget);
    expect(find.text('KG'), findsOneWidget);
    expect(find.text('REPS'), findsOneWidget);
  });

  testWidgets('the weight column header follows the chosen unit', (
    WidgetTester tester,
  ) async {
    await recorder.start();
    await recorder.addExercise('Press');
    await recorder.addSet('id-2');

    await tester.pumpWidget(await screen(unit: MassUnit.pounds));
    await tester.pumpAndSettle();

    expect(find.text('LB'), findsOneWidget);
    expect(find.text('KG'), findsNothing);
  });

  testWidgets('a catalogue movement carries its muscle group and loading', (
    WidgetTester tester,
  ) async {
    // The fix for "just having 'Bench press' looks awful": a bare name tells a
    // lifter nothing they did not already know.
    await recorder.start();
    await recorder.addExercise('Barbell Bench Press');

    await tester.pumpWidget(await screen());
    await tester.pumpAndSettle();

    expect(find.text('Barbell Bench Press'), findsOneWidget);
    expect(find.text('Chest · Barbell'), findsOneWidget);
  });

  testWidgets('a movement they typed is a first-class case, not an error', (
    WidgetTester tester,
  ) async {
    await recorder.start();
    await recorder.addExercise('Smith machine incline press, feet up');

    await tester.pumpWidget(await screen());
    await tester.pumpAndSettle();

    expect(find.text('Your own movement'), findsOneWidget);
  });

  testWidgets('an empty session offers a template before a blank card', (
    WidgetTester tester,
  ) async {
    // The first session is otherwise the hardest: a blank list asks someone to
    // remember what a push day is before they can log anything.
    await recorder.start();

    await tester.pumpWidget(await screen());
    await tester.pumpAndSettle();

    expect(find.text('Use a template'), findsOneWidget);
    expect(find.text('Add exercise'), findsOneWidget);
  });

  testWidgets('a template adds its movements and no numbers', (
    WidgetTester tester,
  ) async {
    // A template says what to do, not what to lift. Pre-filling weights would
    // be the app asserting something only the lifter knows.
    await recorder.start();
    await recorder.addExercise('Barbell Bench Press');
    await recorder.addExercise('Dumbbell Shoulder Press');

    final session = await recorder.current();
    expect(session!.exercises, hasLength(2));
    expect(session.totalSets, 0);
    expect(session.volumeKg, 0);
  });

  testWidgets('an empty session can still be discarded', (
    WidgetTester tester,
  ) async {
    // Found on device. With nothing logged, Finish is disabled and backing out
    // leaves the session open — so Track would offer to resume a session that
    // never happened, with no way to get rid of it.
    await recorder.start();

    await tester.pumpWidget(await screen());
    await tester.pumpAndSettle();

    expect(find.text('Discard session'), findsOneWidget);
  });

  group('rest between sets', () {
    /// A session with one exercise and one untouched set, ready to tick.
    Future<void> oneOpenSet() async {
      await recorder.start();
      await recorder.addExercise('Barbell Bench Press');
      await recorder.addSet('id-2');
      await recorder.updateSet('id-3', reps: 6, weightKg: 85);
      // A second, so the card stays expanded after the first is ticked.
      await recorder.addSet('id-2');
    }

    testWidgets('no rest is running until a set is ticked', (
      WidgetTester tester,
    ) async {
      await oneOpenSet();
      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();

      expect(find.text('RESTING'), findsNothing);
    });

    testWidgets('ticking a set starts it', (WidgetTester tester) async {
      await oneOpenSet();
      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.circle_outlined).first);
      await tester.pump();

      // SectionLabel uppercases.
      expect(find.text('RESTING'), findsOneWidget);
      expect(find.text('1:30'), findsOneWidget);
    });

    testWidgets('un-ticking a set does not start it', (
      WidgetTester tester,
    ) async {
      // Un-ticking is a correction to the log, not the end of a set. Starting a
      // countdown for it would be the app misreading what happened.
      await recorder.start();
      await recorder.addExercise('Barbell Bench Press');
      await recorder.addSet('id-2');
      await recorder.updateSet('id-3', reps: 6, weightKg: 85, isCompleted: true);
      await recorder.addSet('id-2');

      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.check_circle).first);
      await tester.pump();

      expect(find.text('RESTING'), findsNothing);
    });

    testWidgets('it can be skipped', (WidgetTester tester) async {
      await oneOpenSet();
      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.circle_outlined).first);
      await tester.pump();
      await tester.tap(find.text('Skip'));
      await tester.pump();

      expect(find.text('RESTING'), findsNothing);
    });

    testWidgets('adding time extends it', (WidgetTester tester) async {
      await oneOpenSet();
      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.circle_outlined).first);
      await tester.pump();
      await tester.tap(find.text('+30s'));
      await tester.pump();

      expect(find.text('2:00'), findsOneWidget);
    });

    testWidgets('the adjusted length carries to the next set', (
      WidgetTester tester,
    ) async {
      // Someone adding thirty seconds between every set means it. Asking again
      // each time is the app refusing to learn something it has been told.
      await oneOpenSet();
      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.circle_outlined).first);
      await tester.pump();
      await tester.tap(find.text('+30s'));
      await tester.pump();

      // Tick the second set: the new rest starts at the remembered length.
      await tester.tap(find.byIcon(Icons.circle_outlined).first);
      await tester.pump();

      expect(find.text('2:00'), findsOneWidget);
    });

    testWidgets('the log stays reachable while resting', (
      WidgetTester tester,
    ) async {
      // A bar, not a dialog. Resting is exactly when someone notices they typed
      // 8 instead of 6, and a modal would be in the way.
      await oneOpenSet();
      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.circle_outlined).first);
      await tester.pump();

      expect(find.text('RESTING'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '90');
      await tester.pump();

      final stored = await (db.select(
        db.exerciseSets,
      )..where((s) => s.id.equals('id-3'))).getSingle();
      expect(stored.weightKg, 90);
    });
  });

  group('warm-ups', () {
    testWidgets('a warm-up is marked, not left looking like a working set', (
      WidgetTester tester,
    ) async {
      // Found by screenshotting a session: the warm-up was ticked like every
      // other set but counted toward neither the volume nor the set count, so
      // the list showed four ticks above a header reading three with nothing
      // saying which one had been discounted.
      await recorder.start();
      await recorder.addExercise('Barbell Bench Press');
      await recorder.addSet('id-2');
      await recorder.updateSet(
        'id-3',
        reps: 10,
        weightKg: 60,
        isCompleted: true,
        setType: SetType.warmup,
      );
      await recorder.addSet('id-2');
      await recorder.updateSet('id-4', reps: 6, weightKg: 85, isCompleted: true);
      // A set still open, so the card stays expanded and the rows are visible.
      await recorder.addSet('id-2');

      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();

      // Row one reads W rather than a set number.
      expect(find.text('W'), findsOneWidget);
      // Only the working set counts, and the header now says so out loud.
      expect(find.text('510 kg'), findsOneWidget);
    });

    testWidgets('tapping the set number marks a set as a warm-up', (
      WidgetTester tester,
    ) async {
      await recorder.start();
      await recorder.addExercise('Barbell Bench Press');
      await recorder.addSet('id-2');
      await recorder.updateSet('id-3', reps: 10, weightKg: 60, isCompleted: true);
      await recorder.addSet('id-2');

      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();
      expect(find.text('600 kg'), findsOneWidget);

      // Scoped to the row: the header's set count is also "1".
      await tester.tap(
        find.descendant(of: find.byType(card.SetRow), matching: find.text('1')),
      );
      await tester.pumpAndSettle();

      // It still happened, it just stops counting.
      expect(find.text('W'), findsOneWidget);
      final stored = await (db.select(
        db.exerciseSets,
      )..where((s) => s.id.equals('id-3'))).getSingle();
      expect(stored.setType, 'warmup');
      expect(stored.isCompleted, isTrue);
    });

    testWidgets('and tapping it again puts the set back', (
      WidgetTester tester,
    ) async {
      await recorder.start();
      await recorder.addExercise('Barbell Bench Press');
      await recorder.addSet('id-2');
      await recorder.updateSet(
        'id-3',
        reps: 10,
        weightKg: 60,
        isCompleted: true,
        setType: SetType.warmup,
      );
      await recorder.addSet('id-2');

      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('W'));
      await tester.pumpAndSettle();

      expect(find.text('W'), findsNothing);
      expect(find.text('600 kg'), findsOneWidget);
    });
  });

  group('collapsing a finished movement', () {
    // Expanded, a card with three sets is ~350px. Six of them is two thousand
    // pixels of scrolling, and the movement you are actually on ends up off
    // screen — the worst outcome for a screen used between sets.

    testWidgets('a movement with every set ticked folds to one line', (
      WidgetTester tester,
    ) async {
      await recorder.start();
      await recorder.addExercise('Barbell Bench Press');
      await recorder.addSet('id-2');
      await recorder.updateSet(
        'id-3',
        reps: 6,
        weightKg: 85,
        isCompleted: true,
      );

      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();

      // The record of what happened survives; the machinery does not.
      expect(find.text('1 set · 85 kg × 6'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('SET'), findsNothing);
    });

    testWidgets('a movement with a set still open stays open', (
      WidgetTester tester,
    ) async {
      await recorder.start();
      await recorder.addExercise('Barbell Bench Press');
      await recorder.addSet('id-2');
      await recorder.updateSet('id-3', reps: 6, weightKg: 85, isCompleted: true);
      await recorder.addSet('id-2');

      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNWidgets(4)); // two rows, two fields
    });

    testWidgets('tapping a collapsed movement opens it again', (
      WidgetTester tester,
    ) async {
      // "Finished" is the app's guess. The lifter may want another set, and
      // must not have to delete and re-add the movement to get one.
      await recorder.start();
      await recorder.addExercise('Barbell Bench Press');
      await recorder.addSet('id-2');
      await recorder.updateSet('id-3', reps: 6, weightKg: 85, isCompleted: true);

      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('1 set · 85 kg × 6'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.text('Add set'), findsOneWidget);
    });

    testWidgets('a movement opened by hand is not shut by the next tick', (
      WidgetTester tester,
    ) async {
      // The override is what makes this hold: without it, any rebuild would
      // recompute "finished" and close a card the lifter deliberately opened.
      await recorder.start();
      await recorder.addExercise('Barbell Bench Press');
      await recorder.addSet('id-2');
      await recorder.updateSet('id-3', reps: 6, weightKg: 85, isCompleted: true);

      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('1 set · 85 kg × 6'));
      await tester.pumpAndSettle();

      // Add a set, tick it — the movement is "finished" again.
      await tester.tap(find.text('Add set'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.circle_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNWidgets(4));
    });

    testWidgets('the summary counts working sets, not warm-ups', (
      WidgetTester tester,
    ) async {
      // Or a collapsed card becomes a fourth opinion on what a set is, and the
      // warm-up bug comes back one screen over.
      await recorder.start();
      await recorder.addExercise('Barbell Bench Press');
      await recorder.addSet('id-2');
      await recorder.updateSet(
        'id-3',
        reps: 10,
        weightKg: 60,
        isCompleted: true,
        setType: SetType.warmup,
      );
      await recorder.addSet('id-2');
      await recorder.updateSet('id-4', reps: 6, weightKg: 85, isCompleted: true);

      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();

      expect(find.text('1 set · 85 kg × 6'), findsOneWidget);
    });
  });

  testWidgets('volume is shown in the chosen unit', (
    WidgetTester tester,
  ) async {
    await recorder.start();
    await recorder.addExercise('Deadlift');
    await recorder.addSet('id-2');
    await recorder.updateSet('id-3', reps: 5, weightKg: 100, isCompleted: true);

    await tester.pumpWidget(await screen());
    await tester.pumpAndSettle();
    expect(find.text('500 kg'), findsOneWidget);

    await tester.pumpWidget(await screen(unit: MassUnit.pounds));
    await tester.pumpAndSettle();
    // 500 kg is 1102.31 lb, snapped to the pound.
    expect(find.text('1102 lb'), findsOneWidget);
  });
}
