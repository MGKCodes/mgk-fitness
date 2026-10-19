import 'dart:async';

import 'package:mgk_auth/mgk_auth.dart'
    show AccountStatus, EmailFailure, EmailSignInException;

import '../domain/account.dart';

/// An in-memory account, for tests and the preview harness.
///
/// Here rather than under `test/` because the preview binary uses it too, and a
/// second near-identical fake is how two versions of "what signing in does"
/// start disagreeing.
///
/// **The email path works offline, against fixed answers.** [lookupAnswers]
/// says what the lookup says for a few addresses, and every other address is
/// new, as most addresses are. [code] is the code every email carries and
/// [password] the password every account has, so a test or a board can walk
/// the whole path, a wrong password and a refused code included, with no
/// server.
class FakeAuth implements AuthService {
  FakeAuth({
    Account? account,
    this.failWith,
    this.providerOutcome = ProviderOutcome.signedIn,
    this.providerMakesAccount = false,
    this.readsAsNew,
    this.googleName = 'Matt Kay',
    this.emailFailure,
    this.nameFailure,
  }) : _account = account;

  /// What the lookup answers for each of these addresses; every other address
  /// is [AccountStatus.newAccount].
  static const Map<String, AccountStatus> lookupAnswers =
      <String, AccountStatus>{
        returningAddress: AccountStatus.password,
        unconfirmedAddress: AccountStatus.unconfirmed,
        appleAddress: AccountStatus.apple,
        googleAddress: AccountStatus.google,
      };

  /// An account with a password: *Welcome back*.
  static const String returningAddress = 'matt@example.com';

  /// A sign-up nobody confirmed, which looks exactly like a new address.
  static const String unconfirmedAddress = 'started@example.com';

  /// An account made with Apple: *This address signs in with Apple*.
  static const String appleAddress = 'matt@icloud.com';

  /// An account made with Google.
  static const String googleAddress = 'matt@gmail.com';

  /// The code in every email the fake sends.
  static const String code = '204816';

  /// The password every account the fake knows has.
  static const String password = 'lift-2026';

  Account? _account;
  final _controller = StreamController<Account?>.broadcast();

  /// Makes Apple and Google throw. For driving the provider's error states
  /// without a server.
  final AuthFailure? failWith;

  /// How Apple and Google end, when they do not fail: signed in, cancelled at
  /// the provider's sheet, or still going in the browser.
  final ProviderOutcome providerOutcome;

  /// Whether Apple and Google make the account rather than sign into one, as
  /// they do the first time and never say.
  final bool providerMakesAccount;

  /// What [isNewAccount] says whatever the sign-in did, or null for the
  /// truth. False is an address account whose code was typed long after it
  /// was made, which the account no longer reads as new.
  final bool? readsAsNew;

  /// The full name Google sends, for its first word.
  final String? googleName;

  /// Makes every call on the email path fail this way, until it is cleared:
  /// [EmailFailure.unavailable] is no connection.
  EmailFailure? emailFailure;

  /// Makes writing the name fail this way, until it is cleared.
  AuthFailure? nameFailure;

  @override
  late final EmailSignIn emailSignIn = _FakeEmailSignIn(this);

  /// Which provider was last asked, for tests.
  String? lastProvider;

  /// Every name written, in order: null for one cleared. Empty means the
  /// account's name was never touched.
  final List<String?> namesWritten = <String?>[];

  /// What the email path was asked to do, for tests: `create`, `resend`,
  /// `password email`, and the password a confirmed code replaced, if any.
  final List<String> emailCalls = <String>[];

  /// How the current account signs in, and whether this sign-in made it.
  String _via = 'email';
  bool _isNew = false;

  @override
  Account? get current => _account;

  @override
  Stream<Account?> get changes => _controller.stream;

  @override
  bool get isNewAccount => _account != null && (readsAsNew ?? _isNew);

  @override
  bool get signsInWithApple => _account != null && _via == 'apple';

  @override
  String? get googleFirstName {
    if (_account == null || _via != 'google') return null;
    final full = googleName?.trim() ?? '';
    return full.isEmpty ? null : full.split(RegExp(r'\s+')).first;
  }

  @override
  Future<ProviderOutcome> signInWithApple() async =>
      _provider('apple', 'you@privaterelay.appleid.com');

  @override
  Future<ProviderOutcome> signInWithGoogle() async =>
      _provider('google', 'you@gmail.com');

  ProviderOutcome _provider(String provider, String email) {
    lastProvider = provider;
    final failure = failWith;
    if (failure != null) throw AuthException(failure);
    if (providerOutcome != ProviderOutcome.signedIn) {
      // Apple's browser sign-in arrives later, through [arrive]; it is still
      // Apple's.
      _via = provider;
      return providerOutcome;
    }
    _finish(email, via: provider, isNew: providerMakesAccount);
    return ProviderOutcome.signedIn;
  }

  /// Signs in from outside the screen, as Apple's browser sign-in on Android
  /// does when its link comes back: by whichever provider was last asked, or
  /// by email.
  void arrive(String email, {bool? isNew}) => _finish(
    email,
    via: lastProvider ?? 'email',
    isNew: isNew ?? providerMakesAccount,
  );

  Account _finish(String email, {required String via, required bool isNew}) {
    _via = via;
    _isNew = isNew;
    final account = Account(id: 'fake-user', email: email.trim());
    _account = account;
    _controller.add(account);
    return account;
  }

  @override
  Future<void> updateName(String? name) async {
    final failure = nameFailure;
    if (failure != null) throw AuthException(failure);
    final account = _account;
    if (account == null) throw const AuthException(AuthFailure.unavailable);
    final trimmed = name?.trim() ?? '';
    final written = trimmed.isEmpty ? null : trimmed;
    namesWritten.add(written);
    // As Supabase reports `userUpdated`: the same account, with its new name.
    _account = Account(id: account.id, email: account.email, name: written);
    _controller.add(_account);
  }

  @override
  Future<void> signOut() async {
    _account = null;
    _isNew = false;
    _controller.add(null);
  }

  void dispose() => _controller.close();
}

/// The email path's server, answering from [FakeAuth]'s fixed answers.
///
/// Implements `mgk_auth`'s [EmailSignIn] rather than extending it, so nothing
/// here can reach a real Supabase client; `EmailSignInFlow` drives it exactly
/// as it drives the real one.
class _FakeEmailSignIn implements EmailSignIn {
  _FakeEmailSignIn(this._auth);

  final FakeAuth _auth;

  @override
  Duration get timeout => const Duration(seconds: 20);

  void _maybeFail() {
    if (_auth.emailFailure case final EmailFailure failure) {
      throw EmailSignInException(failure);
    }
  }

  @override
  Future<AccountStatus> lookup(String email) async {
    _maybeFail();
    return FakeAuth.lookupAnswers[email.trim().toLowerCase()] ??
        AccountStatus.newAccount;
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    _maybeFail();
    if (password != FakeAuth.password) {
      throw const EmailSignInException(EmailFailure.wrongPassword);
    }
    _auth._finish(email, via: 'email', isNew: false);
  }

  @override
  Future<bool> createAccount({
    required String email,
    required String password,
  }) async {
    _maybeFail();
    _auth.emailCalls.add('create');
    // Email confirmation is on, as it is in production: a code, not a session.
    return false;
  }

  @override
  Future<bool> confirm({
    required String email,
    required String code,
    String? replacePassword,
  }) async {
    _maybeFail();
    if (code.trim() != FakeAuth.code) {
      throw const EmailSignInException(EmailFailure.codeRefused);
    }
    if (replacePassword != null) {
      _auth.emailCalls.add('replace password');
    }
    _auth._finish(email, via: 'email', isNew: true);
    return true;
  }

  @override
  Future<void> resendCode(String email) async {
    _maybeFail();
    _auth.emailCalls.add('resend');
  }

  @override
  Future<void> sendPasswordEmail(String email) async {
    _maybeFail();
    _auth.emailCalls.add('password email');
  }
}
