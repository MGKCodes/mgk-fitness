/// The platform-correct default [DisclaimerStore], chosen at compile time.
///
/// A conditional export, so widgets that only need *a* store never pull
/// `dart:io` into their import graph. That keeps the web preview harness
/// compilable while iOS still gets real persistence.
///
/// ```dart
/// final store = disclaimer ?? createDisclaimerStore();
/// ```
library;

export 'disclaimer_store_stub.dart'
    if (dart.library.io) 'disclaimer_store_io.dart';
