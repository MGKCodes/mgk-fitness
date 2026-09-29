import 'package:flutter/foundation.dart';

/// Everything the app needs from the outside world, read at compile time.
///
/// Supplied by `--dart-define-from-file=config/app_config.json`, which is
/// **gitignored** because it carries real keys. `config/app_config.example.json`
/// is committed with placeholders. This repo is public, so credentials must not
/// live in it.
///
/// A build without the file comes out unable to reach Supabase rather than
/// failing loudly — [isConfigured] is false and the app says so on a dedicated
/// screen. That is deliberate: a missing define is a build mistake, and crashing
/// on launch makes it look like an app bug.
class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    this.revenueCatKey = '',
    this.revenueCatGoogleKey = '',
  });

  /// Reads the compile-time environment.
  ///
  /// The RevenueCat names are Run's, deliberately: the keys differ per app but
  /// each build only ever holds its own, so the same name in two Codemagic
  /// groups is two answers to one question rather than a collision.
  factory AppConfig.fromEnvironment() => const AppConfig(
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    supabasePublishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
    revenueCatKey: String.fromEnvironment('REVENUECAT_PUBLIC_KEY'),
    revenueCatGoogleKey: String.fromEnvironment('REVENUECAT_GOOGLE_KEY'),
  );

  final String supabaseUrl;

  /// The publishable (anon) key. **Never** the service key: this one is meant to
  /// be public and ships in every binary, and RLS is what protects the data.
  final String supabasePublishableKey;

  /// RevenueCat's public SDK key for Lift's **App Store** app — `appl_…`.
  ///
  /// Configuration rather than a secret, like the publishable key above: it is
  /// designed to ship in a client. The webhook secret is the one that matters,
  /// and it never leaves the server.
  final String revenueCatKey;

  /// The same, for Lift's **Google Play** app — `goog_…`. A separate key
  /// because RevenueCat issues one per store app, and the wrong one does not
  /// degrade: the SDK refuses to configure at all.
  final String revenueCatGoogleKey;

  /// Whether this build can actually reach a backend.
  ///
  /// The URL has to parse with a host, not merely be non-empty. Build 9 shipped
  /// `SUPABASE_URL` as a bare `<ref>.supabase.co`: non-empty, but it parses as a
  /// *path*, so every request failed with "No host specified in URI" — and only
  /// at the first sign-up, long after the app looked healthy. A build that
  /// cannot reach Supabase should say so on the first screen instead.
  ///
  /// `http` is permitted so a local Supabase stack still works. The release
  /// build insists on https in `codemagic.yaml`, which is where a plaintext
  /// backend would actually matter.
  bool get isConfigured =>
      _hasHost(supabaseUrl) && supabasePublishableKey.isNotEmpty;

  /// The key for the store this build is running against.
  String get storeKey {
    if (kIsWeb) return '';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => revenueCatGoogleKey,
      _ => revenueCatKey,
    };
  }

  /// Whether this build can sell anything. False is a normal state — a local
  /// build, or one made before the store apps existed — and the paywall says so
  /// rather than showing a shop with nothing in it.
  bool get canSell => storeKey.isNotEmpty;

  static bool _hasHost(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.host.isNotEmpty &&
        (uri.scheme == 'https' || uri.scheme == 'http');
  }
}
