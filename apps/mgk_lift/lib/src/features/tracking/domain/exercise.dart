import 'package:meta/meta.dart';

/// A movement in the exercise library.
///
/// Ported from Liftio, which is why the shape is what it is: 266 entries, each
/// with a start/end image pair showing the top and bottom of the movement. That
/// library is the single most valuable thing the old app had, and rebuilding it
/// from nothing would have been months of work for no gain.
///
/// This is the *catalogue* entry — what a movement is. What a lifter actually
/// did with it is [SessionExercise], which references this only by name. The
/// separation is deliberate: someone who types "smith machine incline press,
/// feet up" is not wrong, and a log that can only hold catalogue entries is a
/// log people work around.
@immutable
class Exercise {
  const Exercise({
    required this.name,
    required this.category,
    required this.muscleGroup,
    required this.equipment,
    required this.imageKey,
    this.secondaryMuscles = const <String>[],
  });

  final String name;

  /// How it is loaded: Barbell, Dumbbell, Machine, Cable, Bodyweight, EZ Bar,
  /// Cardio.
  final String category;

  /// What it is mainly for. One of nine, so it can drive a filter without a
  /// scrolling list of one-offs.
  final String muscleGroup;

  final String equipment;

  /// Names the image pair: `<imageKey>-1.webp` is the start of the movement and
  /// `-2.webp` the end. Every catalogue entry has both — asserted by a test,
  /// because a missing form image is invisible until someone opens that one
  /// exercise.
  final String imageKey;

  final List<String> secondaryMuscles;

  String get startImage => 'assets/exercises/$imageKey-1.webp';
  String get endImage => 'assets/exercises/$imageKey-2.webp';

  /// `Chest · Barbell`, for the line under the name on a card.
  String get subtitle => '$muscleGroup · $equipment';

  bool get isCardio => muscleGroup == 'Cardio';
}
