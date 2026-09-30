import 'package:mgk_auth/mgk_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'provider_ids.dart';

/// What the app reacts to: **the identity changed**, not "gotrue emitted".
///
/// The stream this names used to be `Stream<void>` — type-erased, on the
/// reasoning that a listener only needs to know *that* something moved and can
/// re-read [AuthRepository.isSignedIn] itself. That is true of routing, which
/// is all it had when it was written, and false of everything added since.
///
/// `onAuthStateChange` also emits `tokenRefreshed`, **periodically and on every
/// resume**. Once a listener hung a restore off it, build 13 showed the cost:
/// the "restored your runs" message arrived again every time the token turned
/// over, which reads as the app repeatedly discovering the same history. A
/// listener cannot filter what the stream declined to tell it, so the type is
/// the fix rather than a condition at the far end.
enum AuthChange {
  /// A session now exists that did not before, or belongs to somebody else.
  signedIn,

  /// The session is gone.
  signedOut,

  /// Same person, changed details — a rename. Not a reason to restore.
  userUpdated,
}

/// The single seam the UI uses for authentication, so screens never touch the
/// Supabase client directly.
///
/// The client is accessed lazily (per call), so constructing an
/// [AuthRepository] does not require Supabase to be initialised — which keeps
/// widgets that hold one testable without a live backend.
class AuthRepository {
  const AuthRepository({this.timeout = const Duration(seconds: 20)});

  /// How long one call on the auth path may take before it counts as failed.
  ///
  /// **Nothing here had a deadline.** Build 12 was field-tested with the radio
  /// off and creating an account neither failed nor said anything: gotrue
  /// classes a failed fetch as *retryable* and keeps the request alive, so the
  /// call simply sat there behind a spinner. The runner was given no way to
  /// tell a slow connection from no connection, and the app looked stopped
  /// rather than offline. Every other network call in this app is already
  /// bounded — entitlements and the unit read at 5s, the coach at 90 — and this
  /// was the one path without one.
  ///
  /// Longer than the reads, deliberately. Those are best-effort and have a
  /// default to fall back on, so cutting them short costs nothing; this one is
  /// the runner's account, and a deadline tight enough to sever a slow-but-
  /// working connection would refuse sign-ups that were about to succeed. Long
  /// enough to survive a bad carriage, short enough that a dead radio gets
  /// reported instead of waited on.
  final Duration timeout;

  SupabaseClient get _client => Supabase.instance.client;

  Session? get currentSession => _client.auth.currentSession;
  User? get currentUser => _client.auth.currentUser;

  /// Whether a user is currently signed in. The routing seam the app depends
  /// on, so widgets decide auth state without importing Supabase's [Session].
  bool get isSignedIn => currentSession != null;

  /// The signed-in user's email, or null when signed out. Exposed so widgets
  /// display identity without importing Supabase's [User] type.
  String? get currentEmail => _client.auth.currentUser?.email;

  /// Who is signed in, as an opaque id, or null when nobody is.
  ///
  /// Exposed for the same reason [currentEmail] is — a caller comparing "is
  /// this the same person as last time" should not have to import Supabase's
  /// [User] to do it. `HomeShell` uses exactly that comparison to tell a
  /// genuine sign-in from gotrue re-announcing the one already in hand.
  String? get currentUserId => currentUser?.id;

  /// Fires when the signed-in identity changes. See [AuthChange] for why this
  /// carries a value rather than being erased to `void`.
  ///
  /// **Deliberately not de-duplicated here.** Two consecutive `signedIn` events
  /// for the same person are dropped by the listener that acts on them, not by
  /// this method: knowing whether an identity is *the same as last time* needs
  /// per-subscriber state, and this class is `const` (six call sites construct
  /// it as a default argument). A `distinct()` here would also be wrong for two
  /// subscribers, which is exactly what the app has — [AuthGate] routes on it
  /// and `HomeShell` restores on it, and they must not share a filter.
  Stream<AuthChange> authChanges() => _client.auth.onAuthStateChange
      .map(_classify)
      .where((AuthChange? change) => change != null)
      .cast<AuthChange>();

  /// Null for events the app has no reaction to, which are then filtered out.
  ///
  /// `tokenRefreshed` is the important omission and the reason this exists:
  /// it fires on a timer and on resume, and it says nothing about identity.
  /// `passwordRecovery` and `mfaChallengeVerified` are likewise not identity.
  ///
  /// `initialSession` is classified by whether there *is* one, because that is
  /// the event [AuthGate] needs on a cold launch with a restored session — it
  /// is the only one that will arrive.
  static AuthChange? _classify(AuthState state) => switch (state.event) {
    AuthChangeEvent.signedIn => AuthChange.signedIn,
    AuthChangeEvent.signedOut => AuthChange.signedOut,
    AuthChangeEvent.userUpdated => AuthChange.userUpdated,
    AuthChangeEvent.initialSession =>
      state.session == null ? AuthChange.signedOut : AuthChange.signedIn,
    _ => null,
  };

  /// Signs in with Apple, making the account the first time.
  ///
  /// [ProviderOutcome.continuing] on Android, where Apple's sign-in finishes
  /// in the browser and the session arrives through [authChanges]. Throws a
  /// [ProviderSignInException] for anything but a sign-in or a cancel.
  Future<ProviderOutcome> signInWithApple() async {
    final outcome = await _providers().apple();
    if (outcome == ProviderOutcome.signedIn) await ensureProfileBestEffort();
    return outcome;
  }

  /// Signs in with Google, making the account the first time.
  Future<ProviderOutcome> signInWithGoogle() async {
    final outcome = await _providers().google();
    if (outcome == ProviderOutcome.signedIn) await ensureProfileBestEffort();
    return outcome;
  }

  /// Made per call: this class is `const`, and holds nothing between calls.
  ProviderSignIn _providers() =>
      ProviderSignIn(ids: runProviderIds, timeout: timeout);

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth
        .signInWithPassword(email: email, password: password)
        .timeout(timeout);
    await ensureProfileBestEffort();
  }

  /// Sends a reset email, and says nothing about whether it went.
  ///
  /// Reporting failure for an unknown address would be a way to find out who
  /// has an account, so the screen says "if that address has an account" either
  /// way. The link lands on mgkfitness.mgkcodes.com/reset-password: the email
  /// template names the page, so no redirect is passed from here.
  Future<void> sendPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email.trim()).timeout(timeout);
    } on Object {
      // Deliberately swallowed; see above.
    }
  }

  /// Returns true if a session was created (email confirmation disabled), or
  /// false if the user must confirm their email before signing in.
  ///
  /// **The answer is about the session, and nothing else.** It used to be about
  /// the session *and* the `core.profiles` row, because the profile write was
  /// awaited into the result — see [ensureProfileBestEffort] for why that made
  /// a created account report itself as a failure.
  ///
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
    final response = await _client.auth
        .signUp(
          email: email,
          password: password,
          data: trimmed == null || trimmed.isEmpty
              ? null
              : <String, dynamic>{'name': trimmed},
        )
        .timeout(timeout);
    if (response.session != null) {
      await ensureProfileBestEffort();
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

  Future<void> signOut() async {
    await _client.auth.signOut();
    // After, not before: leaving is what matters, and a Google account left
    // remembered only means the next "Continue with Google" skips the chooser.
    await _providers().forget();
  }

  /// This app's own keys on the shared profile.
  ///
  /// `run_ai_consent` is the runner's answer about the coach's use of their
  /// data, and `run_intro_seen` is [hasMetCoach]. The name is not here: it is
  /// the profile's, and Lift reads it.
  static const List<String> _runKeys = <String>['run_ai_consent', _metCoachKey];

  /// Removes [_runKeys] from the profile, when this app's data has been
  /// deleted and the login kept for Lift.
  ///
  /// **The server's sweep does not reach auth metadata.** It erases the `run`
  /// schema and leaves the login alone, so without this a runner who deleted
  /// their account and later came back through the same login would find an
  /// answer about the coach still on file, and would skip the introduction --
  /// and its permission asks -- as though their account had never gone.
  ///
  /// Needs the session, so it runs before signing out. Bounded like every
  /// other call on the auth path.
  Future<void> clearRunMetadata() async {
    await _client.auth
        .updateUser(
          UserAttributes(
            data: <String, dynamic>{for (final key in _runKeys) key: null},
          ),
        )
        .timeout(timeout);
  }

  /// Ensures a row in the shared `public.profiles` table for the signed-in
  /// user — the shared identity across the MGKCodes fitness apps.
  Future<void> ensureProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client
        .schema('core')
        .from('profiles')
        .upsert({'id': user.id, 'email': user.email})
        .timeout(timeout);
  }

  /// [ensureProfile] with its failure absorbed — the only shape the sign-in and
  /// sign-up paths may use it in.
  ///
  /// **An account that exists is not a failure, whatever happened next.**
  /// [ensureProfile] is a second write, to a different schema, after gotrue has
  /// already created the account and issued the session; a connection that dies
  /// between the two is enough to fail it on its own. Awaited into the result,
  /// that threw straight past [signUp]'s `return true` and out to the screen,
  /// which told the runner their sign-up had gone wrong. It had not — and
  /// because `onAuthenticated` never fired, the gate they signed up from never
  /// dismissed either, so the obvious response was to fill the form in again
  /// and be told "User already registered". A dead end reached by doing
  /// everything right, and the one the field test walked into in row E5.
  ///
  /// **The row is not abandoned by swallowing this.** `HomeShell.initState`
  /// calls [ensureProfile] on every launch precisely to cover a session it did
  /// not create, so the repair costs nothing and happens on its own — often
  /// within the same second, since a sign-in from the signed-out flow builds
  /// that shell immediately afterwards. Refusing to authenticate until the row
  /// lands would not have helped: a device that could not write it a moment ago
  /// cannot write it now, and the profile is not what the runner asked for.
  Future<void> ensureProfileBestEffort() async {
    try {
      await ensureProfile();
    } catch (_) {
      // Deliberately silent. The next launch writes it; see above.
    }
  }
}
