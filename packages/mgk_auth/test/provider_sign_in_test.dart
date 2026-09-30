import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mgk_auth/mgk_auth.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

const _ids = ProviderIds(
  googleServerClientId: 'web.apps.googleusercontent.com',
  googleIosClientId: 'ios.apps.googleusercontent.com',
  redirect: 'com.example.app://login-callback',
);

/// The providers' SDKs, answering however a test needs.
class _FakePlatform implements ProviderPlatform {
  _FakePlatform({
    this.appleIsNative = true,
    this.appleToken = 'apple-id-token',
    this.googleTokens = (idToken: 'google-id-token', accessToken: null),
    this.throwing,
  });

  @override
  final bool appleIsNative;
  final String? appleToken;
  final ({String idToken, String? accessToken})? googleTokens;
  final Object? throwing;

  String? hashedNonceSeen;
  var forgotten = 0;

  @override
  Future<String?> appleIdToken({required String hashedNonce}) async {
    hashedNonceSeen = hashedNonce;
    if (throwing case final Object e) throw e;
    return appleToken;
  }

  @override
  Future<({String idToken, String? accessToken})?> google(
    ProviderIds ids,
  ) async {
    if (throwing case final Object e) throw e;
    return googleTokens;
  }

  @override
  Future<void> forgetGoogle() async => forgotten++;
}

/// Where the PKCE verifier goes between leaving for the browser and coming back.
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

/// Opens nothing; remembers what it was asked to open, and how.
class _FakeLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final List<(String, PreferredLaunchMode)> opened =
      <(String, PreferredLaunchMode)>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add((url, options.mode));
    return true;
  }
}

Map<String, Object?> _session() => <String, Object?>{
  'access_token': 'access',
  'token_type': 'bearer',
  'expires_in': 3600,
  'refresh_token': 'refresh',
  'user': <String, Object?>{
    'id': 'user-1',
    'aud': 'authenticated',
    'email': 'you@example.com',
    'created_at': '2026-09-30T00:00:00Z',
    'app_metadata': <String, Object?>{},
    'user_metadata': <String, Object?>{},
  },
};

void main() {
  late List<http.Request> sent;
  late int status;

  GoTrueClient client() => GoTrueClient(
    url: 'https://auth.example/auth/v1',
    autoRefreshToken: false,
    httpClient: MockClient((request) async {
      sent.add(request);
      return http.Response(
        jsonEncode(
          status == 200
              ? _session()
              : <String, Object?>{'error': 'invalid_grant', 'msg': 'No.'},
        ),
        status,
        headers: <String, String>{'content-type': 'application/json'},
      );
    }),
  );

  setUp(() {
    sent = <http.Request>[];
    status = 200;
  });

  Map<String, Object?> body(http.Request r) =>
      jsonDecode(r.body) as Map<String, Object?>;

  group('Apple, on a phone that has its sheet', () {
    test('Apple is given the hash of the nonce Supabase is given', () async {
      final platform = _FakePlatform();
      final auth = client();
      final outcome = await ProviderSignIn(
        ids: _ids,
        auth: () => auth,
        platform: platform,
      ).apple();

      expect(outcome, ProviderOutcome.signedIn);
      final request = sent.single;
      expect(request.url.queryParameters['grant_type'], 'id_token');
      final sentBody = body(request);
      expect(sentBody['provider'], 'apple');
      expect(sentBody['id_token'], 'apple-id-token');
      // The pairing that is easy to get backwards: Apple signs the hash into
      // its token, and Supabase hashes the raw nonce to check it.
      final raw = sentBody['nonce']! as String;
      expect(
        platform.hashedNonceSeen,
        sha256.convert(utf8.encode(raw)).toString(),
      );
      expect(auth.currentUser?.id, 'user-1');
    });

    test('closing the sheet is a cancel, and nothing is sent', () async {
      final outcome = await ProviderSignIn(
        ids: _ids,
        auth: client,
        platform: _FakePlatform(appleToken: null),
      ).apple();

      expect(outcome, ProviderOutcome.cancelled);
      expect(sent, isEmpty);
    });

    test('Supabase saying no is a refusal', () async {
      status = 400;
      await expectLater(
        ProviderSignIn(
          ids: _ids,
          auth: client,
          platform: _FakePlatform(),
        ).apple(),
        throwsA(
          isA<ProviderSignInException>().having(
            (e) => e.failure,
            'failure',
            ProviderFailure.refused,
          ),
        ),
      );
    });
  });

  group('Apple, on Android', () {
    test('goes to the browser, and back to the app\'s own link', () async {
      final launcher = _FakeLauncher();
      UrlLauncherPlatform.instance = launcher;
      final auth = GoTrueClient(
        url: 'https://auth.example/auth/v1',
        autoRefreshToken: false,
        asyncStorage: _MemoryStorage(),
      );

      final outcome = await ProviderSignIn(
        ids: _ids,
        auth: () => auth,
        platform: _FakePlatform(appleIsNative: false),
      ).apple();

      // It finishes later, through the link, not in this call.
      expect(outcome, ProviderOutcome.continuing);
      final (url, mode) = launcher.opened.single;
      final uri = Uri.parse(url);
      expect(uri.path, endsWith('/authorize'));
      expect(uri.queryParameters['provider'], 'apple');
      expect(uri.queryParameters['redirect_to'], _ids.redirect);
      expect(uri.queryParameters['scopes'], 'email');
      // The browser, where somebody can see whose page asks for their Apple
      // password — not a view inside the app.
      expect(mode, PreferredLaunchMode.externalApplication);
      expect(sent, isEmpty);
    });
  });

  group('Google', () {
    test('hands its id token to Supabase, with no nonce', () async {
      final outcome = await ProviderSignIn(
        ids: _ids,
        auth: client,
        platform: _FakePlatform(),
      ).google();

      expect(outcome, ProviderOutcome.signedIn);
      final sentBody = body(sent.single);
      expect(sentBody['provider'], 'google');
      expect(sentBody['id_token'], 'google-id-token');
      expect(sentBody['nonce'], isNull);
    });

    test('passes the access token when Google gave one', () async {
      await ProviderSignIn(
        ids: _ids,
        auth: client,
        platform: _FakePlatform(
          googleTokens: (idToken: 'google-id-token', accessToken: 'at'),
        ),
      ).google();

      expect(body(sent.single)['access_token'], 'at');
    });

    test('closing the chooser is a cancel', () async {
      final outcome = await ProviderSignIn(
        ids: _ids,
        auth: client,
        platform: _FakePlatform(googleTokens: null),
      ).google();

      expect(outcome, ProviderOutcome.cancelled);
      expect(sent, isEmpty);
    });

    test(
      'a failure from the SDK arrives as the one it was sorted into',
      () async {
        await expectLater(
          ProviderSignIn(
            ids: _ids,
            auth: client,
            platform: _FakePlatform(
              throwing: const ProviderSignInException(
                ProviderFailure.unavailable,
              ),
            ),
          ).google(),
          throwsA(
            isA<ProviderSignInException>().having(
              (e) => e.failure,
              'failure',
              ProviderFailure.unavailable,
            ),
          ),
        );
      },
    );
  });

  test('forgetting never throws, and forgets Google', () async {
    final platform = _FakePlatform();
    await ProviderSignIn(ids: _ids, auth: client, platform: platform).forget();
    expect(platform.forgotten, 1);

    await ProviderSignIn(
      ids: _ids,
      auth: client,
      platform: _ThrowingForget(),
    ).forget();
  });
}

class _ThrowingForget extends _FakePlatform {
  @override
  Future<void> forgetGoogle() async => throw StateError('not started');
}
