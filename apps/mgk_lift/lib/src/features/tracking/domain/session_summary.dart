import 'package:meta/meta.dart';
import 'package:mgk_units/mgk_units.dart';

import '../../stats/domain/training_stats.dart';
import 'session.dart';

/// What a finished session amounts to: the four totals, and anything in it that
/// was a first.
///
/// **A separate type rather than getters on [Session]**, because none of this
/// is a property of the session alone — a personal best only exists relative to
/// every session before it, and [Session] deliberately knows nothing about the
/// log it sits in. Keeping the comparison here also means the summary screen
/// can be a widget that draws things, and the rule about what counts as a best
/// is testable without pumping one.
///
/// Every figure folds over [Session.workingSets] or over
/// [TrainingStats.topSet] rather than restating either. That is the same
/// rule `TrainingStats` was written to enforce, and for the same reason: the
/// session header and Profile once disagreed about whether a warm-up counted,
/// so the same lifter saw two different volumes depending which screen they
/// were on. A third opinion here would be the same bug again.
@immutable
class SessionSummary {
  const SessionSummary._({
    required this.session,
    required this.duration,
    required this.volume,
    required this.workingSets,
    required this.movements,
    required this.personalBests,
  });

  /// Folds a finished session, comparing it against [log] to find what is new.
  ///
  /// [log] is the log **as it stood before this session**. The session's own id
  /// is filtered out regardless, so it is safe to pass a log that has already
  /// been refreshed — without that, a session would be compared against itself
  /// and could never beat anything.
  factory SessionSummary.of(
    Session session, {
    List<Session> log = const <Session>[],
  }) {
    assert(
      !session.isInProgress,
      'A summary is a record of a session that has ended. '
      'TrainingStats reads finished sessions only, so an open one would '
      'report no bests at all rather than reporting none honestly.',
    );

    final prior = <Session>[
      for (final s in log)
        if (s.id != session.id) s,
    ];

    final bests = <PersonalBest>[];
    final seen = <String>{};

    for (final exercise in session.exercises) {
      // A lifter who came back to the bench at the end has one movement in
      // this list, not two. `topSet` already folds every exercise of that name
      // in the session, so the second visit would otherwise produce a
      // duplicate row claiming the same best twice.
      if (!seen.add(exercise.name.toLowerCase())) continue;

      // Null for bodyweight work, which has no weight to have beaten.
      final today = TrainingStats.topSet(<Session>[session], exercise.name);
      if (today == null) continue;

      final before = TrainingStats.topSet(prior, exercise.name);

      // **A movement with no history is not a personal best.** There is
      // nothing to have beaten. Counting it would make a first session
      // nothing but bests — every movement in it, by definition — which
      // empties the word of the meaning the section depends on. It becomes a
      // best the next time they do it and go past this.
      if (before == null) continue;

      // Heavier, or as heavy for more reps. Matching a best is not setting
      // one, and a session that repeats last week's top set to the kilogram
      // should not be told it moved.
      if (!today.beats(before)) continue;

      bests.add(
        PersonalBest(movement: exercise.name, set: today, beat: before),
      );
    }

    return SessionSummary._(
      session: session,
      // `elapsedAt` reads the clock only while a session is open, and this one
      // is closed — so the argument is never used and the duration is the
      // stamped one. A summary must not grow while it is being read.
      duration: session.elapsedAt(session.startedAt),
      volume: Mass.kilograms(session.volumeKg),
      workingSets: session.completedSets,
      movements: session.exercises.length,
      // In the order they were trained, not sorted by how much they moved.
      // The lifter read the session in that order ninety seconds ago, and a
      // reordered list makes them find each movement again.
      personalBests: List<PersonalBest>.unmodifiable(bests),
    );
  }

  final Session session;

  String get name => session.name;

  /// Start to finish, as stamped. Includes the time spent standing about,
  /// because that is also what the session cost.
  final Duration duration;

  /// Total load moved. Warm-ups and unticked sets excluded — see
  /// [Session.volumeKg].
  final Mass volume;

  /// Sets that count: performed, and not warm-ups.
  final int workingSets;

  /// How many movements were in the session, including any that were added and
  /// never worked. That is what the session contained, and the breakdown says
  /// plainly which ones had nothing logged on them.
  final int movements;

  /// Movements where this session went heavier than ever before, or as heavy
  /// for more reps. Empty is the ordinary case.
  final List<PersonalBest> personalBests;
}

/// A movement that went past its previous best in this session, and what it
/// beat.
///
/// **Measured on weight lifted, not on an estimate** (#3). In 2.0.0 a best was
/// an estimated one-rep max going up, so 95 × 5 was "a new best" on a bench
/// already done at 100 — because it estimated 111, a weight nobody had lifted. Now it is a
/// set that actually happened: heavier than any before, or as heavy for more
/// reps.
@immutable
class PersonalBest {
  const PersonalBest({
    required this.movement,
    required this.set,
    required this.beat,
  });

  final String movement;

  /// This session's top set: its heaviest, and the most reps at that weight.
  final TopSet set;

  /// The top set it beat. Never null: a movement with no history does not
  /// appear here at all — see [SessionSummary.of].
  final TopSet beat;

  /// Went heavier, rather than doing more reps at the same weight.
  bool get isHeavier => set.isHeavierThan(beat);
}

/// What a best says under its name: the set, then what it went past.
///
/// One wording for the summary and for the bubble during a session, which
/// announce the same best and should not describe it two ways.
String bestDetail(TopSet set, TopSet beat, MassUnit unit) {
  final done = '${set.weight.label(unit)} × ${set.reps}';
  return set.isHeavierThan(beat)
      ? '$done. Your heaviest yet, past ${beat.weight.label(unit)}.'
      : '$done. Your most reps at that weight, up from ${beat.reps}.';
}
