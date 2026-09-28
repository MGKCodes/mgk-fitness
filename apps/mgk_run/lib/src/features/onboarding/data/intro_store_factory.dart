/// The platform-correct default [IntroStore], chosen at compile time.
///
/// A conditional export, so widgets that only need *a* store never pull
/// `dart:io` into their import graph. That keeps the web preview harness
/// compilable while iOS still gets real persistence.
///
/// ```dart
/// final store = introStore ?? createIntroStore();
/// ```
library;

export 'intro_store_stub.dart' if (dart.library.io) 'intro_store_io.dart';
