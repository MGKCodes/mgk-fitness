import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/core/config/app_config.dart';

void main() {
  group('AppConfig', () {
    test('is configured when both values are present', () {
      const config = AppConfig(
        supabaseUrl: 'https://x.supabase.co',
        supabasePublishableKey: 'key',
      );
      expect(config.isConfigured, isTrue);
    });

    test('is not configured when a value is empty', () {
      expect(
        const AppConfig(
          supabaseUrl: '',
          supabasePublishableKey: 'key',
        ).isConfigured,
        isFalse,
      );
      expect(
        const AppConfig(
          supabaseUrl: 'https://x.supabase.co',
          supabasePublishableKey: '',
        ).isConfigured,
        isFalse,
      );
    });

    // Build 9 shipped a bare host here and the app looked healthy right up to
    // the first sign-up, which failed with "No host specified in URI".
    test('is not configured when the URL has no scheme', () {
      expect(
        const AppConfig(
          supabaseUrl: 'cwpwzxjjhxbkwhrgnasn.supabase.co',
          supabasePublishableKey: 'key',
        ).isConfigured,
        isFalse,
      );
    });

    test('is configured against a local http stack', () {
      expect(
        const AppConfig(
          supabaseUrl: 'http://127.0.0.1:54321',
          supabasePublishableKey: 'key',
        ).isConfigured,
        isTrue,
      );
    });
  });
}
