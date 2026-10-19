import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mgk_lift/src/features/auth/data/supabase_auth.dart';
import 'package:mgk_lift/src/features/auth/domain/account.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// What the auth server says about the one user these tests sign in.
Map<String, Object?> _user({
  Map<String, Object?> metadata = const <String, Object?>{},
  List<String> providers = const <String>['email'],
  String createdAt = '2026-10-20T09:00:00Z',
  String lastSignInAt = '2026-10-20T09:04:00Z',
}) => <String, Object?>{
  'id': 'user-1',
  'aud': 'authenticated',
  'email': 'sam@example.com',
  'created_at': createdAt,
  'last_sign_in_at': lastSignInAt,
  'app_metadata': <String, Object?>{'providers': providers},
  'user_metadata': metadata,
};

void main() {
  late List<http.Request> sent;

  /// The user the next sign-in and the next update answer with.
  late Map<String, Object?> user;
  late int updateStatus;

  http.Response json(int status, Object body) => http.Response(
    jsonEncode(body),
    status,
    headers: <String, String>{'content-type': 'application/json'},
  );

  /// A client signed in as [user], over a server that answers from memory.
  Future<SupabaseAuth> signedIn() async {
    final client = sb.SupabaseClient(
      'https://project.example',
      'anon',
      authOptions: const sb.AuthClientOptions(
        authFlowType: sb.AuthFlowType.implicit,
        autoRefreshToken: false,
      ),
      httpClient: MockClient((request) async {
        sent.add(request);
        final path = request.url.path;
        if (path.endsWith('/token')) {
          return json(200, <String, Object?>{
            'access_token': 'access',
            'token_type': 'bearer',
            'expires_in': 3600,
            'refresh_token': 'refresh',
            'user': user,
          });
        }
        if (path.endsWith('/user') && request.method == 'PUT') {
          if (updateStatus != 200) {
            return json(updateStatus, <String, Object?>{'msg': 'down'});
          }
          final data =
              (jsonDecode(request.body) as Map<String, Object?>)['data']
                  as Map<String, Object?>;
          final metadata = <String, Object?>{
            ...user['user_metadata']! as Map<String, Object?>,
          };
          // As Supabase merges it: a null removes the key.
          data.forEach((key, value) {
            if (value == null) {
              metadata.remove(key);
            } else {
              metadata[key] = value;
            }
          });
          user = <String, Object?>{...user, 'user_metadata': metadata};
          return json(200, user);
        }
        return json(404, <String, Object?>{'msg': 'no route'});
      }),
    );
    addTearDown(client.dispose);
    await client.auth.signInWithPassword(
      email: 'sam@example.com',
      password: 'lifting-1',
    );
    return SupabaseAuth(client);
  }

  Map<String, Object?>? written() {
    final put = sent.lastWhere((r) => r.method == 'PUT');
    return (jsonDecode(put.body) as Map<String, Object?>)['data']
        as Map<String, Object?>?;
  }

  setUp(() {
    sent = <http.Request>[];
    user = _user();
    updateStatus = 200;
  });

  test("the account's name is display_name, never Google's name", () async {
    user = _user(
      metadata: <String, Object?>{'display_name': 'Sam', 'name': 'Samuel Lee'},
      providers: <String>['google'],
    );
    expect((await signedIn()).current?.name, 'Sam');

    // A Google account with no name of its own has none: `name` is whatever
    // Google last sent.
    user = _user(
      metadata: <String, Object?>{'name': 'Samuel Lee', 'full_name': 'Samuel'},
      providers: <String>['google'],
    );
    final google = await signedIn();
    expect(google.current?.name, isNull);
    expect(google.googleFirstName, 'Samuel');
  });

  test('a name is written to display_name alone, trimmed', () async {
    final auth = await signedIn();
    await auth.updateName('  Sam ');

    expect(written(), <String, Object?>{'display_name': 'Sam'});
    expect(auth.current?.name, 'Sam');
  });

  test('a blank name clears it rather than storing nothing', () async {
    user = _user(metadata: <String, Object?>{'display_name': 'Sam'});
    final auth = await signedIn();
    await auth.updateName('   ');

    expect(written(), <String, Object?>{'display_name': null});
    expect(auth.current?.name, isNull);
  });

  test('a name that does not reach the server says so', () async {
    final auth = await signedIn();
    updateStatus = 503;
    await expectLater(
      auth.updateName('Sam'),
      throwsA(
        isA<AuthException>().having(
          (e) => e.failure,
          'failure',
          AuthFailure.unavailable,
        ),
      ),
    );
  });

  test('whether the account is new is read from the account', () async {
    // Made four minutes before this sign-in: the code was typed after it.
    expect((await signedIn()).isNewAccount, isTrue);

    user = _user(createdAt: '2026-09-01T09:00:00Z');
    expect((await signedIn()).isNewAccount, isFalse);
  });

  test('an account that can sign in with Apple says so', () async {
    expect((await signedIn()).signsInWithApple, isFalse);

    user = _user(providers: <String>['apple']);
    final apple = await signedIn();
    expect(apple.signsInWithApple, isTrue);
    // Nothing to fill in after Apple.
    expect(apple.googleFirstName, isNull);
  });
}
