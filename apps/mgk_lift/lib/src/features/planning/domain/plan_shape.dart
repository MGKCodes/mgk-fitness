import '../../tracking/data/exercise_catalogue.dart';
import '../../tracking/domain/exercise.dart';
import 'standing_plan.dart';

/// Whether a plan is any good, judged by what it does rather than what it is
/// called.
///
/// ## Why this replaced a list of allowed splits
///
/// The first version checked that a plan WAS one of three shapes — full body,
/// upper/lower, push/pull/legs — chosen by day count. That made the three
/// templates the definition of a valid plan, which is a much smaller claim than
/// anybody wants: an upper/lower with a dedicated arm day is a perfectly good
/// four-day plan and would have been rejected for not being on the list.
///
/// **The properties are the rule; the shape is whatever serves them.** A plan
/// is fine if every muscle it trains gets trained often enough, in enough
/// volume, with a day's gap, out of movements that exist and equipment the
/// lifter has. Nothing in that sentence names a split, and a model free to
/// invent one is only dangerous if nothing checks the result.
///
/// ## What the numbers are, and where they come from
///
/// Roughly 12–20 hard sets per muscle per week — claim **C1** in
/// docs/research/training.md, which is where the citation, the confidence and
/// the date it was last checked live.
///
/// **The two-exposure rule rests on C3, not on "twice beats once".** That
/// older claim (C2) came from a 2016 meta-analysis with a known confounder, and
/// the same group's later 25-study review found frequency close to neutral once
/// volume is equated. What survives is practical: a muscle needing 12–20 hard
/// sets a week is badly served by one session, because sets late in a long one
/// are done under accumulated fatigue.
///
/// **The volume cap counts PRIMARY work only; frequency counts both.** Those
/// are different questions and they were being answered with one number. "Sets
/// for a muscle" in the literature means direct work, so counting fractional
/// secondary sets against a hard cap mixes conventions and systematically
/// inflates whatever gets listed as a secondary most often — back and shoulders,
/// which nearly every pull and press touches. Under one combined count a
/// perfectly ordinary pull day read as 29 sets of back.
///
/// Frequency is the opposite case: a muscle worked hard as a secondary HAS been
/// trained that day, and pretending otherwise would demand a second direct day
/// for something already getting plenty.
abstract final class PlanShape {
  /// Muscles a plan is judged on. Core is trained incidentally by most
  /// compounds and nobody quits over its volume; cardio is not this app's job.
  static const Set<String> judged = <String>{
    'Chest',
    'Back',
    'Legs',
    'Shoulders',
    'Biceps',
    'Triceps',
  };

  /// The weekly band. Wide on purpose: it is a guard rail against a plan that
  /// is obviously wrong, not an opinion about the best number.
  static const int minWeeklySets = 8;
  static const int maxWeeklySets = 26;

  /// **"Legs" is one label for quadriceps, hamstrings, glutes and calves**, so
  /// a per-muscle band does not apply to it — four muscles inside the evidence's
  /// 12–20 each would blow a 26 cap on their own. The catalogue's taxonomy is
  /// the limitation here rather than the programming, and a higher ceiling is
  /// the honest way to say so until the catalogue splits them.
  static int capFor(String muscle) =>
      muscle == 'Legs' ? maxWeeklySets * 2 : maxWeeklySets;

  /// Assumed only when a slot does not carry its own set count, which should
  /// not happen now that the planner prescribes them. Kept as a floor so a
  /// malformed slot cannot silently count as zero volume.
  static const int assumedSets = 3;

  /// Reasons this plan should not be shown, phrased as instructions so the list
  /// can go straight back to whatever produced it.
  static List<String> violations(
    StandingPlan plan, {
    Set<String> equipment = const <String>{},
    Set<String> avoidRoles = const <String>{},
    ExerciseLookup? catalogue,
  }) {
    final out = <String>[];
    final look = catalogue ?? const _Catalogue();

    if (plan.weekdays.isEmpty) {
      return <String>['Give the plan at least one training day.'];
    }
    if (plan.weekdays.toSet().length != plan.weekdays.length) {
      out.add('Each training day must be a different weekday.');
    }

    final dayNames = plan.dayOrder;
    if (dayNames.length != plan.weekdays.length) {
      out.add(
        'Give ${plan.weekdays.length} days, one per training day; '
        'this has ${dayNames.length}.',
      );
    }

    // ---- every day does something -------------------------------------
    for (final day in dayNames.toSet()) {
      final slots = plan.slots[day] ?? const <MovementSlot>[];
      if (slots.isEmpty) {
        out.add('Put at least one movement in $day.');
      } else if (slots.length > 8) {
        // A nine-movement session is the one people quietly start cutting
        // short, and a plan somebody abandons has no volume at all.
        out.add('$day has ${slots.length} movements; keep it to eight.');
      }
    }

    final all = plan.slots.values.expand((s) => s).toList();
    if (all.isEmpty) return out..add('The plan has no movements in it.');

    // ---- the movements are real ---------------------------------------
    for (final s in all) {
      final ex = look.byName(s.movement);
      if (ex == null) {
        out.add(
          'Replace "${s.movement}" — it is not in the exercise catalogue.',
        );
      } else if (equipment.isNotEmpty && !equipment.contains(ex.equipment)) {
        out.add(
          'Replace "${s.movement}" — it needs ${ex.equipment}, '
          'which this lifter does not have.',
        );
      }
      if (avoidRoles.contains(s.role)) {
        out.add('Remove the ${s.role} work; this lifter is avoiding it.');
      }
    }

    // ---- something to measure progress in -------------------------------
    if (!all.any((s) => s.isMain)) {
      out.add(
        'Mark at least one movement as a main lift to measure progress in.',
      );
    }

    // ---- frequency and volume, per muscle -------------------------------
    // Direct work only, for the cap.
    final directSets = <String, double>{};
    // Direct or indirect, for the frequency question and the floor.
    final anySets = <String, double>{};
    final exposures = <String, int>{};
    // **Over dayOrder, not over its distinct names.** An Upper/Lower week runs
    // 'Upper' twice, and counting day NAMES made that one exposure — which had
    // this telling a perfectly good four-day plan to train legs on a second
    // day it was already training them on.
    for (var i = 0; i < dayNames.length; i++) {
      final hitThisDay = <String>{};
      for (final s in plan.slots[dayNames[i]] ?? const <MovementSlot>[]) {
        final ex = look.byName(s.movement);
        if (ex == null) continue;
        // The slot's OWN set count. Assuming three flattered a plan that
        // prescribed five and understated one that prescribed two, which is
        // the difference between a volume check and a movement count.
        final sets = (s.sets > 0 ? s.sets : assumedSets).toDouble();

        void add(String muscle, {required bool direct}) {
          if (!judged.contains(muscle)) return;
          if (direct) {
            directSets[muscle] = (directSets[muscle] ?? 0) + sets;
          }
          anySets[muscle] = (anySets[muscle] ?? 0) + (direct ? sets : sets / 2);
          hitThisDay.add(muscle);
        }

        add(ex.muscleGroup, direct: true);
        for (final m in ex.secondaryMuscles) {
          add(m, direct: false);
        }
      }
      for (final m in hitThisDay) {
        exposures[m] = (exposures[m] ?? 0) + 1;
      }
    }

    for (final entry in directSets.entries) {
      final sets = entry.value.round();
      final cap = capFor(entry.key);
      if (sets > cap) {
        out.add(
          '${entry.key} gets about $sets sets a week; bring it under $cap.',
        );
      }
    }

    // A muscle the plan trains ONCE a week is a poor way to deliver a week's
    // volume — see C3. A muscle it does not train at all is a choice (nobody
    // has to train calves) and is left alone.
    for (final entry in exposures.entries) {
      final trained = anySets[entry.key]?.round() ?? 0;
      if (trained >= minWeeklySets && entry.value < 2) {
        out.add(
          'Train ${entry.key.toLowerCase()} on a second day; '
          'once a week is the one thing the evidence is against.',
        );
      }
    }

    // ---- a day between hits ---------------------------------------------
    //
    // Only when the two lists agree. A mismatch is already reported above, and
    // walking `dayNames` by `weekdays.length` past that point is a RangeError
    // rather than a violation — this crashed on a proposal that gave one day
    // for a four-day week, which is exactly the malformed input this function
    // exists to survive.
    if (dayNames.length != plan.weekdays.length) return out;

    for (var i = 0; i < plan.weekdays.length; i++) {
      final j = (i + 1) % plan.weekdays.length;
      final gap = (plan.weekdays[j] - plan.weekdays[i] + 7) % 7;
      if (gap != 1) continue;
      final a = _primary(plan.slots[dayNames[i]] ?? const [], look);
      final b = _primary(plan.slots[dayNames[j]] ?? const [], look);
      final shared = a.intersection(b);
      if (shared.length >= 2) {
        out.add(
          'Move ${dayNames[j]} — it trains ${shared.join(' and ')} '
          'the day after ${dayNames[i]} does.',
        );
      }
    }

    return out;
  }

  static bool isUsable(
    StandingPlan plan, {
    Set<String> equipment = const <String>{},
    Set<String> avoidRoles = const <String>{},
    ExerciseLookup? catalogue,
  }) => violations(
    plan,
    equipment: equipment,
    avoidRoles: avoidRoles,
    catalogue: catalogue,
  ).isEmpty;

  static Set<String> _primary(List<MovementSlot> slots, ExerciseLookup look) =>
      <String>{
        for (final s in slots)
          if (look.byName(s.movement)?.muscleGroup case final String m)
            if (judged.contains(m)) m,
      };
}

/// Looks a movement up by name. An interface so a test can pass three
/// exercises instead of 266.
abstract interface class ExerciseLookup {
  Exercise? byName(String name);
}

class _Catalogue implements ExerciseLookup {
  const _Catalogue();

  @override
  Exercise? byName(String name) {
    final key = name.trim().toLowerCase();
    for (final e in exerciseCatalogue) {
      if (e.name.toLowerCase() == key) return e;
    }
    return null;
  }
}
