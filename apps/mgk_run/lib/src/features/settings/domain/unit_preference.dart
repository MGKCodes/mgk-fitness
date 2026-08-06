import 'package:mgk_units/mgk_units.dart';

/// Translation between [UnitSystem] and the text stored in the **shared**
/// `public.user_settings.distance_unit` column.
///
/// The column is shared with Liftio (ADR-0008) and Liftio already writes `'km'`,
/// so that vocabulary is fixed for us — Runio matches it rather than inventing
/// `metric`/`imperial` and leaving the sibling app reading a value it doesn't
/// understand.
///
/// Decoding is deliberately tolerant: an unknown, empty or absent value is
/// metric, never an error. A user with no settings row is indistinguishable from
/// one who never chose, and both should simply see the default.
extension UnitPreference on UnitSystem {
  /// The value to store in the shared column.
  String get storedValue => switch (this) {
    UnitSystem.metric => 'km',
    UnitSystem.imperial => 'mi',
  };

  /// Reads a stored value, defaulting to metric for anything unrecognised.
  static UnitSystem fromStored(Object? value) {
    final text = value?.toString().trim().toLowerCase();
    if (text == null || text.isEmpty) return UnitSystem.metric;
    return switch (text) {
      'mi' || 'mile' || 'miles' || 'imperial' => UnitSystem.imperial,
      _ => UnitSystem.metric,
    };
  }
}
