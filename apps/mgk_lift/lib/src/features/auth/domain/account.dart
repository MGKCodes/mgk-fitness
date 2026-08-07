import 'package:meta/meta.dart';

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
  unavailable;

  String get message => switch (this) {
    wrongCredentials => 'That email and password do not match.',
    emailTaken => 'There is already an account with that email.',
    invalidEmail => 'That does not look like an email address.',
    weakPassword => 'Use at least 8 characters.',
    needsConfirmation =>
      'Check your email and follow the link, then sign in.',
    unavailable =>
      'Could not reach the server. Your training is safe on this device.',
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

  Future<void> signOut();

  /// Sends a reset link. Succeeds silently for an address with no account, so
  /// this cannot be used to discover who has one.
  Future<void> sendPasswordReset(String email);
}
