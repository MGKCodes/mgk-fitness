import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/settings/data/local_unit_preferences.dart';
import 'package:mgk_lift/src/features/settings/data/unit_preferences_repository.dart';
import 'package:mgk_lift/src/features/settings/domain/unit_preferences.dart';
import 'package:mgk_units/mgk_units.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Not the default, so an assertion cannot pass by accident on a value that
/// simply never changed.
const UnitPreferences imperial = UnitPreferences(
  distance: UnitSystem.imperial,
  mass: MassUnit.pounds,
);
const UnitPreferences metric = UnitPreferences();

/// A source that can be told whether to answer.
///
/// Deliberately not a mock of `SupabaseUnitPreferences`: what the repository
/// depends on is the null-means-no-answer contract, and the four situations
/// that produce null — signed out, no row, timed out, failed — are
/// indistinguishable by design. One fake covers all four.
class _FakeSource implements UnitPreferencesSource {
  _FakeSource(this.answer);

  UnitPreferences? answer;
  int fetches = 0;
  final List<UnitPreferences> saved = <UnitPreferences>[];

  @override
  Future<UnitPreferences?> fetch() async {
    fetches++;
    return answer;
  }

  @override
  Future<void> save(UnitPreferences prefs) async => saved.add(prefs);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<LocalUnitPreferences> deviceStore([
    Map<String, Object> seed = const <String, Object>{},
  ]) async {
    SharedPreferences.setMockInitialValues(seed);
    return LocalUnitPreferences(prefs: await SharedPreferences.getInstance());
  }

  group('the device store', () {
    test('says nothing before it has been told anything', () async {
      expect(await (await deviceStore()).fetch(), isNull);
    });

    test('a stored choice survives a new instance', () async {
      final local = await deviceStore();
      await local.save(imperial);

      final reopened = LocalUnitPreferences(
        prefs: await SharedPreferences.getInstance(),
      );
      expect(await reopened.fetch(), imperial);
    });

    test(
      'writes the vocabulary core.user_settings uses, not enum names',
      () async {
        final local = await deviceStore();
        await local.save(imperial);

        // The property worth pinning: a value written here can be sent straight
        // to `core.user_settings`, and one read from it can be stored here, with
        // no translation table that could disagree with itself.
        final raw = await SharedPreferences.getInstance();
        expect(raw.getString('units.distance'), 'mi');
        expect(raw.getString('units.mass'), 'lbs');
      },
    );

    test('fetch says "no answer"; load flattens it to the default', () async {
      final local = await deviceStore();
      expect(await local.fetch(), isNull);
      expect(await local.load(), metric);
    });
  });

  group('when the account answers', () {
    test('it wins over a different device value', () async {
      final local = await deviceStore();
      await local.save(metric);

      final repo = UnitPreferencesRepository(
        local: local,
        remote: _FakeSource(imperial),
      );

      // The account is the only store that can carry a choice made in Run or
      // on another device, so it is at least as current by definition.
      expect(await repo.load(), imperial);
    });

    test('the answer is cached, so the next launch needs no network', () async {
      final local = await deviceStore();
      final repo = UnitPreferencesRepository(
        local: local,
        remote: _FakeSource(imperial),
      );
      await repo.load();

      expect(await local.fetch(), imperial);
    });
  });

  group('when the account says nothing', () {
    test('the device value is kept, not overwritten by the default', () async {
      final local = await deviceStore();
      await local.save(imperial);

      final repo = UnitPreferencesRepository(
        local: local,
        remote: _FakeSource(null),
      );

      // The regression this exists for. Returning the default on no answer is
      // what made an unreachable server indistinguishable from a lifter who
      // uses kilograms, and silently reset a real choice.
      expect(await repo.load(), imperial);
    });

    test('with nothing stored either, the default is the answer', () async {
      final repo = UnitPreferencesRepository(
        local: await deviceStore(),
        remote: _FakeSource(null),
      );
      expect(await repo.load(), metric);
    });

    test('it is asked once per load, not polled', () async {
      final remote = _FakeSource(null);
      final repo = UnitPreferencesRepository(
        local: await deviceStore(),
        remote: remote,
      );
      await repo.load();
      expect(remote.fetches, 1);
    });
  });

  group('with no account at all', () {
    // Supabase unconfigured, which the app treats as "this device only".
    // Tracking is free and needs no sign-in, so this is an ordinary lifter
    // rather than an edge case — and the case cloud-only storage got wrong.
    test('a choice still survives a relaunch', () async {
      final repo = UnitPreferencesRepository(
        local: await deviceStore(),
        remote: null,
      );
      await repo.save(imperial);

      final relaunched = UnitPreferencesRepository(
        local: LocalUnitPreferences(
          prefs: await SharedPreferences.getInstance(),
        ),
        remote: null,
      );
      expect(await relaunched.load(), imperial);
    });

    test('saving is not an error', () async {
      final repo = UnitPreferencesRepository(
        local: await deviceStore(),
        remote: null,
      );
      await expectLater(repo.save(imperial), completes);
    });
  });

  group('saving', () {
    test('the device write has landed before the call returns', () async {
      final local = await deviceStore();
      final repo = UnitPreferencesRepository(
        local: local,
        remote: _FakeSource(null),
      );
      await repo.save(imperial);

      expect(await local.fetch(), imperial);
    });

    test('the account write is fired, not waited on', () async {
      final local = await deviceStore();
      final remote = _FakeSource(null);
      final repo = UnitPreferencesRepository(local: local, remote: remote);

      await repo.save(imperial);
      // What must be true on return is the device write. The account write is
      // allowed to still be in flight — a slow network must not put a spinner
      // on a settings toggle.
      expect(await local.fetch(), imperial);

      await Future<void>.delayed(Duration.zero);
      expect(remote.saved, <UnitPreferences>[imperial]);
    });
  });
}
