import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/data/account_ai_consent.dart';
import 'package:mgk_run/src/features/coaching/data/file_ai_consent_cache.dart';
import 'package:mgk_run/src/features/coaching/domain/ai_consent.dart';

/// Auth user metadata, one map per account, as gotrue would hold it.
class _Accounts implements AiConsentAccount {
  @override
  String? userId = 'runner-a';

  final Map<String, Object?> metadata = <String, Object?>{};

  /// Thrown by [store] in place of writing: no signal, or gotrue refusing.
  Object? failure;

  int writes = 0;

  @override
  Object? get stored => userId == null ? null : metadata[userId];

  @override
  Future<void> store(Map<String, Object?>? value) async {
    final error = failure;
    if (error != null) throw error;
    writes++;
    if (value == null) {
      metadata.remove(userId);
    } else {
      metadata[userId!] = value;
    }
  }
}

/// **The coach's permission is an account's, and it has to survive a phone
/// with no signal in both directions.**
///
/// The answer lives in auth metadata under `run_ai_consent`, the way
/// `run_intro_seen` does, and the phone keeps any answer the account has not
/// received yet. The failure these pin is the one the obvious design has: a
/// withdrawal made offline that the account never hears about, leaving the
/// coach free to send.
void main() {
  late _Accounts accounts;
  late InMemoryAiConsentCache cache;
  late AccountAiConsent store;
  final at = DateTime.utc(2026, 9, 29, 8);

  setUp(() {
    accounts = _Accounts();
    cache = InMemoryAiConsentCache();
    store = AccountAiConsent(account: accounts, cache: cache, now: () => at);
  });

  /// Lets an unawaited write back to the account finish.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('nothing stored is not agreement', () async {
    expect(await store.isGranted(), isFalse);
  });

  test('agreeing writes the account in the documented shape', () async {
    await store.grant();

    expect(await store.isGranted(), isTrue);
    // The exact key and shape: account deletion clears this key by name.
    expect(kAiConsentMetadataKey, 'run_ai_consent');
    expect(accounts.metadata['runner-a'], <String, Object>{
      'version': kAiConsentVersion,
      'at': '2026-09-29T08:00:00.000Z',
    });
    expect(
      await cache.read('runner-a'),
      isNull,
      reason: 'once the account has it, the phone holds nothing of its own',
    );
  });

  test('another account on the same phone is asked again', () async {
    await store.grant();

    accounts.userId = 'runner-b';
    expect(await store.isGranted(), isFalse);

    accounts.userId = 'runner-a';
    expect(await store.isGranted(), isTrue);
  });

  test('an answer to an older question asks again', () async {
    accounts.metadata['runner-a'] = <String, Object?>{
      'version': kAiConsentVersion - 1,
      'at': '2026-09-01T08:00:00.000Z',
    };

    expect(await store.isGranted(), isFalse);
  });

  test('an answer nobody can read is no answer', () async {
    for (final Object? unreadable in <Object?>[
      true,
      'yes',
      <String, Object?>{'version': 'one', 'at': '2026-09-29T08:00:00.000Z'},
      <String, Object?>{'version': kAiConsentVersion},
      <String, Object?>{'version': kAiConsentVersion, 'at': 'yesterday'},
    ]) {
      accounts.metadata['runner-a'] = unreadable;
      expect(await store.isGranted(), isFalse, reason: '$unreadable');
    }
  });

  test('withdrawing clears the account and the phone', () async {
    await store.grant();
    await store.withdraw();

    expect(await store.isGranted(), isFalse);
    expect(accounts.metadata.containsKey('runner-a'), isFalse);
    expect(await cache.read('runner-a'), isNull);
  });

  test('agreeing with no signal counts on this phone, and reaches the '
      'account later', () async {
    accounts.failure = const SocketException('offline');
    await store.grant();

    expect(await store.isGranted(), isTrue);
    expect(accounts.metadata, isEmpty);

    accounts.failure = null;
    await store.isGranted();
    await settle();

    expect(accounts.metadata['runner-a'], isNotNull);
    expect(await cache.read('runner-a'), isNull);
    expect(await store.isGranted(), isTrue);
  });

  test('a withdrawal with no signal stops the coach at once', () async {
    await store.grant();
    accounts.failure = const SocketException('offline');

    await store.withdraw();

    expect(
      await store.isGranted(),
      isFalse,
      reason:
          'the account still says yes, and it must not win over a decision '
          'made on this phone afterwards',
    );

    accounts.failure = null;
    await store.isGranted();
    await settle();

    expect(accounts.metadata.containsKey('runner-a'), isFalse);
    expect(await cache.read('runner-a'), isNull);
    expect(await store.isGranted(), isFalse);
  });

  test('a withdrawal made on another phone arrives here', () async {
    await store.grant();

    // What a session refresh brings back after the other phone withdrew.
    accounts.metadata.remove('runner-a');

    expect(await store.isGranted(), isFalse);
  });

  test(
    'an answer kept on this phone never carries to another account',
    () async {
      accounts.failure = const SocketException('offline');
      await store.grant();

      accounts.userId = 'runner-b';
      expect(await store.isGranted(), isFalse);
    },
  );

  test(
    'with nobody signed in there is no answer, and nothing is written',
    () async {
      accounts.userId = null;

      await store.grant();

      expect(await store.isGranted(), isFalse);
      expect(accounts.writes, 0);
    },
  );

  test('an answer that lands nowhere says so', () async {
    accounts.failure = const SocketException('offline');
    cache.failure = const FileSystemException('disk full');

    await expectLater(store.grant(), throwsA(isA<AiConsentNotSaved>()));
    expect(await store.isGranted(), isFalse);
  });

  group('the file the phone keeps them in', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('run_ai_consent_test');
    });

    tearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    FileAiConsentCache fileIn(Directory d) =>
        FileAiConsentCache(directory: () async => d);

    test('an entry survives a new cache over the same directory', () async {
      await fileIn(dir).write('runner-a', <String, Object?>{'version': 1});

      expect(await fileIn(dir).read('runner-a'), <String, Object?>{
        'version': 1,
      });
      expect(await fileIn(dir).read('runner-b'), isNull);
    });

    test('removing the last entry removes the file', () async {
      final cache = fileIn(dir);
      await cache.write('runner-a', <String, Object?>{'version': 1});
      await cache.write('runner-b', <String, Object?>{'version': 1});

      await cache.write('runner-a', null);
      expect(await cache.read('runner-a'), isNull);
      expect(await cache.read('runner-b'), isNotNull);

      await cache.write('runner-b', null);
      expect(dir.listSync(), isEmpty);
    });

    test(
      'a directory that cannot be reached throws, so a caller can tell',
      () async {
        final broken = FileAiConsentCache(
          directory: () async =>
              throw const FileSystemException('no directory'),
        );

        await expectLater(
          broken.write('runner-a', <String, Object?>{'version': 1}),
          throwsA(isA<FileSystemException>()),
        );
      },
    );
  });
}
