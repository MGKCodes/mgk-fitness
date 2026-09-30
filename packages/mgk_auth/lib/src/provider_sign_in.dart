import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The ids each provider needs, which differ per app.
///
/// **None of these is a secret.** A client id is sent to Google or Apple in the
/// clear by every sign-in; what makes a token trustworthy is Supabase checking
/// its audience against the ids listed in the dashboard (see Lift's
/// `docs/store-setup.md`, step 7).
@immutable
class ProviderIds {
  const ProviderIds({
    required this.googleServerClientId,
    required this.googleIosClientId,
    required this.redirect,
  });

  /// Google's *web* client, the one Supabase holds the secret for. Android
  /// signs in through it (Android has no client id of its own in the app), and
  /// it is the audience of the tokens both platforms hand to Supabase.
  final String googleServerClientId;

  /// This app's *iOS* client. Its reversed form must also be a URL scheme in
  /// the app's `Info.plist`, or Google's sheet has no way back.
  final String googleIosClientId;

  /// Where Apple's web sign-in on Android comes back to:
  /// `<package>://login-callback`, which must be in Supabase's redirect list
  /// and in the app's intent filters.
  final String redirect;
}

/// How signing in with a provider ended.
enum ProviderOutcome {
  /// Signed in. The session is in hand and the auth stream has said so.
  signedIn,

  /// They closed the provider's sheet. Not a failure, and worth no message.
  cancelled,

  /// Apple on Android: the browser has it now, and the session arrives through
  /// the link back into the app. Watch the auth stream for it.
  continuing,
}

/// Why signing in with a provider failed, in the two ways an app can say
/// something useful about.
enum ProviderFailure {
  /// No network, or the server did not answer in time. Nothing they did.
  unavailable,

  /// The provider or the server said no: a misconfigured client, a revoked
  /// app, an account that is not allowed in. Not theirs to fix either, but not
  /// worth retrying straight away.
  refused,
}

class ProviderSignInException implements Exception {
  const ProviderSignInException(this.failure, [this.cause]);

  final ProviderFailure failure;

  /// What the provider or Supabase actually said, for logs. Never shown.
  final Object? cause;

  @override
  String toString() => 'ProviderSignInException($failure, $cause)';
}

/// The providers' own SDKs, behind a seam: the rules around them — the nonce,
/// what counts as cancelling, which errors are whose — are worth testing, and
/// the SDKs only run on a phone.
abstract interface class ProviderPlatform {
  /// True where Apple's own sheet exists (iOS, macOS); elsewhere Apple is a
  /// web sign-in.
  bool get appleIsNative;

  /// Apple's identity token for a sign-in carrying [hashedNonce], or null if
  /// they cancelled.
  Future<String?> appleIdToken({required String hashedNonce});

  /// Google's tokens, or null if they cancelled. The access token is null
  /// unless Google hands it over without asking the person again.
  Future<({String idToken, String? accessToken})?> google(ProviderIds ids);

  /// Forgets the Google account on this phone, so the next sign-in asks which.
  Future<void> forgetGoogle();
}

/// Sign in with Apple and with Google, into the suite's one Supabase project.
///
/// **Email only (O1).** Neither provider is asked for a name or a photograph:
/// the privacy policies promise "an email address and an identifier", and the
/// coach asks for a name in its own words when it needs one.
///
/// **Apple is native where Apple is.** On iOS the system sheet signs in and
/// hands over a token carrying a hashed nonce; Supabase is given the raw one to
/// check it against. On Android there is no sheet, so Apple's web sign-in runs
/// in the browser through the suite's Services ID and comes back to
/// [ProviderIds.redirect] — the only flow here that finishes after its call
/// has returned ([ProviderOutcome.continuing]).
///
/// **Google is native on both.** Its token is checked by Supabase against the
/// web client id, which is why Android needs nothing but that.
class ProviderSignIn {
  ProviderSignIn({
    required this.ids,
    GoTrueClient Function()? auth,
    ProviderPlatform? platform,
    this.timeout = const Duration(seconds: 20),
  }) : _auth = auth ?? (() => Supabase.instance.client.auth),
       _platform = platform ?? PluginProviderPlatform();

  final ProviderIds ids;
  final GoTrueClient Function() _auth;
  final ProviderPlatform _platform;

  /// The same bound Run's `AuthRepository` puts on every call on the auth path:
  /// long enough for a slow connection, short enough that a dead one is
  /// reported rather than waited on.
  final Duration timeout;

  Future<ProviderOutcome> apple() =>
      _platform.appleIsNative ? _appleNative() : _appleWeb();

  Future<ProviderOutcome> _appleNative() async {
    final auth = _auth();
    final rawNonce = auth.generateRawNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
    final idToken = await _platform.appleIdToken(hashedNonce: hashedNonce);
    if (idToken == null) return ProviderOutcome.cancelled;
    await _exchange(
      () => auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      ),
    );
    return ProviderOutcome.signedIn;
  }

  Future<ProviderOutcome> _appleWeb() async {
    final bool launched;
    try {
      launched = await _auth().signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: ids.redirect,
        scopes: 'email',
        // The browser, not a view inside the app: Apple's page is where
        // somebody types an Apple password, and they should be able to see
        // whose address bar it is in.
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
    } on Object catch (e) {
      throw ProviderSignInException(ProviderFailure.unavailable, e);
    }
    if (!launched) {
      throw const ProviderSignInException(ProviderFailure.refused);
    }
    return ProviderOutcome.continuing;
  }

  Future<ProviderOutcome> google() async {
    final tokens = await _platform.google(ids);
    if (tokens == null) return ProviderOutcome.cancelled;
    await _exchange(
      () => _auth().signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: tokens.idToken,
        accessToken: tokens.accessToken,
      ),
    );
    return ProviderOutcome.signedIn;
  }

  /// Call on signing out, so "Continue with Google" asks which account next
  /// time instead of quietly using the one that just left. Never throws.
  Future<void> forget() async {
    try {
      await _platform.forgetGoogle();
    } on Object {
      // Nothing to forget, or nothing to forget it with.
    }
  }

  /// Hands a provider's token to Supabase, sorting what goes wrong into the
  /// two things the screen can say.
  Future<void> _exchange(Future<AuthResponse> Function() call) async {
    try {
      await call().timeout(timeout);
    } on AuthRetryableFetchException catch (e) {
      throw ProviderSignInException(ProviderFailure.unavailable, e);
    } on TimeoutException catch (e) {
      throw ProviderSignInException(ProviderFailure.unavailable, e);
    } on AuthException catch (e) {
      throw ProviderSignInException(ProviderFailure.refused, e);
    }
  }
}

/// The real SDKs.
class PluginProviderPlatform implements ProviderPlatform {
  /// `initialize` must run exactly once per process, before anything else.
  static Future<void>? _googleReady;

  @override
  bool get appleIsNative =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Future<String?> appleIdToken({required String hashedNonce}) async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const <AppleIDAuthorizationScopes>[
          AppleIDAuthorizationScopes.email,
        ],
        nonce: hashedNonce,
      );
      final token = credential.identityToken;
      if (token == null) {
        throw const ProviderSignInException(ProviderFailure.refused);
      }
      return token;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      throw ProviderSignInException(ProviderFailure.refused, e);
    } on SignInWithAppleException catch (e) {
      throw ProviderSignInException(ProviderFailure.refused, e);
    }
  }

  @override
  Future<({String idToken, String? accessToken})?> google(
    ProviderIds ids,
  ) async {
    final google = GoogleSignIn.instance;
    try {
      final ready = _googleReady ??= google.initialize(
        clientId: appleIsNative ? ids.googleIosClientId : null,
        serverClientId: ids.googleServerClientId,
      );
      try {
        await ready;
      } on Object {
        // A failed start is not remembered as a started one: the next tap
        // tries again rather than inheriting the failure for the life of the
        // process.
        _googleReady = null;
        rethrow;
      }
      final account = await google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const ProviderSignInException(ProviderFailure.refused);
      }
      // Only if Google hands it over without a second screen: the sign-in's
      // own email is all this asks for (O1), and Supabase checks the id token
      // either way.
      String? accessToken;
      try {
        accessToken = (await account.authorizationClient.authorizationForScopes(
          const <String>['email'],
        ))?.accessToken;
      } on Object {
        accessToken = null;
      }
      return (idToken: idToken, accessToken: accessToken);
    } on GoogleSignInException catch (e) {
      switch (e.code) {
        case GoogleSignInExceptionCode.canceled:
        case GoogleSignInExceptionCode.interrupted:
          return null;
        case GoogleSignInExceptionCode.uiUnavailable:
          throw ProviderSignInException(ProviderFailure.unavailable, e);
        default:
          throw ProviderSignInException(ProviderFailure.refused, e);
      }
    } on ProviderSignInException {
      rethrow;
    } on Object catch (e) {
      // A platform error the plugin did not wrap — a missing client id in the
      // app's own configuration, most likely.
      throw ProviderSignInException(ProviderFailure.refused, e);
    }
  }

  @override
  Future<void> forgetGoogle() async {
    final ready = _googleReady;
    if (ready == null) return;
    await ready;
    await GoogleSignIn.instance.signOut();
  }
}
