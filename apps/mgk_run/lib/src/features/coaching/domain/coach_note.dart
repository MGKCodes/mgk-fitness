import 'package:mgk_units/mgk_units.dart';
import '../../recording/domain/run_summary.dart';
import 'run_note.dart' show beatsDistanceRecord;

/// A short observation the coach makes about what the runner has been doing.
///
/// **Derived in Dart, not generated.** The same rule that governs plans applies
/// here: a remark about a runner's training has to be true, and the cheapest way
/// to guarantee that is to compute it from their runs rather than ask a model to
/// describe them. These notes are also what a model-written note would later be
/// validated *against* — it must not congratulate someone on a personal best
/// they did not set.
///
/// Ordered by how much a runner would care: a record beats a first. Only one is
/// shown, because a coach who says four things at once is not saying anything.
///
/// **Deliberately narrow.** It says nothing about volume or consistency — Home
/// draws both, and a remark restating the chart under it is the app talking to
/// itself (ADR-0017's cost function applies: a second voice for the same fact).
class CoachNote {
  const CoachNote({required this.headline, required this.detail, this.kind});

  /// One line, in the coach's voice.
  final String headline;

  /// The evidence behind it, so the remark is checkable rather than flattering.
  final String detail;

  final CoachNoteKind? kind;

  /// The single most notable thing about [runs], or null if there is nothing
  /// honest to say yet.
  ///
  /// [now] and [unit] are no longer read — every remaining note is a comparison
  /// between runs rather than a figure in a window. Both stay on the signature
  /// because callers pass them and a model-written note, validated against
  /// these, will need them again.
  static CoachNote? forRuns(
    List<RunSummary> runs, {
    DateTime? now,
    UnitSystem unit = UnitSystem.metric,
  }) {
    if (runs.isEmpty) return null;

    final sorted = <RunSummary>[...runs]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final latest = sorted.first;
    final earlier = sorted.skip(1).toList();

    // A first run is the only thing worth saying to someone with one run.
    if (earlier.isEmpty) {
      return const CoachNote(
        headline: 'That’s one in the bank.',
        detail: 'Your first logged run. The next one is the one that counts.',
        kind: CoachNoteKind.milestone,
      );
    }

    // A pace record, but only over a distance where pace means something.
    final pace = _pace(latest);
    if (pace != null && latest.distanceMeters >= 1000) {
      final priorBest = earlier
          .where((r) => r.distanceMeters >= 1000)
          .map(_pace)
          .whereType<double>()
          .fold<double?>(
            null,
            (best, p) => best == null || p < best ? p : best,
          );
      if (priorBest != null && pace < priorBest) {
        return const CoachNote(
          headline: 'Fastest you’ve run.',
          detail: 'Your last run beat every pace you’ve logged before.',
          kind: CoachNoteKind.record,
        );
      }
    }

    // A distance record.
    final priorLongest = earlier
        .map((r) => r.distanceMeters)
        .fold<double>(0, (a, b) => a > b ? a : b);
    if (beatsDistanceRecord(latest.distanceMeters, priorLongest)) {
      return const CoachNote(
        headline: 'Longest one yet.',
        detail: 'You went further than you ever have. Recover properly.',
        kind: CoachNoteKind.record,
      );
    }

    // **Nothing about volume, consistency, or a gap since the last run.**
    // Three tiers used to sit here — "Strong month", "You're turning up",
    // "Been a while" — and Home now draws all three as marks: the volume chart
    // is this month's distance, and the consistency grid is both turning up and
    // the gap, under a heading that read *Turning up* directly beneath a note
    // saying the same words. A coach reading out the chart above their own
    // remark is one voice too many.
    //
    // What is left is what a chart cannot show: a first, and a record. Those
    // are the coach noticing something, which is the only reason this line
    // exists.
    return null;
  }

  static double? _pace(RunSummary run) {
    if (run.avgPaceSecondsPerKm != null) return run.avgPaceSecondsPerKm;
    if (run.distanceMeters <= 0 || run.duration == Duration.zero) return null;
    return run.duration.inSeconds / (run.distanceMeters / 1000);
  }
}

/// What kind of thing the coach noticed. Available for future styling; the
/// design language keeps them monochrome for now (ADR-0009).
///
/// [consistency] and [nudge] are unused since the volume and turning-up tiers
/// went to the charts. Kept because a model-written note is validated against
/// this vocabulary, and narrowing it would be a decision about what the coach
/// may notice rather than about what Home draws.
enum CoachNoteKind { record, milestone, consistency, nudge }
