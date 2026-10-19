import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mgk_auth/mgk_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, Object?> _user() => <String, Object?>{
  'id': 'user-1',
  'aud': 'authenticated',
  'email': 'you@example.com',
  'created_at': '2026-10-19T00:00:00Z',
  'app_metadata': <String, Object?>{},
  'user_metadata': <String, Object?>{},
};

Map<String, Object?> _session() => <String, Object?>{
  'access_token': 'access',
  'token_type': 'bearer',
  'expires_in': 3600,
  'refresh_token': 'refresh',
  'user': _user(),
};

/// One answer from a server: a status and a JSON body.
typedef _Answer = (int, Object?);

/// Where the PKCE verifier goes. The apps' client runs the PKCE flow, which
/// keeps one for a sign-up, a resend and a reset; without storage gotrue
/// refuses to send them.
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

void main() {
  late List<http.Request> sent;

  /// What the auth server answers, by path. A path not listed is a 404, so a
  /// call nobody expected fails the test rather than passing quietly.
  late Map<String, _Answer> auth;

  /// What the functions server answers to `account-lookup`.
  late _Answer lookup;

  http.Response respond(_Answer answer) => http.Response(
    jsonEncode(answer.$2),
    answer.$1,
    headers: <String, String>{'content-type': 'application/json'},
  );

  EmailSignIn client() {
    final goTrue = GoTrueClient(
      url: 'https://auth.example/auth/v1',
      autoRefreshToken: false,
      asyncStorage: _MemoryStorage(),
      httpClient: MockClient((request) async {
        sent.add(request);
        final answer = auth[request.url.path.replaceFirst('/auth/v1', '')];
        return respond(answer ?? (404, <String, Object?>{'msg': 'no route'}));
      }),
    );
    final functions = FunctionsClient(
      'https://functions.example/functions/v1',
      const <String, String>{},
      httpClient: MockClient((request) async {
        sent.add(request);
        return respond(lookup);
      }),
    );
    return EmailSignIn(auth: () => goTrue, functions: () => functions);
  }

  Map<String, Object?> body(http.Request r) =>
      jsonDecode(r.body) as Map<String, Object?>;

  Matcher fails(EmailFailure failure) => throwsA(
    isA<EmailSignInException>().having((e) => e.failure, 'failure', failure),
  );

  setUp(() {
    sent = <http.Request>[];
    auth = <String, _Answer>{};
    lookup = (200, <String, Object?>{'status': 'new'});
  });

  group('the address first', () {
    test('every answer the function gives is a screen', () async {
      const wire = <String, AccountStatus>{
        'new': AccountStatus.newAccount,
        'unconfirmed': AccountStatus.unconfirmed,
        'password': AccountStatus.password,
        'apple': AccountStatus.apple,
        'google': AccountStatus.google,
      };
      for (final MapEntry(:key, :value) in wire.entries) {
        lookup = (200, <String, Object?>{'status': key});
        expect(await client().lookup('you@example.com'), value, reason: key);
      }
    });

    test('the address is sent trimmed to account-lookup', () async {
      await client().lookup('  you@example.com ');
      final request = sent.single;
      expect(request.url.path, endsWith('/account-lookup'));
      expect(request.method, 'POST');
      expect(body(request), <String, Object?>{'email': 'you@example.com'});
    });

    test('only new and unconfirmed make an account', () {
      expect(AccountStatus.newAccount.makesAnAccount, isTrue);
      expect(AccountStatus.unconfirmed.makesAnAccount, isTrue);
      expect(AccountStatus.password.makesAnAccount, isFalse);
      expect(AccountStatus.apple.makesAnAccount, isFalse);
    });

    test(
      'an error from the function is no connection, never a guess',
      () async {
        lookup = (500, <String, Object?>{'error': 'lookup_failed'});
        await expectLater(
          client().lookup('you@example.com'),
          fails(EmailFailure.unavailable),
        );
      },
    );

    test('an answer this build does not know is no connection too', () async {
      lookup = (200, <String, Object?>{'status': 'passkey'});
      await expectLater(
        client().lookup('you@example.com'),
        fails(EmailFailure.unavailable),
      );
    });
  });

  group('welcome back', () {
    test('the password signs in', () async {
      auth['/token'] = (200, _session());
      await client().signIn(email: 'you@example.com', password: 'secret');
      expect(sent.single.url.queryParameters['grant_type'], 'password');
      expect(body(sent.single)['password'], 'secret');
    });

    test('a wrong password is called a wrong password', () async {
      auth['/token'] = (
        400,
        <String, Object?>{
          'error_code': 'invalid_credentials',
          'msg': 'Invalid login credentials',
        },
      );
      await expectLater(
        client().signIn(email: 'you@example.com', password: 'nope'),
        fails(EmailFailure.wrongPassword),
      );
    });

    test('a server that is down is no connection', () async {
      auth['/token'] = (503, <String, Object?>{'msg': 'down'});
      await expectLater(
        client().signIn(email: 'you@example.com', password: 'secret'),
        fails(EmailFailure.unavailable),
      );
    });
  });

  group('a new account', () {
    test('is made with the address and password, and nothing else', () async {
      auth['/signup'] = (200, _user());
      final signedIn = await client().createAccount(
        email: ' you@example.com',
        password: 'Password1!',
      );
      expect(signedIn, isFalse, reason: 'confirmation is on: a code comes');
      final sentBody = body(sent.single);
      expect(sentBody['email'], 'you@example.com');
      expect(sentBody['password'], 'Password1!');
      // The name is asked after the account exists, by the app's own step.
      expect(sentBody['data'], anyOf(isNull, isEmpty));
    });

    test('the code signs the account in', () async {
      auth['/verify'] = (200, _session());
      final email = client();
      await email.confirm(email: 'you@example.com', code: ' 123456 ');
      final sentBody = body(sent.single);
      expect(sentBody['type'], 'signup');
      expect(sentBody['email'], 'you@example.com');
      expect(sentBody['token'], '123456');
    });

    test(
      'an unconfirmed address gets the new password, after the code',
      () async {
        auth['/verify'] = (200, _session());
        auth['/user'] = (200, _user());
        await client().confirm(
          email: 'you@example.com',
          code: '123456',
          replacePassword: 'Newer1!pass',
        );
        expect(sent.map((r) => r.url.path), <String>[
          '/auth/v1/verify',
          '/auth/v1/user',
        ]);
        expect(sent.last.method, 'PUT');
        expect(body(sent.last)['password'], 'Newer1!pass');
      },
    );

    test('a refused code writes no password', () async {
      auth['/verify'] = (
        403,
        <String, Object?>{
          'error_code': 'otp_expired',
          'msg': 'Token has expired or is invalid',
        },
      );
      await expectLater(
        client().confirm(
          email: 'you@example.com',
          code: '000000',
          replacePassword: 'Newer1!pass',
        ),
        fails(EmailFailure.codeRefused),
      );
      expect(sent.single.url.path, '/auth/v1/verify');
    });

    test('the code is sent again as a sign-up code', () async {
      auth['/resend'] = (200, <String, Object?>{});
      await client().resendCode('you@example.com');
      expect(body(sent.single)['type'], 'signup');
      expect(body(sent.single)['email'], 'you@example.com');
    });

    test("Supabase's email limit is its own failure", () async {
      auth['/resend'] = (
        429,
        <String, Object?>{
          'error_code': 'over_email_send_rate_limit',
          'msg': 'Email rate limit exceeded',
        },
      );
      await expectLater(
        client().resendCode('you@example.com'),
        fails(EmailFailure.tooManyEmails),
      );
    });
  });

  test('setting a password sends the reset email', () async {
    auth['/recover'] = (200, <String, Object?>{});
    await client().sendPasswordEmail(' you@example.com');
    expect(sent.single.url.path, '/auth/v1/recover');
    expect(body(sent.single)['email'], 'you@example.com');
  });
}
