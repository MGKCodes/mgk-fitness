import 'package:flutter/foundation.dart';

/// A pre-seeded developer account for the debug-only quick sign-in buttons.
///
/// Sourced from **local, gitignored** config — never committed. This repo is
/// public, so credentials must not live in it. See [AppConfig.devAccounts].
class DevAccount {
  const DevAccount({
    required this.label,
    required this.email,
    required this.password,
  });

  final String label;
  final String email;
  final String password;
}

/// Compile-time application configuration.
///
/// Injected at build time with
/// `--dart-define-from-file=config/app_config.json` (see the committed
/// `config/app_config.example.json`). Nothing here is a hard secret — the
/// Supabase URL and publishable key are designed to ship in a client, gated by
/// Row Level Security — but real values are kept out of the repo all the same.
class AppConfig {
  const AppConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    this.mapTileUrlTemplate = '',
    this.mapAttribution = '',
    this.revenueCatKey = '',
    this.revenueCatGoogleKey = '',
  });

  final String supabaseUrl;
  final String supabasePublishableKey;

  /// The basemap tile template, e.g.
  /// `https://api.maptiler.com/maps/streets-v2-dark/{z}/{x}/{y}.png?key=…`.
  ///
  /// Configured rather than hard-coded so the shipped app only ever calls the
  /// provider named in the privacy policy, and so a restricted key stays
  /// out of this public repo. Empty means **draw no basemap** — the route still
  /// renders on the charcoal base. See [hasBasemap].
  final String mapTileUrlTemplate;

  /// Attribution required by the tile provider's terms, shown on the map.
  final String mapAttribution;

  /// RevenueCat's **public** SDK key for the **Apple** store, beginning
  /// `appl_`.
  ///
  /// Designed to ship in a client, exactly like [supabasePublishableKey]: it
  /// can present offerings and start a purchase and nothing else. The secret
  /// that matters is `REVENUECAT_WEBHOOK_SECRET`, which authenticates the
  /// server-to-server webhook and never leaves Supabase.
  ///
  /// Empty is a normal state, not an error. A build made before the RevenueCat
  /// account existed cannot sell anything, and the paywall says so rather than
  /// showing an empty shop. See [canSell].
  ///
  /// **Read [storeKey], not this**, anywhere that is about to configure the
  /// SDK. This field is the Apple half of a pair.
  final String revenueCatKey;

  /// RevenueCat's public SDK key for the **Google** store, beginning `goog_`.
  ///
  /// A second field rather than one key reused, because RevenueCat issues a
  /// *different* key per platform within the same project and configuring the
  /// SDK with the other store's key does not degrade — it fails outright, with
  /// no offerings and no purchase. There is no single value that could be
  /// correct on both, which is why this cannot be one variable set twice.
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

  static bool _hasHost(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.host.isNotEmpty &&
        (uri.scheme == 'https' || uri.scheme == 'http');
  }

  /// Whether a basemap is available. False in a build with no tile provider
  /// configured, which is a normal state rather than an error.
  bool get hasBasemap => mapTileUrlTemplate.isNotEmpty;

  /// The RevenueCat key for the store this build will actually be sold
  /// through — the only one worth configuring the SDK with.
  ///
  /// Resolved at runtime rather than at build time because one `AppConfig` is
  /// compiled per *build*, and a build knows its platform; the alternative was
  /// a single `REVENUECAT_PUBLIC_KEY` set to whichever key the workflow
  /// happened to mean, which is how the Android build shipped with the Apple
  /// key latent in it and no way for the app to notice.
  ///
  /// Web is empty on purpose. `purchases_flutter` has no web implementation,
  /// so the preview harness must fall through to [canSell] being false and get
  /// the gate's no-button state rather than a paywall that cannot transact.
  String get storeKey {
    if (kIsWeb) return '';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => revenueCatGoogleKey,
      _ => revenueCatKey,
    };
  }

  /// Whether this build can take a payment. False leaves the coach gate as a
  /// statement of what a subscription buys, with no button to press.
  ///
  /// Keyed on [storeKey], so an Android build with only the Apple key
  /// configured reports false — which is the honest answer, since that build
  /// could not have completed a purchase.
  bool get canSell => storeKey.isNotEmpty;

  /// The configuration baked in at build time.
  static const AppConfig current = AppConfig(
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    supabasePublishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
    mapTileUrlTemplate: String.fromEnvironment('MAP_TILE_URL_TEMPLATE'),
    mapAttribution: String.fromEnvironment('MAP_ATTRIBUTION'),
    revenueCatKey: String.fromEnvironment('REVENUECAT_PUBLIC_KEY'),
    revenueCatGoogleKey: String.fromEnvironment('REVENUECAT_GOOGLE_KEY'),
  );

  // Optional developer quick-sign-in accounts, injected only in local builds
  // via --dart-define-from-file. Absent in any build that does not supply them,
  // and never surfaced outside debug mode (see SignInScreen). Up to three; an
  // account is included only when its email and password are both non-empty.
  static const String _dev1Label = String.fromEnvironment(
    'DEV_ACCOUNT_1_LABEL',
  );
  static const String _dev1Email = String.fromEnvironment(
    'DEV_ACCOUNT_1_EMAIL',
  );
  static const String _dev1Password = String.fromEnvironment(
    'DEV_ACCOUNT_1_PASSWORD',
  );
  static const String _dev2Label = String.fromEnvironment(
    'DEV_ACCOUNT_2_LABEL',
  );
  static const String _dev2Email = String.fromEnvironment(
    'DEV_ACCOUNT_2_EMAIL',
  );
  static const String _dev2Password = String.fromEnvironment(
    'DEV_ACCOUNT_2_PASSWORD',
  );
  static const String _dev3Label = String.fromEnvironment(
    'DEV_ACCOUNT_3_LABEL',
  );
  static const String _dev3Email = String.fromEnvironment(
    'DEV_ACCOUNT_3_EMAIL',
  );
  static const String _dev3Password = String.fromEnvironment(
    'DEV_ACCOUNT_3_PASSWORD',
  );

  /// Developer quick-sign-in accounts supplied by local config, if any. Empty
  /// unless the corresponding `DEV_ACCOUNT_*` defines were provided at build.
  List<DevAccount> get devAccounts {
    final rows = <List<String>>[
      [_dev1Label, _dev1Email, _dev1Password],
      [_dev2Label, _dev2Email, _dev2Password],
      [_dev3Label, _dev3Email, _dev3Password],
    ];
    return <DevAccount>[
      for (final row in rows)
        if (row[1].isNotEmpty && row[2].isNotEmpty)
          DevAccount(
            label: row[0].isNotEmpty ? row[0] : row[1],
            email: row[1],
            password: row[2],
          ),
    ];
  }
}
