import 'run_split.dart';

/// How a race was run: its checkpoints and its two halves, measured against the
/// course rather than against the phone.
///
/// **The phone always reads long in a race, and it reads long everywhere.** A
/// half marathon on Sunday 11 October recorded 21.69 km: 590 m of weaving round
/// other runners and missing the tangents, spread over the whole course rather
/// than saved up for the end. Cutting the trace at the phone's own 5 km mark
/// therefore lands about 140 m short of the course's 5K sign, and by 15K the
/// gap is 400 m — a section breakdown cut that way reports the runner reaching
/// every checkpoint before they did.
///
/// So the checkpoints are placed proportionally: the course's 5K is taken to be
/// the same *fraction* of the phone's distance as it is of the race. Checked
/// against that Sunday's chip timing (`race_breakdown_test.dart`), each
/// section's pace came out within five seconds a kilometre of the results
/// page, and the checkpoints within about twenty seconds of the mats: the
/// phone over-reads most in the crowd at the start, so it reaches each mat a
/// little early by its own reckoning. That is the accuracy this promises: a
/// pace per section a runner can trust to a few seconds a kilometre, never a
/// checkpoint time to the second.
///
/// Read from the splits rather than from the trace. They are the same walk
/// (`splitRun`), they are mirrored and restored where the trace may not be, and
/// they already have every gap in the recording taken out — a breakdown that
/// charged the runner for a hole in the GPS would be measuring the phone.
class RaceBreakdown {
  const RaceBreakdown({
    required this.raceMeters,
    required this.sections,
    required this.firstHalf,
    required this.secondHalf,
  });

  /// The course distance the breakdown is measured against.
  final double raceMeters;

  /// The race between checkpoints, in order, ending at the finish.
  final List<RaceSection> sections;

  /// Start to halfway, and halfway to the finish.
  final RaceSection firstHalf;
  final RaceSection secondHalf;

  /// How much slower the second half was than the first, as a fraction of the
  /// first half's pace. Positive is a fade; negative is a negative split.
  double get fade =>
      (secondHalf.paceSecondsPerKm - firstHalf.paceSecondsPerKm) /
      firstHalf.paceSecondsPerKm;
}

/// One stretch of a race, between two points on the course.
class RaceSection {
  const RaceSection({
    required this.fromMeters,
    required this.toMeters,
    required this.duration,
    this.isFinish = false,
  });

  /// Course metres at the start and end of the section.
  final double fromMeters;
  final double toMeters;

  final Duration duration;

  /// Whether this section ends at the finish line, which is what a runner
  /// calls it rather than by its distance.
  final bool isFinish;

  double get meters => toMeters - fromMeters;

  /// Pace over the course distance of the section, in seconds per kilometre.
  double get paceSecondsPerKm =>
      duration.inMilliseconds / 1000 / (meters / 1000);
}

/// The phone may read this far from the course and still be the race.
///
/// GPS reads long in a race, 1–4% on a city course, and occasionally short
/// under tall buildings or trees. Outside this band the recording is not a
/// slightly-off copy of the course but something else — a watch left running
/// on the walk home, a phone that lost the first half — and checkpoints placed
/// proportionally along it would be confidently wrong. No breakdown is shown
/// then; the race keeps its time and loses only its sections.
const double kRaceBreakdownLow = 0.9;
const double kRaceBreakdownHigh = 1.15;

/// How long a section is for a race of [raceMeters]: a kilometre for a 5K, two
/// for a 10K, and the 5K checkpoints every timed road race uses beyond that.
double raceSectionMeters(double raceMeters) {
  if (raceMeters <= 5500) return 1000;
  if (raceMeters <= 10500) return 2000;
  return 5000;
}

/// A remainder shorter than this share of a section is folded into the one
/// before it rather than shown on its own. A half marathon's last 1.1 km is
/// "15K to the finish" on every results page, because a pace over the final
/// kilometre and a bit says more about the sprint than about the race; a
/// marathon's last 2.2 km keeps its own row, as 40K to the finish always does.
const double _foldRemainderBelow = 0.4;

/// The race in [splits], measured against a course of [raceMeters], or null
/// when there is nothing a breakdown could honestly say.
///
/// Null when there are no splits (a treadmill run, a hand-entered race, a race
/// restored without its splits), and when the phone's distance is outside
/// [kRaceBreakdownLow]..[kRaceBreakdownHigh] of the course.
RaceBreakdown? raceBreakdownFor(List<RunSplit> splits, double raceMeters) {
  if (raceMeters <= 0) return null;

  // The splits as a ladder: metres covered and milliseconds elapsed at the end
  // of each, starting from zero. Ordered by index rather than trusted to arrive
  // in order, because a restore inserts rows in whatever order the server sent.
  final ordered = <RunSplit>[
    for (final s in splits)
      if (s.distanceMeters > 0) s,
  ]..sort((a, b) => a.index.compareTo(b.index));
  if (ordered.isEmpty) return null;

  final meters = <double>[0];
  final ms = <int>[0];
  for (final split in ordered) {
    meters.add(meters.last + split.distanceMeters);
    ms.add(ms.last + split.duration.inMilliseconds);
  }
  final measured = meters.last;
  final ratio = measured / raceMeters;
  if (ratio < kRaceBreakdownLow || ratio > kRaceBreakdownHigh) return null;

  // Milliseconds elapsed at [course] metres along the race, interpolated inside
  // the split it falls in at constant pace — the same assumption `splitRun`
  // makes about a single hop, over a kilometre rather than a second.
  int at(double course) {
    final target = (course * ratio).clamp(0.0, measured);
    for (var i = 1; i < meters.length; i++) {
      if (meters[i] >= target) {
        final span = meters[i] - meters[i - 1];
        final into = span <= 0 ? 0.0 : (target - meters[i - 1]) / span;
        return (ms[i - 1] + (ms[i] - ms[i - 1]) * into).round();
      }
    }
    return ms.last;
  }

  final step = raceSectionMeters(raceMeters);
  final marks = <double>[];
  for (var m = step; m < raceMeters - 1e-6; m += step) {
    marks.add(m);
  }
  // Fold a short remainder into the section before it.
  if (marks.isNotEmpty &&
      raceMeters - marks.last < step * _foldRemainderBelow) {
    marks.removeLast();
  }
  marks.add(raceMeters);

  final sections = <RaceSection>[];
  var from = 0.0;
  for (final to in marks) {
    sections.add(
      RaceSection(
        fromMeters: from,
        toMeters: to,
        duration: Duration(milliseconds: at(to) - at(from)),
        isFinish: to == raceMeters,
      ),
    );
    from = to;
  }

  final half = raceMeters / 2;
  final halfway = at(half);
  return RaceBreakdown(
    raceMeters: raceMeters,
    sections: sections,
    firstHalf: RaceSection(
      fromMeters: 0,
      toMeters: half,
      duration: Duration(milliseconds: halfway),
    ),
    secondHalf: RaceSection(
      fromMeters: half,
      toMeters: raceMeters,
      duration: Duration(milliseconds: ms.last - halfway),
      isFinish: true,
    ),
  );
}
