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
class SupabaseAuth implements AuthService {
  SupabaseAuth(this._client, {ProviderSignIn? providers})
    : _providers =
          providers ??
          ProviderSignIn(ids: liftProviderIds, auth: () => _client.auth);

  final sb.SupabaseClient _client;
  final ProviderSignIn _providers;

  @override
  Account? get current => _toAccount(_client.auth.currentUser);

  @override
  Stream<Account?> get changes => _client.auth.onAuthStateChange.map(
    (event) => _toAccount(event.session?.user),
  );

  @override
  Future<Account> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final user = res.user;
      if (user == null) throw const AuthException(AuthFailure.unavailable);
      return _toAccount(user)!;
    } on sb.AuthException catch (e) {
      throw AuthException(_map(e, signingUp: false));
    } on Object {
      throw const AuthException(AuthFailure.unavailable);
    }
  }

  @override
  Future<Account> signUp({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _client.auth.signUp(
        email: email.trim(),
        password: password,
      );
      final user = res.user;
      if (user == null) throw const AuthException(AuthFailure.unavailable);
      // A project with email confirmation on returns a user and no session.
      // That is a success, but the lifter is not signed in yet and the screen
      // has to say so rather than sitting there.
      if (res.session == null) {
        throw const AuthException(AuthFailure.needsConfirmation);
      }
      return _toAccount(user)!;
    } on sb.AuthException catch (e) {
      throw AuthException(_map(e, signingUp: true));
    } on AuthException {
      rethrow;
    } on Object {
      throw const AuthException(AuthFailure.unavailable);
    }
  }

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

  /// The link lands on mgkfitness.mgkcodes.com/reset-password. The email
  /// template names that page, so no redirect is passed from here, and copies
  /// of the app installed before it existed get a working reset too.
  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email.trim());
    } on Object {
      // Deliberately swallowed. Reporting failure for an unknown address is a
      // way to enumerate who has an account; the screen says "if that address
      // has an account, a link is on its way" either way.
    }
  }

  Account? _toAccount(sb.User? user) =>
      user == null ? null : Account(id: user.id, email: user.email);

  /// Maps Supabase's message to something a person can act on.
  ///
  /// Matching on text is unpleasant and is what the API gives us. It is kept in
  /// one place so the unpleasantness does not spread, and everything unmatched
  /// falls through to the honest catch-all rather than being shown raw.
  static AuthFailure _map(sb.AuthException e, {required bool signingUp}) {
    final m = e.message.toLowerCase();
    if (m.contains('already registered') ||
        m.contains('already been registered')) {
      return AuthFailure.emailTaken;
    }
    if (m.contains('invalid') && m.contains('email')) {
      return AuthFailure.invalidEmail;
    }
    if (m.contains('password') && (m.contains('least') || m.contains('weak'))) {
      return AuthFailure.weakPassword;
    }
    if (m.contains('not confirmed')) return AuthFailure.needsConfirmation;
    if (m.contains('invalid login') || m.contains('invalid credentials')) {
      return AuthFailure.wrongCredentials;
    }
    // A 400 on sign-in is nearly always bad credentials; on sign-up it is
    // nearly always something about the input we did not match above.
    if (e.statusCode == '400') {
      return signingUp
          ? AuthFailure.invalidEmail
          : AuthFailure.wrongCredentials;
    }
    return AuthFailure.unavailable;
  }
}
