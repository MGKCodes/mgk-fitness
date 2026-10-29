import 'package:meta/meta.dart';
import 'package:mgk_units/mgk_units.dart';

import '../../tracking/domain/session.dart';
import 'training_stats.dart';

/// The three rep ranges a working weight is given for.
///
/// 4–6 / 7–11 / 12–16, not 7–12 / 12–16: the first draft overlapped at 12,
/// and a set of twelve cannot belong to two bands.
enum RepRange {
  strength(4, 6),
  hypertrophy(7, 11),
  endurance(12, 16);

  const RepRange(this.min, this.max);

  final int min;
  final int max;

  /// Epley is fitted to low-rep work and drifts past about ten reps, so this
  /// band is the formula at its least sure, and is shown as approximate.
  bool get isRough => this == endurance;
}

/// What to load for one rep range.
@immutable
class WeightBand {
  const WeightBand({
    required this.range,
    required this.low,
    required this.high,
  });

  final RepRange range;

  /// For the top of the range: the most reps, so the lightest weight.
  final Mass low;

  /// For the bottom of the range.
  final Mass high;

  /// Rounding brought both ends to the same weight, which is one number on
  /// screen rather than "10–10 kg".
  bool get isSingle => (high.kilograms - low.kilograms).abs() < 0.001;
}

/// What to load for each rep range, worked out from a recent best set (#3).
///
/// **A guide, not a claim.** It replaced *Est. 1RM* on a movement's screen: a
/// one-rep max is a number nobody loads, and showing it next to the heaviest
/// weight somebody actually lifted made it read like a best they had set. The
/// estimate is still the right tool for turning one set into another, so it is
/// kept underneath — this is where it is used, rather than shown.
///
/// - **From the last six weeks**, not all time: what somebody can lift now.
/// - **Sets of twelve or fewer**, the territory Epley is fitted to (see
///   [TrainingStats.estimateOneRepMax]).
/// - **One rep in reserve.** The formula predicts reps to failure, and a
///   working weight that is somebody's limit for the top of its range is too
///   heavy for every set after the first.
/// - **Rounded down to a weight the kit has** ([loadStep]), so a band is never
///   heavier than the formula says, and never a number that cannot be loaded.
@immutable
class WorkingWeights {
  const WorkingWeights._({required this.from, required this.bands});

  /// How far back a set can come from.
  static const Duration window = Duration(days: 42);

  /// Reps left in the tank on every band.
  static const int repsInReserve = 1;

  /// The bands for [movement], or null when nothing in the last six weeks
  /// qualifies — which hides them rather than guessing.
  ///
  /// [kit] is the catalogue's `category` (Barbell, Dumbbell, Cable…), or null
  /// for a movement the lifter typed. [unit] is what the screen shows, because
  /// plates are counted in it: 5 lb steps are not 2.5 kg steps converted.
  static WorkingWeights? of(
    List<Session> log,
    String movement, {
    required DateTime now,
    required MassUnit unit,
    String? kit,
  }) {
    final best = TrainingStats.bestOneRepMax(
      log,
      movement,
      since: now.subtract(window),
    );
    if (best == null) return null;

    final step = loadStep(kit, unit);
    final oneRm = best.estimate.inDisplayUnit(unit);
    final bands = <WeightBand>[];
    for (final range in RepRange.values) {
      final low = _floor(_weightFor(oneRm, range.max), step);
      final high = _floor(_weightFor(oneRm, range.min), step);
      // Rounding down to nothing would put an empty bar in front of somebody.
      // Below one step there is no honest number to give.
      if (low < step) continue;
      bands.add(
        WeightBand(
          range: range,
          low: Mass.inUnit(low, unit),
          high: Mass.inUnit(high, unit),
        ),
      );
    }
    if (bands.isEmpty) return null;
    return WorkingWeights._(from: best, bands: List.unmodifiable(bands));
  }

  /// The set the bands were worked out from.
  final OneRepMax from;

  /// Heaviest range first. A range too light to load is left out.
  final List<WeightBand> bands;

  /// Epley turned around: the weight [reps] can be done with, leaving
  /// [repsInReserve] in the tank.
  static double _weightFor(double oneRm, int reps) =>
      oneRm / (1 + (reps + repsInReserve) / 30);

  /// Down to a multiple of [step]. The nudge keeps 79.999… from becoming 77.5.
  static double _floor(double value, double step) =>
      (value / step + 1e-9).floorToDouble() * step;
}

/// The smallest change in load the kit allows, in [unit].
///
/// A barbell moves by a pair of the smallest plates; dumbbells come in fixed
/// pairs, which most gyms here step by 2 kg; a stack's plates are usually
/// 5 kg. A movement the lifter typed has no known kit, and gets the barbell's.
/// Pounds are their own steps, not these converted.
double loadStep(String? kit, MassUnit unit) => switch (kit) {
  'Dumbbell' => unit.isMetric ? 2 : 5,
  'Machine' || 'Cable' => unit.isMetric ? 5 : 10,
  _ => unit.isMetric ? 2.5 : 5,
};
