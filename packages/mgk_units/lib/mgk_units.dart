/// Measurement types for the MGKCodes fitness suite.
///
/// One rule, expressed four ways: **storage is canonical metric, conversion
/// happens at display.** [Distance] holds metres, [Elevation] holds metres of
/// climb, [Pace] holds seconds per kilometre, [Mass] holds kilograms, and
/// [UnitSystem] exists only so the presentation layer knows what to render them
/// as.
///
/// Extracted from the running app once a second caller existed, rather than
/// designed for one that did not. It is pure Dart on purpose — measurement is a
/// domain concern, so the rules are testable without a widget binding and this
/// package can never quietly grow a dependency on the UI it sits below.
///
/// The failure it exists to prevent has already happened once: Liftio stored
/// weights as unitless numbers and appended whichever label the account was set
/// to, so changing the setting silently reinterpreted every set ever logged.
library;

export 'src/distance.dart';
export 'src/elevation.dart';
export 'src/duration_format.dart';
export 'src/mass.dart';
export 'src/pace.dart';
export 'src/unit_system.dart';
