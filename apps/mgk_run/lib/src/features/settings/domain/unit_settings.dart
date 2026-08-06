import 'package:mgk_units/mgk_units.dart';

/// Where the runner's chosen display unit is read and written.
///
/// An interface so the preview harness and widget tests can supply a fake — the
/// real implementation talks to Supabase, which neither has.
///
/// **Neither method may throw.** A unit preference is cosmetic: failing to read
/// it should show kilometres, never an error screen, and failing to write it
/// should not lose the runner's tap in the UI. Callers rely on that.
abstract interface class UnitSettings {
  /// The unit to display in. Returns [UnitSystem.metric] when there is nothing
  /// stored, nothing cached, and no way to ask.
  Future<UnitSystem> load();

  /// Records the choice. Best-effort: a failure to reach the server must still
  /// leave the choice in effect on this device.
  Future<void> save(UnitSystem unit);
}

/// A [UnitSettings] that forgets on restart — the preview harness, widget tests,
/// and the fallback when no real implementation is wired.
class InMemoryUnitSettings implements UnitSettings {
  InMemoryUnitSettings({UnitSystem unit = UnitSystem.metric}) : _unit = unit;

  UnitSystem _unit;

  /// Every unit saved, in order — handy in tests.
  final List<UnitSystem> saved = <UnitSystem>[];

  @override
  Future<UnitSystem> load() async => _unit;

  @override
  Future<void> save(UnitSystem unit) async {
    _unit = unit;
    saved.add(unit);
  }
}
