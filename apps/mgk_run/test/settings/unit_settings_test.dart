import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/units/unit_system.dart';
import 'package:mgk_run/src/features/settings/data/supabase_unit_settings.dart';
import 'package:mgk_run/src/features/settings/data/unit_cache.dart';
import 'package:mgk_run/src/features/settings/domain/unit_preference.dart';
import 'package:mgk_run/src/features/settings/domain/unit_settings.dart';
import 'package:mgk_run/src/features/settings/presentation/settings_screen.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';

/// A cache that records how often it was consulted.
class _CountingCache implements UnitCache {
  _CountingCache([this._unit]);

  UnitSystem? _unit;
  int reads = 0;
  final List<UnitSystem> writes = <UnitSystem>[];

  @override
  Future<UnitSystem?> read() async {
    reads++;
    return _unit;
  }

  @override
  Future<void> write(UnitSystem unit) async {
    _unit = unit;
    writes.add(unit);
  }
}

void main() {
  group('the shared km/mi vocabulary', () {
    test('encodes to what Liftio already writes', () {
      // Liftio stores 'km'; inventing 'metric' would leave the sibling app
      // reading a value it does not understand.
      expect(UnitSystem.metric.storedValue, 'km');
      expect(UnitSystem.imperial.storedValue, 'mi');
    });

    test('decodes the values Liftio and Runio write', () {
      expect(UnitPreference.fromStored('km'), UnitSystem.metric);
      expect(UnitPreference.fromStored('mi'), UnitSystem.imperial);
      expect(UnitPreference.fromStored('MI'), UnitSystem.imperial);
      expect(UnitPreference.fromStored(' miles '), UnitSystem.imperial);
    });

    test('anything unrecognised is metric, never an error', () {
      // A user with no settings row looks identical to one who never chose.
      for (final value in <Object?>[null, '', '   ', 'furlongs', 42]) {
        expect(
          UnitPreference.fromStored(value),
          UnitSystem.metric,
          reason: 'value: $value',
        );
      }
    });

    test('a value survives a round trip', () {
      for (final unit in UnitSystem.values) {
        expect(UnitPreference.fromStored(unit.storedValue), unit);
      }
    });
  });

  group('SupabaseUnitSettings', () {
    // No Supabase is initialised in tests, so the client resolves to null and
    // every remote call is a no-op — which is exactly the offline path.
    test('a cached choice is returned with no server reachable', () async {
      final cache = _CountingCache(UnitSystem.imperial);
      final settings = SupabaseUnitSettings(cache: cache);

      expect(await settings.load(), UnitSystem.imperial);
      expect(cache.reads, 1);
    });

    test('no cache and no server falls back to metric', () async {
      final settings = SupabaseUnitSettings(cache: _CountingCache());
      expect(await settings.load(), UnitSystem.metric);
    });

    test(
      'saving writes the cache even when the server cannot be told',
      () async {
        final cache = _CountingCache();
        final settings = SupabaseUnitSettings(cache: cache);

        await settings.save(UnitSystem.imperial);

        expect(cache.writes, <UnitSystem>[UnitSystem.imperial]);
        // The choice must hold on this device regardless of the push.
        expect(await settings.load(), UnitSystem.imperial);
      },
    );

    test('load and save never throw', () async {
      final settings = SupabaseUnitSettings(cache: _CountingCache());
      await expectLater(settings.load(), completes);
      await expectLater(settings.save(UnitSystem.imperial), completes);
    });
  });

  testWidgets('choosing miles stores it and tells the app', (tester) async {
    final settings = InMemoryUnitSettings();
    UnitSystem? announced;

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          unit: UnitSystem.metric,
          settings: settings,
          auth: FakeAuthRepository(signedIn: true, email: 'dev@runio.app'),
          onUnitChanged: (u) => announced = u,
        ),
      ),
    );

    await tester.tap(find.text('Miles'));
    await tester.pumpAndSettle();

    expect(settings.saved, <UnitSystem>[UnitSystem.imperial]);
    expect(
      announced,
      UnitSystem.imperial,
      reason: 'the app around it must re-render in the chosen unit',
    );
  });

  testWidgets('the settings screen says the choice is shared with Liftio', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          unit: UnitSystem.metric,
          settings: InMemoryUnitSettings(),
          auth: FakeAuthRepository(signedIn: true, email: 'dev@runio.app'),
        ),
      ),
    );

    // One account across both apps — surprising if unexplained.
    expect(find.textContaining('Liftio'), findsOneWidget);
  });
}
