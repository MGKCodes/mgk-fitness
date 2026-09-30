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
/// [TrainingStats.bestOneRepMax] rather than restating either. That is the same
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
    required this.hasEstimate,
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
    var hasEstimate = false;

    for (final exercise in session.exercises) {
      // A lifter who came back to the bench at the end has one movement in
      // this list, not two. `bestOneRepMax` already folds every exercise of
      // that name in the session, so the second visit would otherwise produce
      // a duplicate row claiming the same best twice.
      if (!seen.add(exercise.name.toLowerCase())) continue;

      final today = TrainingStats.bestOneRepMax(<Session>[
        session,
      ], exercise.name);

      // No estimate is a real state, not a failure. Epley is capped at 12
      // reps — see [TrainingStats.estimateOneRepMax] — so a movement worked
      // for fifteens produces nothing here, and that is the honest answer
      // rather than a number invented to fill the row.
      if (today == null) continue;
      hasEstimate = true;

      final before = TrainingStats.bestOneRepMax(prior, exercise.name);

      // **A movement with no history is not a personal best.** There is
      // nothing to have beaten. Counting it would make a first session
      // nothing but bests — every movement in it, by definition — which
      // empties the word of the meaning the section depends on. It becomes a
      // best the next time they do it and go past this.
      if (before == null) continue;

      // Strictly greater. Matching a best is not setting one, and a session
      // that repeats last week's top set to the kilogram should not be told
      // it moved.
      if (today.estimate.kilograms <= before.estimate.kilograms) continue;

      bests.add(
        PersonalBest(
          movement: exercise.name,
          estimate: today.estimate,
          weight: today.weight,
          reps: today.reps,
          previous: before.estimate,
          previousOn: before.on,
        ),
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
      hasEstimate: hasEstimate,
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

  /// Movements whose best estimated one-rep max went past everything before
  /// this session. Empty is the ordinary case.
  final List<PersonalBest> personalBests;

  /// Whether any set in this session could be estimated from at all.
  ///
  /// Separates the two silences. "Nothing beat your best" and "nothing here
  /// can be turned into an estimate" are different facts, and a screen that
  /// renders them identically tells a lifter who trained entirely in fifteens
  /// that they went backwards.
  final bool hasEstimate;
}

/// A movement whose estimated one-rep max went past its previous best in this
/// session, and what it beat.
///
/// The estimate is Epley's, which is a fitted line rather than a measurement —
/// so anything showing this should say "estimated" rather than asserting the
/// lifter can hit it. [weight] and [reps] are the set that actually happened,
/// and are the honest half of the claim.
@immutable
class PersonalBest {
  const PersonalBest({
    required this.movement,
    required this.estimate,
    required this.weight,
    required this.reps,
    required this.previous,
    required this.previousOn,
  });

  final String movement;

  /// This session's best estimate.
  final Mass estimate;

  /// The set that produced it.
  final Mass weight;
  final int reps;

  /// The estimate it beat. Never null: a movement with no history does not
  /// appear here at all — see [SessionSummary.of].
  final Mass previous;

  /// When that previous best was set. Shown, because beating something from
  /// last week and beating something from last year are different sessions.
  final DateTime previousOn;
}
