import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/core/database/app_database.dart' show AppDatabase;
import 'package:mgk_lift/src/features/stats/presentation/exercise_stats_screen.dart';
import 'package:mgk_lift/src/features/tracking/data/drift_session_recorder.dart';
import 'package:mgk_lift/src/features/tracking/domain/rest_alerts.dart';
import 'package:mgk_lift/src/features/tracking/domain/rest_lengths.dart';
import 'package:mgk_lift/src/features/tracking/presentation/active_session_screen.dart';
import 'package:mgk_lift/src/features/tracking/presentation/exercise_card.dart';
import 'package:mgk_lift/src/features/tracking/presentation/exercise_picker_sheet.dart';
import 'package:mgk_lift/src/features/settings/domain/unit_preferences.dart';
import 'package:mgk_lift/src/features/settings/presentation/settings_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// The in-workout gaps the 2026-09-29 competitor research found, closed:
/// a rest alert that reaches a locked phone, rest remembered per movement,
/// the timer's first offer of alerts, a swap for everybody, and reordering —
/// since 29 October by holding a movement where it sits.
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
      expect(find.widgetWithText(SettingsRow, 'Off'), findsOneWidget);

      alerts.isAllowed = true;
      await tester.tap(find.text('Rest timer alerts'));
      await tester.pumpAndSettle();

      expect(alerts.calls, contains('ask'));
      expect(find.widgetWithText(SettingsRow, 'On'), findsOneWidget);
      // What On means, behind the row.
      await tester.tap(find.text('Rest timer alerts'));
      await tester.pumpAndSettle();
      expect(find.textContaining('A buzz when rest is over'), findsOne);
    });

    testWidgets('refused by the phone, it says where the switch is', (
      tester,
    ) async {
      final alerts = FakeRestAlerts(isAllowed: false);
      await openSettings(tester, alerts);
      await tester.tap(find.text('Rest timer alerts'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(SettingsRow, 'Not allowed'), findsOneWidget);

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
  });

  /// Reordering, in place (29 October 2026): a movement is held by its
  /// picture and name — or a folded one anywhere — and dragged where it sits,
  /// carried folded to its header. It replaced a button at the foot of the
  /// list and a sheet of its own.
  group('moving a movement, by holding it', () {
    Future<List<String>> storedOrder() async => <String>[
      for (final e in (await recorder.current())!.exercises) e.name,
    ];

    Finder card(int i) => find.byType(ExerciseCard).at(i);

    /// Holds [from] past the long-press delay, drags it by [by] in small steps
    /// as a thumb would, and lets go.
    Future<void> holdAndDrag(
      WidgetTester tester,
      Finder from,
      Offset by, {
      Duration hold = const Duration(milliseconds: 600),
    }) async {
      final gesture = await tester.startGesture(tester.getCenter(from));
      await tester.pump(hold);
      const steps = 12;
      for (var i = 0; i < steps; i++) {
        await gesture.moveBy(by / steps.toDouble());
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
    }

    /// Every haptic asked of the platform, by type.
    List<String> recordHaptics(WidgetTester tester) {
      final haptics = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add('${call.arguments}');
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      return haptics;
    }

    testWidgets('held by its name and dragged up, a movement moves, sets and '
        'all, and is written', (tester) async {
      await seed(<String>['Bench press', 'Incline press']);
      await pump(tester);
      final haptics = recordHaptics(tester);

      final up = tester.getTopLeft(card(0)).dy - tester.getTopLeft(card(1)).dy;
      await holdAndDrag(tester, find.text('Incline press'), Offset(0, up));

      expect(await storedOrder(), <String>['Incline press', 'Bench press']);
      final stored = (await recorder.current())!.exercises;
      expect(stored.map((e) => e.orderIndex), <int>[0, 1]);
      expect(stored.first.sets, hasLength(2), reason: 'its sets go with it');
      // On disk, so a recorder opened afresh — the app after a restart —
      // reads the same order.
      expect(
        (await DriftSessionRecorder(
          db,
        ).current())!.exercises.map((e) => e.name),
        <String>['Incline press', 'Bench press'],
      );
      // And the screen agrees, without waiting to be reopened.
      expect(
        tester.getTopLeft(find.text('Incline press')).dy,
        lessThan(tester.getTopLeft(find.text('Bench press')).dy),
      );
      // One light tick, as it lifted; nothing on the drop.
      expect(haptics, <String>['HapticFeedbackType.selectionClick']);
    });

    testWidgets('carried, an open card folds to its header, and opens again '
        'where it lands', (tester) async {
      await seed(<String>['Bench press', 'Incline press']);
      await pump(tester);
      Finder rowsOf(int i) =>
          find.descendant(of: card(i), matching: find.byType(SetRow));
      expect(rowsOf(1), findsNWidgets(2));

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Incline press')),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      // In flight: the name and its icons, and none of its sets. The card it
      // is carried past keeps all of its own.
      expect(find.text('Incline press'), findsOneWidget);
      expect(
        find.byTooltip('Remove Incline press'),
        findsOneWidget,
        reason: 'its own header, not a stand-in',
      );
      expect(rowsOf(0), findsNWidgets(2));
      expect(find.byType(SetRow), findsNWidgets(2));

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.byType(SetRow), findsNWidgets(4));
    });

    testWidgets('held still, a card whose sets run past the foot of the '
        'screen stays where it is', (tester) async {
      // Four movements of three sets: the second one's name is on screen
      // and most of its sets are below the fold. Carried at full height,
      // the list scrolled itself under a thumb that had not moved and took
      // the card to the end — see HoldToMove.
      await recorder.start();
      for (final name in <String>['A one', 'B two', 'C three', 'D four']) {
        final s = await recorder.addExercise(name);
        for (var i = 0; i < 3; i++) {
          await recorder.addSet(s.exercises.last.id);
        }
      }
      await pump(tester);
      final view = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(
        tester.getBottomLeft(card(1)).dy,
        greaterThan(view.height),
        reason: 'the case: a card reaching past the foot of the screen',
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('B two')),
      );
      await tester.pump(const Duration(milliseconds: 600));
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(await storedOrder(), <String>[
        'A one',
        'B two',
        'C three',
        'D four',
      ]);
    });

    testWidgets('scrolled to the end, the folded card stays under the thumb, '
        'and nothing jumps when it opens again', (tester) async {
      await recorder.start();
      for (final name in <String>['A one', 'B two', 'C three', 'D four']) {
        final s = await recorder.addExercise(name);
        for (var i = 0; i < 3; i++) {
          await recorder.addSet(s.exercises.last.id);
        }
      }
      await pump(tester);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -5000));
      await tester.pumpAndSettle();
      final thumb = tester.getCenter(find.text('D four'));

      // Folding takes most of the last card away. A list scrolled to its
      // end that got shorter would scroll back, and carry the card off.
      final gesture = await tester.startGesture(thumb);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        tester.getCenter(find.text('D four').last).dy,
        moreOrLessEquals(thumb.dy, epsilon: 1),
      );

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(find.text('D four')).dy,
        moreOrLessEquals(thumb.dy, epsilon: 1),
        reason: 'opened again where it was, with the list where it was',
      );
    });

    testWidgets('a folded movement is held anywhere on its line', (
      tester,
    ) async {
      await seed(<String>['Bench press', 'Incline press']);
      for (final s in (await recorder.current())!.exercises.first.sets) {
        await recorder.updateSet(s.id, isCompleted: true);
      }
      await pump(tester);
      // Folded, it reads as its summary — held there, not on its name.
      final line = find.text('2 sets · 100 kg × 5');
      expect(line, findsOneWidget);

      final down = tester.getSize(card(1)).height;
      await holdAndDrag(tester, line, Offset(0, down));

      expect(await storedOrder(), <String>['Incline press', 'Bench press']);
    });

    testWidgets('a tap is still a tap: a number takes the keyboard and the '
        'name opens its stats', (tester) async {
      await seed(<String>['Bench press', 'Incline press']);
      await pump(tester);
      final weight = (await recorder.current())!.exercises[1].sets.first;

      await tester.tap(
        find
            .descendant(of: card(1), matching: find.byType(SetNumberField))
            .first,
      );
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        '${weight.id}:weight',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Incline press'));
      await tester.pumpAndSettle();
      expect(find.byType(ExerciseStatsScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(await storedOrder(), <String>['Bench press', 'Incline press']);
    });

    testWidgets("held on a set's number, nothing lifts", (tester) async {
      await seed(<String>['Bench press', 'Incline press']);
      await pump(tester);
      final haptics = recordHaptics(tester);

      // A thumb resting on the weight while deciding what to type, then
      // moving: the list scrolls, and no card comes with it.
      final up = tester.getTopLeft(card(0)).dy - tester.getTopLeft(card(1)).dy;
      await holdAndDrag(
        tester,
        find
            .descendant(of: card(1), matching: find.byType(SetNumberField))
            .first,
        Offset(0, up),
        hold: const Duration(seconds: 1),
      );

      expect(await storedOrder(), <String>['Bench press', 'Incline press']);
      expect(haptics, isEmpty);
    });

    testWidgets("holding a set's label still opens its menu", (tester) async {
      await seed(<String>['Bench press', 'Incline press']);
      await pump(tester);

      await tester.longPress(
        find
            .descendant(
              of: find.descendant(of: card(1), matching: find.byType(SetRow)),
              matching: find.text('1'),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Warm-up'), findsOneWidget);
      expect(await storedOrder(), <String>['Bench press', 'Incline press']);
    });

    testWidgets("a screen reader moves it with the list's own actions", (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await seed(<String>['Bench press', 'Incline press']);
      await pump(tester);

      // The list gives every card Move up, Move down, Move to the start and
      // Move to the end. Only the first card can move down.
      const moveDown = CustomSemanticsAction(label: 'Move down');
      final id = CustomSemanticsAction.getIdentifier(moveDown);
      tester.semantics.customAction(
        find.semantics.byPredicate(
          (node) =>
              node.getSemanticsData().customSemanticsActionIds?.contains(id) ??
              false,
        ),
        moveDown,
      );
      await tester.pumpAndSettle();

      expect(await storedOrder(), <String>['Incline press', 'Bench press']);
      semantics.dispose();
    });

    testWidgets('the button and its sheet are gone', (tester) async {
      await seed(<String>['Bench press', 'Incline press']);
      await pump(tester);
      await tester.scrollUntilVisible(
        find.text('Discard session'),
        200,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first,
      );
      expect(find.text('Reorder movements'), findsNothing);
      expect(find.byIcon(Icons.swap_vert), findsNothing);
    });

    testWidgets('one movement has nothing to hold', (tester) async {
      await seed(<String>['Bench press']);
      await pump(tester);
      expect(find.byType(ReorderableDelayedDragStartListener), findsNothing);

      final haptics = recordHaptics(tester);
      await holdAndDrag(tester, find.text('Bench press'), const Offset(0, 200));
      expect(haptics, isEmpty, reason: 'nothing lifted');
      expect(await storedOrder(), <String>['Bench press']);
    });
  });

  testWidgets("a movement's name opens its stats, mid-session", (tester) async {
    await seed(<String>['Barbell Bench Press']);
    await pump(tester);

    await tester.tap(find.text('Barbell Bench Press'));
    await tester.pumpAndSettle();

    expect(find.byType(ExerciseStatsScreen), findsOneWidget);
    // Nothing from this session counts until it is finished.
    expect(find.textContaining('Nothing logged on this yet'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(ActiveSessionScreen), findsOneWidget);
  });
}
