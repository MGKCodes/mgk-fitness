import 'package:mgk_ui/mgk_ui.dart';

/// Re-exported so this file is the single import for every name the app
/// shows a person: the platform half, this app's half, and the two joined.
export 'package:mgk_ui/mgk_ui.dart' show kPlatformName;

/// This app's half of the product name, and the label on the home screen.
///
/// **Must stay identical to `CFBundleDisplayName` and `android:label`.** Copy
/// tells people where to find the app in system settings, and that sentence is
/// a lie the moment the two drift.
///
/// The home-screen label is only the app half on purpose — iOS truncates an
/// icon label at roughly twelve characters, so `MGKFitness: Run` and
/// `MGKFitness: Lift` would both render as `MGKFitness:…`. The store listing
/// carries the platform name; the phone carries the app name.
///
/// Note the bundle identifier does not follow: this app ships as
/// `com.mgkcodes.liftio` on both stores and always will, because changing it
/// makes a new app with no users, reviews or purchases. See
/// `docs/naming.md`.
const String kAppName = 'Lift';

/// The full product name: the App Store listing, and what copy says on first
/// mention.
///
/// ## The rule for prose
///
/// First mention in a document gets [kProductName]. After that, say "the app".
///
/// **Never write a bare "Lift" into a sentence.** The app is named after a noun
/// the domain already uses, so "your Lift data" and "your lift data" read as
/// the same phrase meaning different things. The full name and "the app" both
/// dodge it.
const String kProductName = '$kPlatformName: $kAppName';

/// Where a lifter writes to us: support, and anything the policy says to email.
///
/// One address for this app, on the suite's own domain. `docs/` and the pages
/// under `web/` name it too, and `legal_copy_test.dart` holds the three
/// together.
const String kSupportEmail = 'lift@mgkfitness.mgkcodes.com';

/// Lift's support page on the suite's site, which both store listings point
/// at. Settings opens it, as Run's Settings opens Run's.
const String kSupportUrl = 'https://mgkfitness.mgkcodes.com/lift/support';
