import 'package:meta/meta.dart';
import 'package:mgk_units/mgk_units.dart';

import '../../tracking/domain/session.dart';
import 'training_stats.dart';

/// Everything the log says about one movement, for its stats screen (R9).
///
/// Folded over sessions like [TrainingStats], and on the same rules: only
/// finished sessions, only working sets ([SessionExercise.workingSets]), and an
/// estimate only where [TrainingStats.estimateOneRepMax] will give one. A name
/// matches ignoring case, as [TrainingStats.bestOneRepMax] does, so the best on
/// this screen is the best Profile used to show.
@immutable
class MovementHistory {
  const MovementHistory._({
    required this.name,
    required this.sessions,
    required this.best,
  });

  factory MovementHistory.of(List<Session> log, String name) {
    final wanted = name.toLowerCase();
    final found = <MovementSession>[];
    for (final session in log) {
      if (session.isInProgress) continue;
      final sets = <SessionSet>[
        for (final exercise in session.exercises)
          if (exercise.name.toLowerCase() == wanted) ...exercise.workingSets,
      ];
      if (sets.isEmpty) continue;
      found.add(MovementSession._(session: session, sets: sets));
    }
    found.sort((a, b) => b.on.compareTo(a.on));
    return MovementHistory._(
      name: name,
      sessions: found,
      best: TrainingStats.bestOneRepMax(log, name),
    );
  }

  final String name;

  /// Every finished session with working sets of it, newest first.
  final List<MovementSession> sessions;

  /// The best estimated one-rep max, and the set behind it. Null when no
  /// working set qualifies: bodyweight work, or nothing at 12 reps or fewer.
  final OneRepMax? best;

  /// The heaviest weight moved in a working set, at any reps.
  SessionSet? get heaviest {
    SessionSet? top;
    for (final s in sessions) {
      for (final set in s.sets) {
        if (top == null || set.weightKg > top.weightKg) top = set;
      }
    }
    return top == null || top.weightKg <= 0 ? null : top;
  }

  /// Each session's best estimate, oldest first: the line on the chart.
  /// Sessions with no qualifying set are left out rather than drawn as zero.
  List<({DateTime on, Mass estimate})> get estimates =>
      <({DateTime on, Mass estimate})>[
        for (final s in sessions.reversed)
          if (s.bestEstimate case final Mass estimate)
            (on: s.on, estimate: estimate),
      ];
}

/// One session's working sets of a movement.
@immutable
class MovementSession {
  MovementSession._({required this.session, required this.sets})
    : bestEstimate = _best(sets);

  final Session session;

  /// Its working sets, in the order they were done.
  final List<SessionSet> sets;

  /// The session's best estimated one-rep max, or null if no set qualifies.
  final Mass? bestEstimate;

  DateTime get on => session.startedAt;

  static Mass? _best(List<SessionSet> sets) {
    Mass? best;
    for (final set in sets) {
      final e = TrainingStats.estimateOneRepMax(
        Mass.kilograms(set.weightKg),
        set.reps,
      );
      if (e != null && (best == null || e.kilograms > best.kilograms)) {
        best = e;
      }
    }
    return best;
  }
}
