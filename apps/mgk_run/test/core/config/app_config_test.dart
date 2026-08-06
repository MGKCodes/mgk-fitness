import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/config/app_config.dart';

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
  });
}
