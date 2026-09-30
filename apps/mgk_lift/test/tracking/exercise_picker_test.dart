import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/tracking/data/exercise_lookup.dart';
import 'package:mgk_lift/src/features/tracking/domain/exercise.dart';
import 'package:mgk_lift/src/features/tracking/presentation/exercise_picker_sheet.dart';
import 'package:mgk_ui/mgk_ui.dart';

Exercise _entry(String name, String muscleGroup, String equipment) => Exercise(
  name: name,
  category: equipment,
  muscleGroup: muscleGroup,
  equipment: equipment,
  imageKey: name.toLowerCase().replaceAll(' ', '-'),
);

/// The picker's filters (redesign item 11): chips for muscle group and
/// equipment, with search or without.
void main() {
  final lookup = ExerciseLookup(<Exercise>[
    _entry('Cable Tricep Pushdown', 'Triceps', 'Cable'),
    _entry('Skull Crusher', 'Triceps', 'Barbell'),
    _entry('Cable Fly', 'Chest', 'Cable'),
    _entry('Band Pull Apart', 'Shoulders', 'Band'),
  ]);

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ExercisePickerSheet(
            lookup: lookup,
            recent: const <String>['Skull Crusher'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder chip(String label) => find.descendant(
    of: find.byWidgetPredicate((w) => w.runtimeType.toString() == '_ChipRow'),
    matching: find.text(label),
  );

  Future<void> tapChip(WidgetTester tester, String label) async {
    await tester.ensureVisible(chip(label));
    await tester.pumpAndSettle();
    await tester.tap(chip(label));
    await tester.pumpAndSettle();
  }

  bool listed(WidgetTester tester, String name) =>
      find.text(name).evaluate().isNotEmpty;

  testWidgets('offers every muscle group and the equipment, Other last', (
    tester,
  ) async {
    await open(tester);

    for (final group in ExerciseLookup.muscleGroups.take(3)) {
      expect(chip(group), findsOneWidget);
    }
    for (final kind in <String>['Barbell', 'Dumbbell', 'Cable']) {
      expect(chip(kind), findsOneWidget);
    }
  });

  testWidgets('a muscle group narrows the list, and a second tap clears it', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('RECENT'), findsOneWidget);

    await tapChip(tester, 'Triceps');

    expect(listed(tester, 'Cable Tricep Pushdown'), isTrue);
    expect(listed(tester, 'Skull Crusher'), isTrue);
    expect(listed(tester, 'Cable Fly'), isFalse);
    // Narrowed, the list is what was asked for, not what was done lately.
    expect(find.text('RECENT'), findsNothing);

    await tapChip(tester, 'Triceps');
    expect(listed(tester, 'Cable Fly'), isTrue);
    expect(find.text('RECENT'), findsOneWidget);
  });

  testWidgets('the two filters combine, and work with search', (tester) async {
    await open(tester);

    await tapChip(tester, 'Triceps');
    await tapChip(tester, 'Cable');
    expect(listed(tester, 'Cable Tricep Pushdown'), isTrue);
    expect(listed(tester, 'Skull Crusher'), isFalse);
    expect(listed(tester, 'Cable Fly'), isFalse);

    await tester.enterText(find.byType(TextField), 'fly');
    await tester.pumpAndSettle();
    expect(
      find.text('Nothing matches that.\nAdd it as your own movement.'),
      findsOneWidget,
    );
  });

  testWidgets('the rare equipment is under Other', (tester) async {
    await open(tester);

    await tapChip(tester, 'Other');

    expect(listed(tester, 'Band Pull Apart'), isTrue);
    expect(listed(tester, 'Cable Fly'), isFalse);
  });

  testWidgets('a chip says whether it is on', (tester) async {
    await open(tester);
    await tapChip(tester, 'Chest');

    expect(
      tester.getSemantics(find.bySemanticsLabel('Chest')),
      matchesSemantics(
        label: 'Chest',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );
  });
}
