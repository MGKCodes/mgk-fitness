import 'package:mgk_ui/mgk_ui.dart';

/// Re-exported so this file is the single import for every name the app
/// shows a person: the platform half, this app's half, and the two joined.
export 'package:mgk_ui/mgk_ui.dart' show kPlatformName;

/// This app's half of the product name, and the label on the home screen.
///
/// **Must stay identical to `CFBundleDisplayName` and `android:label`.** Copy
/// tells people where to find the app in system settings — "Settings › Run ›
/// Location" — and that sentence is a lie the moment the two drift.
///
/// The home-screen label is only the app half on purpose. iOS truncates an icon
/// label at roughly twelve characters, so `MGKFitness: Run` and
/// `MGKFitness: Lift` would both render as `MGKFitness:…` and become
/// indistinguishable on the same home screen. The store listing carries the
/// platform name; the phone carries the app name. The happy side effect is that
/// renaming [kPlatformName] later does not touch the phone at all.
const String kAppName = 'Run';

/// The full product name: the App Store listing, and what copy says on first
/// mention.
///
/// ## The rule for prose
///
/// First mention in a document gets [kProductName]. After that, say "the app".
///
/// **Never write a bare "Run" into a sentence.** This app is named after the
/// noun it measures, so "your Run data" and "your run data" are the same phrase
/// carrying different meanings, and a reader cannot tell which one you meant.
/// The full name and "the app" both dodge it; the bare app name does not.
const String kProductName = '$kPlatformName: $kAppName';
