import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// What `account-lookup` says about an address, which decides the next screen
/// (Run's ADR-0047, "Email first").
enum AccountStatus {
  /// No account: *Create your account*, then a code by email.
  newAccount,

  /// A sign-up nobody confirmed. **Shown exactly as [newAccount].** The app
  /// keeps the difference only so that, once the code proves the inbox, the
  /// password typed now replaces the one the account was first made with.
  unconfirmed,

  /// *Welcome back*, and a password field.
  password,

  /// This address signs in with Apple: its button, and *Set a password
  /// instead*.
  apple,

  /// This address signs in with Google: its button, and *Set a password
  /// instead*.
  google;

  /// Whether the next screen makes an account.
  bool get makesAnAccount => this == newAccount || this == unconfirmed;

  static AccountStatus? _fromWire(Object? value) => switch (value) {
    'new' => AccountStatus.newAccount,
    'unconfirmed' => AccountStatus.unconfirmed,
    'password' => AccountStatus.password,
    'apple' => AccountStatus.apple,
    'google' => AccountStatus.google,
    _ => null,
  };
}

/// Why a step of the email path failed, in the ways the screen says something
/// different about.
enum EmailFailure {
  /// No network, or no answer in time. "No connection", with what was typed
  /// kept. Never a guess at new or returning.
  unavailable,

  /// The password does not match. Called a wrong password, now that the
  /// screen already knows the address has one.
  wrongPassword,

  /// The code is wrong or has expired. Supabase answers both with the same
  /// error, so the screen says both, with *Resend*.
  codeRefused,

  /// Too many emails to this address for now. Supabase's own limit.
  tooManyEmails,

  /// The server said no for a reason none of the above covers.
  refused,
}

class EmailSignInException implements Exception {
  const EmailSignInException(this.failure, [this.cause]);

  final EmailFailure failure;

  /// What the server actually said, for logs. Never shown.
  final Object? cause;

  @override
  String toString() => 'EmailSignInException($failure, $cause)';
}

/// Signing in, and making an account, with an email address, into the suite's
/// one Supabase project. Lift and Run both draw their screens over this.
///
/// **The address comes first.** [lookup] asks `account-lookup` which screen is
/// next, so nobody has to know whether to sign in or sign up before they type
/// anything (ADR-0047, which ends the two-mode form).
///
/// **A new address is confirmed with a code typed into the app**, not only a
/// link: [createAccount] sends it and [confirm] checks it, signing the account
/// in. Every Run before 1.0.2 and every Lift before 2.0.1 know only the link,
/// so the email carries both.
///
/// **Nothing here asks for a name.** The name is the account's, asked once
/// after any new account by the app's own screen, and never after Sign in with
/// Apple (guideline 4, the rejection of 16 October 2026).
class EmailSignIn {
  EmailSignIn({
    GoTrueClient Function()? auth,
    FunctionsClient Function()? functions,
    this.timeout = const Duration(seconds: 20),
  }) : _auth = auth ?? (() => Supabase.instance.client.auth),
       _functions = functions ?? (() => Supabase.instance.client.functions);

  final GoTrueClient Function() _auth;
  final FunctionsClient Function() _functions;

  /// The bound every call on the auth path has: long enough for a slow
  /// connection, short enough that a dead one is reported, not waited on.
  final Duration timeout;

  /// Which screen [email] leads to.
  ///
  /// Throws [EmailFailure.unavailable] for anything but a clear answer: a
  /// failed request, an error status, or a status this build does not know.
  /// Guessing new would offer to make a second account for somebody who has
  /// one; guessing returning would ask a new person for a password they never
  /// set.
  Future<AccountStatus> lookup(String email) async {
    final FunctionResponse response;
    try {
      response = await _functions()
          .invoke(
            'account-lookup',
            body: <String, String>{'email': email.trim()},
          )
          .timeout(timeout);
    } on Object catch (e) {
      throw EmailSignInException(EmailFailure.unavailable, e);
    }
    final data = response.data;
    final status = data is Map ? AccountStatus._fromWire(data['status']) : null;
    if (status == null) {
      throw EmailSignInException(EmailFailure.unavailable, data);
    }
    return status;
  }

  /// Signs in an account [lookup] said has a password.
  Future<void> signIn({required String email, required String password}) =>
      _call(
        () =>
            _auth().signInWithPassword(email: email.trim(), password: password),
        onCredentials: EmailFailure.wrongPassword,
      );

  /// Makes an account, or starts again on one nobody confirmed, and sends the
  /// code. Returns true only if the project signed the account in straight
  /// away, which it does not while email confirmation is on.
  ///
  /// **No name, no metadata.** The name is asked for after the account exists,
  /// by the app's own step, and stored as `display_name`.
  ///
  /// For an [AccountStatus.unconfirmed] address Supabase resends the code and
  /// keeps the first password; [confirm] replaces it once the code checks out.
  Future<bool> createAccount({
    required String email,
    required String password,
  }) async {
    final response = await _call(
      () => _auth().signUp(email: email.trim(), password: password),
    );
    return response.session != null;
  }

  /// Checks the code from the email, which signs the account in.
  ///
  /// [replacePassword] is the password typed this time, for an address that
  /// was [AccountStatus.unconfirmed]. It is written only after the code has
  /// proved the inbox: never before, because writing a password to a brand-new
  /// account sends the "password changed" notice to everybody who signs up.
  Future<void> confirm({
    required String email,
    required String code,
    String? replacePassword,
  }) async {
    await _call(
      () => _auth().verifyOTP(
        type: OtpType.signup,
        email: email.trim(),
        token: code.trim(),
      ),
      onCode: EmailFailure.codeRefused,
    );
    if (replacePassword != null) {
      await _call(
        () => _auth().updateUser(UserAttributes(password: replacePassword)),
      );
    }
  }

  /// Sends the code again.
  Future<void> resendCode(String email) =>
      _call(() => _auth().resend(type: OtpType.signup, email: email.trim()));

  /// Sends the email that sets a password: *Forgot your password?*, and *Set a
  /// password instead* for an account made with Apple or Google. The link
  /// lands on the site's reset page, which the email template names.
  Future<void> sendPasswordEmail(String email) =>
      _call(() => _auth().resetPasswordForEmail(email.trim()));

  /// Runs one call against the auth server, sorting what goes wrong into what
  /// the screen can say.
  Future<T> _call<T>(
    Future<T> Function() call, {
    EmailFailure? onCredentials,
    EmailFailure? onCode,
  }) async {
    try {
      return await call().timeout(timeout);
    } on TimeoutException catch (e) {
      throw EmailSignInException(EmailFailure.unavailable, e);
    } on AuthRetryableFetchException catch (e) {
      throw EmailSignInException(EmailFailure.unavailable, e);
    } on AuthException catch (e) {
      final code = e.code;
      if (code == ErrorCode.overEmailSendRateLimit.code) {
        throw EmailSignInException(EmailFailure.tooManyEmails, e);
      }
      // The server's `invalid_credentials`, which gotrue-dart's ErrorCode
      // does not list (errorcodes.go in supabase/auth does).
      if (onCredentials != null && code == 'invalid_credentials') {
        throw EmailSignInException(onCredentials, e);
      }
      if (onCode != null && code == ErrorCode.otpExpired.code) {
        throw EmailSignInException(onCode, e);
      }
      throw EmailSignInException(EmailFailure.refused, e);
    }
  }
}
