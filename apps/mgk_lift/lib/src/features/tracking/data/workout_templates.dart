// GENERATED from Liftio's constants/PremadeWorkouts.ts and WorkoutSplits.ts on
// 2026-08-06.
//
// 15 ready-made sessions and 8 weekly splits. Ported rather than rewritten:
// these are ordinary, well-understood programmes, and inventing new ones would
// be change for its own sake.
//
// **All fifteen are the coach's raw material; six are the picker's menu.** The
// coach composes from the whole set — it knows what a push day contains and in
// what order, so it never invents a session from nothing — while the picker
// offers only the six that answer "what should I do today" for somebody who has
// just opened a tracker. See `offeredTemplates` at the foot of this file. That
// is a display rule and not a tier: tracking is free and stays free.
//
// Edit directly. There is no generator to re-run — the source is a frozen repo,
// and from here these evolve with Lift.
//
// Two cross-references hold, and workout_templates_test.dart asserts both so
// an edit cannot break them silently:
//
//   * every split's templateIds resolve to a template here;
//   * every template's exercise names resolve to the 266-entry catalogue, so a
//     templated session always arrives with form images and muscle groups.

import '../domain/workout_template.dart';

const List<WorkoutTemplate> workoutTemplates = <WorkoutTemplate>[
  WorkoutTemplate(
    id: 'push',
    offered: true,
    name: 'Push',
    description: 'Chest, shoulders & triceps',
    exercises: <String>[
      'Barbell Bench Press',
      'Barbell Incline Bench Press',
      'Dumbbell Shoulder Press',
      'Cable Fly',
      'Dumbbell Lateral Raise',
      'Cable Tricep Pushdown',
    ],
  ),
  WorkoutTemplate(
    id: 'pull',
    offered: true,
    name: 'Pull',
    description: 'Back & biceps',
    exercises: <String>[
      'Barbell Deadlift',
      'Barbell Row',
      'Wide Grip Lat Pull Down',
      'Cable Row',
      'Dumbbell Bicep Curl',
      'Dumbbell Rear Delt Fly',
    ],
  ),
  WorkoutTemplate(
    id: 'legs',
    offered: true,
    name: 'Legs',
    description: 'Quads, hamstrings & calves',
    exercises: <String>[
      'Barbell Back Squat',
      'Barbell Romanian Deadlift',
      'Leg Press',
      'Leg Curl',
      'Leg Extension',
      'Calf Raise Machine',
    ],
  ),
  WorkoutTemplate(
    id: 'upper',
    offered: true,
    name: 'Upper Body',
    description: 'Chest, back, shoulders & arms',
    exercises: <String>[
      'Barbell Bench Press',
      'Barbell Overhead Press',
      'Barbell Row',
      'Wide Grip Lat Pull Down',
      'Dumbbell Lateral Raise',
      'EZ Bar Curl',
      'Cable Tricep Pushdown',
    ],
  ),
  WorkoutTemplate(
    id: 'lower',
    offered: true,
    name: 'Lower Body',
    description: 'Quads, glutes, hamstrings & calves',
    exercises: <String>[
      'Barbell Back Squat',
      'Barbell Romanian Deadlift',
      'Barbell Hip Thrust',
      'Leg Press',
      'Leg Curl',
      'Calf Raise Machine',
    ],
  ),
  WorkoutTemplate(
    id: 'full-body',
    offered: true,
    name: 'Full Body',
    description: 'All major muscle groups',
    exercises: <String>[
      'Barbell Back Squat',
      'Barbell Bench Press',
      'Barbell Row',
      'Barbell Overhead Press',
      'Barbell Romanian Deadlift',
      'Dumbbell Bicep Curl',
      'Cable Tricep Pushdown',
    ],
  ),
  WorkoutTemplate(
    id: 'chest-triceps',
    name: 'Chest & Triceps',
    description: 'Pressing & tricep isolation',
    exercises: <String>[
      'Barbell Bench Press',
      'Dumbbell Incline Bench Press',
      'Cable Fly',
      'Dip',
      'Cable Tricep Pushdown',
      'Dumbbell Skull Crusher',
    ],
  ),
  WorkoutTemplate(
    id: 'back-biceps',
    name: 'Back & Biceps',
    description: 'Pulling & bicep isolation',
    exercises: <String>[
      'Barbell Deadlift',
      'Wide Grip Lat Pull Down',
      'Dumbbell Row',
      'Cable Row',
      'EZ Bar Curl',
      'Dumbbell Hammer Curl',
    ],
  ),
  WorkoutTemplate(
    id: 'shoulders-arms',
    name: 'Shoulders & Arms',
    description: 'Delts, biceps & triceps',
    exercises: <String>[
      'Barbell Overhead Press',
      'Dumbbell Lateral Raise',
      'Dumbbell Rear Delt Fly',
      'Barbell Curl',
      'Cable Tricep Pushdown',
      'EZ Bar Skull Crusher',
    ],
  ),
  WorkoutTemplate(
    id: 'glutes-hamstrings',
    name: 'Glutes & Hamstrings',
    description: 'Posterior chain focus',
    exercises: <String>[
      'Barbell Hip Thrust',
      'Barbell Romanian Deadlift',
      'Dumbbell Goblet Squat',
      'Leg Curl',
      'Dumbbell Lunge',
      'Hip Abductor Machine',
    ],
  ),
  WorkoutTemplate(
    id: 'chest-back',
    name: 'Chest & Back',
    description: 'Pressing & pulling supersets',
    exercises: <String>[
      'Barbell Bench Press',
      'Barbell Row',
      'Barbell Incline Bench Press',
      'Wide Grip Lat Pull Down',
      'Cable Fly',
      'Cable Row',
    ],
  ),
  WorkoutTemplate(
    id: 'shoulders',
    name: 'Shoulders',
    description: 'Delt-focused pressing & raises',
    exercises: <String>[
      'Barbell Overhead Press',
      'Dumbbell Shoulder Press',
      'Dumbbell Lateral Raise',
      'Dumbbell Rear Delt Fly',
      'Barbell Shrug',
    ],
  ),
  WorkoutTemplate(
    id: 'arms',
    name: 'Arms',
    description: 'Biceps & triceps isolation',
    exercises: <String>[
      'Barbell Curl',
      'EZ Bar Skull Crusher',
      'Dumbbell Hammer Curl',
      'Cable Tricep Pushdown',
      'Dumbbell Bicep Curl',
      'Dip',
    ],
  ),
  WorkoutTemplate(
    id: 'upper-power',
    name: 'Upper Power',
    description: 'Low-rep upper body compounds',
    exercises: <String>[
      'Barbell Bench Press',
      'Barbell Row',
      'Barbell Overhead Press',
      'Wide Grip Lat Pull Down',
      'EZ Bar Curl',
      'Cable Tricep Pushdown',
    ],
  ),
  WorkoutTemplate(
    id: 'lower-power',
    name: 'Lower Power',
    description: 'Low-rep lower body compounds',
    exercises: <String>[
      'Barbell Back Squat',
      'Barbell Deadlift',
      'Leg Press',
      'Leg Curl',
      'Calf Raise Machine',
    ],
  ),
];

const List<WorkoutSplit> workoutSplits = <WorkoutSplit>[
  WorkoutSplit(
    id: 'ppl',
    name: 'PPL',
    description: 'Push · Pull · Legs',
    templateIds: <String>['push', 'pull', 'legs'],
    daysPerWeek: 3,
    image: 'assets/images/splits/ppl.webp',
  ),
  WorkoutSplit(
    id: 'upper-lower',
    name: 'Upper / Lower',
    description: 'Upper · Lower',
    templateIds: <String>['upper', 'lower'],
    daysPerWeek: 4,
    image: 'assets/images/splits/upper-lower.webp',
  ),
  WorkoutSplit(
    id: 'arnold',
    name: 'Arnold',
    description: 'Chest & Back · Shoulders & Arms · Legs',
    templateIds: <String>['chest-back', 'shoulders-arms', 'legs'],
    daysPerWeek: 6,
    image: 'assets/images/splits/arnold.webp',
  ),
  WorkoutSplit(
    id: 'body-part-4',
    name: '4-Day Body Part',
    description: 'Chest · Back · Shoulders · Legs',
    templateIds: <String>['chest-triceps', 'back-biceps', 'shoulders', 'legs'],
    daysPerWeek: 4,
    image: 'assets/images/splits/body-part-4.webp',
  ),
  WorkoutSplit(
    id: 'full-body',
    name: 'Full Body',
    description: 'Full Body',
    templateIds: <String>['full-body'],
    daysPerWeek: 3,
    image: 'assets/images/splits/full-body.webp',
  ),
  WorkoutSplit(
    id: 'body-part',
    name: 'Body Part',
    description: 'Chest · Back · Shoulders · Arms · Legs',
    templateIds: <String>[
      'chest-triceps',
      'back-biceps',
      'shoulders',
      'arms',
      'legs',
    ],
    daysPerWeek: 5,
    image: 'assets/images/splits/body-part.webp',
  ),
  WorkoutSplit(
    id: 'upper-lower-ppl',
    name: 'Upper / Lower + PPL',
    description: 'Upper · Lower · Push · Pull · Legs',
    templateIds: <String>['upper', 'lower', 'push', 'pull', 'legs'],
    daysPerWeek: 5,
    image: 'assets/images/splits/upper-lower-ppl.webp',
  ),
  WorkoutSplit(
    id: 'phul',
    name: 'Power / Hypertrophy',
    description: 'Upper Power · Lower Power · Upper · Lower',
    templateIds: <String>['upper-power', 'lower-power', 'upper', 'lower'],
    daysPerWeek: 4,
    image: 'assets/images/splits/phul.webp',
  ),
];

/// The templates the picker offers — the six that answer "what should I do
/// today" for somebody with no plan.
///
/// [workoutTemplates] stays whole. The other nine are body-part sessions for a
/// lifter who already knows what they are doing, and they are what the coach
/// composes from rather than something withheld to sell it.
final List<WorkoutTemplate> offeredTemplates = workoutTemplates
    .where((WorkoutTemplate t) => t.offered)
    .toList(growable: false);

/// The splits the picker offers, **derived rather than listed**.
///
/// A split is offered when every template it references is. Keeping a second
/// hand-written list is how you end up offering a split whose Tuesday opens a
/// session that is no longer in the picker — and that failure looks like a bug
/// in the picker rather than a stale constant.
final List<WorkoutSplit> offeredSplits = workoutSplits
    .where(
      (WorkoutSplit s) => s.templateIds.every(
        (String id) => offeredTemplates.any((WorkoutTemplate t) => t.id == id),
      ),
    )
    .toList(growable: false);
