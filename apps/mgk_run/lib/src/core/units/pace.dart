import 'distance.dart';
import 'unit_system.dart';

/// An immutable running pace: the time taken to cover a unit distance.
///
/// The canonical representation is **seconds per kilometre**. Seconds-per-mile
/// is derived. Like [Distance], storage is metric and conversion is at display.
class Pace implements Comparable<Pace> {
  const Pace.secondsPerKilometer(this.secondsPerKilometer);

  factory Pace.secondsPerMile(double secondsPerMile) =>
      Pace.secondsPerKilometer(
        secondsPerMile * metersPerKilometer / metersPerMile,
      );

  /// The pace implied by covering [distance] in [duration].
  ///
  /// Throws [ArgumentError] if [distance] is not positive.
  factory Pace.from(Distance distance, Duration duration) {
    if (distance.meters <= 0) {
      throw ArgumentError.value(
        distance.meters,
        'distance',
        'must be greater than zero',
      );
    }
    final seconds = duration.inMicroseconds / Duration.microsecondsPerSecond;
    return Pace.secondsPerKilometer(seconds / distance.kilometers);
  }

  /// The canonical value, in seconds per kilometre.
  final double secondsPerKilometer;

  double get secondsPerMile =>
      secondsPerKilometer * metersPerMile / metersPerKilometer;

  double secondsPerDisplayUnit(UnitSystem system) =>
      system.isMetric ? secondsPerKilometer : secondsPerMile;

  /// A display string such as `5:00 /km` or `8:03 /mi` (`m:ss`).
  String format(UnitSystem system) =>
      '${_formatMinutesSeconds(secondsPerDisplayUnit(system))} '
      '${system.paceSuffix}';

  @override
  int compareTo(Pace other) =>
      secondsPerKilometer.compareTo(other.secondsPerKilometer);

  @override
  bool operator ==(Object other) =>
      other is Pace && other.secondsPerKilometer == secondsPerKilometer;

  @override
  int get hashCode => secondsPerKilometer.hashCode;

  @override
  String toString() => 'Pace(${secondsPerKilometer}s/km)';
}

String _formatMinutesSeconds(double totalSeconds) {
  final rounded = totalSeconds.round();
  final minutes = rounded ~/ 60;
  final seconds = rounded % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
