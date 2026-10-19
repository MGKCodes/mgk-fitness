import 'dart:async';

import 'package:mgk_auth/mgk_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../domain/account.dart';
import 'provider_ids.dart';

/// Supabase auth, with its errors mapped to the small set the screens know.
///
/// **Nothing here gates tracking.** Logging a session works signed out and
/// always will; an account is where training lives across devices, and what the coach
/// hangs off.
/// That ordering is the whole product decision — an app that demands an account
/// before it will let you write down a set is one people close.
///
/// **The email path is `mgk_auth`'s [EmailSignIn]**, built here over this
/// client, so Lift and Run look an address up, sign in, make an account and
/// check its code through the same calls (Run's ADR-0047). Apple and Google
/// are `mgk_auth`'s [ProviderSignIn], with Lift's own ids.
class SupabaseAuth implements AuthService {
  SupabaseAuth(this._client, {ProviderSignIn? providers, EmailSignIn? email})
    : _providers =
          providers ??
          ProviderSignIn(ids: liftProviderIds, auth: () => _client.auth),
      _email =
          email ??
          EmailSignIn(
            auth: () => _client.auth,
            functions: () => _client.functions,
          );

  final sb.SupabaseClient _client;
  final ProviderSignIn _providers;
  final EmailSignIn _email;

  @override
  Account? get current => _toAccount(_client.auth.currentUser);

  @override
  Stream<Account?> get changes => _client.auth.onAuthStateChange.map(
    (event) => _toAccount(event.session?.user),
  );

  @override
  EmailSignIn get emailSignIn => _email;

  @override
  Future<ProviderOutcome> signInWithApple() => _provider(_providers.apple);

  @override
  Future<ProviderOutcome> signInWithGoogle() => _provider(_providers.google);

  Future<ProviderOutcome> _provider(
    Future<ProviderOutcome> Function() signIn,
  ) async {
    try {
      return await signIn();
    } on ProviderSignInException catch (e) {
      throw AuthException(switch (e.failure) {
        ProviderFailure.unavailable => AuthFailure.unavailable,
        ProviderFailure.refused => AuthFailure.providerRefused,
      });
    }
  }

  @override
  Future<void> signOut() async {
    await _client.auth.signOut();
    // After, not before: leaving is what matters, and a Google account left
    // remembered only means the next "Continue with Google" skips the chooser.
    await _providers.forget();
  }

  @override
  bool get isNewAccount => accountIsNew(_client.auth.currentUser);

  @override
  bool get signsInWithApple => hasIdentity(_client.auth.currentUser, 'apple');

  @override
  String? get googleFirstName => googleFirstNameOf(_client.auth.currentUser);

  /// Writes [kDisplayNameKey] and nothing else: `name` is Google's, rewritten
  /// on every Google sign-in, and Run 1.0.1 still reads it for its coach.
  ///
  /// **A cleared name is written as empty, not null** ([displayNameData]), so
  /// the key stays and says "no name": an account still holding Run's
  /// pre-1.0.2 `name` would otherwise show that name again the moment this one
  /// was cleared. Bounded like every call on the auth path, so a dead
  /// connection is reported rather than waited on.
  @override
  Future<void> updateName(String? name) async {
    try {
      await _client.auth
          .updateUser(sb.UserAttributes(data: displayNameData(name)))
          .timeout(const Duration(seconds: 20));
    } on Object {
      throw const AuthException(AuthFailure.unavailable);
    }
  }

  Account? _toAccount(sb.User? user) => user == null
      ? null
      : Account(id: user.id, email: user.email, name: displayNameOf(user));
}
