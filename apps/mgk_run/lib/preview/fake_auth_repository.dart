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
    _email = email;
    _signedIn = true;
    _changes.add(null);
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
    _email = email;
    _name = name;
    _signedIn = true;
    _changes.add(null);
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
  Future<void> ensureProfile() async {}
}
