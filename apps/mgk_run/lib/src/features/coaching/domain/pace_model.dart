import 'dart:math' as math;

import '../../../core/units/distance.dart';
import '../../../core/units/pace.dart';
import '../../../core/units/unit_system.dart';

/// Deterministic pace derivation — done in **Dart, never the LLM** (see
/// docs/architecture/plan-generation.md). One input, a recent race or time
/// trial, produces predicted times and the training zones.
///
/// Everything here is a formula (Riegel, % of threshold). No VDOT tables or
/// published schedules are reproduced — those are copyrighted and this repo is
/// public (ADR-0003).

/// Riegel's endurance exponent.
const double riegelExponent = 1.06;

/// Predicts the time to cover [to], given a known result of [fromTime] over
/// [from]: `T₂ = T₁ × (D₂/D₁)^1.06`.
Duration riegelPredict(Distance from, Duration fromTime, Distance to) {
  final ratio = to.meters / from.meters;
  final seconds = fromTime.inSeconds * math.pow(ratio, riegelExponent);
  return Duration(seconds: seconds.round());
}

/// Training zones derived from one race result. Each zone is a fraction of
/// **threshold speed** (so a smaller fraction is a slower pace): easy ~77%,
/// marathon ~88%, threshold 100%, interval ~107%.
class TrainingPaces {
  const TrainingPaces({required this.thresholdSecondsPerKm});

  final double thresholdSecondsPerKm;

  /// Derives zones from a race/time-trial result. Threshold is taken as the
  /// pace sustainable for a ~60-minute effort, found from the result via Riegel.
  factory TrainingPaces.fromRace(Distance distance, Duration time) {
    if (distance.meters <= 0 || time.inSeconds <= 0) {
      throw ArgumentError('race distance and time must be positive');
    }
    // Distance whose predicted time is ~1 hour: D₁ × (3600/T₁)^(1/1.06).
    final thresholdMeters =
        distance.meters *
        math.pow(3600 / time.inSeconds, 1 / riegelExponent).toDouble();
    final thresholdSecPerKm = 3600 / (thresholdMeters / 1000);
    return TrainingPaces(thresholdSecondsPerKm: thresholdSecPerKm);
  }

  Pace get recovery => _atSpeedFraction(0.70);
  Pace get easy => _atSpeedFraction(0.775);
  Pace get marathon => _atSpeedFraction(0.88);
  Pace get threshold => _atSpeedFraction(1.0);
  Pace get interval => _atSpeedFraction(1.07);

  /// The same zones as **bands**, which is what they actually are.
  ///
  /// A single number is false precision twice over: the threshold pace it hangs
  /// off is a Riegel extrapolation from one time trial, and no runner holds a
  /// pace to the second on a rolling road in a headwind. Telling someone to run
  /// 4:39 /km invites them to treat 4:45 as a failure, which is the opposite of
  /// what an easy run is for. The band is the honest form of the same number.
  PaceBand get recoveryBand => _band(0.66, 0.74);
  PaceBand get easyBand => _band(0.745, 0.805);
  PaceBand get marathonBand => _band(0.855, 0.905);
  PaceBand get thresholdBand => _band(0.97, 1.03);
  PaceBand get intervalBand => _band(1.04, 1.10);

  /// Pace at [fraction] of threshold *speed*. Pace scales inversely with speed.
  Pace _atSpeedFraction(double fraction) =>
      Pace.secondsPerKilometer(thresholdSecondsPerKm / fraction);

  /// A band between two speed fractions. The *slower* pace comes from the lower
  /// fraction, so the band reads slow-to-fast the way a runner would say it.
  PaceBand _band(double slowFraction, double fastFraction) => PaceBand(
    slow: _atSpeedFraction(slowFraction),
    fast: _atSpeedFraction(fastFraction),
  );
}

/// A range of paces to aim between, rather than a single number to miss.
class PaceBand {
  const PaceBand({required this.slow, required this.fast});

  /// The slower end — the larger seconds-per-km.
  final Pace slow;

  /// The faster end.
  final Pace fast;

  /// The midpoint, for the places that genuinely need one value.
  Pace get middle => Pace.secondsPerKilometer(
    (slow.secondsPerKilometer + fast.secondsPerKilometer) / 2,
  );

  /// `5:40–6:00 /km` — one unit suffix, not two.
  String format(UnitSystem unit) {
    final fastText = fast.format(unit);
    final suffix = ' ${unit.paceSuffix}';
    final fastValue = fastText.endsWith(suffix)
        ? fastText.substring(0, fastText.length - suffix.length)
        : fastText;
    return '$fastValue–${slow.format(unit)}';
  }
}
