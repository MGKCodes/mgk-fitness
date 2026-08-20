import 'standing_plan.dart';
import 'training_split.dart';

/// Builds a whole plan from the intake, deterministically.
///
/// ## Roles first, movements second
///
/// A day is a list of **roles** — horizontal press, vertical pull, hinge — and
/// the movement is whichever thing best fills that role with the equipment
/// somebody has. That ordering is what makes the plan survive contact with a
/// real gym: no cable machine swaps the movement and leaves the role alone, so
/// "your horizontal press has stalled" still means something afterwards.
///
/// ## Why this is not a model's job
///
/// Third time the same principle: the load rule became a schema property, the
/// split became arithmetic on the day count, and the shape of a week is a
/// template. A generated plan can be checked ([StandingPlanRules]) but a
/// template cannot be wrong in the first place, and `surfaces.ts` is explicit
/// that anything the coach lays out in prose is a second version of somebody's
/// training that nobody checked.
///
/// What the coach is still for is everything a template cannot know: what to do
/// about a sore shoulder, whether this week was enough, and which movement to
/// put in a slot that has stopped paying.
///
/// ## Volume
///
/// Each day carries five or six movements, which at three or four hard sets
/// apiece and two exposures a week lands each muscle group inside the 12–20
/// weekly sets the evidence points at. Six is the ceiling on purpose: a
/// seven-movement session is the one people quietly start cutting short, and a
/// plan somebody abandons has no volume at all.
abstract final class PlanTemplate {
  /// The roles each day of a split is made of, in the order they are trained.
  ///
  /// Compounds first, throughout. The movement that most needs a fresh nervous
  /// system is the one worth doing first, and it is also the one whose numbers
  /// the plan is measured in.
  static const Map<String, List<({String role, bool main})>> _days = {
    // ---- Upper / Lower ----
    'Upper': <({String role, bool main})>[
      (role: 'horizontal press', main: true),
      (role: 'vertical pull', main: true),
      (role: 'vertical press', main: false),
      (role: 'horizontal row', main: false),
      (role: 'lateral raise', main: false),
      (role: 'triceps', main: false),
    ],
    'Lower': <({String role, bool main})>[
      (role: 'squat', main: true),
      (role: 'hinge', main: true),
      (role: 'quad accessory', main: false),
      (role: 'hamstring accessory', main: false),
      (role: 'calf', main: false),
    ],
    // ---- Push / Pull / Legs ----
    'Push': <({String role, bool main})>[
      (role: 'horizontal press', main: true),
      (role: 'vertical press', main: false),
      (role: 'incline press', main: false),
      (role: 'lateral raise', main: false),
      (role: 'triceps', main: false),
    ],
    'Pull': <({String role, bool main})>[
      (role: 'vertical pull', main: true),
      (role: 'horizontal row', main: false),
      (role: 'rear delt', main: false),
      (role: 'biceps', main: false),
    ],
    'Legs': <({String role, bool main})>[
      (role: 'squat', main: true),
      (role: 'hinge', main: true),
      (role: 'quad accessory', main: false),
      (role: 'hamstring accessory', main: false),
      (role: 'calf', main: false),
    ],
    // ---- Full body ----
    //
    // Three variants rather than one repeated, so a two- or three-day week
    // still rotates its main lift instead of squatting heavy every session.
    'Full body A': <({String role, bool main})>[
      (role: 'squat', main: true),
      (role: 'horizontal press', main: true),
      (role: 'horizontal row', main: false),
      (role: 'hamstring accessory', main: false),
      (role: 'calf', main: false),
    ],
    'Full body B': <({String role, bool main})>[
      (role: 'hinge', main: true),
      (role: 'vertical press', main: true),
      (role: 'vertical pull', main: false),
      (role: 'quad accessory', main: false),
      (role: 'lateral raise', main: false),
    ],
    'Full body C': <({String role, bool main})>[
      (role: 'squat', main: true),
      (role: 'incline press', main: true),
      (role: 'horizontal row', main: false),
      (role: 'triceps', main: false),
      (role: 'biceps', main: false),
    ],
  };

  /// What fills a role, best first.
  ///
  /// **Every name here exists in `exerciseCatalogue`.** Checked rather than
  /// written from memory: half of a first draft did not — no "Lat Pulldown", no
  /// "Romanian Deadlift", no "Standing Calf Raise" — and a plan naming a
  /// movement the catalogue does not have renders a placeholder thumbnail and
  /// breaks the swap, which reads as the app being broken rather than as a
  /// typo.
  static const Map<String, List<({String movement, Equipment needs})>>
  _fills = {
    'horizontal press': <({String movement, Equipment needs})>[
      (movement: 'Barbell Bench Press', needs: Equipment.fullGym),
      (movement: 'Dumbbell Bench Press', needs: Equipment.homeWeights),
      (movement: 'Push-up', needs: Equipment.bodyweight),
    ],
    'incline press': <({String movement, Equipment needs})>[
      (movement: 'Incline Dumbbell Press', needs: Equipment.homeWeights),
      (movement: 'Chest Dips', needs: Equipment.bodyweight),
    ],
    'vertical press': <({String movement, Equipment needs})>[
      (movement: 'Barbell Overhead Press', needs: Equipment.fullGym),
      (movement: 'Dumbbell Shoulder Press', needs: Equipment.homeWeights),
    ],
    'vertical pull': <({String movement, Equipment needs})>[
      (movement: 'Wide Grip Lat Pull Down', needs: Equipment.fullGym),
      (movement: 'Pull-up', needs: Equipment.bodyweight),
    ],
    'horizontal row': <({String movement, Equipment needs})>[
      (movement: 'Barbell Row', needs: Equipment.fullGym),
      (movement: 'Cable Row', needs: Equipment.fullGym),
      (movement: 'Dumbbell Row', needs: Equipment.homeWeights),
      (movement: 'Body Row', needs: Equipment.bodyweight),
    ],
    'lateral raise': <({String movement, Equipment needs})>[
      (movement: 'Dumbbell Lateral Raise', needs: Equipment.homeWeights),
    ],
    'rear delt': <({String movement, Equipment needs})>[
      (
        movement: 'Lying One Arm Rear Lateral Raise',
        needs: Equipment.homeWeights,
      ),
    ],
    'triceps': <({String movement, Equipment needs})>[
      (movement: 'Cable Tricep Pushdown', needs: Equipment.fullGym),
      (movement: 'Bench Dips', needs: Equipment.bodyweight),
    ],
    'biceps': <({String movement, Equipment needs})>[
      (
        movement: 'Alternating Bicep Curl With Dumbbell',
        needs: Equipment.homeWeights,
      ),
      (movement: 'Chin-up', needs: Equipment.bodyweight),
    ],
    'squat': <({String movement, Equipment needs})>[
      (movement: 'Barbell Back Squat', needs: Equipment.fullGym),
      (movement: 'Barbell Lunges', needs: Equipment.homeWeights),
    ],
    'hinge': <({String movement, Equipment needs})>[
      (movement: 'Barbell Deadlift', needs: Equipment.fullGym),
      (movement: 'Barbell Romanian Deadlift', needs: Equipment.fullGym),
      (movement: 'Dumbbell Romanian Deadlift', needs: Equipment.homeWeights),
      (movement: 'Hyperextensions', needs: Equipment.bodyweight),
    ],
    'quad accessory': <({String movement, Equipment needs})>[
      (movement: 'Leg Press', needs: Equipment.fullGym),
      (movement: 'Barbell Lunges', needs: Equipment.homeWeights),
    ],
    'hamstring accessory': <({String movement, Equipment needs})>[
      (movement: 'Leg Curl', needs: Equipment.fullGym),
      (movement: 'Dumbbell Romanian Deadlift', needs: Equipment.homeWeights),
      (movement: 'Hyperextensions', needs: Equipment.bodyweight),
    ],
    'calf': <({String movement, Equipment needs})>[
      (movement: 'Calf Raise Machine', needs: Equipment.fullGym),
      (
        movement: 'Rocking Standing Calf Raise With Barbell',
        needs: Equipment.homeWeights,
      ),
      (movement: 'Donkey Calf Raises', needs: Equipment.bodyweight),
    ],
  };

  /// Builds every slot for a split.
  ///
  /// [avoid] is matched against the ROLE, not the movement — an intake that
  /// says "left shoulder on pressing" rules out overhead work whatever it is
  /// called this month, where matching movement names would rule out one
  /// barbell and leave the dumbbell version in.
  static Map<String, List<MovementSlot>> slotsFor({
    required TrainingSplit split,
    required int days,
    Equipment equipment = Equipment.fullGym,
    Set<String> avoid = const <String>{},
  }) {
    final out = <String, List<MovementSlot>>{};
    for (final day in split.weekFor(days).toSet()) {
      final roles = _days[day] ?? const <({String role, bool main})>[];
      final slots = <MovementSlot>[];
      for (final r in roles) {
        if (avoid.contains(r.role)) continue;
        final movement = _fill(r.role, equipment);
        if (movement == null) continue;
        slots.add(
          MovementSlot(
            id: '${day.toLowerCase().replaceAll(' ', '-')}-${r.role.replaceAll(' ', '-')}',
            role: r.role,
            movement: movement,
            isMain: r.main,
          ),
        );
      }
      out[day] = slots;
    }
    return out;
  }

  /// The best movement for a role that the equipment allows, or null when the
  /// role cannot be filled at all.
  ///
  /// **Dropping the slot is more honest than inventing one**, and the gaps are
  /// real: the 266-movement catalogue has no bodyweight squat, no pike push-up
  /// and no glute bridge, so a bodyweight-only lifter genuinely cannot be given
  /// a squat, a vertical press or a lateral raise from it. That is a catalogue
  /// problem rather than a planning one, and papering over it with a movement
  /// that does not exist would render a placeholder thumbnail and break the
  /// swap — see the note on [_fills].
  static String? _fill(String role, Equipment have) {
    for (final f in _fills[role] ?? const []) {
      if (have.canDo(f.needs)) return f.movement;
    }
    return null;
  }
}

/// What somebody has to train with, coarsest first.
enum Equipment {
  bodyweight,
  minimalKit,
  homeWeights,
  fullGym;

  /// Whether this kit covers a movement's requirement. Ordered, so a full gym
  /// can do everything a home setup can and a home setup everything bodyweight
  /// can — which is why the fill lists read best-first and stop at the first
  /// thing that fits.
  bool canDo(Equipment needs) => index >= needs.index;

  static Equipment fromAnswer(String answer) => switch (answer.toLowerCase()) {
    'a full gym' => Equipment.fullGym,
    'home, with weights' => Equipment.homeWeights,
    'minimal kit' => Equipment.minimalKit,
    _ => Equipment.bodyweight,
  };
}
