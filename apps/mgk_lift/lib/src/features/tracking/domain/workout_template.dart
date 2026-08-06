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
  });

  final String id;
  final String name;

  /// What it trains, in plain words — `Chest, shoulders & triceps`.
  final String description;

  /// Movement names, in the order they should be done.
  final List<String> exercises;
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
