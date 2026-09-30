import '../domain/workout_library.dart';
import '../domain/workout_template.dart';
import 'workout_templates.dart';

/// The ready-made workouts somebody is offered, and the only ones (R11).
///
/// The design review found the ready-made library confusing — eight splits
/// and fifteen sessions, with chips, in a sheet — and asked for far fewer
/// options, with the coach offering workouts instead of a catalogue. So three
/// starting points are shown, and only where one is needed: an empty library
/// and Track before anything is saved. The whole catalogue stays in
/// [workoutTemplates], as the coach's raw material.
///
/// Three because they cover the question a new lifter actually has — how many
/// days can you train? — at three, four and three-to-six: a whole body each
/// time, an upper/lower alternation, and push, pull, legs.
const List<String> starterSplitIds = <String>[
  'full-body',
  'upper-lower',
  'ppl',
];

/// The starters, in the order they are offered.
final List<WorkoutSplit> starterSplits = <WorkoutSplit>[
  for (final id in starterSplitIds)
    workoutSplits.firstWhere((WorkoutSplit s) => s.id == id),
];

/// The sessions a split is made of.
List<WorkoutTemplate> templatesOf(WorkoutSplit split) => <WorkoutTemplate>[
  for (final id in split.templateIds)
    workoutTemplates.firstWhere((WorkoutTemplate t) => t.id == id),
];

/// Adds a starter's sessions to the library, and returns what it added so the
/// caller can offer Undo.
///
/// Named so nothing collides with what is already saved — a second PPL adds
/// `Push (2)`, never a second `Push` — and each copy remembers the template it
/// came from, as any premade copy always has.
Future<List<SavedWorkout>> addStarter(
  WorkoutLibrary library,
  WorkoutSplit split,
) async {
  final taken = <String>{for (final w in await library.all()) w.name};
  final added = <SavedWorkout>[];
  for (final template in templatesOf(split)) {
    final name = uniqueWorkoutName(template.name, taken);
    added.add(
      await library.save(
        name: name,
        movements: <TemplateMovement>[
          for (final m in template.exercises) TemplateMovement(m),
        ],
        fromPremade: template.id,
      ),
    );
    taken.add(name);
  }
  return added;
}
