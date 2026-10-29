import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mgk_run/src/features/auth/data/auth_repository.dart';
import 'package:mgk_auth/mgk_auth.dart';

/// In-memory [AuthRepository] for the preview harness and widget tests. It
/// never touches Supabase, so it drives the real [AuthGate] flow without a
/// backend: [signIn], the email path and the providers flip it to signed-in
/// and emit on [authChanges], exactly as the real repository does when
/// Supabase reports a session.
///
/// It also records the last credentials passed to [signIn] and the email path,
/// handy for asserting the quick-sign-in buttons.
///
/// **The email path answers by address** (see [emailSignIn]), so every step of
/// it can be reached offline, by a test, a plate or the web preview, by typing
/// the address that leads there.
class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository({
    bool signedIn = false,
    String? email,
    String? name,
    this.metCoach = true,
    bool apple = false,
    this.newAccount = false,
    this.googleName,
  }) : _signedIn = signedIn,
       _email = email,
       _name = name,
       _apple = apple,
       super();

  // --- The email path's addresses -------------------------------------------
  //
  // What the fake lookup says about an address. Anything not listed here is a
  // new address, so any made-up one reaches *Create your account*.

  /// Has a password: *Welcome back*. [rightPassword] signs it in.
  static const String passwordAddress = 'sam@example.com';

  /// Made with Apple: *This address signs in with Apple*.
  static const String appleAddress = 'apple@example.com';

  /// Made with Google: *This address signs in with Google*.
  static const String googleAddress = 'google@example.com';

  /// A sign-up nobody confirmed. Looks exactly like a new address.
  static const String unconfirmedAddress = 'pending@example.com';

  /// The password [passwordAddress] has. Any other is a wrong password.
  static const String rightPassword = 'hunter2222';

  /// The code in every fake confirmation email. Any other is refused.
  static const String rightCode = '123456';

  /// What the fake lookup says about [email].
  static AccountStatus statusOf(String email) =>
      switch (email.trim().toLowerCase()) {
        passwordAddress => AccountStatus.password,
        appleAddress => AccountStatus.apple,
        googleAddress => AccountStatus.google,
        unconfirmedAddress => AccountStatus.unconfirmed,
        _ => AccountStatus.newAccount,
      };

  /// Thrown by every call on the email path, as [EmailSignInException]s, in
  /// place of an answer: [EmailFailure.unavailable] is the phone with no
  /// signal. Null on the normal path.
  EmailFailure? emailFailure;

  /// Whether the project signs a new email account in without a code, as it
  /// would with email confirmation off. False, as the real project is.
  bool confirmationOff = false;

  /// Whether the account in hand was just made. Set by the email path when it
  /// makes one; settable, so a test can say the same of an Apple or Google
  /// account, which make one without saying so.
  bool newAccount;

  /// The name Google holds for a Google account, for the intro's question to
  /// start filled in with. Only answered while signed in.
  String? googleName;

  /// The address each email went to, in order: codes, and links to set a
  /// password.
  final List<String> codesSent = <String>[];
  final List<String> passwordEmails = <String>[];

  /// The last code typed, and the password it was to replace the first one
  /// with (for an unconfirmed address), if any.
  String? lastCode;
  String? lastReplacement;

  /// How many addresses were looked up.
  int lookups = 0;

  /// Whether writing the password typed this time over an unconfirmed
  /// address's first one fails once the code has signed it in. The account is
  /// signed in all the same; only the first password still works.
  bool replacementFails = false;

  @override
  EmailSignIn emailSignIn() => _FakeEmailSignIn(this);

  @override
  bool get accountIsNew => _signedIn && newAccount;

  @override
  String? get googleFirstName => _signedIn ? googleName : null;

  /// Signs in [email] as the email path does once it has a session.
  void _arrive(String email, {required bool made}) {
    _email = email;
    _signedIn = true;
    _apple = false;
    newAccount = made;
    // A new account has never been anywhere, so it has never met the coach.
    if (made) metCoach = false;
    _changes.add(AuthChange.signedIn);
  }

  bool _signedIn;

  /// Whether the account in hand came through Apple. Set by [signInWithApple],
  /// or up front for a test that starts signed in.
  bool _apple;
  String? _email;
  String? _name;
  final StreamController<AuthChange> _changes =
      StreamController<AuthChange>.broadcast();

  /// Who is signed in. Settable, so a test can drive two *different* people
  /// signing in one after the other — the case the shell's de-duplication must
  /// not swallow. The real repository answers this from the gotrue session;
  /// [currentUser] here is null, so without this seam every fake identity would
  /// compare equal and the de-duplication would look correct while being
  /// untested.
  String? userId = 'fake-user';

  String? lastEmail;
  String? lastPassword;

  /// Thrown by [signIn] and the providers in place of signing in, so a test
  /// can put the screen in the state build 12 was field-tested in — a call that
  /// never reaches the server. Null on the normal path, which is every other
  /// test. The email path has its own, [emailFailure].
  Object? failure;

  /// Thrown by [ensureProfile], so a test can reproduce the half-success that
  /// stranded a runner in row E5: gotrue makes the account, and the separate
  /// `core.profiles` write does not land.
  Object? profileFailure;

  /// How many times the profile row was attempted. Lets a test tell a write
  /// that failed apart from one that was never made at all.
  int profileWrites = 0;

  @override
  bool get isSignedIn => _signedIn;

  @override
  String? get currentEmail => _email;

  @override
  Session? get currentSession => null;

  @override
  User? get currentUser => null;

  @override
  String? get currentUserId => _signedIn ? userId : null;

  @override
  Stream<AuthChange> authChanges() => _changes.stream;

  /// Replays an event the real stream emits and the app must ignore.
  ///
  /// There is no other way to reproduce the repeating restore offline: the real
  /// cause is gotrue announcing a session the app already has, and nothing in
  /// this fake does that on its own.
  void emit(AuthChange change) => _changes.add(change);

  @override
  Future<void> signIn({required String email, required String password}) async {
    lastEmail = email;
    lastPassword = password;
    final error = failure;
    if (error != null) throw error;
    _email = email;
    _signedIn = true;
    _changes.add(AuthChange.signedIn);
    // Through the real wrapper rather than [ensureProfile] directly. The point
    // of that seam is that the profile write cannot fail an authentication, and
    // a fake that reached past it would leave exactly that untested.
    await ensureProfileBestEffort();
  }

  /// How Apple and Google end when [failure] is null: signed in, cancelled at
  /// the provider's sheet, or still going in the browser.
  ProviderOutcome providerOutcome = ProviderOutcome.signedIn;

  /// Which provider was last asked.
  String? lastProvider;

  @override
  Future<ProviderOutcome> signInWithApple() =>
      _provider('apple', 'you@privaterelay.appleid.com');

  @override
  Future<ProviderOutcome> signInWithGoogle() =>
      _provider('google', 'you@gmail.com');

  Future<ProviderOutcome> _provider(String provider, String email) async {
    lastProvider = provider;
    final error = failure;
    if (error != null) throw error;
    if (providerOutcome != ProviderOutcome.signedIn) return providerOutcome;
    _email = email;
    _signedIn = true;
    _apple = provider == 'apple';
    _changes.add(AuthChange.signedIn);
    await ensureProfileBestEffort();
    return ProviderOutcome.signedIn;
  }

  @override
  String? get currentName => _name;

  @override
  bool get signedInWithApple => _signedIn && _apple;

  /// Whether the opening conversation has been had. Settable, so a test can
  /// stand up a runner who is signed in and has never seen it - which is what
  /// arriving from Lift looks like.
  bool metCoach;

  @override
  bool get hasMetCoach => metCoach;

  /// How many times the fact was written. A test asserts it is written once.
  int coachMarks = 0;

  @override
  Future<void> markCoachMet() async {
    coachMarks++;
    metCoach = true;
  }

  /// Mirrors the real repository: blank clears rather than storing empty, so a
  /// runner who would rather not be named has a reachable answer.
  @override
  Future<void> updateName(String? name) async {
    final trimmed = name?.trim();
    _name = trimmed == null || trimmed.isEmpty ? null : trimmed;
    _changes.add(AuthChange.userUpdated);
  }

  @override
  Future<void> signOut() async {
    _signedIn = false;
    _email = null;
    _apple = false;
    newAccount = false;
    _changes.add(AuthChange.signedOut);
  }

  @override
  Future<void> ensureProfile() async {
    profileWrites++;
    final error = profileFailure;
    if (error != null) throw error;
  }

  /// Whether the session was still there each time this app's keys were
  /// cleared off the profile. The real call needs one, so a test asserts the
  /// order rather than just the call.
  final List<bool> runMetadataClears = <bool>[];

  @override
  Future<void> clearRunMetadata() async {
    runMetadataClears.add(_signedIn);
    metCoach = false;
  }
}

/// The email path, answered from [FakeAuthRepository]'s addresses: no lookup
/// function, no auth server and no inbox.
class _FakeEmailSignIn extends EmailSignIn {
  _FakeEmailSignIn(this._repo);

  final FakeAuthRepository _repo;

  /// The step a test or a plate means to show, failing as it was told to.
  void _failIfTold() {
    final failure = _repo.emailFailure;
    if (failure != null) throw EmailSignInException(failure);
  }

  @override
  Future<AccountStatus> lookup(String email) async {
    _repo.lookups++;
    _failIfTold();
    return FakeAuthRepository.statusOf(email);
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    _repo
      ..lastEmail = email
      ..lastPassword = password;
    _failIfTold();
    if (FakeAuthRepository.statusOf(email) != AccountStatus.password ||
        password != FakeAuthRepository.rightPassword) {
      throw const EmailSignInException(EmailFailure.wrongPassword);
    }
    _repo._arrive(email.trim(), made: false);
  }

  @override
  Future<bool> createAccount({
    required String email,
    required String password,
  }) async {
    _repo
      ..lastEmail = email
      ..lastPassword = password;
    _failIfTold();
    if (_repo.confirmationOff) {
      _repo._arrive(email.trim(), made: true);
      return true;
    }
    _repo.codesSent.add(email.trim());
    return false;
  }

  @override
  Future<bool> confirm({
    required String email,
    required String code,
    String? replacePassword,
  }) async {
    _repo
      ..lastCode = code
      ..lastReplacement = replacePassword;
    _failIfTold();
    if (code.trim() != FakeAuthRepository.rightCode) {
      throw const EmailSignInException(EmailFailure.codeRefused);
    }
    _repo._arrive(email.trim(), made: true);
    // Signed in either way, as the real one is: a replacement that does not
    // land keeps the first password and is no failure of the code.
    return replacePassword == null || !_repo.replacementFails;
  }

  @override
  Future<void> resendCode(String email) async {
    _failIfTold();
    _repo.codesSent.add(email.trim());
  }

  @override
  Future<void> sendPasswordEmail(String email) async {
    _failIfTold();
    _repo.passwordEmails.add(email.trim());
  }
}
