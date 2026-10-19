import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mgk_run/src/features/auth/data/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// **The name is the account's, kept as `display_name`** (ADR-0047, "The name
/// belongs to the account").
///
/// Run kept the coach's name under `name` until 1.0.2, and Supabase writes
/// Google's profile over `name` on every Google sign-in. So the name is read
/// from `display_name` first, the old key only where Google cannot have
/// written it, and the old key is copied across once, before it can be.
///
/// Against the real [AuthRepository] and a real gotrue client, answered by a
/// fake auth server, so what is asserted is what would be sent.
void main() {
  late List<http.Request> sent;

  /// The user the fake server says is signed in, and answers an update with.
  late Map<String, Object?> user;

  /// What `PUT /user` answers, when it should not be the updated user.
  int? updateStatus;

  Map<String, Object?> userJson({
    Map<String, Object?> metadata = const <String, Object?>{},
    List<String> providers = const <String>['email'],
    String createdAt = '2026-10-01T09:00:00Z',
    String lastSignInAt = '2026-10-19T09:00:00Z',
  }) => <String, Object?>{
    'id': 'user-1',
    'aud': 'authenticated',
    'email': 'sam@example.com',
    'created_at': createdAt,
    'last_sign_in_at': lastSignInAt,
    'app_metadata': <String, Object?>{'providers': providers},
    'user_metadata': metadata,
    'identities': <Object?>[
      for (final provider in providers)
        <String, Object?>{
          'id': '$provider-sub',
          'user_id': 'user-1',
          'provider': provider,
          'identity_data': <String, Object?>{'sub': '$provider-sub'},
        },
    ],
  };

  http.Response json(int status, Object? body) => http.Response(
    jsonEncode(body),
    status,
    headers: <String, String>{'content-type': 'application/json'},
  );

  /// A repository signed in as [user], through the password grant, which is
  /// the plainest way to hand gotrue a session.
  Future<AuthRepository> signedIn() async {
    final goTrue = GoTrueClient(
      url: 'https://auth.example/auth/v1',
      autoRefreshToken: false,
      asyncStorage: _MemoryStorage(),
      httpClient: MockClient((request) async {
        sent.add(request);
        final path = request.url.path.replaceFirst('/auth/v1', '');
        if (path == '/token') {
          return json(200, <String, Object?>{
            'access_token': 'access',
            'token_type': 'bearer',
            'expires_in': 3600,
            'refresh_token': 'refresh',
            'user': user,
          });
        }
        if (path == '/user' && request.method == 'PUT') {
          if (updateStatus case final int status) {
            return json(status, <String, Object?>{'msg': 'down'});
          }
          final data =
              (jsonDecode(request.body) as Map<String, Object?>)['data']
                  as Map<String, Object?>;
          final metadata = <String, Object?>{
            ...(user['user_metadata']! as Map<String, Object?>),
            ...data,
          };
          user = <String, Object?>{...user, 'user_metadata': metadata};
          return json(200, user);
        }
        return json(404, <String, Object?>{'msg': 'no route'});
      }),
    );
    await goTrue.signInWithPassword(
      email: 'sam@example.com',
      password: 'secret',
    );
    sent.clear();
    return AuthRepository(auth: () => goTrue);
  }

  /// What the last `PUT /user` asked to write into the metadata.
  Map<String, Object?> written() =>
      (jsonDecode(sent.last.body) as Map<String, Object?>)['data']
          as Map<String, Object?>;

  setUp(() {
    sent = <http.Request>[];
    updateStatus = null;
  });

  group('the name is read', () {
    test('from display_name first', () async {
      user = userJson(metadata: {'display_name': 'Sam', 'name': 'Old'});
      expect((await signedIn()).currentName, 'Sam');
    });

    test("from Run's old name where Google cannot have written it", () async {
      user = userJson(metadata: {'name': 'Sam'});
      expect((await signedIn()).currentName, 'Sam');
    });

    test("never from Google's name, which nobody chose here", () async {
      user = userJson(
        metadata: {'name': 'Samuel Smith', 'full_name': 'Samuel Smith'},
        providers: ['google'],
      );
      final auth = await signedIn();
      expect(auth.currentName, isNull);
      // Offered to the intro as a start, and only the first word of it.
      expect(auth.googleFirstName, 'Samuel');
    });

    test('and Apple offers nothing to start with', () async {
      user = userJson(providers: ['apple']);
      final auth = await signedIn();
      expect(auth.googleFirstName, isNull);
      expect(auth.signedInWithApple, isTrue);
    });
  });

  group("Run's old name is copied once", () {
    test('to display_name, leaving the old key alone', () async {
      user = userJson(metadata: {'name': 'Sam'});
      final auth = await signedIn();

      await auth.keepNameBestEffort();

      expect(sent, hasLength(1));
      expect(sent.single.method, 'PUT');
      expect(written(), <String, Object?>{'display_name': 'Sam'});
      expect(auth.currentName, 'Sam');

      // Once: the account has a display_name now, so there is nothing to copy.
      await auth.keepNameBestEffort();
      expect(sent, hasLength(1));
    });

    test('and not over a display_name the account already has', () async {
      user = userJson(metadata: {'display_name': 'Samantha', 'name': 'Sam'});
      final auth = await signedIn();

      await auth.keepNameBestEffort();

      expect(sent, isEmpty);
      expect(auth.currentName, 'Samantha');
    });

    test("and not from a Google account, whose name is Google's", () async {
      user = userJson(
        metadata: {'name': 'Samuel Smith'},
        providers: ['google'],
      );
      final auth = await signedIn();

      await auth.keepNameBestEffort();

      expect(sent, isEmpty);
    });

    test('and not where there is no name at all', () async {
      user = userJson();
      await (await signedIn()).keepNameBestEffort();
      expect(sent, isEmpty);
    });

    test('quietly, when the write does not land', () async {
      user = userJson(metadata: {'name': 'Sam'});
      final auth = await signedIn();
      updateStatus = 503;

      await expectLater(auth.keepNameBestEffort(), completes);
      expect(sent, hasLength(1), reason: 'tried, and tried again next launch');
    });

    test('and without even a client to ask, says nothing', () async {
      // Fired and forgotten from the shell, so it must not throw even where
      // reading the session does: here, with no Supabase initialised.
      await expectLater(const AuthRepository().keepNameBestEffort(), completes);
    });
  });

  test('a new name is written to display_name only', () async {
    user = userJson(metadata: {'name': 'Sam'});
    final auth = await signedIn();

    await auth.updateName('  Alex ');

    expect(written(), <String, Object?>{'display_name': 'Alex'});
    expect(auth.currentName, 'Alex');

    // Blank clears it rather than storing blank.
    await auth.updateName('  ');
    expect(written(), <String, Object?>{'display_name': null});
  });

  group('whether the account is new is read from the account', () {
    test('made at the sign-in that just happened', () async {
      user = userJson(
        createdAt: '2026-10-19T09:00:00Z',
        lastSignInAt: '2026-10-19T09:04:00Z',
      );
      expect((await signedIn()).accountIsNew, isTrue);
    });

    test('made weeks before it', () async {
      user = userJson(
        createdAt: '2026-09-01T09:00:00Z',
        lastSignInAt: '2026-10-19T09:00:00Z',
      );
      expect((await signedIn()).accountIsNew, isFalse);
    });
  });

  test('signed out, there is no name and nothing new', () {
    final auth = AuthRepository(
      auth: () => GoTrueClient(
        url: 'https://auth.example/auth/v1',
        autoRefreshToken: false,
        asyncStorage: _MemoryStorage(),
      ),
    );
    expect(auth.currentName, isNull);
    expect(auth.googleFirstName, isNull);
    expect(auth.accountIsNew, isFalse);
    expect(AuthRepository.legacyNameToCopy(null), isNull);
  });
}

/// Where gotrue keeps its PKCE verifier. Nothing here needs one, but the
/// client refuses to start some calls without somewhere to put it.
class _MemoryStorage extends GotrueAsyncStorage {
  final Map<String, String> _items = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => _items[key];

  @override
  Future<void> setItem({required String key, required String value}) async =>
      _items[key] = value;

  @override
  Future<void> removeItem({required String key}) async => _items.remove(key);
}
