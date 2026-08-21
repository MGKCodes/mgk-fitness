/// The platform half of every product name in the suite.
///
/// **One line, because it is deliberately temporary.** `MGKFitness` is a
/// placeholder for a consumer name that does not exist yet — it was chosen so
/// that not having one stops delaying releases, not because it is right. The
/// entire reason every mention routes through this const is that replacing it
/// later should cost one edit rather than a sweep of eighty-odd strings.
///
/// So: never hard-code the platform name in copy. If you are about to type
/// "MGKFitness" into a string, import this instead.
///
/// ## What cannot read this
///
/// Four things are outside Dart's reach and have to be changed by hand. This is
/// the complete list, and `docs/naming.md` holds it too:
///
///   * `apps/*/ios/Runner/Info.plist` — `CFBundleDisplayName`
///   * `apps/*/android/app/src/main/AndroidManifest.xml` — `android:label`
///   * the App Store Connect and Play Console listing names
///   * the published privacy policy and medical disclaimer, which have to match
///     the in-app copy word for word
///
/// The home-screen labels deliberately do **not** carry the platform name — see
/// each app's `brand.dart` for why — which means a future rename touches the
/// store listings and this const, and leaves the phone alone.
const String kPlatformName = 'MGKFitness';
