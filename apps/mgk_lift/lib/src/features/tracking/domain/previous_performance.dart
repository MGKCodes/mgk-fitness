import 'session.dart';

/// What a lifter did on one movement the last time they trained it.
///
/// **The number you want is the one you are about to beat.** Mid-set, a lifter
/// is deciding what to load, and the honest answer is almost never a lifetime
/// best — it is what they managed a week ago on the same bar. A personal best
/// belongs on Profile, where it is a record; here it would be discouraging on
/// most days and misleading on the rest, because a best is usually a single and
/// the working sets around it were lighter.
///
/// It reads the finished log the session screen is already given, so this
/// needed no new plumbing — `ActiveSessionScreen` has taken `log` since it was
/// written, to derive a swap target.
class PreviousPerformance {
  const PreviousPerformance({required this.on, required this.sets});

  /// When that session started. Shown, because "last time" means something
  /// different at four days than at four months.
  final DateTime on;

  /// The working sets of that movement, in the order they were done.
  ///
  /// Warm-ups are left out for the same reason they are left out of volume:
  /// they were not the work, and a lifter comparing today against an empty bar
  /// is comparing against nothing.
  final List<SessionSet> sets;

  /// The heaviest set of that session, which is the single figure worth leading
  /// with when there is only room for one.
  SessionSet get best => sets.reduce((a, b) => b.weightKg > a.weightKg ? b : a);

  /// The most recent finished session containing [exerciseName], or null.
  ///
  /// Matched on name, case-insensitively, because that is what a session
  /// records — the catalogue is a source of names and images, not an identity a
  /// logged movement is required to have. A movement somebody typed themselves
  /// gets its history on exactly the same terms as one of the 266.
  ///
  /// [excludeSessionId] keeps the session in progress out of its own answer.
  /// Without it, the first set logged today immediately becomes "last time",
  /// and the line would tell a lifter what they did ninety seconds ago.
  static PreviousPerformance? of(
    List<Session> log,
    String exerciseName, {
    String? excludeSessionId,
  }) {
    final name = exerciseName.toLowerCase();
    final finished = <Session>[
      for (final s in log)
        if (!s.isInProgress && s.id != excludeSessionId) s,
    ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));

    for (final session in finished) {
      for (final exercise in session.exercises) {
        if (exercise.name.toLowerCase() != name) continue;
        final sets = exercise.workingSets.toList();
        // A movement that was added and never worked is not a performance.
        // Skipping it rather than returning an empty one means the line falls
        // through to the session before it, which is the useful answer.
        if (sets.isEmpty) continue;
        return PreviousPerformance(on: session.startedAt, sets: sets);
      }
    }
    return null;
  }
}
