import 'package:mgk_units/mgk_units.dart';

/// A local copy of the runner's unit choice, so a cold launch with no network
/// shows the units they picked instead of defaulting to kilometres.
///
/// The server is the store of record (the column is shared with Liftio); this is
/// only a cache. Like the rest of the offline-first plumbing it must never
/// throw — an unreadable cache is simply a cache miss.
abstract interface class UnitCache {
  /// The cached unit, or null if nothing has been cached.
  Future<UnitSystem?> read();

  Future<void> write(UnitSystem unit);
}

/// A [UnitCache] that lasts for the session — web preview and tests.
class InMemoryUnitCache implements UnitCache {
  InMemoryUnitCache({UnitSystem? unit}) : _unit = unit;

  UnitSystem? _unit;

  @override
  Future<UnitSystem?> read() async => _unit;

  @override
  Future<void> write(UnitSystem unit) async => _unit = unit;
}
