import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../../auth/domain/account.dart';
import '../../auth/presentation/sign_in_screen.dart';
import '../../coaching/domain/coach.dart';
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
import '../../photos/domain/progress_photo.dart';
import '../../photos/presentation/photos_surface.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../sync/domain/sync_status.dart';
import '../../stats/domain/session_history.dart';
import '../../tracking/domain/session.dart';
import '../../tracking/domain/session_recorder.dart';
import '../../tracking/domain/workout_library.dart';
import '../../tracking/presentation/track_controller.dart';
import '../../tracking/presentation/track_surface.dart';

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
    this.hasCoachNote = false,
    this.photos,
    this.photoSource,
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

class _LiftShellState extends State<LiftShell> {
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

  /// What is waiting to upload, and how the last attempt went. Held here so
  /// Settings opens with the count already known rather than flickering.
  SyncPending? _pending;
  SyncReport? _lastReport;
  bool _syncing = false;

  /// Who is signed in. Kept in step with the service rather than read on demand,
  /// so a session restored at launch or expiring mid-use both reach the UI.
  Account? _account;
  StreamSubscription<Account?>? _authSub;

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

  @override
  void initState() {
    super.initState();
    unawaited(_loadUnits());
    unawaited(_loadCoachPreference());
    unawaited(_refreshSession());
    unawaited(_refreshLog());
    unawaited(_refreshPending());
    unawaited(_refreshPlan());

    final auth = widget.auth;
    if (auth != null) {
      _account = auth.current;
      _authSub = auth.changes.listen((account) {
        if (!mounted) return;
        setState(() => _account = account);
        // Signing in is the moment there is somewhere to put the backlog.
        if (account != null) unawaited(_syncNow());
        // ...and the moment the account's units become readable. The load in
        // initState runs before Supabase has restored a session, so without
        // this the shared choice is only ever picked up on the launch *after*
        // signing in. Runs on sign-out too: the device value is then the only
        // answer, and it should be the one on screen.
        unawaited(_loadUnits());
      });
    }
  }

  @override
  void dispose() {
    unawaited(_authSub?.cancel());
    super.dispose();
  }

  Future<void> _openSignIn() async {
    final auth = widget.auth;
    if (auth == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) =>
            SignInScreen(auth: auth, pendingWorkouts: _pending?.workouts ?? 0),
      ),
    );
  }

  Future<void> _refreshPending() async {
    final sync = widget.sync;
    if (sync == null) return;
    final pending = await sync.pending();
    if (!mounted) return;
    setState(() => _pending = pending);
  }

  /// Runs a sync and reports the outcome.
  ///
  /// Nothing about this blocks logging. It is started from Settings, it can
  /// fail, and failing costs nothing — the local database still has everything
  /// and the rows stay pending.
  Future<void> _syncNow() async {
    final sync = widget.sync;
    if (sync == null || _syncing) return;
    setState(() => _syncing = true);
    final report = await sync.run();
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _lastReport = report;
    });
    await _refreshPending();
    await _refreshLog();
  }

  Future<void> _loadUnits() async {
    final store = widget.units;
    if (store == null) return;
    final loaded = await store.load();
    if (!mounted || loaded == _units) return;
    setState(() => _units = loaded);
  }

  Future<void> _refreshLog() async {
    final source = widget.history;
    if (source == null) return;
    final loaded = await source.all();
    if (!mounted) return;
    setState(() => _log = loaded);
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
              ).padding.copyWith(bottom: coach == null ? 0 : _coachMarkReserve),
            ),
            child: IndexedStack(
              index: _index,
              children: <Widget>[
                TrackSurface(
                  onOpenPlan: () => _go(_planTab),
                  openSession: _openSessionDetail,
                  log: _log,
                  onStartSession: widget.recorder == null ? null : _openSession,
                  plan: _plan,
                  today: widget.today,
                  unit: _units.mass,
                  onStartPlanned: widget.recorder == null
                      ? null
                      : _openPlannedSession,
                ),
                PlanSurface(
                  isEntitled: widget.isEntitled,
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
                  now: widget.today,
                  massUnit: _units.mass,
                  onOpenTrack: () => _go(_trackTab),
                  onOpenSettings: _openSettings,
                  onOpenPhotos: widget.photos == null ? null : _openPhotos,
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
              bottom: AppSpacing.lg,
              child: CoachButton(
                hasUnread: widget.hasCoachNote,
                onTap: _openCoach,
              ),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _go,
        destinations: const <NavigationDestination>[
          // "Track", not "Home". In Run the front page is a summary of the day;
          // here it is the thing you are actually doing in the gym, and the
          // label should say so.
          NavigationDestination(
            icon: Icon(Icons.fitness_center_outlined),
            selectedIcon: Icon(Icons.fitness_center),
            label: 'Track',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Plan',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
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
          pending: _pending,
          isSignedIn: _account != null,
          email: _account?.email,
          isSyncing: _syncing,
          lastReport: _lastReport,
          onSyncNow: widget.sync == null ? null : _syncNow,
          onSignIn: widget.auth == null ? null : _openSignIn,
          onSignOut: _account == null ? null : _signOut,
          coachMemory: widget.coachMemory,
          auth: widget.auth,
          deleter: widget.deleter,
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
    if (!widget.isEntitled) {
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
    await _refreshPending();
  }

  Future<void> _openPhotos() async {
    final library = widget.photos;
    if (library == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            PhotosSurface(library: library, source: widget.photoSource),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.failure.message)));
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

    await TrackController(recorder, library: widget.library).openPlanned(
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
      },
    );
    await _refreshSession();
    await _refreshLog();
  }

  Future<void> _openSession() async {
    final recorder = widget.recorder;
    if (recorder == null) return;
    await TrackController(recorder, library: widget.library).openSession(
      context,
      massUnit: _units.mass,
      planner: widget.planner,
      log: _log,
      onOpenCoach: widget.coach == null ? null : _openCoach,
      onDone: () {
        unawaited(_refreshSession());
        unawaited(_refreshLog());
      },
    );
    // Also on return, not only via onDone: backing out of the screen with the
    // session still open must leave Track offering to resume it.
    await _refreshSession();
    await _refreshLog();
  }
}
