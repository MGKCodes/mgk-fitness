import 'file_unit_cache.dart';
import 'unit_cache.dart';

/// Native (iOS) default: the unit choice persists to the filesystem.
UnitCache createUnitCache() => FileUnitCache();
