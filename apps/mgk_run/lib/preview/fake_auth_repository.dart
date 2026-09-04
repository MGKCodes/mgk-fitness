import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mgk_run/src/features/auth/data/auth_repository.dart';

/// In-memory [AuthRepository] for the preview harness and widget tests. It
/// never touches Supabase, so it drives the real [AuthGate] flow without a
/// backend: [signIn] / [signUp] flip it to signed-in and emit on [authChanges],
/// exactly as the real repository does when Supabase reports a session.
///
/// It also records the last credentials passed to [signIn] / [signUp], handy
/// for asserting the quick-sign-in buttons.
class FakeAuthRepository extends AuthRepository {
  FakeAuthRepository({
    bool signedIn = false,
    String? email,
    String? name,
    this.metCoach = true,
  }) : _signedIn = signedIn,
       _email = email,
       _name = name,
       super();

  bool _signedIn;
  String? _email;
  String? _name;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  String? lastEmail;
  String? lastPassword;

  /// Thrown by [signIn] and [signUp] in place of signing in, so a test can put
  /// the screen in the state build 12 was field-tested in — a call that never
  /// reaches the server. Null on the normal path, which is every other test.
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
  Stream<void> authChanges() => _changes.stream;

  @override
  Future<void> signIn({required String email, required String password}) async {
    lastEmail = email;
    lastPassword = password;
    final error = failure;
    if (error != null) throw error;
    _email = email;
    _signedIn = true;
    _changes.add(null);
    // Through the real wrapper rather than [ensureProfile] directly. The point
    // of that seam is that the profile write cannot fail an authentication, and
    // a fake that reached past it would leave exactly that untested.
    await ensureProfileBestEffort();
  }

  /// The name the last sign-up passed, so a test can assert it travelled.
  String? lastName;

  @override
  Future<bool> signUp({
    required String email,
    required String password,
    String? name,
  }) async {
    lastEmail = email;
    lastPassword = password;
    lastName = name;
    final error = failure;
    if (error != null) throw error;
    _email = email;
    _name = name;
    _signedIn = true;
    _changes.add(null);
    await ensureProfileBestEffort();
    // True because the account exists, which is what this answer is about. The
    // real repository says the same thing for the same reason, whatever the
    // profile write did afterwards.
    return true;
  }

  @override
  String? get currentName => _name;

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
    _changes.add(null);
  }

  @override
  Future<void> signOut() async {
    _signedIn = false;
    _email = null;
    _changes.add(null);
  }

  @override
  Future<void> ensureProfile() async {
    profileWrites++;
    final error = profileFailure;
    if (error != null) throw error;
  }
}
