import 'package:meta/meta.dart';
import 'package:mgk_auth/mgk_auth.dart' show EmailSignIn, ProviderOutcome;

export 'package:mgk_auth/mgk_auth.dart' show EmailSignIn, ProviderOutcome;

/// Who is signed in, if anybody.
@immutable
class Account {
  const Account({required this.id, required this.email, this.name});

  final String id;
  final String? email;

  /// What the account's owner asked to be called, or null where they gave
  /// nothing (Run's ADR-0047, "The name belongs to the account").
  ///
  /// **The MGKFitness account's name, not Lift's.** Run shows the same one and
  /// its coach uses it; Lift shows it on Settings and the account screen and
  /// sends it nowhere. Lift's coach does not use it, which the ADR leaves
  /// open. Read with `mgk_auth`'s `displayNameOf`, never from Google's `name`,
  /// which Supabase rewrites on every Google sign-in.
  final String? name;
}

/// What went wrong with Apple, Google, a name or signing out, in terms a
/// lifter can act on.
///
/// **Deliberately a small closed set.** Supabase returns a wide range of
/// messages, many of them about internals; mapping them here means the screen
/// never has to render a sentence nobody wrote for a human.
///
/// **Not the email path's.** Signing in with an address is `mgk_auth`'s
/// `EmailSignInFlow`, whose failures and words are shared with Run, and which
/// calls a wrong password a wrong password: the lookup has already said the
/// address has an account, so hiding which half was wrong would hide nothing
/// (ADR-0047, "Email first", point 7). This used to have one case for a wrong
/// email or password "on purpose", for the rule that signing in never says
/// whether an address has an account. That rule ended with 2.0.1. What is left
/// here is the provider path, the name, and whatever else still throws one.
enum AuthFailure {
  /// No network, or the server is down. Nothing the lifter did.
  unavailable,

  /// Apple or Google, or the server behind them, said no. Not the lifter's to
  /// fix, and not worth retrying the same way at once.
  providerRefused;

  String get message => switch (this) {
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

/// Signing in and out, and the few facts about the account the sign-in needs.
///
/// An interface because the screens are worth testing without a network, and
/// because a build with no Supabase configured needs a version of this that
/// says so rather than one that crashes.
abstract interface class AuthService {
  Account? get current;

  /// Emits on every change, so the shell can rebuild when a session is restored
  /// at launch or expires mid-use. A changed name arrives here too, as the
  /// same account with its new [Account.name].
  Stream<Account?> get changes;

  /// The email path: the address first, then the step the lookup leads to,
  /// and a code to confirm a new address (ADR-0047). Shared with Run, so the
  /// steps, the waiting and the words are the same in both apps; the sign-in
  /// screen drives it through `mgk_auth`'s `EmailSignInFlow`.
  EmailSignIn get emailSignIn;

  /// Signs in with Apple, making the account the first time.
  ///
  /// [ProviderOutcome.cancelled] when they closed Apple's sheet, and
  /// [ProviderOutcome.continuing] on Android, where Apple's sign-in finishes
  /// in the browser and the account arrives on [changes] afterwards.
  Future<ProviderOutcome> signInWithApple();

  /// Signs in with Google, making the account the first time.
  Future<ProviderOutcome> signInWithGoogle();

  Future<void> signOut();

  /// Whether [current] was made by the sign-in that just happened, read from
  /// the account rather than from which button was pressed: Apple and Google
  /// make an account or sign into one without saying which (ADR-0047, "Email
  /// first", point 7). False when nobody is signed in.
  bool get isNewAccount;

  /// Whether [current] can sign in with Apple. **Nothing asks such an account
  /// for a name**, however it signed in this time: App Review rejected Run
  /// 1.0.0 for asking after Sign in with Apple, though the question could be
  /// skipped (guideline 4, 16 October 2026).
  bool get signsInWithApple;

  /// The first name Google gave [current], to start the name step filled in,
  /// or null. Only ever a suggestion: nobody has to use the name their
  /// provider holds.
  String? get googleFirstName;

  /// Gives the account a name, or takes it away: null or blank clears it.
  ///
  /// The suite's one name, so Run shows the change too. Throws
  /// [AuthFailure.unavailable] when it did not reach the server, and nothing
  /// is changed then.
  Future<void> updateName(String? name);

  /// Removes Lift's own keys from the account, when Lift's data has been
  /// deleted and the login kept for Run.
  ///
  /// **The server's sweep does not reach auth metadata.** It erases the
  /// `lift` schema and leaves the login alone, so without this a lifter who
  /// deleted their Lift data and came back through the same login would find
  /// their yes to the coach still on file, as though nothing had gone. Run
  /// clears its own keys the same way. The name is not here: it is the
  /// account's, and Run shows it.
  ///
  /// Needs the session, so it runs before signing out. Throws when it did not
  /// reach the server.
  Future<void> clearLiftMetadata();
}
