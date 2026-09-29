import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../../auth/domain/account.dart';
import '../../auth/presentation/sign_in_screen.dart';
import '../../coaching/domain/coach.dart';
import '../../entitlement/domain/entitlement.dart';
import '../../purchases/domain/purchases.dart';
import '../../coaching/domain/coach_memory.dart';
import '../../coaching/presentation/coach_sheet.dart';
import '../../coaching/presentation/plan_surface.dart';
import '../../legal/domain/account_deleter.dart';
import '../../settings/domain/coach_preference.dart';
import '../../planning/domain/intake_flow.dart';
import '../../planning/domain/plan_intake.dart';
import '../../planning/domain/plan_builder.dart';
import '../../planning/domain/session_prescription.dart';
import '../../planning/domain/coach_planner.dart';
import '../../planning/domain/plan_template.dart';
import '../../planning/domain/standing_plan.dart';
import '../../planning/domain/standing_plan_store.dart';
import '../../planning/presentation/plan_intake_screen.dart';
import '../../profile/presentation/profile_surface.dart';
import '../../settings/domain/unit_preferences.dart';
import '../../photos/domain/photo_backup.dart';
import '../../photos/domain/progress_photo.dart';
import '../../photos/presentation/photos_surface.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../sync/domain/sync_status.dart';
import '../../sync/presentation/backup_messages.dart';
import '../../sync/presentation/backup_scheduler.dart';
import '../../stats/domain/session_history.dart';
import '../../stats/presentation/history_screen.dart';
import '../../tracking/domain/session.dart';
import '../../tracking/domain/session_recorder.dart';
import '../../tracking/domain/workout_library.dart';
import '../../tracking/presentation/active_session_screen.dart';
import '../../tracking/presentation/session_summary_screen.dart';
import '../../tracking/presentation/track_controller.dart';
import '../../tracking/presentation/track_surface.dart';
import '../../tracking/data/exercise_lookup.dart';
import '../../tracking/presentation/workout_library_screen.dart';

/// The authenticated app: Track / Plan / Profile, with the coach floating over
/// all three.
///
/// Deliberately the same shape as `mgk_run`'s `HomeShell`, because the two apps
/// are one product rather than two apps sharing a palette. Three surfaces, three
/// time horizons:
///
///   Track    now      — the session you are in, or the one you are about to do
///   Plan     ahead    — what the coach has you working toward (paid)
///   Profile  behind   — the log, progress photos, settings
///
/// **The coach is a mark at the shell, not a dock inside a tab** (Run's
/// ADR-0017). A dock can only exist on one screen, so the coach would be present
/// on a third of the app and absent from the rest. Floating it means the answer
/// to "can I ask about this?" is always yes, wherever you are.
///
/// Everything is injected. The real Drift + Supabase stack is wired only in
/// `main.dart`, so tests and previews pass fakes and this file stays free of
/// both.
class LiftShell extends StatefulWidget {
  const LiftShell({
    super.key,
    this.recorder,
    this.editorFor,
    this.library,
    this.units,
    this.history,
    this.coach,
    this.transcript,
    this.coachMemory,
    this.coachPreference,
    this.deleter,
    this.planner,
    this.plans,
    this.isEntitled = false,
    this.entitlements,
    this.purchases,
    this.hasCoachNote = false,
    this.photos,
    this.photoSource,
    this.photoBackup,
    this.sync,
    this.auth,
    this.initialTab = 0,
    this.today,
  });

  /// What the three surfaces should treat as today. Null is the wall clock,
  /// which is what the app wants and what every caller but one passes.
  ///
  /// The exception is the preview harness, and it is not a small one: all three
  /// surfaces already took a date for exactly this reason, and the shell was the
  /// one link in the chain that did not pass it on. That made every shell
  /// screenshot drift with the day it was taken — a plan that has something for
  /// today on Thursday and nothing on Saturday — so the harness rendered the
  /// surfaces bare to keep them still, and lost the nav bar and the coach mark
  /// doing it. One parameter buys back both.
  final DateTime? today;

  /// Owns a session while it is happening. **Null disables starting one**,
  /// which is the right behaviour for a build with no on-device database — the
  /// app still runs and the action reads as unavailable rather than erroring.
  final SessionRecorder? recorder;

  /// A recorder aimed at one finished session, for fixing it afterwards.
  /// **Null hides Edit** on a past session — a build with no database.
  final SessionRecorder Function(String workoutId)? editorFor;

  /// The lifter's saved workouts, which a session's empty state offers and a
  /// finished session can be added to. **Null hides both**, which is the right
  /// behaviour for a build with no on-device database — the same rule
  /// [recorder] follows, and for the same reason: the two are stored in the
  /// same three tables.
  final WorkoutLibrary? library;

  /// Where the lifter's chosen units come from. Null keeps them for the session
  /// at the defaults, which is what tests and previews want.
  final UnitPreferencesStore? units;

  /// The finished sessions Profile reports on. Null reads as an empty log,
  /// which is a real state (a new account) rather than an error.
  final SessionHistory? history;

  /// The conversation. **Null hides the mark entirely** rather than showing an
  /// inert one — a mark that cannot open anything is worse than no mark.
  final CoachService? coach;

  /// What was said before, so opening the coach resumes rather than restarts.
  /// Null is a build that can talk but not remember out loud — a preview, or a
  /// session with no server — and the screen falls back to its empty state.
  final CoachTranscript? transcript;

  /// What the coach remembers, for Settings to show and clear. Separate from
  /// [coach] because it needs neither the Edge Function nor an entitlement:
  /// somebody who has stopped paying should still be able to read what was
  /// stored about them and delete it.
  final CoachMemoryStore? coachMemory;

  /// Whether the lifter wants the coach at all, and where that is kept.
  ///
  /// Null hides the switch and leaves the coach on, which is what a build
  /// with no store wired up should do: the toggle is a consent control, and
  /// one that cannot persist an answer is worse than none.
  final CoachPreferenceStore? coachPreference;

  /// Erases the account. Null hides the deletion row — a build with no
  /// server cannot delete anything, and offering to would be a button that
  /// fails at the moment somebody most needs it to work.
  final AccountDeleter? deleter;

  /// Builds and adapts plans. Null hides the entry point rather than showing
  /// one that cannot work — the same rule every other optional dependency here
  /// follows.
  final CoachPlanner? planner;

  /// Where the block lives between sessions.
  final StandingPlanStore? plans;

  /// Whether this account has the paid tier for Lift.
  ///
  /// Read from `core.entitlements`, which is client-read-only - the server
  /// decides, and the edge function checks again before spending anything. This
  /// only decides what the app *shows*: Plan was hardcoded to the sales pitch,
  /// so somebody who had just paid still saw the offer.
  final bool isEntitled;

  /// Where the live answer comes from. **Null keeps [isEntitled] as given**,
  /// which is what the preview and the widget tests rely on — they state the
  /// tier they want to render rather than standing up a server to be told it.
  ///
  /// Non-null makes [isEntitled] the *starting* value and this the truth after
  /// the first resolve. Production passes one; before 2026-09-02 nothing did,
  /// which is why every account in production took the `false` default no
  /// matter what `core.entitlements` said about them.
  final EntitlementGate? entitlements;

  /// The store. **Null hides every purchase affordance**, which is the honest
  /// state for a build without one — both paywalls already say so out loud
  /// rather than showing a button that does nothing.
  ///
  /// Paired with [entitlements] rather than used alone: a purchase that cannot
  /// be reconciled against `core.entitlements` is a charge with nothing to show
  /// for it, so one without the other buys nothing.
  final Purchases? purchases;

  /// Whether the coach has an observation the lifter has not seen. Drives the
  /// unread dot only; the mark itself is always available when [onOpenCoach] is.
  final bool hasCoachNote;

  /// Where progress photos are stored. **Null hides the entry point** rather
  /// than opening an empty screen — a build with no on-device database has
  /// nowhere to put a photo.
  final PhotoLibrary? photos;

  /// The camera. Null leaves photos readable but not addable, which is the
  /// honest state in a preview.
  final PhotoSource? photoSource;

  /// Photos to the bucket and back. Null means this build cannot upload one,
  /// which is the state with no server — and the state the screen describes
  /// rather than hides.
  ///
  /// **Run separately from [sync], and only when entitled.** A photo is
  /// megabytes over a storage API and a session is a few text rows; folding
  /// them into one call would let a stalled image upload take the training
  /// backup down with it, which is the wrong thing to sacrifice.
  final PhotoBackup? photoBackup;

  /// Backup. **Null means this build has no server**, which Settings reports as
  /// "this device only" rather than hiding the section — somebody whose
  /// training exists in one place should be told so while the phone still
  /// exists.
  final BackupService? sync;

  /// Signing in and out. **Null means this build has no account system**, which
  /// Settings reports as "this device only". Nothing in the app requires it:
  /// tracking works signed out and always will.
  final AuthService? auth;

  /// Which surface to open on. Exists so a preview can address a tab directly —
  /// tapping Flutter's canvas from an automation harness is unreliable.
  final int initialTab;

  @override
  State<LiftShell> createState() => _LiftShellState();
}

class _LiftShellState extends State<LiftShell> with WidgetsBindingObserver {
  late int _index = widget.initialTab;

  /// By name rather than by literal, so re-ordering the bar cannot silently send
  /// someone to the wrong surface. Only the two that are navigated to *in code*
  /// need one — Profile is reachable from the bar alone, and a constant nothing
  /// references is just another thing to keep in step with the list.
  static const int _trackTab = 0;
  static const int _planTab = 1;

  /// Vertical room the floating mark occupies, handed to the surfaces through
  /// MediaQuery so their SafeArea absorbs it. Only applied when there is a mark.
  ///
  /// **Derived, not typed in.** It was 64 — the old 56px circle plus its gap —
  /// and stayed 64 when the mark changed size, which is how a reserve and the
  /// thing it reserves for drift apart. `kCoachMarkExtent` already includes the
  /// overhang of the unread dot, so this is that plus the inset the mark is
  /// positioned at, and it follows the mark from now on.
  static const double _coachMarkReserve = kCoachMarkExtent + AppSpacing.lg;

  /// Everything floating at the foot: the nav pill, the gap above it, and the
  /// mark when there is one.
  ///
  /// **The nav bar floats now** (ADR-0033), so the `Scaffold` no longer takes
  /// its height off the body and the reserve has to. Reserved here rather than
  /// at each surface for the reason the mark's own reserve gives: the mark is
  /// conditional, so three surfaces reserving it themselves left dead space
  /// above the bar whenever the coach was absent.
  ///
  /// Run does the opposite — it pads inside each scroll view — because its
  /// surfaces had already stopped absorbing a bottom inset. Two mechanisms for
  /// one problem, deliberately: each app's surfaces already handled insets one
  /// way, and changing that was the larger risk.
  double _floatingChromeReserve(bool hasCoach) =>
      kNavPillHeight + AppSpacing.md + (hasCoach ? _coachMarkReserve : 0);

  /// Held at the shell rather than on a surface, because Track logs in these
  /// units and Profile reports in them — one load, so the two cannot disagree.
  UnitPreferences _units = const UnitPreferences();

  /// Whether a session is already open, so Track can offer to resume rather
  /// than to start. Refreshed whenever a session ends.

  /// The open session itself, so Track can say what they were doing rather
  /// than only that something was open.
  Session? _openSessionDetail;

  /// The finished log, held at the shell because Profile reports on it and
  /// finishing a session on Track changes it.
  List<Session> _log = const <Session>[];

  /// The same log, for screens pushed above the shell — the history list —
  /// which a `setState` here does not reach.
  final ValueNotifier<List<Session>> _logFeed = ValueNotifier<List<Session>>(
    const <Session>[],
  );

  /// The lifter's saved workouts, for Track's row. Read at the shell so the
  /// row and the library screen it opens cannot disagree about what exists.
  List<SavedWorkout> _workouts = const <SavedWorkout>[];

  /// When backup runs, and where it stands — read by Track's pill, the
  /// summary, the library's rows and Settings, so no two can disagree. Null
  /// is a build with no server.
  BackupScheduler? _backup;

  /// Who is signed in. Kept in step with the service rather than read on demand,
  /// so a session restored at launch or expiring mid-use both reach the UI.
  Account? _account;
  StreamSubscription<Account?>? _authSub;

  /// Track's row follows the library, whichever screen changed it — the
  /// summary teaching a workout included. See [WorkoutLibrary.changes].
  StreamSubscription<void>? _librarySub;

  /// The live block, held at the shell because Track shows today's session and
  /// Plan shows the week — one load, so the two cannot disagree.
  StandingPlan? _plan;
  bool _buildingPlan = false;

  /// Whether the coach is switched on. Held here rather than in Settings
  /// because it governs the mark floating over every surface and whether
  /// Plan can build anything — both of which outlive the screen that
  /// flips it.
  ///
  /// Starts true and is corrected by the load. The window is a frame or two
  /// on a device that has already opted out, and it costs nothing: the mark
  /// being briefly present sends nothing, and every path that would send is
  /// behind a tap that cannot happen that fast.
  bool _useCoach = true;

  /// What the paid surfaces are rendered against. Starts at whatever was passed
  /// and is corrected by the first resolve, on the same reasoning [_useCoach]
  /// gives for starting optimistic: the window is a frame or two, and nothing
  /// behind the gate can be reached inside it.
  late bool _entitled = widget.isEntitled;

  /// What the store will sell, for the paywall to price itself from. Empty
  /// until the store answers, which the tier block renders as "not known yet"
  /// rather than as a guess.
  List<PurchaseOffer> _offers = const <PurchaseOffer>[];

  @override
  void initState() {
    super.initState();
    unawaited(_loadUnits());
    unawaited(_loadCoachPreference());
    unawaited(_refreshSession());
    unawaited(_refreshLog());
    unawaited(_refreshWorkouts());
    _librarySub = widget.library?.changes.listen((_) {
      unawaited(_refreshWorkouts());
      // A saved workout changed — saved, edited, taught at Finish, deleted.
      _backup?.checkpoint();
    });
    WidgetsBinding.instance.addObserver(this);
    final sync = widget.sync;
    if (sync != null) {
      _backup = BackupScheduler(run: _runBackup, pending: sync.pending);
      unawaited(_backup!.refresh());
      // Launch is a checkpoint: whatever a killed app left unsent goes now.
      _backup!.checkpoint();
    }
    unawaited(_refreshPlan());
    unawaited(_refreshEntitlement());
    unawaited(_loadOffers());

    final auth = widget.auth;
    if (auth != null) {
      _account = auth.current;
      _authSub = auth.changes.listen((account) {
        if (!mounted) return;
        setState(() => _account = account);
        // Signing in is the moment there is somewhere to put the backlog, and
        // signing out the moment backup has to say it has stopped.
        unawaited(_backup?.runNow());
        // ...and the moment the account's units become readable. The load in
        // initState runs before Supabase has restored a session, so without
        // this the shared choice is only ever picked up on the launch *after*
        // signing in. Runs on sign-out too: the device value is then the only
        // answer, and it should be the one on screen.
        unawaited(_loadUnits());
        // Entitlements are per account, so both directions matter. Signing in
        // is when the paid half can appear; signing out is when it must stop,
        // and must stop for the *device* rather than only for this frame.
        unawaited(_refreshEntitlement(signedOut: account == null));
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_authSub?.cancel());
    unawaited(_librarySub?.cancel());
    _backup?.dispose();
    _logFeed.dispose();
    super.dispose();
  }

  /// Back in the foreground is a checkpoint — and, with no connectivity
  /// listener in the app, one of the two ways a returned connection is found.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _backup?.checkpoint();
  }

  /// Resolves what the paid surfaces should show.
  ///
  /// No gate means the caller stated the answer — the preview and the widget
  /// tests — so this does nothing rather than overwriting them with a `false`
  /// obtained from a server neither of them has.
  Future<void> _refreshEntitlement({bool signedOut = false}) async {
    final gate = widget.entitlements;
    if (gate == null) return;
    if (signedOut) await gate.forget();
    final entitled = await gate.isEntitled();
    if (!mounted || entitled == _entitled) return;
    setState(() => _entitled = entitled);
  }

  /// Buying and restoring, or null when either half is missing.
  PurchaseFlow? get _flow {
    final store = widget.purchases;
    final gate = widget.entitlements;
    if (store == null || gate == null) return null;
    return PurchaseFlow(purchases: store, gate: gate);
  }

  Future<void> _loadOffers() async {
    final store = widget.purchases;
    if (store == null) return;
    final offers = await store.offers();
    if (!mounted || offers.isEmpty) return;
    setState(() => _offers = offers);
  }

  /// The primary button buys **Coach**, which is what it names.
  ///
  /// **Premium Coach is displayed and not purchasable**, which is a gap rather
  /// than a decision: the tier block renders a row nothing here can reach, and
  /// the paywall needs a way to choose before that is honest. Recorded in
  /// `docs/submission-week.md` rather than left in a comment nobody reads.
  Future<void> _startPurchase() async {
    final flow = _flow;
    if (flow == null) return;

    final offers = await flow.purchases.offers();
    PurchaseOffer? offer;
    for (final candidate in offers) {
      if (candidate.tier == EntitlementTier.paid) {
        offer = candidate;
        break;
      }
    }
    offer ??= offers.isEmpty ? null : offers.first;

    if (offer == null) {
      // Reached the store and it offered nothing. Almost always a
      // misconfiguration rather than a network failure, and saying "try again"
      // would send somebody round a loop that cannot end.
      _say('The store has nothing to sell right now. Nothing was charged.');
      return;
    }

    await _report(await flow.buy(offer));
  }

  Future<void> _restorePurchases() async {
    final flow = _flow;
    if (flow == null) return;
    await _report(await flow.restore(), restoring: true);
  }

  /// Says what happened, and makes the screen agree with it.
  Future<void> _report(PurchaseResult result, {bool restoring = false}) async {
    // Refreshed regardless of outcome: a restore that found nothing still
    // settles the screen onto the truth, and the gate is cheap.
    await _refreshEntitlement();
    if (!mounted) return;

    switch (result.status) {
      case PurchaseStatus.entitled:
        _say(restoring ? 'Your subscription is back.' : 'You are all set.');
      case PurchaseStatus.pending:
        // Charged, and the webhook has not landed. Neither "done" nor "failed"
        // is true, and saying either would be the wrong kind of wrong.
        _say(
          'Payment went through. It can take a moment to appear — '
          'reopen the app if it has not.',
        );
      case PurchaseStatus.nothingToRestore:
        _say('There is no subscription on this account to restore.');
      case PurchaseStatus.failed:
        _say(result.message ?? 'That did not go through.');
      case PurchaseStatus.cancelled:
        // Deliberately silent. Backing out of a store sheet is not an event
        // worth narrating, and a message would read as a failure.
        break;
    }
  }

  void _say(String message) {
    if (!mounted) return;
    AppToast.show(context, message);
  }

  Future<void> _openSignIn() async {
    final auth = widget.auth;
    if (auth == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => SignInScreen(
          auth: auth,
          pendingWorkouts: _backup?.status.value.pending.workouts ?? 0,
        ),
      ),
    );
  }

  /// One backup run, as the scheduler calls it.
  ///
  /// Nothing about this blocks logging: it runs at checkpoints, it can fail,
  /// and failing costs nothing — the local database still has everything and
  /// the rows stay pending.
  Future<SyncReport> _runBackup() async {
    final sync = widget.sync;
    if (sync == null) return const SyncReport.signedOut();
    final report = await sync.run();

    // Photos second, and only for an account that has them. The training log
    // is the half that cannot be re-derived from anywhere, so it goes first
    // and its result is the one reported — a photo upload that stalls must not
    // make a successful log backup look like a failure.
    final photos = widget.photoBackup;
    if (photos != null && _entitled && !report.isFailure) {
      await photos.run();
    }

    // What came down from another phone is written straight to the database,
    // past the library's own signal, so both lists are read again.
    if (report.pulled > 0 && mounted) {
      await _refreshLog();
      await _refreshWorkouts();
    }
    return report;
  }

  /// *Sync now*, pressed. The one failure that buzzes: somebody asked and is
  /// looking. A background failure never does.
  Future<void> _syncNow() async {
    final report = await _backup?.runNow();
    if (report != null && report.isFailure) unawaited(AppHaptics.problem());
  }

  /// What a backup message's action does, wherever the message is.
  void _onBackupAction(BackupAction action) {
    switch (action) {
      case BackupAction.retry:
        unawaited(_syncNow());
      case BackupAction.signIn:
        unawaited(_openSignIn());
      case BackupAction.review:
        unawaited(_openSettings());
      case BackupAction.none:
        break;
    }
  }

  /// For the session and summary screens, which sit on routes above this one.
  BackupHooks? get _backupHooks {
    final backup = _backup;
    if (backup == null) return null;
    return BackupHooks(
      status: backup.status,
      onRetry: () => unawaited(_syncNow()),
      onSignIn: widget.auth == null ? null : () => unawaited(_openSignIn()),
    );
  }

  Future<void> _loadUnits() async {
    final store = widget.units;
    if (store == null) return;
    final loaded = await store.load();
    if (!mounted || loaded == _units) return;
    setState(() => _units = loaded);
  }

  Future<void> _refreshWorkouts() async {
    final library = widget.library;
    if (library == null) return;
    final all = await library.all();
    if (!mounted) return;
    setState(() => _workouts = all);
  }

  Future<void> _refreshLog() async {
    final source = widget.history;
    if (source == null) return;
    final loaded = await source.all();
    if (!mounted) return;
    setState(() => _log = loaded);
    _logFeed.value = loaded;
  }

  Future<void> _refreshSession() async {
    final recorder = widget.recorder;
    if (recorder == null) return;
    final session = await recorder.current();
    if (!mounted) return;
    // The session itself, not only whether there is one: Track says what they
    // were doing, and a bare bool cannot. There was briefly both, assigned on
    // this line from the same value, which let Track branch on two things that
    // were always equal.
    setState(() => _openSessionDetail = session);
  }

  Future<void> _loadCoachPreference() async {
    final store = widget.coachPreference;
    if (store == null) return;
    final enabled = await store.load();
    if (!mounted) return;
    setState(() => _useCoach = enabled);
  }

  Future<void> _setUseCoach(bool enabled) async {
    // Applied immediately, not after the write — the same call the units
    // control makes, and more clearly right here: somebody turning the
    // coach off wants the mark gone now, not once a plugin has answered.
    setState(() => _useCoach = enabled);
    await widget.coachPreference?.save(enabled: enabled);
  }

  @override
  Widget build(BuildContext context) {
    // Off means absent, not inert. main.dart already makes this call when
    // there is no server — "the mark stays absent rather than inert" — and
    // an inert mark is a promise the app then refuses to keep.
    final coach = _useCoach ? widget.coach : null;
    return Scaffold(
      body: Stack(
        children: <Widget>[
          // The room the mark needs is reserved *here*, by the thing that knows
          // whether there is a mark. Each surface reserving it itself meant
          // dead space above the nav bar whenever the coach was absent — and
          // three places to remember to keep in step.
          MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: MediaQuery.of(
                context,
              ).padding.copyWith(bottom: _floatingChromeReserve(coach != null)),
            ),
            child: IndexedStack(
              index: _index,
              children: <Widget>[
                _withBackup(
                  (backup) => TrackSurface(
                    backup: backup,
                    onBackupAction: _onBackupAction,
                    onOpenPlan: () => _go(_planTab),
                    openSession: _openSessionDetail,
                    log: _log,
                    onStartSession: widget.recorder == null
                        ? null
                        : _openSession,
                    plan: _plan,
                    today: widget.today,
                    unit: _units.mass,
                    onStartPlanned: widget.recorder == null
                        ? null
                        : _openPlannedSession,
                    workouts: _workouts,
                    onStartWorkout: widget.recorder == null
                        ? null
                        : _openWorkout,
                    onOpenLibrary: widget.library == null ? null : _openLibrary,
                  ),
                ),
                PlanSurface(
                  isEntitled: _entitled,
                  onSubscribe: _flow == null ? null : _startPurchase,
                  onRestore: _flow == null ? null : _restorePurchases,
                  offers: _offers,
                  plan: _plan,
                  today: widget.today,
                  unit: _units.mass,
                  onBuildPlan: _canPlan ? _buildPlan : null,
                  // So the note under a disabled button names the real
                  // reason. Only when a planner exists: with no server
                  // the connection line is the true one.
                  coachIsOff: !_useCoach && widget.planner != null,
                  onOpenSession: widget.recorder == null
                      ? null
                      : _openPlannedSession,
                  // Adapting a WEEK no longer has a subject: a standing plan
                  // has no weeks. What the feature was for is real and moves to
                  // the post-session review, where the coach reads what
                  // happened and the lifter's own answer changes the next
                  // session. See docs/plan-model.md.
                ),
                ProfileSurface(
                  log: _log,
                  onOpenSession: _openPastSession,
                  onOpenHistory: _openHistory,
                  now: widget.today,
                  massUnit: _units.mass,
                  onOpenTrack: () => _go(_trackTab),
                  onOpenSettings: _openSettings,
                  // Shown whether or not the account is entitled. A lapsed
                  // lifter has to be able to reach photos they already took, and
                  // somebody who has never had it should meet the offer rather than
                  // a tab that is not there.
                  onOpenPhotos: widget.photos == null ? null : _openPhotos,
                ),
              ],
            ),
          ),
          // **Floating, not `Scaffold.bottomNavigationBar`** (ADR-0033), and
          // shared with Run rather than hand-written a second time — the two
          // apps kept separate copies of the same construct until this.
          Positioned(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            bottom: AppSpacing.lg + MediaQuery.paddingOf(context).bottom,
            child: FloatingNavBar(
              selectedIndex: _index,
              onSelected: _go,
              destinations: const <NavPillDestination>[
                // "Track", not "Home". In Run the front page is a summary of
                // the day; here it is the thing you are actually doing in the
                // gym, and the label should say so. The component takes its
                // destinations as data for exactly this reason.
                NavPillDestination(
                  icon: Icons.fitness_center_outlined,
                  selectedIcon: Icons.fitness_center,
                  label: 'Track',
                ),
                NavPillDestination(
                  icon: Icons.calendar_month_outlined,
                  selectedIcon: Icons.calendar_month,
                  label: 'Plan',
                ),
                NavPillDestination(
                  icon: Icons.person_outline,
                  selectedIcon: Icons.person,
                  label: 'Profile',
                ),
              ],
            ),
          ),

          // Over every surface, which is the entire point.
          //
          // Right-aligned and only as wide as its label, **not** stretched to
          // the margins. Full-width it sat directly under Track's "Start a
          // session" button as a second pill of the same size and weight, and
          // the eye could not tell which one was the point of the screen. The
          // coach is permanently available, not the thing you came here to do.
          if (coach != null)
            Positioned(
              right: AppSpacing.lg,
              // Above the nav pill (main's floating bar) rather than level with
              // it: the pill spans the margins, so the mark rides one step over.
              bottom:
                  AppSpacing.lg +
                  MediaQuery.paddingOf(context).bottom +
                  kNavPillHeight +
                  AppSpacing.md,
              child: CoachButton(
                hasUnread: widget.hasCoachNote,
                onTap: _openCoach,
              ),
            ),
        ],
      ),
    );
  }

  void _go(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  /// Opens Settings, applying unit changes as they happen rather than on close.
  ///
  /// The shell holds the units, so a change here reaches Track and Profile
  /// without either of them reloading — one source, so the two cannot disagree
  /// about what a lifter works in.
  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          initial: _units,
          store: widget.units,
          onChanged: (prefs) => setState(() => _units = prefs),
          backup: _backup?.status,
          isSignedIn: _account != null,
          email: _account?.email,
          onSyncNow: _backup == null ? null : _syncNow,
          onSignIn: widget.auth == null ? null : _openSignIn,
          onSignOut: _account == null ? null : _signOut,
          coachMemory: widget.coachMemory,
          auth: widget.auth,
          deleter: widget.deleter,
          onRestorePurchases: _flow == null ? null : _restorePurchases,
          useCoach: widget.coachPreference == null ? null : _useCoach,
          onUseCoachChanged: widget.coachPreference == null
              ? null
              : _setUseCoach,
        ),
      ),
    );
  }

  /// Opens the coach, or the thing that has to happen first.
  ///
  /// **Checked before the message, not after it.** Sending a question and
  /// getting "sign in" or "that is a paid feature" back means the lifter typed
  /// something for nothing, and the refusal arrives on a screen with no route
  /// to the thing that would fix it. The server still enforces both - this only
  /// stops a round trip that cannot succeed.
  Future<void> _openCoach() async {
    final coach = widget.coach;
    if (coach == null || !_useCoach) return;
    if (_account == null) {
      await _openSignIn();
      return;
    }
    if (!_entitled) {
      _go(_planTab);
      return;
    }
    // A sheet over the surface you were on, not a fourth destination pushed on
    // top of it. See CoachSheet for why the difference is more than presentation.
    await CoachSheet.show(context, coach: coach, transcript: widget.transcript);
  }

  Future<void> _signOut() async {
    // Local data is deliberately left alone. Signing out is "stop syncing",
    // not "erase my training" - and the rows are already backed up.
    await widget.auth?.signOut();
  }

  Future<void> _openPhotos() async {
    final library = widget.photos;
    if (library == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotosSurface(
          library: library,
          source: widget.photoSource,
          isEntitled: _entitled,
          onSubscribe: _flow == null ? null : _startPurchase,
          onRestore: _flow == null ? null : _restorePurchases,
        ),
      ),
    );
  }

  /// Whether a plan can be built at all: it takes a coach and somewhere to put
  /// the result, and both are optional in a preview or an offline build.
  /// Building a plan is an AI request like any other, so the switch reaches
  /// it too. Without this the coach could be off and Plan would still send
  /// the intake answers — including the injury notes — to OpenRouter, which
  /// is exactly what the switch promises it does not do.
  bool get _canPlan =>
      _useCoach &&
      widget.planner != null &&
      widget.plans != null &&
      !_buildingPlan;

  Future<void> _refreshPlan() async {
    final plans = widget.plans;
    if (plans == null) return;
    try {
      final plan = await plans.active();
      if (!mounted) return;
      setState(() => _plan = plan);
    } on PlanException {
      // A plan that will not load is not worth an error on the home screen.
      // Track and Plan both read a null plan as "no block", which is a state
      // they already handle, and the next refresh tries again.
    }
  }

  /// Intake, generation, review, accept. Four steps, and the lifter can stop
  /// after any of them.
  Future<void> _buildPlan() async {
    final planner = widget.planner;
    final plans = widget.plans;
    if (planner == null || plans == null) return;

    final intake = await Navigator.of(context).push<PlanIntake>(
      MaterialPageRoute<PlanIntake>(
        builder: (_) => PlanIntakeScreen(
          planner: planner,
          // The flow's own first question, rather than a second copy of it
          // written here. The hardcoded opener this replaces asked two things
          // at once and led with the goal — which is the field with the least
          // leverage over the block, and the flow orders by leverage on
          // purpose. See planning/domain/intake_flow.dart.
          opener: IntakeField.days.question,
        ),
      ),
    );
    if (intake == null || !mounted) return;

    setState(() => _buildingPlan = true);
    try {
      final equipment = Equipment.fromAnswer(intake.equipment ?? '');
      final built =
          await PlanBuilder(
            propose:
                ({
                  required PlanIntake intake,
                  required List<int> weekdays,
                  required List<String> catalogue,
                  List<String> violations = const <String>[],
                }) => planner.plan(
                  intake: intake,
                  weekdays: weekdays,
                  catalogue: catalogue,
                  violations: violations,
                ),
          ).build(
            id: 'plan-${DateTime.now().millisecondsSinceEpoch}',
            intake: intake,
            // What they said, or a sensible week if they declined. Days is the one
            // question the intake will not let somebody skip, so this is a
            // belt-and-braces default rather than a real case.
            weekdays: intake.availableWeekdays ?? const <int>[1, 2, 4, 5],
            catalogue: catalogueFor(equipment),
            equipment: equipment,
          );

      await plans.replace(built.plan);
      if (!mounted) return;

      // **No separate review screen.** Reviewing a block made sense when four
      // model calls produced twelve weeks nobody had seen. A standing plan is
      // one week, it carries the coach's own reason for its shape, and the plan
      // surface has "Change the split" on it — so landing there IS the review,
      // and an extra screen in between would be a gate on the thing they asked
      // for.
      setState(() {
        _plan = built.plan;
        _index = _planTab;
      });
    } on PlanException catch (e) {
      if (!mounted) return;
      AppToast.show(context, e.failure.message);
    } finally {
      if (mounted) setState(() => _buildingPlan = false);
    }
  }

  /// Starts a planned session, and records which workout it became.
  ///
  /// The link is written when the session FINISHES, not when it starts: a
  /// session opened and abandoned is not a session they did, and marking the
  /// plan complete on open would claim otherwise.
  /// Starts today's session from the plan.
  ///
  /// **Derived on the spot rather than looked up.** A standing plan has no
  /// session rows to open — [SessionPrescription] turns today's slots into
  /// movements, with the weight worked out from what this lifter has actually
  /// lifted and left blank where there is nothing to work it out from.
  Future<void> _openPlannedSession(String day) async {
    final recorder = widget.recorder;
    final plan = _plan;
    if (recorder == null || plan == null) return;

    final slots = plan.slots[day] ?? const <MovementSlot>[];
    if (slots.isEmpty) return;

    await TrackController(
      recorder,
      library: widget.library,
      backup: _backupHooks,
    ).openPlanned(
      context,
      day,
      SessionPrescription.forDay(slots),
      massUnit: _units.mass,
      planner: widget.planner,
      log: _log,
      // The summary the session ends on offers the conversation; the shell
      // still owns what opening the coach means, including both gates.
      onOpenCoach: widget.coach == null ? null : _openCoach,
      onDone: () {
        // Recording what the session did to each slot -- the top set and
        // whether it moved -- is the post-session review, and is the next
        // thing to build. Until then the plan does not learn from a workout,
        // which is a gap rather than a decision.
        unawaited(_refreshSession());
        unawaited(_refreshLog());
        _afterSession();
      },
    );
    await _refreshSession();
    await _refreshLog();
  }

  Future<void> _openSession() async {
    final recorder = widget.recorder;
    if (recorder == null) return;
    await TrackController(
      recorder,
      library: widget.library,
      backup: _backupHooks,
    ).openSession(
      context,
      massUnit: _units.mass,
      planner: widget.planner,
      log: _log,
      onOpenCoach: widget.coach == null ? null : _openCoach,
      onDone: () {
        unawaited(_refreshSession());
        unawaited(_refreshLog());
        _afterSession();
      },
    );
    // Also on return, not only via onDone: backing out of the screen with the
    // session still open must leave Track offering to resume it. **The session
    // only** — backing out changes no finished session, and the whole log was
    // reloaded twice per visit, once here and once in onDone.
    await _refreshSession();
  }

  /// Starts a session from a saved workout, every set laid out.
  Future<void> _openWorkout(SavedWorkout workout) async {
    final recorder = widget.recorder;
    if (recorder == null) return;
    await TrackController(
      recorder,
      library: widget.library,
      backup: _backupHooks,
    ).openWorkout(
      context,
      workout,
      massUnit: _units.mass,
      planner: widget.planner,
      log: _log,
      onOpenCoach: widget.coach == null ? null : _openCoach,
      onDone: () {
        unawaited(_refreshSession());
        unawaited(_refreshLog());
        _afterSession();
      },
    );
    // Not the workouts: this returns when Finish swaps the session for the
    // summary, before the summary teaches the workout. The row follows the
    // library's own `changes` instead.
    await _refreshSession();
  }

  /// The whole library, from Track's "See all".
  Future<void> _openLibrary() async {
    final library = widget.library;
    if (library == null) return;
    final chosen = await WorkoutLibraryScreen.open(
      context,
      library: library,
      lookup: ExerciseLookup(),
      log: _log,
      backup: _backup?.status,
      blockedReason: _openSessionDetail == null
          ? null
          : 'Finish or discard the session you have open first.',
    );
    if (!mounted) return;
    if (chosen != null) await _openWorkout(chosen);
  }

  /// Every session, grouped by week — following the log as it changes.
  Future<void> _openHistory() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ValueListenableBuilder<List<Session>>(
          valueListenable: _logFeed,
          builder: (context, log, _) => HistoryScreen(
            log: log,
            massUnit: _units.mass,
            now: widget.today,
            backup: _backup?.status,
            onOpen: _openPastSession,
          ),
        ),
      ),
    );
  }

  /// A session that happened, on the summary's layout, with Edit and Delete.
  Future<void> _openPastSession(Session session) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SessionSummaryScreen(
          session: session,
          massUnit: _units.mass,
          // What came before it, so its bests are the bests it set then.
          log: <Session>[
            for (final s in _log)
              if (s.startedAt.isBefore(session.startedAt)) s,
          ],
          offerSave: false,
          backup: _backupHooks,
          onEdit: widget.editorFor == null
              ? null
              : () => unawaited(_editPastSession(session)),
          onDelete: widget.history == null
              ? null
              : () => unawaited(_deletePastSession(session)),
        ),
      ),
    );
  }

  /// Fixes a past session with the session screen itself — the same rows,
  /// limits and input rules — then shows its page again, as it now is.
  Future<void> _editPastSession(Session session) async {
    final make = widget.editorFor;
    if (make == null) return;
    final editor = make(session.id);
    final current = await editor.current();
    if (current == null || !mounted) return;
    // In the page's place, so leaving the editor does not land on the page
    // as it was before the edit.
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ActiveSessionScreen(
          recorder: editor,
          session: current,
          editing: true,
          massUnit: _units.mass,
          planner: widget.planner,
          log: _log,
          onFinished: () {
            unawaited(_refreshLog());
            _afterSession();
          },
        ),
      ),
    );
    if (!mounted) return;
    await _refreshLog();
    if (!mounted) return;
    for (final s in _log) {
      if (s.id == session.id) {
        await _openPastSession(s);
        return;
      }
    }
  }

  /// Deletes a past session, softly, with Undo. It leaves the log and every
  /// total at once, and reaches the other devices as a tombstone.
  Future<void> _deletePastSession(Session session) async {
    final history = widget.history;
    if (history == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete ${session.name}?'),
        content: const Text(
          'It comes out of your log and every total. You can undo it for a '
          'few seconds.',
        ),
        actions: <Widget>[
          AppTextButton(
            label: 'Keep it',
            onPressed: () => Navigator.of(dialog).pop(false),
          ),
          AppTextButton(
            label: 'Delete',
            onPressed: () => Navigator.of(dialog).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await history.remove(session.id);
    if (!mounted) return;
    // Off the session's page, which no longer has a session.
    Navigator.of(context).pop();
    await _refreshLog();
    _afterSession();
    if (!mounted) return;
    AppToast.show(
      context,
      '${session.name} deleted.',
      actionLabel: 'Undo',
      onAction: () async {
        await history.restore(session.id);
        await _refreshLog();
        _afterSession();
      },
    );
  }

  /// A session finished or was thrown away. Finish is a checkpoint — backup
  /// runs once the summary is up, never while the session is being logged.
  void _afterSession() {
    final backup = _backup;
    if (backup == null) return;
    // Read at once, so the summary starts from "saved on this phone" with
    // this session counted as waiting rather than from a stale empty queue.
    unawaited(backup.refresh());
    backup.checkpoint();
  }

  /// Builds [child] with the live backup status, or with none.
  Widget _withBackup(Widget Function(BackupStatus? status) child) {
    final backup = _backup;
    if (backup == null) return child(null);
    return ValueListenableBuilder<BackupStatus>(
      valueListenable: backup.status,
      builder: (context, status, _) => child(status),
    );
  }
}
