import 'package:meta/meta.dart';
import 'package:mgk_auth/mgk_auth.dart' show ProviderOutcome;

export 'package:mgk_auth/mgk_auth.dart' show ProviderOutcome;

/// Who is signed in, if anybody.
@immutable
class Account {
  const Account({required this.id, required this.email});

  final String id;
  final String? email;
}

/// What went wrong, in terms a lifter can act on.
///
/// **Deliberately a small closed set.** Supabase returns a wide range of
/// messages, many of them about internals; mapping them here means the screen
/// never has to render a sentence nobody wrote for a human, and never leaks
/// whether an email exists.
enum AuthFailure {
  /// Wrong email or password. **One case for both**, on purpose: distinguishing
  /// them tells anybody with an email address whether that address has an
  /// account here, which for a fitness app is not nothing.
  wrongCredentials,

  /// The address is already registered.
  emailTaken,

  /// Not an email address.
  invalidEmail,

  /// Too short, or otherwise rejected by the server's policy.
  weakPassword,

  /// Signed up, but the address has not been confirmed yet.
  needsConfirmation,

  /// No network, or the server is down. Nothing the lifter did.
  unavailable,

  /// Apple or Google, or the server behind them, said no. Not the lifter's to
  /// fix, and not worth retrying the same way at once.
  providerRefused;

  String get message => switch (this) {
    wrongCredentials => 'That email and password do not match.',
    emailTaken => 'There is already an account with that email.',
    invalidEmail => 'That does not look like an email address.',
    weakPassword => 'Use at least 8 characters.',
    needsConfirmation => 'Check your email and follow the link, then sign in.',
    unavailable =>
      'Could not reach the server. Your training is safe on this device.',
    providerRefused =>
      'That sign-in did not go through. Try again, or use your email.',
  };
}

/// Thrown by [AuthService] rather than returned, so a screen cannot forget to
/// check — an ignored error here is a lifter staring at a spinner.
@immutable
class AuthException implements Exception {
  const AuthException(this.failure);

  final AuthFailure failure;

  @override
  String toString() => failure.message;
}

/// Signing in and out.
///
/// An interface because the screens are worth testing without a network, and
/// because a build with no Supabase configured needs a version of this that
/// says so rather than one that crashes.
abstract interface class AuthService {
  Account? get current;

  /// Emits on every change, so the shell can rebuild when a session is restored
  /// at launch or expires mid-use.
  Stream<Account?> get changes;

  Future<Account> signIn({required String email, required String password});

  /// Creates the account. May complete without a session when the project
  /// requires email confirmation — hence [AuthFailure.needsConfirmation].
  Future<Account> signUp({required String email, required String password});

  /// Signs in with Apple, making the account the first time.
  ///
  /// [ProviderOutcome.cancelled] when they closed Apple's sheet, and
  /// [ProviderOutcome.continuing] on Android, where Apple's sign-in finishes
  /// in the browser and the account arrives on [changes] afterwards.
  Future<ProviderOutcome> signInWithApple();

  /// Signs in with Google, making the account the first time.
  Future<ProviderOutcome> signInWithGoogle();

  Future<void> signOut();

  /// Sends a reset link. Succeeds silently for an address with no account, so
  /// this cannot be used to discover who has one.
  Future<void> sendPasswordReset(String email);
}
