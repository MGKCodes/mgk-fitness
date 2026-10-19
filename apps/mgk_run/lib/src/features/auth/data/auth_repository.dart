import 'package:flutter/foundation.dart';
import 'package:mgk_auth/mgk_auth.dart';
import 'package:mgk_auth/mgk_auth.dart' as account show accountIsNew;
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
  const AuthRepository({
    this.timeout = const Duration(seconds: 20),
    GoTrueClient Function()? auth,
    FunctionsClient Function()? functions,
  }) : _authOverride = auth,
       _functionsOverride = functions;

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

  /// The auth and functions clients to use in place of the app's, for a test
  /// that answers them from a fake server. Null in the app, which reads
  /// `Supabase.instance` on every call so that constructing this needs nothing
  /// initialised.
  final GoTrueClient Function()? _authOverride;
  final FunctionsClient Function()? _functionsOverride;

  SupabaseClient get _client => Supabase.instance.client;
  GoTrueClient get _auth => _authOverride?.call() ?? _client.auth;

  Session? get currentSession => _auth.currentSession;
  User? get currentUser => _auth.currentUser;

  /// Whether a user is currently signed in. The routing seam the app depends
  /// on, so widgets decide auth state without importing Supabase's [Session].
  bool get isSignedIn => currentSession != null;

  /// The signed-in user's email, or null when signed out. Exposed so widgets
  /// display identity without importing Supabase's [User] type.
  String? get currentEmail => currentUser?.email;

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
  Stream<AuthChange> authChanges() => _auth.onAuthStateChange
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

  /// The email path: the address first, then the step it leads to (ADR-0047).
  ///
  /// Made per call, as [_providers] is, and handed to the screen's
  /// `EmailSignInFlow`, which decides the steps. Kept behind this seam so a
  /// test and the preview can answer it without a server.
  ///
  /// **It replaces `signUp`, and the reset that never said whether it went.**
  /// The lookup tells the screen whether an address has an account before a
  /// password is typed, so a wrong password is called one and *Forgot your
  /// password?* says where the link went. The two-mode form, which had to keep
  /// that secret, kept it only on screen: the server's sign-up answer already
  /// gave it away to anybody holding the public key.
  EmailSignIn emailSignIn() => EmailSignIn(
    auth: _authOverride,
    functions: _functionsOverride,
    timeout: timeout,
  );

  /// Signs in with an address and a password, straight past the lookup.
  ///
  /// **Only the debug quick sign-in uses this**, for seeded accounts it already
  /// knows have a password. The screen's email path goes through
  /// [emailSignIn], which looks the address up first.
  Future<void> signIn({required String email, required String password}) async {
    await _auth
        .signInWithPassword(email: email, password: password)
        .timeout(timeout);
    await ensureProfileBestEffort();
  }

  /// What the coach calls this runner, or null where they never said.
  ///
  /// Read from the session rather than a table, so it is available offline and
  /// costs no round trip.
  ///
  /// **The account's name, `display_name`, since 1.0.2** (ADR-0047, "The name
  /// belongs to the account"). Run kept it under `name` until then, which
  /// Supabase overwrites with Google's profile on every Google sign-in, so a
  /// runner who chose "Sam" and later used Google would have been called
  /// whatever Google holds. [displayNameOf] takes `display_name` as the answer
  /// whenever the key is there, empty meaning cleared, and reads the old
  /// `name` only on an account that has never had one and that Google has
  /// never touched.
  String? get currentName => displayNameOf(currentUser);

  /// The first name Google gave this account, to start the coach's question
  /// filled in, or null for anything but a Google account.
  ///
  /// **Offered, never kept on its own.** The intro puts it in the field and the
  /// runner sends it, changes it or clears it; nothing writes it to the account
  /// unless they send it. Nobody has to use the name their provider holds.
  String? get googleFirstName => googleFirstNameOf(currentUser);

  /// Whether the account in hand was made by the sign-in that just happened.
  ///
  /// **Read from the account, for every way in** (ADR-0047, point 7), where it
  /// used to be guessed from which half of the form was showing. Apple and
  /// Google make an account or sign into one without saying which, and Apple's
  /// browser flow on Android finishes after its call has returned, so the
  /// screen could only ever say what the runner meant to do.
  ///
  /// It stays true until the account next signs in, which can be days: a
  /// session restored at launch is not a sign-in. `AuthGate` asks it only about
  /// a sign-in it watched happen, for that reason.
  bool get accountIsNew => account.accountIsNew(currentUser);

  /// Copies the name Run kept under `name` to `display_name`, once, where the
  /// account has no `display_name` yet. Fails quietly.
  ///
  /// **Before Google can take it.** [currentName] already reads the old key on
  /// an account with no Google identity, so nothing on screen changes. What
  /// changes is what happens next: the first time such an account signs in
  /// with Google, Supabase writes Google's profile over `name`, and from then
  /// on [displayNameOf] rightly ignores it. Copied now, the runner's own choice
  /// survives that. The old key is left where it is: Run 1.0.1 and earlier
  /// still read it, and they share the account.
  ///
  /// Once only because of what it checks: after one copy the account has a
  /// `display_name`, and this does nothing again. Best effort for the reason
  /// [ensureProfileBestEffort] gives: the next launch tries again.
  Future<void> keepNameBestEffort() async {
    try {
      // Inside the catch too: reading the session needs Supabase, and a
      // copy that cannot even look must still not throw at a caller that
      // fired it and moved on.
      final legacy = legacyNameToCopy(currentUser);
      if (legacy == null) return;
      await _auth
          .updateUser(UserAttributes(data: displayNameData(legacy)))
          .timeout(timeout);
    } catch (_) {
      // Deliberately silent; see above.
    }
  }

  /// The old `name` to copy to `display_name`, or null when there is nothing
  /// to copy: no account, a `display_name` key already (**empty included**, a
  /// name cleared on purpose, which must never be refilled from underneath),
  /// a Google identity (whose `name` is Google's), or no old name at all.
  @visibleForTesting
  static String? legacyNameToCopy(User? user) {
    if (hasDisplayNameKey(user)) return null;
    // With no display_name key, this is exactly the old name, and only where
    // Google has never written over it.
    return displayNameOf(user);
  }

  /// Whether this account signs in with Apple.
  ///
  /// **Apple has already been asked who this is, so the app may not ask
  /// again.** App Review rejected 1.0.0 under guideline 4 because the intro
  /// asked "What should I call you?" straight after Sign in with Apple: the
  /// rule is that a name or an email Apple's sheet could have supplied is never
  /// asked for afterwards. The sheet is asked for email only (O1, see
  /// `ProviderSignIn`), so an Apple account simply goes without a name unless
  /// the runner gives one in Settings, where nothing prompts for it.
  ///
  /// Either record answers, as [hasIdentity] says: `identities` is what the
  /// deletion's revocation reads, and `providers` is there on a session
  /// restored without them.
  bool get signedInWithApple => hasIdentity(currentUser, 'apple');

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
  /// Writes to auth metadata, so it travels with the account and needs no
  /// migration against the `public.profiles` table Liftio shares. Under
  /// `display_name` since 1.0.2, the account's name in both apps; the old
  /// `name` is left alone, because Google rewrites it and Run 1.0.1 and earlier
  /// still read it.
  ///
  /// An empty or whitespace-only name **clears** it, so "I would rather you
  /// did not use a name" is a reachable answer. Every reader already treats
  /// null as "say nothing" — [currentName] returns null for blank, and
  /// `CoachBrief.write` omits the mention entirely.
  ///
  /// **Cleared is written as empty, not removed** ([displayNameData], shared
  /// with Lift). The key staying is what says "no name, on purpose": with it
  /// gone, [displayNameOf] would fall back to the old `name` underneath, and
  /// [keepNameBestEffort] would copy that back, undoing the clear.
  Future<void> updateName(String? name) async {
    await _auth.updateUser(UserAttributes(data: displayNameData(name)));
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
  bool get hasMetCoach => currentUser?.userMetadata?[_metCoachKey] == true;

  /// Records that the conversation happened.
  Future<void> markCoachMet() async {
    await _auth.updateUser(
      UserAttributes(data: <String, dynamic>{_metCoachKey: true}),
    );
  }

  Future<void> signOut() async {
    await _auth.signOut();
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
    await _auth
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
    final user = currentUser;
    if (user == null) return;
    await _client
        .schema('core')
        .from('profiles')
        .upsert({'id': user.id, 'email': user.email})
        .timeout(timeout);
  }

  /// [ensureProfile] with its failure absorbed — the only shape the sign-in and
  /// sign-up paths may use it in. The email path's too: the sign-in screen
  /// calls it once the flow has a session.
  ///
  /// **An account that exists is not a failure, whatever happened next.**
  /// [ensureProfile] is a second write, to a different schema, after gotrue has
  /// already created the account and issued the session; a connection that dies
  /// between the two is enough to fail it on its own. Awaited into the result,
  /// that threw straight past the old `signUp`'s `return true` and out to the
  /// screen,
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
