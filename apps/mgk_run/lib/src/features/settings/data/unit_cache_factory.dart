/// The platform-correct default [UnitCache], chosen at compile time.
///
/// A conditional export so nothing that merely needs *a* cache drags `dart:io`
/// into its import graph, keeping the web preview harness compilable while iOS
/// gets real persistence. Same shape as `disclaimer_store_factory.dart`.
library;

export 'unit_cache_stub.dart' if (dart.library.io) 'unit_cache_io.dart';
