/// The unit used when *displaying* distances and paces.
///
/// **Distance only.** Mass is [MassUnit] and the two are chosen independently:
/// kilometres with pounds is a perfectly ordinary combination, and a single
/// metric/imperial switch cannot express it. `core.user_settings` has held two
/// columns — `distance_unit` and `weight_unit` — since before this package
/// existed, so the storage was always right and it is the code that had to
/// catch up.
///
/// Storage is metric regardless (see [Distance] and [Pace]); this enum only
/// affects the presentation layer. The load-bearing rule is "store metric,
/// convert at display" — never branch on a unit below the UI.
///
/// **One choice, whole suite.** The preference lives in `core`, not in either
/// app's schema, so a runner who picked miles sees miles wherever a distance
/// appears.
enum UnitSystem {
  metric(distanceSuffix: 'km', paceSuffix: '/km', storedValue: 'km'),
  imperial(distanceSuffix: 'mi', paceSuffix: '/mi', storedValue: 'mi');

  const UnitSystem({
    required this.distanceSuffix,
    required this.paceSuffix,
    required this.storedValue,
  });

  /// Short suffix for a distance in this system, e.g. `km` or `mi`.
  final String distanceSuffix;

  /// Short suffix for a pace in this system, e.g. `/km` or `/mi`.
  final String paceSuffix;

  /// What goes in `core.user_settings.distance_unit`.
  final String storedValue;

  bool get isMetric => this == UnitSystem.metric;

  bool get isImperial => this == UnitSystem.imperial;

  /// Reads `core.user_settings.distance_unit`.
  ///
  /// Anything unrecognised — including the null most accounts have, since only
  /// 5 of 12 hold a settings row — falls back to metric rather than guessing.
  /// Weight values are deliberately **not** accepted here: `'lbs'` reaching a
  /// distance setting means something upstream has crossed the two over, and
  /// silently reading it as miles would hide that.
  static UnitSystem fromStored(String? value) => switch (value) {
    'mi' || 'miles' || 'imperial' => UnitSystem.imperial,
    _ => UnitSystem.metric,
  };
}

/// The unit used when *displaying* a mass.
///
/// Independent of [UnitSystem]. Someone who runs in miles and lifts in
/// kilograms is not confused — that is simply what British gyms and British
/// roads do — and the settings table has always allowed it.
enum MassUnit {
  kilograms(suffix: 'kg', storedValue: 'kg', displayStep: 0.5),
  pounds(suffix: 'lb', storedValue: 'lbs', displayStep: 1);

  const MassUnit({
    required this.suffix,
    required this.storedValue,
    required this.displayStep,
  });

  /// Short suffix, e.g. `kg` or `lb`.
  ///
  /// `lb` rather than `lbs`: the symbol is unpluralised. The value stored in
  /// `core.user_settings.weight_unit` is the string `'lbs'`, which is a
  /// separate thing — see [storedValue]. Map it; do not display it.
  final String suffix;

  /// What goes in `core.user_settings.weight_unit`.
  final String storedValue;

  /// The smallest increment worth showing.
  ///
  /// Plates are discrete and the conversion between them is not, so a displayed
  /// weight snaps to something loadable. Switching to pounds therefore shows
  /// the closest the rounding can get; the next weight entered is a whole
  /// pound value and stored as its exact equivalent.
  final double displayStep;

  bool get isMetric => this == MassUnit.kilograms;

  /// Reads `core.user_settings.weight_unit`.
  ///
  /// Note the app default this replaces: Liftio defaulted to `'lbs'` when no
  /// row existed. This falls back to kilograms instead, matching the rest of
  /// the suite rather than one app's history.
  static MassUnit fromStored(String? value) => switch (value) {
    'lbs' || 'lb' || 'pounds' || 'imperial' => MassUnit.pounds,
    _ => MassUnit.kilograms,
  };
}
