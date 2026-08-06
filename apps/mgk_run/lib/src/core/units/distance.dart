import 'unit_system.dart';

/// Metres in one kilometre.
const double metersPerKilometer = 1000.0;

/// Metres in one statute mile (exact).
const double metersPerMile = 1609.344;

/// An immutable distance.
///
/// The canonical representation is **meters**. Kilometres and miles are derived
/// on demand — this is the "store metric, convert at display" rule in code.
class Distance implements Comparable<Distance> {
  const Distance.meters(this.meters);

  factory Distance.kilometers(double kilometers) =>
      Distance.meters(kilometers * metersPerKilometer);

  factory Distance.miles(double miles) =>
      Distance.meters(miles * metersPerMile);

  /// The canonical value, in meters.
  final double meters;

  double get kilometers => meters / metersPerKilometer;

  double get miles => meters / metersPerMile;

  /// The magnitude expressed in [system]'s distance unit (km or mi).
  double inDisplayUnit(UnitSystem system) =>
      system.isMetric ? kilometers : miles;

  /// A display string such as `5.00 km` or `3.11 mi`.
  String format(UnitSystem system, {int fractionDigits = 2}) =>
      '${inDisplayUnit(system).toStringAsFixed(fractionDigits)} '
      '${system.distanceSuffix}';

  Distance operator +(Distance other) => Distance.meters(meters + other.meters);

  Distance operator -(Distance other) => Distance.meters(meters - other.meters);

  bool operator <(Distance other) => meters < other.meters;

  bool operator <=(Distance other) => meters <= other.meters;

  bool operator >(Distance other) => meters > other.meters;

  bool operator >=(Distance other) => meters >= other.meters;

  @override
  int compareTo(Distance other) => meters.compareTo(other.meters);

  @override
  bool operator ==(Object other) => other is Distance && other.meters == meters;

  @override
  int get hashCode => meters.hashCode;

  @override
  String toString() => 'Distance(${meters}m)';
}
