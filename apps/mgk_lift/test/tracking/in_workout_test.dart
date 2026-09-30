import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/core/database/app_database.dart';
import 'package:mgk_lift/src/features/tracking/data/drift_session_recorder.dart';
import 'package:mgk_lift/src/features/tracking/domain/rest_alerts.dart';
import 'package:mgk_lift/src/features/tracking/domain/rest_lengths.dart';
import 'package:mgk_lift/src/features/tracking/presentation/active_session_screen.dart';
import 'package:mgk_lift/src/features/tracking/presentation/exercise_picker_sheet.dart';
import 'package:mgk_lift/src/features/settings/domain/unit_preferences.dart';
import 'package:mgk_lift/src/features/settings/presentation/settings_screen.dart';

/// The in-workout gaps the 2026-09-29 competitor research found, closed:
/// a rest alert that reaches a locked phone, rest remembered per movement,
/// the timer's first offer of alerts, a swap for everybody, and reordering.
void main() {
  late AppDatabase db;
  late DriftSessionRecorder recorder;
  var counter = 0;
  final now = DateTime(2026, 9, 29, 18);

  setUp(() {
    counter = 0;
    db = AppDatabase.memory();
    recorder = DriftSessionRecorder(db, idFactory: () => 'id-${++counter}');
  });

  tearDown(() async => db.close());

  /// A session with one movement per name, two sets each, reps filled so a
  /// tick is allowed.
  Future<void> seed(List<String> names) async {
    await recorder.start();
    for (final name in names) {
      final session = await recorder.addExercise(name);
      final exercise = session.exercises.last;
      await recorder.addSet(exercise.id);
      await recorder.addSet(exercise.id);
      final sets = (await recorder.current())!.exercises.last.sets;
      for (final s in sets) {
        await recorder.updateSet(s.id, reps: 5, weightKg: 100);
      }
    }
  }

  Future<void> pump(
    WidgetTester tester, {
    RestAlerts? alerts,
    RestLengths? lengths,
  }) async {
    tester.view
      ..physicalSize = const Size(1179, 2556)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final session = (await recorder.current())!;
    await tester.pumpWidget(
      MaterialApp(
        home: ActiveSessionScreen(
          recorder: recorder,
          session: session,
          now: now,
          restAlerts: alerts,
          restLengths: lengths,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tickFirst(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Mark done').first);
    await tester.pumpAndSettle();
  }

  /// Through the states a real app passes, in order.
  Future<void> background(WidgetTester tester) async {
    for (final state in <AppLifecycleState>[
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
  }

  Future<void> foreground(WidgetTester tester) async {
    for (final state in <AppLifecycleState>[
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
  }

  group('the rest alert', () {
    testWidgets('a rest running when the phone locks becomes a system alert '
        'at its end, naming the next set', (tester) async {
      await seed(<String>['Bench press']);
      final alerts = FakeRestAlerts();
      await pump(tester, alerts: alerts);

      await tickFirst(tester);
      await background(tester);

      expect(alerts.scheduledAt, now.add(const Duration(seconds: 90)));
      expect(alerts.scheduledBody, 'Next: Bench press, set 2.');
    });

    testWidgets('coming back withdraws it, so there is never a second buzz', (
      tester,
    ) async {
      await seed(<String>['Bench press']);
      final alerts = FakeRestAlerts();
      await pump(tester, alerts: alerts);

      await tickFirst(tester);
      await background(tester);
      await foreground(tester);

      expect(alerts.scheduledAt, isNull);
      expect(alerts.calls.last, 'cancel');
    });

    testWidgets('no rest running, nothing scheduled', (tester) async {
      await seed(<String>['Bench press']);
      final alerts = FakeRestAlerts();
      await pump(tester, alerts: alerts);

      await background(tester);

      expect(alerts.calls, isNot(contains('schedule')));
    });

    testWidgets('it is offered once, beside the first rest, and Turn on asks', (
      tester,
    ) async {
      await seed(<String>['Bench press']);
      final alerts = FakeRestAlerts(isAllowed: false, wasAsked: false);
      await pump(tester, alerts: alerts);

      await tickFirst(tester);
      expect(find.textContaining('buzz when rest is over'), findsOneWidget);
      // Offered is answered: never offered again, whatever they do next.
      expect(alerts.wasAsked, isTrue);

      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();
      expect(alerts.calls, contains('ask'));
    });

    testWidgets('it is not offered to somebody who already allowed it', (
      tester,
    ) async {
      await seed(<String>['Bench press']);
      final alerts = FakeRestAlerts(wasAsked: false);
      await pump(tester, alerts: alerts);

      await tickFirst(tester);
      expect(find.textContaining('buzz when rest is over'), findsNothing);
    });
  });

  group('rest per movement', () {
    testWidgets('a movement starts the rest its lifter last settled on', (
      tester,
    ) async {
      await seed(<String>['Squat']);
      await pump(
        tester,
        lengths: InMemoryRestLengths(<String, Duration>{
          'squat': const Duration(minutes: 3),
        }),
      );

      await tickFirst(tester);

      expect(find.text('3:00'), findsOneWidget);
    });

    testWidgets('an adjustment is remembered for that movement', (
      tester,
    ) async {
      await seed(<String>['Squat']);
      final lengths = InMemoryRestLengths();
      await pump(tester, lengths: lengths);

      await tickFirst(tester);
      await tester.tap(find.text('+30s'));
      await tester.pumpAndSettle();

      expect((await lengths.all())['squat'], const Duration(minutes: 2));
    });
  });

  group('the way back, in Settings', () {
    Future<void> openSettings(WidgetTester tester, RestAlerts alerts) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            initial: const UnitPreferences(),
            restAlerts: alerts,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('off, a tap asks, and the row says what happened', (
      tester,
    ) async {
      final alerts = FakeRestAlerts(isAllowed: false);
      await openSettings(tester, alerts);
      expect(find.textContaining('Off. Tap to get a buzz'), findsOneWidget);

      alerts.isAllowed = true;
      await tester.tap(find.text('Rest timer alerts'));
      await tester.pumpAndSettle();

      expect(alerts.calls, contains('ask'));
      expect(find.textContaining('On. A buzz when rest is over'), findsOne);
    });

    testWidgets('refused by the phone, it says where the switch is', (
      tester,
    ) async {
      final alerts = FakeRestAlerts(isAllowed: false);
      await openSettings(tester, alerts);
      await tester.tap(find.text('Rest timer alerts'));
      await tester.pumpAndSettle();
      expect(find.textContaining("your phone's settings"), findsOneWidget);
    });
  });

  group('the movement itself', () {
    testWidgets('with no coach, swap picks a replacement by hand', (
      tester,
    ) async {
      await seed(<String>['Cable fly']);
      await pump(tester);

      await tester.tap(find.byTooltip('Swap this out'));
      await tester.pumpAndSettle();
      expect(find.text('REPLACE CABLE FLY'), findsOneWidget);

      // The picker's own search field, not a set's field on the screen behind.
      await tester.enterText(
        find.descendant(
          of: find.byType(ExercisePickerSheet),
          matching: find.byType(TextField),
        ),
        'Pec deck',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Add "Pec deck"'));
      await tester.pumpAndSettle();

      final names = (await recorder.current())!.exercises
          .map((e) => e.name)
          .toList();
      expect(names, <String>['Pec deck']);
      // The work that was left comes with it.
      expect((await recorder.current())!.exercises.single.sets, hasLength(2));
    });

    testWidgets('reordering moves a movement, sets and all', (tester) async {
      await seed(<String>['Bench press', 'Incline press']);
      await pump(tester);

      // The list builds its rows lazily, so the button at its foot may not
      // exist until the list scrolls to it: ensureVisible can only reach a
      // row that is already built, which is how this test failed once the
      // cards grew taller.
      await tester.scrollUntilVisible(
        find.text('Reorder movements'),
        200,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reorder movements'));
      await tester.pumpAndSettle();

      final handle = find.byIcon(Icons.drag_handle).last;
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(0, -30));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();

      final order = (await recorder.current())!.exercises
          .map((e) => e.name)
          .toList();
      expect(order, <String>['Incline press', 'Bench press']);
      expect((await recorder.current())!.exercises.first.sets, hasLength(2));
    });

    testWidgets('one movement has no order to change', (tester) async {
      await seed(<String>['Bench press']);
      await pump(tester);
      expect(find.text('Reorder movements'), findsNothing);
    });
  });
}
