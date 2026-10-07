import 'package:meta/meta.dart';

import 'plan_intake.dart';

/// Everything the coach needs before it can build anything, and what to ask
/// next when some of it is missing.
///
/// ## Four questions, not seven
///
/// This flow was designed with seven: the four below, and year of birth,
/// height and weight. Those three are body facts rather than training facts,
/// and docs/coach-profile.md puts them in `core` so that Runio gets them free —
/// *"You are a certain age, a certain height and a certain weight, and none of
/// those become different facts because you opened a different binary."*
///
/// **`core` has nowhere to put them.** There is no `core.body_metrics`, no
/// `height_cm` and no `year_of_birth` in any migration; coach-profile.md opens
/// by saying so. Asking a question whose answer is dropped on the floor is
/// worse than not asking it, so the three are cut here rather than rendered
/// and discarded. They come back with the schema that stores them, and the
/// wheel that asks them already exists — [CoachAsk] and the coach screen's
/// slider are built and shipping, so what is missing is a table, not a control.
///
/// ## Ordered by leverage, not by convention
///
/// Days decides the split outright. Equipment decides whether the movements are
/// possible at all. Injuries are hard constraints. Goal moves rep ranges at the
/// margin. That order survives the cut: the three that left were the tail of
/// it, which is why losing them costs the flow nothing structural.
///
/// ## Missing, not next
///
/// [IntakeProgress.next] returns the first field still unknown rather than the
/// next in a script. That is what keeps the conversation a conversation: the
/// composer stays live throughout, and somebody who types "4 days, home gym,
/// bad shoulder" answers three at once and is never asked them again. A
/// fixed-order form would make them answer all three separately, which is the
/// exact failure PlanIntakeScreen was built to avoid — and the reason the
/// options below sit *under* a live composer rather than replacing it.
enum IntakeField {
  days,
  equipment,
  injuries,
  goal;

  /// What the coach says when it needs this.
  ///
  /// Days invites the weekdays without asking for them separately: somebody
  /// who already knows says "Mon, Wed, Fri" and answers both, and everybody
  /// else taps a count and gets it spread across the week
  /// ([PlanIntake.weekdaysOrDefault]).
  String get question => switch (this) {
    days =>
      'How many days a week can you actually train? Be honest rather '
          'than optimistic — I would rather build four you keep than six you do '
          'not. If you know which days, tell me those.',
    equipment => 'What do you have to train with?',
    injuries =>
      'Anything I should train around? An injury, a movement that hurts, '
          'something you have been told to avoid.',
    goal => 'What are you training for?',
  };

  /// Tapped answers, where the answer is a choice rather than prose.
  ///
  /// **Three goals, not six.** An option earns its place by changing the
  /// output: "lose weight" and "gain weight" are nutrition goals whose training
  /// answer is the same block as "gain muscle", so offering them separately
  /// costs a decision and buys nothing. What is left is the three that produce
  /// genuinely different programming.
  List<String> get options => switch (this) {
    days => const <String>['2 days', '3 days', '4 days', '5 or more'],
    equipment => const <String>[
      'A full gym',
      'Home, with weights',
      'Minimal kit',
      'Bodyweight only',
    ],
    injuries => const <String>['Nothing to work around'],
    goal => const <String>[
      'Get stronger',
      'Build muscle',
      'Lose fat, keep muscle',
    ],
  };

  /// **Everything except days is skippable.** A plan can be built without
  /// knowing somebody's goal or what hurts — worse, but built. It cannot be
  /// built without knowing how often they train, because that is the number
  /// the split is chosen from.
  bool get required => this == IntakeField.days;

  /// The tapped answer that means "moving on", for a field that can be
  /// skipped.
  ///
  /// **Sent as a turn, not swallowed.** Declining is a thing the lifter said,
  /// so it goes into the transcript the coach reads back — the same choice the
  /// coach screen's slider makes with its own "Prefer not to say". A skip that
  /// only mutated local state would leave the coach asking around a subject
  /// somebody had already closed.
  ///
  /// Injuries decline by answering: *nothing to work around* is a real reply
  /// rather than a refusal, and offering "prefer not to say" underneath it
  /// would be two rows for one intention.
  String? get skip => switch (this) {
    days => null,
    injuries => 'Nothing to work around',
    equipment || goal => 'Prefer not to say',
  };

  /// What to put under the newest question: the options, plus the way out
  /// where that is not already one of them.
  List<String> get offered => <String>[
    ...options,
    if (skip case final String s when !options.contains(s)) s,
  ];

  /// The field a coach turn says it is asking about ([IntakeTurn.asking]), or
  /// null for anything else — "done", nothing, or a name this build does not
  /// know.
  static IntakeField? named(String? name) =>
      name == null ? null : IntakeField.values.asNameMap()[name];
}

/// What has been learned so far.
@immutable
class IntakeProgress {
  const IntakeProgress({
    this.plan = const PlanIntake(),
    this.declined = const <IntakeField>{},
  });

  final PlanIntake plan;

  /// Fields the lifter chose not to answer. **Held separately from "unknown"**,
  /// or the flow would ask again for ever — a declined question has been
  /// answered, and asking twice is not accepting the answer.
  final Set<IntakeField> declined;

  /// What the coach extracted this turn, folded in.
  ///
  /// Merged, never replaced: every intake turn returns every field, and a null
  /// means "not learned this turn" rather than "forget it".
  IntakeProgress merge(PlanIntake next) =>
      IntakeProgress(plan: plan.merge(next), declined: declined);

  /// The lifter passed on [field].
  IntakeProgress decline(IntakeField field) =>
      IntakeProgress(plan: plan, declined: <IntakeField>{...declined, field});

  bool has(IntakeField f) {
    if (declined.contains(f)) return true;
    return switch (f) {
      IntakeField.days => plan.daysPerWeek != null,
      IntakeField.equipment => plan.equipment != null,
      IntakeField.injuries => plan.injuryNotes != null,
      IntakeField.goal => plan.goal != null,
    };
  }

  /// The first field still unknown, or null when there is nothing left to ask.
  IntakeField? get next => unsettled.firstOrNull;

  /// Every field still unknown, in the order they are asked.
  List<IntakeField> get unsettled => <IntakeField>[
    for (final f in IntakeField.values)
      if (!has(f)) f,
  ];

  /// How many are settled, for the bar in the screen's chrome. Counts answers
  /// rather than position, so answering three in one sentence moves it three.
  int get answered => IntakeField.values.where(has).length;

  int get total => IntakeField.values.length;

  bool get isComplete => next == null;
}
