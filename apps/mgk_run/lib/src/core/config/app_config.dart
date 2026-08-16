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

  bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  /// Whether a basemap is available. False in a build with no tile provider
  /// configured, which is a normal state rather than an error.
  bool get hasBasemap => mapTileUrlTemplate.isNotEmpty;

  /// The configuration baked in at build time.
  static const AppConfig current = AppConfig(
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    supabasePublishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
    mapTileUrlTemplate: String.fromEnvironment('MAP_TILE_URL_TEMPLATE'),
    mapAttribution: String.fromEnvironment('MAP_ATTRIBUTION'),
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
