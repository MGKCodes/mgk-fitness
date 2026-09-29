/// The platform-correct default [AiConsentStore], chosen at compile time.
///
/// A conditional export so nothing that merely needs to *ask* whether the
/// coach may send drags `dart:io` into its import graph. Same shape as
/// `backup_consent_factory.dart`.
library;

export 'ai_consent_stub.dart' if (dart.library.io) 'ai_consent_io.dart';
