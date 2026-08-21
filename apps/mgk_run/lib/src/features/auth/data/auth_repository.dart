import 'package:supabase_flutter/supabase_flutter.dart';

/// The single seam the UI uses for authentication, so screens never touch the
/// Supabase client directly.
///
/// The client is accessed lazily (per call), so constructing an
/// [AuthRepository] does not require Supabase to be initialised — which keeps
/// widgets that hold one testable without a live backend.
class AuthRepository {
  const AuthRepository();

  SupabaseClient get _client => Supabase.instance.client;

  Session? get currentSession => _client.auth.currentSession;
  User? get currentUser => _client.auth.currentUser;

  /// Whether a user is currently signed in. The routing seam the app depends
  /// on, so widgets decide auth state without importing Supabase's [Session].
  bool get isSignedIn => currentSession != null;

  /// The signed-in user's email, or null when signed out. Exposed so widgets
  /// display identity without importing Supabase's [User] type.
  String? get currentEmail => _client.auth.currentUser?.email;

  /// Fires whenever auth state changes. Type-erased to `void` so the widget
  /// layer reacts to *that it changed* via [isSignedIn], not to Supabase's
  /// [AuthState] payload.
  Stream<void> authChanges() => _client.auth.onAuthStateChange.map((_) {});

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
    await ensureProfile();
  }

  /// Returns true if a session was created (email confirmation disabled), or
  /// false if the user must confirm their email before signing in.
  /// [name] is what the coach calls them. It goes into **auth user metadata**
  /// rather than a column: `public.profiles` is the shared MGKCodes identity
  /// table that Liftio reads too, so a name column there is a migration against
  /// a schema this app does not own. Metadata travels with the account, needs no
  /// migration, and arrives with the session on every device.
  Future<bool> signUp({
    required String email,
    required String password,
    String? name,
  }) async {
    final trimmed = name?.trim();
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      data: trimmed == null || trimmed.isEmpty
          ? null
          : <String, dynamic>{'name': trimmed},
    );
    if (response.session != null) {
      await ensureProfile();
      return true;
    }
    return false;
  }

  /// What the coach calls this runner, or null where they never said.
  ///
  /// Read from the session rather than a table, so it is available offline and
  /// costs no round trip.
  String? get currentName {
    final value = _client.auth.currentUser?.userMetadata?['name'];
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Changes what the coach calls this runner.
  ///
  /// The intro accepts **any** name, on the grounds that a name is not a format
  /// and every rule that rejects one rejects somebody real. That reasoning only
  /// holds if a mistyped one can be put right, and for a long time it could not
  /// be: the name was written once at sign-up and read back forever. The
  /// comment claiming it was "fixed on the confirmation screen at the end of
  /// intake" pointed at a screen that edits `IntakeSlots`, which has no name in
  /// it. This is that path, finally built.
  ///
  /// Writes to auth metadata, the same place [signUp] puts it, so it travels
  /// with the account and needs no migration against the `public.profiles`
  /// table Liftio shares.
  ///
  /// An empty or whitespace-only name **clears** it rather than storing blank,
  /// so "I would rather you did not use a name" is a reachable answer. Every
  /// reader already treats null as "say nothing" — [currentName] returns null
  /// for blank, and `CoachBrief.write` omits the mention entirely.
  Future<void> updateName(String? name) async {
    final trimmed = name?.trim();
    await _client.auth.updateUser(
      UserAttributes(
        data: <String, dynamic>{
          'name': trimmed == null || trimmed.isEmpty ? null : trimmed,
        },
      ),
    );
  }

  /// The metadata key recording that this app's coach has been met.
  ///
  /// **Namespaced by app on purpose.** One profile spans the suite, so a single
  /// `intro_seen` would mean a runner who onboarded in Lift arrives here having
  /// apparently already met a coach they have never spoken to. The profile is
  /// shared; meeting a coach is not.
  static const String _metCoachKey = 'run_intro_seen';

  /// Whether this runner has been through this app's opening conversation.
  ///
  /// In metadata rather than a table for the same reasons the name is: it
  /// travels with the account, needs no migration, and arrives with the session
  /// on every device, so a reinstall or a second phone does not replay it.
  ///
  /// **Permissions are deliberately not recorded here.** They are per install
  /// and the OS can revoke them behind the app's back, so the only honest
  /// source is the OS, asked every time. This records one fact: the conversation
  /// happened.
  bool get hasMetCoach =>
      _client.auth.currentUser?.userMetadata?[_metCoachKey] == true;

  /// Records that the conversation happened.
  Future<void> markCoachMet() async {
    await _client.auth.updateUser(
      UserAttributes(data: <String, dynamic>{_metCoachKey: true}),
    );
  }

  Future<void> signOut() => _client.auth.signOut();

  /// Ensures a row in the shared `public.profiles` table for the signed-in
  /// user — the shared identity across the MGKCodes fitness apps.
  Future<void> ensureProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client.schema('core').from('profiles').upsert({
      'id': user.id,
      'email': user.email,
    });
  }
}
