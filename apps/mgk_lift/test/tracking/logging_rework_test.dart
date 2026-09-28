import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/core/database/app_database.dart';
import 'package:mgk_lift/src/features/tracking/data/drift_session_recorder.dart';
import 'package:mgk_lift/src/features/tracking/domain/session.dart';
import 'package:mgk_lift/src/features/tracking/presentation/active_session_screen.dart';
// Prefixed: drift generates its own `SetRow` for the sets table.
import 'package:mgk_lift/src/features/tracking/presentation/exercise_card.dart'
    as card;
import 'package:mgk_lift/src/features/tracking/presentation/finish_sheet.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

/// The session screen after the 2026-09-28 audit: typing, the keyboard,
/// removal, the Finish sheet and the limits. Every test here describes a
/// behaviour the screen did not have, or had wrong.
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

  /// The screen over whatever session is open. [keyboard] stands in for the
  /// keyboard's height, which a widget test does not otherwise have.
  Future<Widget> screen({
    MassUnit unit = MassUnit.kilograms,
    List<Session> log = const <Session>[],
    double keyboard = 0,
  }) async {
    final session = await recorder.current() ?? await recorder.start();
    return MaterialApp(
      theme: AppTheme.dark,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(viewInsets: EdgeInsets.only(bottom: keyboard)),
          child: ActiveSessionScreen(
            recorder: recorder,
            session: session,
            massUnit: unit,
            log: log,
          ),
        ),
      ),
    );
  }

  /// Bench press with one set per entry of [sets] — `(reps, kg, done)`.
  Future<List<SessionSet>> bench(List<(int, double, bool)> sets) async {
    await recorder.start();
    final ex = (await recorder.addExercise(
      'Barbell Bench Press',
    )).exercises.single.id;
    for (final (reps, kg, done) in sets) {
      final s = await recorder.addSet(ex);
      final id = s.exercises.single.sets.last.id;
      await recorder.updateSet(id, reps: reps, weightKg: kg, isCompleted: done);
    }
    return (await recorder.current())!.exercises.single.sets;
  }

  Future<List<SetRow>> storedSets() => db.select(db.exerciseSets).get();

  Future<void> leaveField(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
  }

  group('typing', () {
    testWidgets('a number is saved when the field is left, not per keystroke', (
      tester,
    ) async {
      await bench(<(int, double, bool)>[(0, 0, false)]);
      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '102.5');
      await tester.pump();
      // Still typing: nothing written. It used to be a write and two full
      // reads of the session per keystroke.
      expect((await storedSets()).single.weightKg, 0);

      await leaveField(tester);
      expect((await storedSets()).single.weightKg, 102.5);
    });

    testWidgets('a tap anywhere else puts the keyboard away, and saves', (
      tester,
    ) async {
      await bench(<(int, double, bool)>[(0, 0, false)]);
      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '60');
      // A finger cannot tap elsewhere in the same frame the field took focus.
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      // The session's name, well away from every field.
      await tester.tapAt(tester.getCenter(find.text('IN PROGRESS')));
      await tester.pumpAndSettle();

      // The iOS number pad has no key for this, and Flutter does not do it on
      // a phone by default: before, only leaving the screen closed it.
      expect(tester.testTextInput.isVisible, isFalse);
      expect((await storedSets()).single.weightKg, 60);
    });

    testWidgets('a comma is a decimal point', (tester) async {
      await bench(<(int, double, bool)>[(0, 0, false)]);
      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();

      // Measured before: the comma was dropped and 102,5 saved as 1,025 kg.
      await tester.enterText(find.byType(TextField).first, '102,5');
      await leaveField(tester);
      expect((await storedSets()).single.weightKg, 102.5);
    });

    testWidgets('reps take whole numbers only, up to the limit', (
      tester,
    ) async {
      await bench(<(int, double, bool)>[(0, 60, false)]);
      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();
      final reps = find.byType(TextField).at(1);

      // Measured before: "8.5" saved as 0 reps.
      await tester.enterText(reps, '8.5');
      await tester.pump();
      expect(find.widgetWithText(TextField, '8.5'), findsNothing);

      await tester.enterText(reps, '201');
      await tester.pump();
      expect(find.widgetWithText(TextField, '201'), findsNothing);
      expect(find.text('Reps stop at 200.'), findsOneWidget);

      await tester.enterText(reps, '200');
      await leaveField(tester);
      expect((await storedSets()).single.reps, 200);
    });

    testWidgets('a weight past the limit is refused, in the lifter\'s unit', (
      tester,
    ) async {
      await bench(<(int, double, bool)>[(5, 0, false)]);
      await tester.pumpWidget(await screen(unit: MassUnit.pounds));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '2300');
      await tester.pump();
      expect(find.widgetWithText(TextField, '2300'), findsNothing);
      expect(find.textContaining('Weights stop at'), findsOneWidget);
    });
  });

  group('ticking', () {
    testWidgets('a tick needs reps', (tester) async {
      await bench(<(int, double, bool)>[(0, 60, false)]);
      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Mark done'));
      await tester.pumpAndSettle();

      // An empty set ticked is a logged set of nothing.
      expect((await storedSets()).single.isCompleted, isFalse);
      expect(find.text('Add the reps first.'), findsOneWidget);
    });

    testWidgets('the set to do next is the loud row; done ones recede', (
      tester,
    ) async {
      await bench(<(int, double, bool)>[(5, 80, true), (5, 80, false)]);
      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();

      final rows = tester
          .widgetList<card.SetRow>(find.byType(card.SetRow))
          .toList();
      // It was the other way round: done sets took the lighter fill.
      expect(rows[0].isNext, isFalse);
      expect(rows[1].isNext, isTrue);
    });
  });

  group('labels', () {
    testWidgets('a warm-up takes no number: W, 1, 2', (tester) async {
      final sets = await bench(<(int, double, bool)>[
        (10, 40, false),
        (5, 80, false),
        (5, 80, false),
      ]);
      await recorder.updateSet(sets.first.id, setType: SetType.warmup);
      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();

      final labels = <String>[
        for (final row in tester.widgetList<card.SetRow>(
          find.byType(card.SetRow),
        ))
          row.label,
      ];
      // Seen on the emulator before: W, 2, 3.
      expect(labels, <String>['W', '1', '2']);
    });
  });

  group('removing', () {
    testWidgets('a swipe that starts over a number removes the set; Undo '
        'puts it back', (tester) async {
      final sets = await bench(<(int, double, bool)>[
        (5, 80, false),
        (5, 80, false),
      ]);
      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();

      // From over the weight field — which a TextField used to swallow, so the
      // swipe only worked from the 28px label column.
      await tester.drag(find.byType(TextField).first, const Offset(-600, 0));
      await tester.pumpAndSettle();
      expect(await storedSets(), hasLength(1));

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      final back = await storedSets();
      expect(back, hasLength(2));
      expect(back.map((s) => s.id), contains(sets.first.id));
    });

    testWidgets('holding the label opens the set menu', (tester) async {
      await bench(<(int, double, bool)>[(5, 80, false), (5, 80, false)]);
      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();

      await tester.longPress(
        find.descendant(
          of: find.byType(card.SetRow).first,
          matching: find.text('1'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Warm-up'), findsOneWidget);

      await tester.tap(find.text('Remove set'));
      await tester.pumpAndSettle();
      expect(await storedSets(), hasLength(1));
    });

    testWidgets('a movement with logged sets asks before it goes', (
      tester,
    ) async {
      await bench(<(int, double, bool)>[(5, 80, true), (5, 80, false)]);
      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remove Barbell Bench Press'));
      await tester.pumpAndSettle();
      expect(find.text('Remove Barbell Bench Press?'), findsOneWidget);
      expect(find.text('Its 1 logged set goes with it.'), findsOneWidget);

      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      expect(await db.select(db.exercises).get(), hasLength(1));

      await tester.tap(find.byTooltip('Remove Barbell Bench Press'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(await db.select(db.exercises).get(), isEmpty);
    });

    testWidgets('a movement with nothing logged goes at once, with Undo', (
      tester,
    ) async {
      await bench(<(int, double, bool)>[(5, 80, false)]);
      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remove Barbell Bench Press'));
      await tester.pumpAndSettle();
      expect(await db.select(db.exercises).get(), isEmpty);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(await db.select(db.exercises).get(), hasLength(1));
      expect(await storedSets(), hasLength(1));
    });
  });

  group('finishing', () {
    testWidgets('the sheet says what will not be saved, and then drops it', (
      tester,
    ) async {
      await bench(<(int, double, bool)>[(5, 80, true), (5, 80, false)]);
      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Finish'));
      await tester.pumpAndSettle();
      expect(find.byType(FinishSheet), findsOneWidget);
      expect(
        find.text("1 set isn't ticked, so it won't be saved."),
        findsOneWidget,
      );

      await tester.tap(
        find.descendant(
          of: find.byType(FinishSheet),
          matching: find.widgetWithText(FilledButton, 'Finish'),
        ),
      );
      await tester.pumpAndSettle();

      final sets = await storedSets();
      expect(sets, hasLength(1));
      expect(sets.single.isCompleted, isTrue);
    });

    testWidgets('it also says which movements have nothing logged', (
      tester,
    ) async {
      await bench(<(int, double, bool)>[(5, 80, true)]);
      await recorder.addExercise('Cable Fly');
      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Finish'));
      await tester.pumpAndSettle();

      // Seen on the emulator: movements added and never started went without
      // a word, while a single unticked set was called out.
      expect(
        find.text("1 movement has nothing logged, so it won't be kept."),
        findsOneWidget,
      );
      expect(find.textContaining('1 movement'), findsWidgets);
    });

    testWidgets('keep going changes nothing', (tester) async {
      await bench(<(int, double, bool)>[(5, 80, true)]);
      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Finish'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep going'));
      await tester.pumpAndSettle();

      expect(await recorder.current(), isNotNull, reason: 'still open');
    });
  });

  group('limits', () {
    testWidgets('the twenty-first set cannot be added, and the card says why', (
      tester,
    ) async {
      await bench(<(int, double, bool)>[
        for (var i = 0; i < SessionLimits.setsPerMovement; i++) (5, 80, false),
      ]);
      await tester.pumpWidget(await screen());
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('20 sets is the most one movement holds.'),
        300,
        // The list's own; every number field has a Scrollable inside it too.
        scrollable: find.byType(Scrollable).first,
      );

      final add = tester.widget<AppTextButton>(
        find.widgetWithText(AppTextButton, 'Add set'),
      );
      expect(add.onPressed, isNull);
    });
  });

  group('the first set', () {
    testWidgets('starts from what was lifted last time', (tester) async {
      final lastWeek = Session(
        id: 'last',
        name: 'Push',
        startedAt: DateTime(2026, 9, 21),
        endedAt: DateTime(2026, 9, 21, 1),
        exercises: const <SessionExercise>[
          SessionExercise(
            id: 'e',
            name: 'Barbell Bench Press',
            orderIndex: 0,
            sets: <SessionSet>[
              SessionSet(
                id: 's',
                setNumber: 1,
                reps: 8,
                weightKg: 80,
                isCompleted: true,
              ),
            ],
          ),
        ],
      );
      await recorder.start();
      await recorder.addExercise('Barbell Bench Press');
      await tester.pumpWidget(await screen(log: <Session>[lastWeek]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add first set'));
      await tester.pumpAndSettle();

      // It started at 0 × 0 while "Last time · 80 kg × 8" sat above it.
      final set = (await storedSets()).single;
      expect(set.weightKg, 80);
      expect(set.reps, 8);
      expect(set.isCompleted, isFalse, reason: 'prefilled, not logged');
    });
  });

  group('the keyboard bar', () {
    testWidgets('moves between fields and logs the set', (tester) async {
      await bench(<(int, double, bool)>[(0, 85, false), (0, 85, false)]);
      await tester.pumpWidget(await screen(keyboard: 300));
      await tester.pumpAndSettle();

      await tester.showKeyboard(find.byType(TextField).first);
      await tester.pumpAndSettle();
      expect(find.text('Log set'), findsOneWidget);

      await tester.tap(find.byTooltip('Next field'));
      await tester.pumpAndSettle();
      tester.testTextInput.enterText('6');
      await tester.pump();

      await tester.tap(find.text('Log set'));
      await tester.pumpAndSettle();

      final first = (await storedSets()).firstWhere((s) => s.setNumber == 1);
      expect(first.reps, 6);
      expect(first.isCompleted, isTrue);
    });

    testWidgets('Done closes the keyboard', (tester) async {
      await bench(<(int, double, bool)>[(0, 85, false)]);
      await tester.pumpWidget(await screen(keyboard: 300));
      await tester.pumpAndSettle();

      await tester.showKeyboard(find.byType(TextField).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(
        FocusManager.instance.primaryFocus?.context?.widget,
        isNot(isA<EditableText>()),
      );
      expect(find.text('Log set'), findsNothing);
    });
  });
}
