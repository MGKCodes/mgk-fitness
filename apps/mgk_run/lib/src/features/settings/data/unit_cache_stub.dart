import 'unit_cache.dart';

/// Web default (the preview harness only — Runio ships to iOS). No `dart:io`
/// here, so the choice lasts the session and is re-read from the server on the
/// next load, which is the harmless direction for a display preference.
UnitCache createUnitCache() => InMemoryUnitCache();
