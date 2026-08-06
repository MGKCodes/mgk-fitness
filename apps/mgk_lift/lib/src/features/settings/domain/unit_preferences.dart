import 'package:meta/meta.dart';
import 'package:mgk_units/mgk_units.dart';

/// What the lifter has chosen to see things in.
///
/// **Two independent choices, not one metric/imperial switch.** Miles with
/// kilograms is ordinary — British roads and British gyms disagree with each
/// other — and `core.user_settings` has always had two columns to say so.
@immutable
class UnitPreferences {
  const UnitPreferences({
    this.distance = UnitSystem.metric,
    this.mass = MassUnit.kilograms,
  });

  final UnitSystem distance;
  final MassUnit mass;

  UnitPreferences copyWith({UnitSystem? distance, MassUnit? mass}) =>
      UnitPreferences(
        distance: distance ?? this.distance,
        mass: mass ?? this.mass,
      );

  @override
  bool operator ==(Object other) =>
      other is UnitPreferences &&
      other.distance == distance &&
      other.mass == mass;

  @override
  int get hashCode => Object.hash(distance, mass);
}

/// Where the choice is read and written.
///
/// Backed by `core.user_settings`, which is **shared with Run** — changing
/// units in one app changes them in the other, because it is one account and
/// one person. That is the point of the setting living in `core` rather than in
/// either app's schema.
///
/// Neither method throws. A display unit is not worth failing a launch over: a
/// read that cannot reach the server falls back to the last known choice, and a
/// write that cannot reach it is reconciled on the next one.
abstract interface class UnitPreferencesStore {
  Future<UnitPreferences> load();
  Future<void> save(UnitPreferences prefs);
}

/// Keeps the choice for the session only. What tests and previews want, and the
/// fallback when there is no backend wired up.
class InMemoryUnitPreferences implements UnitPreferencesStore {
  InMemoryUnitPreferences([this._prefs = const UnitPreferences()]);

  UnitPreferences _prefs;

  @override
  Future<UnitPreferences> load() async => _prefs;

  @override
  Future<void> save(UnitPreferences prefs) async => _prefs = prefs;
}
