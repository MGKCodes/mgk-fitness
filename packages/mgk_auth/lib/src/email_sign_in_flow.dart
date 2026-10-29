import 'package:flutter/foundation.dart';

import 'email_address.dart';
import 'email_sign_in.dart';
import 'password_rule.dart';

/// Where the email path stands (Run's ADR-0047, "Email first").
enum EmailStep {
  /// The address, alone.
  address,

  /// *Welcome back*: the address, with Change, and a password.
  password,

  /// *This address signs in with Apple* (or Google), with that button and
  /// *Set a password instead*. Which provider is [EmailSignInFlow.status].
  provider,

  /// *Create your account*: the address, with Change, and a new password.
  create,

  /// The 6-digit code from the email.
  code,
}

/// The email path's state, shared by both apps' sign-in screens.
///
/// **The steps, the waiting and the words live here, once.** Each app draws the
/// steps with `mgk_ui`'s `EmailSignInSteps` and decides what happens when
/// somebody is signed in; neither decides which step comes next, or what a
/// failure is called. One account across the suite, so one way into it, said
/// the same way in both apps.
///
/// Every action is ignored while another is running ([busy]), and every
/// failure leaves what was typed where it was: the screen keeps its fields,
/// and this keeps the address.
class EmailSignInFlow extends ChangeNotifier {
  EmailSignInFlow({
    required EmailSignIn api,
    this.resendWait = const Duration(seconds: 60),
    DateTime Function()? clock,
  }) : _api = api,
       _clock = clock ?? DateTime.now;

  final EmailSignIn _api;
  final DateTime Function() _clock;

  /// How long after a code is sent before another can be asked for. Supabase
  /// refuses a second email to one address inside its own minute anyway; this
  /// says so before the button is pressed rather than after.
  final Duration resendWait;

  EmailStep _step = EmailStep.address;
  String _email = '';
  AccountStatus? _status;
  bool _busy = false;
  String? _error;
  String? _notice;
  DateTime? _resendAt;

  /// The password typed on [EmailStep.create] for an address that was
  /// [AccountStatus.unconfirmed], held until the code proves the inbox and
  /// then written over the first one. Never held for a new address.
  String? _replacement;

  EmailStep get step => _step;

  /// The address being signed in with, as it was sent to the lookup. Empty
  /// until one has been.
  String get email => _email;

  /// What the lookup said, and so which provider [EmailStep.provider] names.
  AccountStatus? get status => _status;

  bool get busy => _busy;

  /// What went wrong, in words for the screen, or null.
  String? get error => _error;

  /// The next thing to do, in the quiet colour: an email on its way. Not a
  /// failure, so never in the error colour, where "a link is on its way" read
  /// as the link not having been sent.
  String? get notice => _notice;

  /// When another code may be asked for, or null before the first is sent.
  DateTime? get resendAt => _resendAt;

  /// Whether another code may be asked for now.
  bool get canResend {
    final at = _resendAt;
    return at == null || !_clock().isBefore(at);
  }

  /// The address [typed] was probably meant to be, for "Did you mean …?". See
  /// [suggestEmail]: offered, never applied.
  String? suggestionFor(String typed) => suggestEmail(typed);

  /// Sends the address to the lookup and moves to the step it leads to.
  ///
  /// An address that cannot be one is refused here, without a request. A
  /// failed lookup stays on [EmailStep.address] and says so: the step after it
  /// is never guessed.
  Future<void> submitAddress(String typed) async {
    final email = typed.trim();
    if (!looksLikeEmail(email)) {
      _say(error: 'That does not look like an email address.');
      return;
    }
    await _run(() async {
      final status = await _api.lookup(email);
      _email = email;
      _status = status;
      _replacement = null;
      _step = switch (status) {
        AccountStatus.password => EmailStep.password,
        AccountStatus.apple || AccountStatus.google => EmailStep.provider,
        AccountStatus.newAccount ||
        AccountStatus.unconfirmed => EmailStep.create,
      };
    });
  }

  /// Signs in with [password]. True once signed in.
  Future<bool> signIn(String password) async {
    if (password.isEmpty) {
      _say(error: 'Enter your password.');
      return false;
    }
    return _run(() => _api.signIn(email: _email, password: password));
  }

  /// Makes the account and sends the code. True only if the project signed it
  /// in at once, which it does not while email confirmation is on; otherwise
  /// the flow moves to [EmailStep.code].
  Future<bool> createAccount(String password) async {
    if (!PasswordCheck.of(password).passes) {
      _say(error: 'Use at least 8 characters, with a number and a symbol.');
      return false;
    }
    var signedIn = false;
    await _run(() async {
      signedIn = await _api.createAccount(email: _email, password: password);
      if (signedIn) return;
      _replacement = _status == AccountStatus.unconfirmed ? password : null;
      _step = EmailStep.code;
      _resendAt = _clock().add(resendWait);
    });
    return signedIn;
  }

  /// Checks the code, which signs the new account in. True once signed in.
  ///
  /// For an address that was [AccountStatus.unconfirmed], the password typed
  /// this time is written once the code checks out. If that write fails the
  /// account is still signed in, so this is still true, and
  /// [firstPasswordKept] says the password it was first made with is the one
  /// that works.
  Future<bool> confirm(String code) async {
    final digits = code.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^\d{6}$').hasMatch(digits)) {
      _say(error: 'The code is the 6 digits in the email.');
      return false;
    }
    var replaced = true;
    final ok = await _run(() async {
      replaced = await _api.confirm(
        email: _email,
        code: digits,
        replacePassword: _replacement,
      );
    });
    if (ok) {
      _firstPasswordKept = !replaced;
      _replacement = null;
    }
    return ok;
  }

  bool _firstPasswordKept = false;

  /// After [confirm] signed an unconfirmed address in: true when the password
  /// typed this time could not be written, so the one the account was first
  /// made with still works. A screen may say so; *Forgot your password?* is
  /// the way to a new one either way.
  bool get firstPasswordKept => _firstPasswordKept;

  /// Sends another code, once [canResend].
  Future<void> resend() async {
    if (!canResend) return;
    final ok = await _run(() => _api.resendCode(_email));
    if (!ok) return;
    _resendAt = _clock().add(resendWait);
    _say(notice: 'A new code is on its way to $_email.');
  }

  /// *Forgot your password?*: sends the link to the address already typed.
  ///
  /// The address is said back in full now. The lookup has already told the
  /// screen this address has an account, so "if that address has an account"
  /// would hide nothing and only add doubt.
  Future<void> forgotPassword() async {
    final ok = await _run(() => _api.sendPasswordEmail(_email));
    if (ok)
      _say(notice: 'A link to set a new password is on its way to $_email.');
  }

  /// *Set a password instead*, for an account made with Apple or Google.
  /// Supabase allows a password on one, and the link sets it.
  Future<void> setPasswordInstead() async {
    final ok = await _run(() => _api.sendPasswordEmail(_email));
    if (ok) {
      _say(
        notice:
            'A link to set a password is on its way to $_email. Then sign in '
            'here with it.',
      );
    }
  }

  /// *Change*: back to the address, keeping it to edit.
  void changeAddress() {
    if (_busy) return;
    _step = EmailStep.address;
    _status = null;
    _replacement = null;
    _resendAt = null;
    _error = null;
    _notice = null;
    notifyListeners();
  }

  /// Clears what is said without moving, as when the screen is left and
  /// come back to.
  void clearMessages() {
    if (_error == null && _notice == null) return;
    _error = null;
    _notice = null;
    notifyListeners();
  }

  /// Runs one request: busy while it runs, a failure turned into words, and
  /// true if it finished.
  Future<bool> _run(Future<void> Function() action) async {
    if (_busy) return false;
    _busy = true;
    _error = null;
    _notice = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on EmailSignInException catch (e) {
      _error = _words(e.failure);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  bool _disposed = false;

  /// **A request can outlive its screen.** Somebody who closes the sign-in
  /// while a lookup is in flight leaves this to finish on its own, and its
  /// last word would otherwise be a notification to a disposed notifier,
  /// which throws. So a disposed flow finishes quietly.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  void _say({String? error, String? notice}) {
    _error = error;
    _notice = notice;
    notifyListeners();
  }

  /// What each failure is called, in both apps.
  static String _words(EmailFailure failure) => switch (failure) {
    EmailFailure.unavailable =>
      'No connection. Try again when you have a signal.',
    EmailFailure.wrongPassword =>
      'Wrong password. Try again, or set a new one.',
    EmailFailure.codeRefused =>
      'That code is wrong or has expired. Check it, or send a new one.',
    EmailFailure.tooManyEmails =>
      'Too many emails to this address for now. Try again in a few minutes.',
    EmailFailure.refused => 'That did not go through. Try again.',
  };
}
