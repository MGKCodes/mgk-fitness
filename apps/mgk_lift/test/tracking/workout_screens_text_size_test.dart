import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/tracking/data/exercise_lookup.dart';
import 'package:mgk_lift/src/features/tracking/domain/exercise.dart';
import 'package:mgk_lift/src/features/tracking/domain/workout_library.dart';
import 'package:mgk_lift/src/features/tracking/presentation/track_surface.dart';
import 'package:mgk_lift/src/features/tracking/presentation/workout_editor_screen.dart';
import 'package:mgk_lift/src/features/tracking/presentation/workout_library_screen.dart';

/// The workout screens on the narrowest phone the app supports, with the text
/// turned up. A fixed-height card on Track overflowed the first time this was
/// tried; an overflow fails these tests.
void main() {
  final lookup = ExerciseLookup(const <Exercise>[]);

  final long = SavedWorkout(
    id: 'w',
    name: 'Upper body, heavy, the long version',
    movements: const <TemplateMovement>[
      TemplateMovement('Barbell Bench Press', sets: 5, repTarget: 5),
      TemplateMovement('Single-Arm Cable Lateral Raise (Behind The Back)'),
      TemplateMovement('Weighted Pull-Up', sets: 20, repTarget: 200),
    ],
    savedAt: DateTime(2026, 9, 1),
  );

  for (final scale in <double>[1.3, 2.0]) {
    group('text at ${scale}x, 375pt wide', () {
      Future<void> pump(WidgetTester tester, Widget child) async {
        tester.view
          ..physicalSize = const Size(375 * 3, 812 * 3)
          ..devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: child,
          ),
        );
        await tester.pumpAndSettle();
      }

      testWidgets('Track, with workouts', (tester) async {
        await pump(
          tester,
          Scaffold(
            body: TrackSurface(
              today: DateTime(2026, 9, 29),
              workouts: <SavedWorkout>[
                long,
                long.copyWith(name: 'Legs'),
              ],
              onOpenLibrary: () {},
              onStartWorkout: (_) {},
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('the library', (tester) async {
        final library = InMemoryWorkoutLibrary();
        await library.save(name: long.name, movements: long.movements);
        await pump(
          tester,
          WorkoutLibraryScreen(library: library, lookup: lookup),
        );
        expect(tester.takeException(), isNull);
      });

      // The row opened to every movement — where the preview's list went.
      testWidgets('the library, a row open', (tester) async {
        final library = InMemoryWorkoutLibrary();
        final saved = await library.save(
          name: long.name,
          movements: long.movements,
        );
        await pump(
          tester,
          WorkoutLibraryScreen(
            library: library,
            lookup: lookup,
            openAt: saved.id,
          ),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('the library, empty: the starters', (tester) async {
        await pump(
          tester,
          WorkoutLibraryScreen(
            library: InMemoryWorkoutLibrary(),
            lookup: lookup,
          ),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('the editor', (tester) async {
        await pump(
          tester,
          WorkoutEditorScreen(
            library: InMemoryWorkoutLibrary(),
            lookup: lookup,
            workout: long,
          ),
        );
        expect(tester.takeException(), isNull);
      });
    });
  }
}
