import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/tracking/data/exercise_lookup.dart';
import 'package:mgk_lift/src/features/tracking/domain/exercise.dart';
import 'package:mgk_lift/src/features/tracking/domain/session.dart';
import 'package:mgk_lift/src/features/tracking/domain/workout_library.dart';
import 'package:mgk_lift/src/features/tracking/presentation/workout_editor_screen.dart';

final ExerciseLookup _lookup = ExerciseLookup(<Exercise>[
  const Exercise(
    name: 'Barbell Bench Press',
    category: 'Barbell',
    muscleGroup: 'Chest',
    equipment: 'Barbell',
    imageKey: 'barbell-bench-press',
  ),
  const Exercise(
    name: 'Cable Fly',
    category: 'Cable',
    muscleGroup: 'Chest',
    equipment: 'Cable',
    imageKey: 'cable-fly',
  ),
]);

void main() {
  late InMemoryWorkoutLibrary library;

  setUp(() => library = InMemoryWorkoutLibrary());

  /// The editor, pushed over a page it can pop back to — its back arrow and
  /// its Save both leave.
  Future<void> open(WidgetTester tester, {SavedWorkout? workout}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push<SavedWorkout>(
                  MaterialPageRoute<SavedWorkout>(
                    builder: (_) => WorkoutEditorScreen(
                      library: library,
                      lookup: _lookup,
                      workout: workout,
                    ),
                  ),
                ),
                child: const Text('under'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('under'));
    await tester.pumpAndSettle();
  }

  FilledButton saveButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));

  Future<SavedWorkout> push() => library.save(
    name: 'Push',
    movements: const <TemplateMovement>[
      TemplateMovement('Barbell Bench Press', sets: 4, repTarget: 6),
      TemplateMovement('Cable Fly'),
    ],
  );

  testWidgets('Save waits for a name and a movement', (tester) async {
    await open(tester);
    expect(find.text('New workout'), findsOneWidget);
    expect(saveButton(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, 'Push');
    await tester.pump();
    // A name and nothing in it would start an empty session.
    expect(saveButton(tester).onPressed, isNull);

    await tester.tap(find.text('Add movements'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cable Fly'));
    await tester.pump();
    await tester.tap(find.text('Add 1 movement'));
    await tester.pumpAndSettle();

    expect(saveButton(tester).onPressed, isNotNull);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final saved = (await library.all()).single;
    expect(saved.name, 'Push');
    expect(saved.movements, const <TemplateMovement>[
      TemplateMovement('Cable Fly'),
    ]);
    expect(find.text('under'), findsOneWidget, reason: 'Save leaves');
  });

  testWidgets('a name of spaces is not a name', (tester) async {
    await open(tester, workout: await push());
    await tester.enterText(find.byType(TextField).first, '   ');
    await tester.pump();
    expect(saveButton(tester).onPressed, isNull);
  });

  testWidgets('the set count steps between 1 and 20', (tester) async {
    await library.save(
      name: 'Edge',
      movements: const <TemplateMovement>[
        TemplateMovement('Cable Fly', sets: 1),
        TemplateMovement('Barbell Bench Press', sets: 20),
      ],
    );
    await open(tester, workout: (await library.all()).single);

    IconButton button(String tooltip) => tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip(tooltip),
        matching: find.byType(IconButton),
      ),
    );

    // At the floor, fewer is off; at the ceiling, more is.
    expect(button('One fewer set of Cable Fly').onPressed, isNull);
    expect(button('One more set of Cable Fly').onPressed, isNotNull);
    expect(button('One more set of Barbell Bench Press').onPressed, isNull);
    expect(button('One fewer set of Barbell Bench Press').onPressed, isNotNull);

    await tester.tap(find.byTooltip('One more set of Cable Fly'));
    await tester.pump();
    await tester.tap(find.byTooltip('One fewer set of Barbell Bench Press'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect((await library.all()).single.movements.map((m) => m.sets), <int>[
      2,
      19,
    ]);
  });

  testWidgets('a rep target past 200 is refused, and blank means none', (
    tester,
  ) async {
    await open(tester, workout: await push());

    // Name, then one rep field per movement.
    final bench = find.byType(TextField).at(1);
    await tester.enterText(bench, '201');
    await tester.pump();
    // Refused, not clamped: the field keeps what it had.
    expect(find.widgetWithText(TextField, '201'), findsNothing);

    await tester.enterText(bench, '12');
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(2), '0');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(
      (await library.all()).single.movements.map((m) => m.repTarget),
      <int?>[12, null],
    );
  });

  testWidgets('removing a movement can be undone', (tester) async {
    await open(tester, workout: await push());

    await tester.tap(find.byTooltip('Remove Cable Fly'));
    await tester.pumpAndSettle();
    expect(find.text('Cable Fly'), findsNothing);

    await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Cable Fly'), findsOneWidget);
  });

  testWidgets('editing keeps the id and writes the changes', (tester) async {
    final saved = await push();
    await open(tester, workout: saved);
    expect(find.text('Edit workout'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Push, heavy');
    await tester.tap(find.byTooltip('Remove Cable Fly'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final edited = (await library.byId(saved.id))!;
    expect(edited.name, 'Push, heavy');
    expect(edited.movements, const <TemplateMovement>[
      TemplateMovement('Barbell Bench Press', sets: 4, repTarget: 6),
    ]);
  });

  group('leaving with changes', () {
    testWidgets('asks first, and Keep editing stays', (tester) async {
      await open(tester, workout: await push());
      await tester.tap(find.byTooltip('One more set of Cable Fly'));
      await tester.pump();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Edit workout'), findsOneWidget);
    });

    testWidgets('Discard leaves, and saves nothing', (tester) async {
      final saved = await push();
      await open(tester, workout: saved);
      await tester.tap(find.byTooltip('One more set of Cable Fly'));
      await tester.pump();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Discard'));
      await tester.pumpAndSettle();

      expect(find.text('under'), findsOneWidget);
      expect((await library.byId(saved.id))!.movements, saved.movements);
    });

    testWidgets('the system back asks too', (tester) async {
      await open(tester, workout: await push());
      await tester.tap(find.byTooltip('One more set of Cable Fly'));
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
    });

    testWidgets('with nothing changed, back just leaves', (tester) async {
      await open(tester, workout: await push());
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.text('under'), findsOneWidget);
    });
  });

  testWidgets('a full workout says so instead of offering more', (
    tester,
  ) async {
    await library.save(
      name: 'Everything',
      movements: <TemplateMovement>[
        for (var i = 0; i < SessionLimits.movements; i++)
          TemplateMovement('Movement $i'),
      ],
    );
    await open(tester, workout: (await library.all()).single);

    // `OutlinedButton.icon` is a private subclass, which `byType` does not
    // match — hence the predicate.
    expect(
      tester
          .widget<ButtonStyleButton>(
            find.ancestor(
              of: find.text('Add movements'),
              matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(
      find.text(
        '${SessionLimits.movements} movements is the most one workout '
        'holds.',
      ),
      findsOneWidget,
    );
  });
}
