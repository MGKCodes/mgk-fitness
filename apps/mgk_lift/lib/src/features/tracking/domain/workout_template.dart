import 'package:meta/meta.dart';

/// A ready-made session — a name and an ordered list of movements.
///
/// The point is the **empty-state problem**. Someone opening a tracker for the
/// first time faces a blank session and has to remember what a push day is
/// before they can log anything. A template turns that into one tap.
///
/// It holds exercise **names**, not catalogue objects, for the same reason a
/// logged exercise does: the name is what a session records, and a template
/// that could only reference catalogue entries would be a second, stricter idea
/// of what an exercise is. A test asserts every name here resolves, so the
/// looseness costs nothing in practice.
@immutable
class WorkoutTemplate {
  const WorkoutTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.exercises,
    this.offered = false,
  });

  final String id;
  final String name;

  /// What it trains, in plain words — `Chest, shoulders & triceps`.
  final String description;

  /// Movement names, in the order they should be done.
  final List<String> exercises;

  /// Whether this one leads the list a lifter browses.
  ///
  /// **All of them are the coach's raw material; a few of them are a menu.**
  /// The full fifteen are what the coach composes from — it knows what a push
  /// day contains and in what order, so it never has to invent a session from
  /// nothing. But fifteen is a lot to choose between with no coach and no
  /// plan, and the body-part splits among them are for somebody who already
  /// knows what they are doing. So these six are the ones that answer "what
  /// should I do today" for a person who has just opened a tracker.
  ///
  /// **It orders rather than filters, and it used to do the opposite.** The
  /// template picker showed only these six, because it started a session
  /// directly and that is a decision made standing up in a hurry. That picker
  /// is gone, and so is the ready-made sheet that followed it: three starters
  /// are shown now (`starters.dart`, R11), and the whole catalogue is the
  /// coach's raw material, ordered by this.
  ///
  /// This is a display rule, not a tier: tracking is free and stays free, and
  /// nothing here is withheld to sell anything.
  final bool offered;
}

/// A weekly programme: which sessions, and how many days.
///
/// Splits reference templates by id rather than embedding them, so `legs`
/// appears in four different splits and is defined once. Changing what a leg
/// day contains changes it everywhere, which is the correct behaviour and the
/// reason the indirection is worth it.
@immutable
class WorkoutSplit {
  const WorkoutSplit({
    required this.id,
    required this.name,
    required this.description,
    required this.templateIds,
    required this.daysPerWeek,
    required this.image,
  });

  final String id;
  final String name;

  /// The rotation, as a person would say it — `Push · Pull · Legs`.
  final String description;

  final List<String> templateIds;
  final int daysPerWeek;

  /// Asset path for the split's photograph.
  final String image;
}
