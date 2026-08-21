import 'package:meta/meta.dart';

import '../../coaching/domain/coach.dart';
import 'plan_intake.dart';

/// Everything the coach needs before it can build anything, and what to ask
/// next when some of it is missing.
///
/// ## One list, two destinations
///
/// Four of these end up in `lift` as part of the block; three are body facts
/// and belong to the person, so they go to `core` and Runio gets them free —
/// see docs/coach-profile.md. They are asked together because they are one
/// conversation to the lifter, and split on the way out rather than on the way
/// in.
///
/// ## Ordered by leverage, not by convention
///
/// Days decides the split outright. Equipment decides whether the movements are
/// possible at all. Injuries are hard constraints. Goal moves rep ranges at the
/// margin. Age, height and weight barely touch programming — they are for
/// tracking and load estimation.
///
/// So the body questions go LAST, which is also the polite order: they are the
/// most personal, and asking them after somebody has already invested four
/// answers gets better data than opening with them.
///
/// ## Missing, not next
///
/// [nextFor] returns the first field still unknown rather than the next in a
/// script. That is what keeps the conversation a conversation: the composer
/// stays live throughout, and somebody who types "4 days, home gym, bad
/// shoulder" answers three at once and is never asked them again. A fixed-order
/// form would make them answer all three separately, which is the exact failure
/// PlanIntakeScreen was built to avoid.
enum IntakeField {
  days,
  equipment,
  injuries,
  goal,
  yearOfBirth,
  height,
  weight;

  /// What the coach says when it needs this.
  String get question => switch (this) {
    days =>
      'How many days a week can you actually train? Be honest rather '
          'than optimistic — I would rather build four you keep than six you do '
          'not.',
    equipment => 'What do you have to train with?',
    injuries =>
      'Anything I should train around? An injury, a movement that hurts, '
          'something you have been told to avoid.',
    goal => 'What are you training for?',
    yearOfBirth => 'When were you born?',
    height => 'How tall are you?',
    weight =>
      'And roughly what do you weigh? I will track it from here, so '
          'this is a starting point rather than a number to get right.',
  };

  /// Tapped answers, where the answer is a choice rather than a number.
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
    yearOfBirth || height || weight => const <String>[],
  };

  /// The wheel this field wants, if it is a number.
  CoachAsk? get ask => switch (this) {
    yearOfBirth => CoachAsk.yearOfBirth,
    height => CoachAsk.heightCm,
    weight => CoachAsk.weightKg,
    days || equipment || injuries || goal => null,
  };

  /// **Everything except days is skippable.** A plan can be built without
  /// knowing somebody's weight, their goal or what hurts — worse, but built.
  /// It cannot be built without knowing how often they train, because that is
  /// the number the split is chosen from.
  bool get required => this == IntakeField.days;
}

/// What has been learned so far, across both destinations.
@immutable
class IntakeProgress {
  const IntakeProgress({
    this.plan = const PlanIntake(),
    this.yearOfBirth,
    this.heightCm,
    this.weightKg,
    this.declined = const <IntakeField>{},
  });

  final PlanIntake plan;
  final int? yearOfBirth;
  final int? heightCm;
  final double? weightKg;

  /// Fields the lifter chose not to answer. **Held separately from "unknown"**,
  /// or the flow would ask again for ever — a declined question has been
  /// answered, and asking twice is not accepting the answer.
  final Set<IntakeField> declined;

  bool has(IntakeField f) {
    if (declined.contains(f)) return true;
    return switch (f) {
      IntakeField.days => plan.daysPerWeek != null,
      IntakeField.equipment => plan.equipment != null,
      IntakeField.injuries => plan.injuryNotes != null,
      IntakeField.goal => plan.goal != null,
      IntakeField.yearOfBirth => yearOfBirth != null,
      IntakeField.height => heightCm != null,
      IntakeField.weight => weightKg != null,
    };
  }

  /// The first field still unknown, or null when there is nothing left to ask.
  IntakeField? get next {
    for (final f in IntakeField.values) {
      if (!has(f)) return f;
    }
    return null;
  }

  /// How many are settled, for the bar in the sheet's chrome. Counts answers
  /// rather than position, so answering three in one sentence moves it three.
  int get answered => IntakeField.values.where(has).length;

  int get total => IntakeField.values.length;

  bool get isComplete => next == null;
}
