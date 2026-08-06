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
  });

  /// Reads the compile-time environment.
  factory AppConfig.fromEnvironment() => const AppConfig(
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    supabasePublishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
  );

  final String supabaseUrl;

  /// The publishable (anon) key. **Never** the service key: this one is meant to
  /// be public and ships in every binary, and RLS is what protects the data.
  final String supabasePublishableKey;

  bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
