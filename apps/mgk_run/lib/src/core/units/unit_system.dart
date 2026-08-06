/// The unit system used when *displaying* distances and paces.
///
/// Runio stores everything in metric (see [Distance] and [Pace]); this enum
/// only affects the presentation layer. The load-bearing rule is "store metric,
/// convert at display" — never branch on a unit system below the UI.
enum UnitSystem {
  metric(distanceSuffix: 'km', paceSuffix: '/km'),
  imperial(distanceSuffix: 'mi', paceSuffix: '/mi');

  const UnitSystem({required this.distanceSuffix, required this.paceSuffix});

  /// Short suffix for a distance in this system, e.g. `km` or `mi`.
  final String distanceSuffix;

  /// Short suffix for a pace in this system, e.g. `/km` or `/mi`.
  final String paceSuffix;

  bool get isMetric => this == UnitSystem.metric;

  bool get isImperial => this == UnitSystem.imperial;
}
