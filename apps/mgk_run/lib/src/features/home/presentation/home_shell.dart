import 'dart:async';

import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/sign_in_screen.dart';
import '../../coaching/data/adaptation_service.dart';
import '../../coaching/data/coach_client.dart';
import '../../coaching/data/coach_memory_repository.dart';
import '../../coaching/data/coach_memory_store.dart';
import '../../coaching/domain/coach_memory.dart';
import '../../coaching/data/plan_client.dart';
import '../../coaching/data/plan_repository.dart';
import '../../coaching/data/plan_service.dart';
import '../../coaching/data/plan_store.dart';
import '../../coaching/data/entitlement_repository.dart';
import '../../coaching/data/purchase_client.dart';

import '../../coaching/domain/coach_access.dart';
import '../../coaching/domain/coach_brief.dart';
import '../../coaching/domain/coach_note.dart';
import '../../coaching/domain/plan_shape.dart';
import '../../coaching/domain/race_day.dart';
import '../../coaching/domain/readiness.dart';
import '../../coaching/domain/training_history.dart';
import '../../coaching/domain/week_progress.dart';
import '../../coaching/domain/goal_draft.dart';
import '../../coaching/domain/plan_history.dart';
import 'home_tab.dart';
import 'home_last_run.dart';
import '../../coaching/presentation/session_labels.dart';
import '../../coaching/domain/pace_model.dart';
import '../../coaching/domain/runner_profile.dart';
import '../../coaching/domain/stored_plan.dart';
import '../../coaching/domain/training_plan.dart';
import '../../coaching/domain/training_standing.dart';
import '../../profile/domain/runner_stats.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../settings/domain/unit_settings.dart';
import '../../coaching/presentation/adjust_reasons_sheet.dart';
import '../../coaching/presentation/chat_controller.dart';
import '../../coaching/presentation/coach_conversation.dart';
import '../../coaching/presentation/coach_reveal.dart';
import '../../coaching/presentation/chat_entry.dart';
import '../../coaching/presentation/coach_flow.dart';
import '../../coaching/presentation/coach_gate_sheet.dart';
import '../../coaching/presentation/plan_finish_screen.dart';
import '../../coaching/presentation/plan_screen.dart';
import '../../coaching/presentation/plan_block_screen.dart';
import '../../coaching/presentation/race_result_sheet.dart';
import '../../coaching/presentation/plan_calendar_screen.dart';
import '../../coaching/presentation/week_detail_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../recording/domain/run_recorder.dart';
import '../../recording/domain/run_summary.dart';
import '../../recording/presentation/recording_screen.dart';
import '../../history/domain/run_writer.dart';
import '../../history/domain/run_draft.dart';
import '../../settings/domain/backup_consent.dart';
import '../../settings/presentation/backup_consent_prompt.dart';
import '../../onboarding/domain/intro_store.dart';
import '../../history/presentation/run_form_screen.dart';
import '../../history/presentation/run_tile.dart' show shortRunDate;
import '../../settings/data/backup_eraser.dart';
import '../../recording/presentation/run_start_screen.dart';
import '../../recording/presentation/run_summary_screen.dart';

/// The authenticated app: Home / Coach / Profile tabs.
///
/// The recorder, history data, coach and plan storage are **injected** so the
/// real Drift + geolocator + Supabase stack lives only in the iOS build (see
/// lib/main.dart), while the preview and tests pass fakes. A null
/// [recorderFactory] disables recording; a null [historySource] yields an empty
/// training log; a null [planStore] keeps the plan in memory for the session.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    this.auth = const AuthRepository(),
    this.recorderFactory,
    this.historySource,
    this.coach,
    this.chatClient,
    this.planClient,
    this.planStore,
    this.planBackup,
    this.memoryStore,
    this.memoryMirror,
    this.unitSettings,
    this.runEditor,
    this.restore,
    this.consentStore,
    this.eraser,
    this.initialTab = 0,
    this.justSignedUp = false,
    this.access,
    this.entitlements,
    this.purchases,
    this.runnerName,
    this.introStore,
  });

  final AuthRepository auth;

  /// Creates a fresh recorder for a new run.
  final RunRecorder Function()? recorderFactory;

  /// Loads the runs shown in History.
  final Future<List<RunSummary>> Function()? historySource;

  /// Adds and corrects runs. Null hides both affordances, which is the right
  /// behaviour for a build with no on-device database rather than an error —
  /// the log still reads, it just cannot be written to.
  final RunWriter? runEditor;

  /// Pulls anything this device is missing before the first load, so a
  /// reinstalled phone paints its own data rather than an empty log.
  final DataRestore? restore;

  /// Where the backup answer lives. Null skips the prompt, which is what the
  /// preview harness and tests want.
  final BackupConsentStore? consentStore;

  /// Erases what is already on the server when backup is switched off.
  ///
  /// **Was declared on `SettingsScreen` and never passed.** The switch
  /// therefore stopped future uploads and deleted nothing, while the
  /// published privacy policy said withdrawal "deletes what is already
  /// there" -- a false statement about a UK GDPR right, on special-category
  /// data. Found by the build 12 field test, 2026-09-04.
  final BackupErasure? eraser;

  /// The coach for onboarding. Null hides the Plan tab's build-a-plan action
  /// (e.g. a build with no backend).
  final CoachClient? coach;

  /// The coach for the open conversation. Defaults to [coach] when the injected
  /// coach also speaks the chat surface — [CoachService] does, and so does the
  /// preview's fake, so one injected coach lights up both. Exists as its own
  /// parameter so a test can drive the conversation without also standing up an
  /// intake double.
  final CoachChatClient? chatClient;

  /// The plan client for week adaptation. Null hides the week's "Adjust" action.
  final PlanClient? planClient;

  /// Where the plan is persisted. The real app injects the on-device database
  /// ([DriftPlanStore]); null falls back to an in-memory store, which keeps the
  /// plan for the session but not across launches.
  final PlanStore? planStore;

  /// Optional off-device mirror of the plan. Best-effort only — the plan is
  /// owned by [planStore] (CLAUDE.md rule 1).
  final PlanBackup? planBackup;

  /// Where the coach's memory lives — the transcript and the rolling summary.
  /// The real app injects the on-device database; null falls back to memory for
  /// the session, which is what the preview and widget tests want.
  final CoachMemoryStore? memoryStore;

  /// Optional off-device mirror of that memory. Best-effort only, exactly like
  /// [planBackup]: the coach's memory is owned by the device.
  final CoachMemoryMirror? memoryMirror;

  /// Where the display unit is read and written. Null keeps it in memory for
  /// the session, which is what the preview and widget tests want.
  final UnitSettings? unitSettings;

  /// Which tab to open on. Exists so the preview harness can address a tab by
  /// URL — Playwright cannot reliably tap Flutter's canvas to switch tabs.
  /// The tier to draw with, when a caller wants to pin it.
  ///
  /// Left null in the app, where [entitlements] resolves it from
  /// `core.entitlements` on launch. Passed by tests and the plate board, which
  /// need a tier without a Supabase session behind them.
  final CoachAccess? access;

  /// Where the drawn tier comes from, and **not** where it is enforced — the
  /// Edge Function refuses an unentitled request regardless (ADR-0030). This
  /// exists so a runner is told the coach is part of the subscription instead
  /// of tapping into a sheet that then fails.
  ///
  /// Null falls back to [access], and then to [CoachAccess.free].
  final EntitlementRepository? entitlements;

  /// Presents and performs a purchase. Null in a build with no RevenueCat key,
  /// which leaves the coach gate a statement rather than a shop.
  ///
  /// Deliberately separate from [entitlements]: this one asks for money, that
  /// one asks the server what was bought, and only the second is ever believed
  /// ([ADR-0030](../../../../docs/decisions/0030-the-coach-is-the-paid-half.md)).
  final PurchaseClient? purchases;

  /// What the coach calls this runner.
  ///
  /// Passed in rather than read off [auth], because the name no longer
  /// necessarily lives on an account: the intro asks for it and the app does
  /// not make an account at all until one buys something, so for a new runner
  /// it lives in `IntroStore`. Null falls back to the profile, which is right
  /// for anybody signed in.
  final String? runnerName;

  /// Where that name is kept when there is no account to keep it on.
  ///
  /// Here so **Settings can change it**. The name row wrote to auth metadata
  /// and nowhere else, which meant that for the ordinary new runner - no
  /// account - it displayed nothing and saved nothing: the one thing the intro
  /// gathers was uneditable by exactly the people who had just given it.
  ///
  /// Null keeps the edit in memory for the session, which is what the preview
  /// harness and widget tests want.
  final IntroStore? introStore;

  final int initialTab;

  /// True when this shell was reached by **creating an account** rather than by
  /// signing back into one.
  ///
  /// It no longer sends anybody into the plan flow. A new runner lands on Home
  /// with a working run tracker, and a plan is something they go and ask for
  /// (ADR-0019). What this still decides is that there is nothing on the server
  /// worth restoring, because the account was made seconds ago.
  final bool justSignedUp;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  late int _index = widget.initialTab;

  /// What the coach calls this runner, live.
  ///
  /// Held in state rather than read straight off [HomeShell.runnerName]
  /// because Settings can now change it, and for a runner with no account
  /// that change fires no auth event — there is no session to emit one. The
  /// gate above would go on passing the name it read at launch, and the coach
  /// would keep using the one they had just corrected.
  late String? _runnerName = widget.runnerName ?? widget.auth.currentName;

  /// Where the name lives with no account. In memory when none is injected,
  /// which keeps an edit for the session rather than losing it outright.
  late final IntroStore _introStore =
      widget.introStore ?? InMemoryIntroStore(done: true);

  /// The Plan tab, by name rather than by literal — a re-order that moved it
  /// would otherwise silently send a runner to the wrong page. Profile has no
  /// constant any more: Home stopped linking to the log when its recent-runs
  /// list went, and the nav bar is the only way there now (ADR-0017).
  static const int _planTab = 1;

  /// Built once and held here, not in the tab, so switching tabs or rebuilding
  /// the shell never drops an in-flight write or re-creates the store.
  late final PlanRepository _plans = PlanRepository(
    store: widget.planStore ?? InMemoryPlanStore(),
    backup: widget.planBackup,
    // The same client the conversation uses. Null in a test or a persona, which
    // is the deterministic plan — correct, and not what the runner is paying
    // for (ADR-0003).
    generator: widget.planClient == null
        ? null
        : PlanService(client: widget.planClient!),
  );

  /// The coach's memory, built once here for the same reason [_plans] is: a
  /// repository re-created on rebuild would drop an in-flight append.
  late final CoachMemoryRepository _memory = CoachMemoryRepository(
    store: widget.memoryStore ?? InMemoryCoachMemoryStore(),
    mirror: widget.memoryMirror,
  );

  late final UnitSettings _unitSettings =
      widget.unitSettings ?? InMemoryUnitSettings();

  /// The unit every screen below displays in. Held here, at the one point above
  /// all three tabs, so changing it in Settings re-renders the whole app rather
  /// than only the screen that was open.
  UnitSystem _unit = UnitSystem.metric;

  /// What Home shows. Held on the shell because Home draws on both the plan and
  /// the run log, which no single tab owns.
  TodayView? _todayView;

  /// This week's sessions, for Home's ribbon. Loaded here rather than derived
  /// in the widget so the ribbon and today's card can never disagree.
  TrainingWeek? _thisWeek;

  /// The session the most recent run answered, or null.
  ///
  /// **Matched by the day the run happened on, and only inside the week the
  /// plan currently holds.** A run from three weeks ago is not read against
  /// this Tuesday just because it was also a Tuesday — that would compare an
  /// effort to a session it was never set, and quietly, which is worse than
  /// showing nothing. The shell holds this week and not the whole block, so
  /// the honest range is exactly one week and anything older matches nothing.
  ///
  /// Null on all of: no plan, no runs, a rest day, and a run older than the
  /// current week. Every one of those means the same thing to the card — there
  /// is no comparison to draw — so they are one answer rather than four.
  PlannedAgainst? get _againstLastRun {
    final run = _allRuns.firstOrNull;
    final week = _thisWeek;
    if (run == null || week == null) return null;
    final now = DateTime.now();
    if (run.startedAt.isBefore(mondayOf(now))) return null;
    final session = week.runOn(run.startedAt.weekday);
    if (session == null) return null;
    final profile = _planProfile;
    // Derived in Dart from the profile's time trial, and null without one —
    // `pacesFor` answers null for a profile that has never done one, and a
    // pace row is dropped rather than guessed at.
    final paces = profile == null ? null : pacesFor(profile);
    return PlannedAgainst(
      session: session,
      targetPace: paces == null ? null : paceFor(session.kind, paces),
    );
  }

  /// What became of each prescribed day this week, derived from the run log.
  /// Held here for the same reason [_thisWeek] is: the ribbon and today's card
  /// must be describing one load of the store.
  Map<int, DayOutcome> _outcomes = const <int, DayOutcome>{};

  /// What Home should raise about days that went by without a run, if anything.
  MissedPrompt? _missed;

  /// The long view: weekly distance, and whether they have been turning up.
  /// Folded here with everything else Home draws, so the charts and the day
  /// above them are always one reading of the log.
  List<WeekVolume> _volumes = const <WeekVolume>[];
  List<List<RunDay>> _consistency = const <List<RunDay>>[];
  WeekStanding? _standing;
  CoachNote? _note;

  /// Whether the runner has opened the coach since the note last changed. The
  /// dot is the only thing the mark can say, so it should only say it once.
  bool _coachSeen = false;

  /// Whether this observation has been *announced*. Separate from [_coachSeen]
  /// on purpose: the line plays once per observation, and the dot stays until
  /// the runner actually opens the conversation. Playing it again because they
  /// switched tabs is how a nice touch becomes the thing everyone disables.
  bool _noteDelivered = false;

  /// The open conversation, held at the shell rather than on a tab.
  ///
  /// It used to belong to the Plan tab, which was fine while the way in was a
  /// dock bolted to that tab. The mark floats over all three now, so the
  /// conversation cannot be the property of one of them — and the transcript
  /// was never the screen's anyway.
  ChatController? _chat;

  /// The whole log, not just the three Home shows. A run's note compares it
  /// against everything the runner has done, so a cached handful would call
  /// things records that are not.
  List<RunSummary> _allRuns = const <RunSummary>[];

  /// The profile behind the current plan, for the goal the Profile tab shows.
  /// Held here rather than read in the tab so the goal, the log and Home's
  /// today card are all describing the same load of the store.
  RunnerProfile? _planProfile;

  /// The plans behind the current one, oldest first and labelled. Held here for
  /// the same reason as [_planProfile]: one load of the store, so the Profile
  /// tab and the coach's brief cannot disagree about what the runner has done.
  List<LabelledPlan> _pastPlans = const <LabelledPlan>[];

  @override
  void initState() {
    super.initState();
    // Watched for the coach's session boundary, and only for that: a
    // conversation that has been left alone for longer than the window is over,
    // whether the app was killed in between or merely put down. See ADR-0025.
    WidgetsBinding.instance.addObserver(this);
    // Best-effort: ensure the shared profile row exists (covers a restored
    // session, not just a fresh sign-in).
    unawaited(widget.auth.ensureProfile());
    unawaited(_loadUnit());
    unawaited(_restoreThenLoad());

    unawaited(_resolveAccess());
    unawaited(_identifyForPurchases());
    // **Signing in does not rebuild this shell.** `_ensureAccount` and the
    // Settings row both push a route over a shell that stays mounted, and
    // `AuthGate` returns `_shell(auth)` from both branches at the same position
    // so Flutter reuses the element -- `initState` never runs again. Three
    // things depended on it and all three were wrong afterwards: the tier
    // stayed `free` for somebody who had just signed in as a subscriber (which
    // is why build 12 needed a relaunch before the coach appeared), RevenueCat
    // stayed on an anonymous id so a purchase could not be attributed, and the
    // restore never ran. Re-running them on the auth stream is what makes
    // signing in mid-session mean anything.
    //
    // **Reacted to by identity, not by event.** Seeded here so the
    // `initialSession` that arrives moments from now for the person already
    // signed in is recognised as the one `initState` has just handled, rather
    // than as news. Two *different* people signing in must both restore; the
    // same one arriving twice must not, and on build 13 it did -- repeatedly,
    // because a token refresh also announced itself as a change.
    _lastAuthUserId = widget.auth.currentUserId;
    _authWatch = widget.auth.authChanges().listen((change) {
      final String? id = widget.auth.currentUserId;
      switch (change) {
        case AuthChange.signedIn:
          if (id != null && id == _lastAuthUserId) return;
          _lastAuthUserId = id;
          unawaited(_refreshAccess());
          unawaited(_identifyForPurchases());
          // Signing in is the moment a restore becomes possible: before it
          // there is no user to attribute rows to, and the runner's history is
          // sitting on the server behind an id the app did not have.
          //
          // **Without asking.** Every mid-session sign-in arrives out of a flow
          // that has already settled consent -- the Home prompt asks and then
          // fetches the account, and the Settings switch writes the answer
          // itself. Asking again here puts a second dialog on top of the first
          // and steals the answer to it, which is what happened the moment this
          // listener was added: the prompt's grant was still unwritten, so
          // `needsAsking` was true and the runner met the same question twice.
          unawaited(_restoreThenLoad(askConsent: false));
        case AuthChange.signedOut:
          _lastAuthUserId = null;
          // Drops to free. Nothing to restore and nobody to identify.
          unawaited(_refreshAccess());
        case AuthChange.userUpdated:
          // A rename. The gate above re-reads the name; nothing else moves.
          break;
      }
    });

    final client = _chatClient;
    if (client != null) {
      _chat = ChatController(
        client: client,
        brief: _writeCoachBrief,
        onAdaptRequest: _proposeFromChat,
        onApplyRevision: _applyRevision,
        onLogRunRequest: _proposeRunFromChat,
        onEditRunRequest: _proposeEditFromChat,
        onSetGoalRequest: _proposeGoalFromChat,
        onApplyRun: _applyRun,
        onApplyGoal: _applyGoal,
        memory: _memory,
        summariser: _summariser,
      );
      // Picks a conversation back up only if it is still open — within the
      // session window. A launch after longer than that opens on nothing, and
      // what was said is under Previous conversations rather than in front of
      // the model as though it were this morning.
      unawaited(_chat!.restore());
    }
  }

  @override
  void didUpdateWidget(HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The gate above re-reads the name whenever auth changes, so a rename that
    // *did* travel through an account arrives this way. Adopted only when it
    // actually changed, so a rebuild for any other reason cannot undo an edit
    // this shell is holding for a runner who has no account to carry it.
    if (widget.runnerName != oldWidget.runnerName) {
      _runnerName = widget.runnerName ?? widget.auth.currentName;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Resumed only. The gap is what decides, not the fact of having been away:
    // a runner who checks a notification and comes straight back keeps their
    // conversation, and one who comes back after the school run does not.
    if (state != AppLifecycleState.resumed) return;
    unawaited(_chat?.endStaleConversation() ?? Future<bool>.value(false));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_authWatch?.cancel());
    super.dispose();
  }

  /// The edit-run seam, when the injected coach can do it.
  CoachEditRunClient? get _editRunClient {
    final coach = widget.coach;
    return coach is CoachEditRunClient ? coach as CoachEditRunClient : null;
  }

  /// The log-run seam, when the injected coach can do it. Null in a build that
  /// ships chat without it, and the intent is then ignored rather than
  /// half-honoured — the coach would otherwise acknowledge a run and nothing
  /// would appear.
  CoachLogRunClient? get _logRunClient {
    final coach = widget.coach;
    return coach is CoachLogRunClient ? coach as CoachLogRunClient : null;
  }

  /// The set-goal seam, when the injected coach can do it. Null in a build that
  /// ships chat without it — the safe half to be missing, since honouring the
  /// intent supersedes a plan.
  CoachSetGoalClient? get _setGoalClient {
    final coach = widget.coach;
    return coach is CoachSetGoalClient ? coach as CoachSetGoalClient : null;
  }

  /// The chat seam, explicit if one was injected and otherwise the coach itself.
  CoachChatClient? get _chatClient {
    final explicit = widget.chatClient;
    if (explicit != null) return explicit;
    final coach = widget.coach;
    // Cast rather than promotion: Dart only promotes to a subtype of the
    // declared type, and these two seams are siblings rather than parent and
    // child — which is the whole point of keeping them apart.
    return coach is CoachChatClient ? coach as CoachChatClient : null;
  }

  /// Everything the coach knows about this runner, as prose (`CoachBrief`).
  ///
  /// Written per turn from storage rather than from this widget's fields: a run
  /// recorded on the Home tab a minute ago must be in the next answer, and the
  /// stored plan is the one on disk rather than the one this screen last drew.
  ///
  /// [message] is what the runner has just asked, and it is here for one
  /// reason: the on-demand tier of the coach's memory is a *search*, and a
  /// search needs a query. `recall` has existed since the memory was built and
  /// nothing called it — this is the call.
  ///
  /// Never throws. A brief is context, and losing it should cost the coach some
  /// detail, not cost the runner their question.
  Future<String> _writeCoachBrief(String message) async {
    List<RunSummary> runs;
    try {
      runs = <RunSummary>[
        ...await widget.historySource?.call() ?? const <RunSummary>[],
      ];
    } catch (_) {
      runs = <RunSummary>[];
    }
    runs.sort((a, b) => b.startedAt.compareTo(a.startedAt));

    StoredPlan? plan;
    try {
      plan = await _plans.load();
    } on PlanStoreException {
      plan = null;
    }

    // The rolling summary is the tier that is *always* loaded: the things no
    // schema holds — what they are anxious about, the knee that complains on
    // hills, the route they will not run in the dark. Read locally, so a brief
    // never waits on a network.
    CoachSummary? remembered;
    try {
      remembered = await _memory.summary();
    } catch (_) {
      remembered = null; // A brief is context, not a precondition.
    }

    // The on-demand tier: past turns that match what is being asked, rather
    // than a whole past transcript riding along. Which is the difference
    // between the coach knowing the runner has mentioned a sore calf before and
    // the coach reading last Tuesday as though it were this morning — the
    // failure that produced "you ran 10 km in 60 minutes yesterday" about a run
    // logged a week earlier.
    //
    // The current conversation is excluded because it is already the history
    // the coach is sent; the filtering rules are in `recollectionsFrom`.
    List<CoachTurn> recalled;
    try {
      recalled = recollectionsFrom(
        await _memory.recall(message),
        exceptConversation: _chat?.conversationId,
      );
    } catch (_) {
      recalled = const <CoachTurn>[];
    }

    return CoachBrief.write(
      recentRuns: runs,
      plan: plan,
      profile: plan?.profile,
      recalled: recalled,
      // Read off the session every turn rather than cached: it costs nothing,
      // and a name that arrived on a later device should not wait for a
      // restart to be used.
      name: widget.auth.currentName,
      rollingSummary: remembered?.text,
      // What they have tried before. Local, cheap, and the thing the coach was
      // most obviously missing: every plan was still on disk and it read every
      // runner as a beginner.
      history: await _plans.history(),
      unit: _unit,
    ).text;
  }

  /// A change the runner asked for in conversation, routed into the **existing**
  /// adaptation path: propose, validate against the relaxed adaptation rules,
  /// show the diff, apply only on approval.
  ///
  /// The chat's whole job here is to carry the sentence over. Nothing about the
  /// plan is decided by the model or by this method — the validator disposes
  /// (CLAUDE.md rule 2), and the runner has the last word after that.
  /// A change the runner asked for in conversation → a **validated** revision,
  /// handed back to the dock to offer inside the conversation.
  ///
  /// This used to throw a modal sheet over the screen. A runner who asked for a
  /// change in a sentence had to leave the conversation to agree to it, and the
  /// transcript kept no record of what they agreed — so next week, when they
  /// wondered why Sunday moved, there was nothing to look at. It proposes only:
  /// nothing reaches disk until [_applyRevision].
  Future<ChatProposal?> _proposeFromChat(String request) async {
    if (!mounted) return null;
    final plan = await _loadedPlan();
    final client = widget.planClient;
    if (plan == null || client == null) return null;

    final slot = plan.weekOn(DateTime.now());
    final TrainingWeek week;
    try {
      week = await _plans.weekFor(plan, slot);
    } on PlanStoreException {
      return null;
    }

    // **What has already happened this week, so the revision refits rather
    // than reshuffles.** Without this the adaptation is handed a prescription
    // and a sentence and nothing else, so it rearranges seven days as though
    // none of them had been lived — which is what the build 12 field test
    // meant by "it just reshuffles the week generically". A run that happened
    // on a rest day was invisible to it, and a session already completed could
    // be moved out from under the runner who ran it.
    //
    // `since` is decided here rather than inside the service because this is
    // where the week-1 rule lives: a plan's first week is anchored to
    // `mondayOf(now)`, so its earlier days predate the plan itself and cannot
    // have been missed. A second opinion about that in the service would be a
    // second place for it to be wrong.
    final now = DateTime.now();
    final proposal = await AdaptationService(client: client).propose(
      week: week,
      slot: slot,
      profile: plan.profile,
      request: request,
      soFar: weekAsRun(
        week: week,
        weekStart: plan.dateFor(weekIndex: slot.index, weekday: 1, on: now),
        now: now,
        runs: _allRuns,
        since: slot.index == 1 ? now : plan.startDate,
      ),
    );
    if (proposal == null) return null;
    return ChatProposal(week: proposal.week, changes: proposal.changes);
  }

  /// Bends this week from a situation the runner **picked** rather than typed.
  ///
  /// Plans that will not move are the loudest complaint in this category, and
  /// Runio could already move them — [AdaptationService] proposes, the
  /// validator disposes, the runner approves. It was only ever reachable by
  /// writing a paragraph at the coach, which is the last thing someone does
  /// when they are ill or sore. This is the same path with the sentence
  /// pre-written; nothing reaches disk until the diff has been approved
  /// (CLAUDE.md rule 2).
  Future<void> _adjustThisWeek() async {
    final request = await AdjustReasonsSheet.show(context);
    if (request == null || !mounted) return;
    // Into the **conversation**, not a modal. The first version of this opened
    // `WeekAdjustSheet` — the sheet the codebase had already moved away from,
    // because a runner who asked for a change in a sentence had to leave the
    // conversation to agree to it and the transcript kept no record of what
    // they agreed. These reasons are pre-written sentences, so they belong in
    // the same place a typed one does (ADR-0017).
    _askCoach(request);
  }

  /// The end of a block: what they ran, and the plan closing behind it.
  ///
  /// **The order matters and it is the runner's order, not the database's.**
  /// They are asked what happened, the answer is written, and only then are
  /// they shown the finish — so the screen that says the plan is over is
  /// standing on a plan that is already over on disk. Doing it the other way
  /// round would put a celebration in front of a write that might still fail.
  ///
  /// Backing out of the sheet changes nothing at all. The card keeps asking,
  /// which is the point of it asking for [kRaceGraceDays] rather than once.
  Future<void> _closeRace() async {
    final race = _todayView?.race;
    if (race == null) return;
    final plan = await _loadedPlan();
    if (plan == null || !mounted) return;

    // What the log says, so the sheet opens with the answer already in it
    // rather than with an empty form (ADR-0017 — completion is observed).
    final observed = raceResultFor(plan, _allRuns);
    final answer = await RaceResultSheet.show(
      context,
      race: race,
      observed: observed,
      unit: _unit,
    );
    if (answer == null || !mounted) return;

    try {
      await _plans.finish(plan, closure: answer.closure, raceTime: answer.time);
    } on PlanStoreException {
      // The plan could not be closed, so nothing is shown as though it had
      // been. The card is still there and still asking, which is a better
      // outcome than a finish screen over a plan that is still active.
      return;
    }

    // Rebuilt from the answer rather than from the log, so the screen shows the
    // figure the runner confirmed — including a chip time their phone
    // disagrees with, which is exactly the case the override exists for.
    final result = answer.closure == PlanClosure.raced
        ? raceResultFor(plan, _allRuns, entered: answer.time)
        : null;

    await _refreshHome();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (routeContext) => PlanFinishScreen(
          plan: plan,
          runs: _allRuns,
          result: result,
          unit: _unit,
          onAskCoach: _chat == null
              ? null
              : (opener) {
                  Navigator.of(routeContext).pop();
                  _askCoach(opener);
                },
          onDone: () => Navigator.of(routeContext).pop(),
        ),
      ),
    );
  }

  /// A run the runner mentioned in conversation → a **validated** draft, handed
  /// back to the dock to confirm inside the conversation.
  ///
  /// Proposes only. Nothing reaches the log until [_applyRun], because "I did
  /// 5k in 26 minutes" is a sentence a model can mishear, and a run nobody
  /// agreed to is indistinguishable from one they reported once it is stored.
  ///
  /// An invalid draft returns null rather than a proposal the runner cannot
  /// accept. The dock then says it could not make a run out of that, which is
  /// the honest answer — a card offering to save 5 km in two minutes would ask
  /// them to approve something the editor is about to refuse anyway.
  Future<RunProposal?> _proposeRunFromChat(String request) async {
    final coach = _logRunClient;
    if (!mounted || coach == null) return null;

    final draft = await coach.logRun(request);
    if (draft == null || !draft.isValid(DateTime.now())) return null;
    return RunProposal(draft: draft);
  }

  /// A correction the runner mentioned → a **validated** run to confirm.
  ///
  /// The resolution step is the safety here, and it is deliberately strict.
  /// The coach identifies a run by the day it happened on, because it is never
  /// told a run's id. Two runs on one day is ordinary — an easy morning run and
  /// an evening parkrun — so [soleRunOn] refuses unless exactly one matches. A
  /// wrong choice would rewrite a run the runner never mentioned, and the log
  /// would look entirely normal afterwards.
  Future<RunProposal?> _proposeEditFromChat(String request) async {
    final coach = _editRunClient;
    final editor = widget.runEditor;
    if (!mounted || coach == null || editor == null) return null;

    final correction = await coach.editRun(request);
    if (correction == null || !correction.isUsable) return null;

    final run = soleRunOn<RunSummary>(
      _allRuns,
      correction.on!,
      startedAt: (r) => r.startedAt,
    );
    final id = run?.id;
    if (id == null) return null;

    final existing = await editor.draftOf(id);
    if (existing == null) return null;

    final changed = correction.changes.onto(existing);
    if (!changed.isValid(DateTime.now())) return null;
    return RunProposal(draft: changed, runId: id);
  }

  /// A new target the runner named → a **validated** goal to confirm.
  ///
  /// Starts from what they already have rather than from nothing, because most
  /// of these are partial: "move it to 12 April" restates a date and no
  /// distance, and a draft built from the sentence alone would silently drop
  /// the marathon it was moving.
  ///
  /// Refuses three ways, and all three are the runner being protected from a
  /// misheard sentence rather than from themselves: nothing usable read, a
  /// target the validator rejects, or a target identical to the one they have.
  /// The last matters because accepting it would throw away a block in exchange
  /// for the same block.
  Future<GoalProposal?> _proposeGoalFromChat(String request) async {
    final coach = _setGoalClient;
    if (!mounted || coach == null) return null;

    final change = await coach.setGoal(request);
    if (change == null || !change.isSomething) return null;

    // No plan means no profile, and a profile is not something to invent: how
    // many days they can run and what they are already doing are answers only
    // they have. A runner with a goal and no plan wants onboarding, which is
    // the "Build a plan" the Coach tab is already showing them.
    final plan = await _loadedPlan();
    if (plan == null) return null;

    final draft = change.onto(GoalDraft.from(plan.profile));
    if (!draft.isValid(DateTime.now())) return null;
    // Same target as they already have. Offering it would ask them to approve
    // throwing away a block in exchange for the block they are already in.
    if (!draft.changes(plan.profile)) return null;

    return GoalProposal(
      draft: draft,
      shape: draft.shape,
      // Weeks already worked through, not weeks in the block: what they are
      // losing is the training behind them, and the ones ahead were never
      // theirs yet.
      supersedes: plan
          .weekIndexOn(DateTime.now())
          .clamp(0, plan.skeleton.weeks.length),
    );
  }

  /// Rebuilds the plan around a target the runner confirmed.
  ///
  /// Through [PlanRepository.create], the same path onboarding uses, so a plan
  /// made in conversation is the same object as a plan made on the way in — it
  /// supersedes the old one, validates its skeleton before storing, and pushes
  /// to the backup. A second route would be a second set of rules about what a
  /// legal plan is, and the one that got skipped would be this one.
  Future<bool> _applyGoal(GoalProposal proposal) async {
    try {
      final plan = await _loadedPlan();
      if (plan == null) return false;

      // Everything about the runner except the target survives: their days,
      // their volume, their time trial. They changed a race, not themselves.
      await _plans.create(proposal.draft.onto(plan.profile));
      if (!mounted) return true;
      await _refreshHome();
      return true;
    } catch (_) {
      // Returning false rather than swallowing quietly: the card stays on
      // "that didn't save" and the runner can try again. A goal card that said
      // "done" over an unchanged plan would leave them training for the wrong
      // race with nothing on screen disagreeing.
      return false;
    }
  }

  /// Writes a run the runner confirmed in the conversation.
  ///
  /// Straight through [RunEditor], the same path the manual form uses, so the
  /// rules about what a legal run is live in one place and the conversational
  /// route cannot drift from the typed one (ADR-0016).
  Future<bool> _applyRun(RunProposal proposal) async {
    final editor = widget.runEditor;
    if (editor == null) return false;
    try {
      final id = proposal.runId;
      // The same two paths the manual form uses, chosen by whether there is
      // already a run to correct.
      if (id == null) {
        await editor.add(proposal.draft);
      } else {
        await editor.edit(id, proposal.draft);
      }
    } on Object {
      // Includes RunDraftInvalid, which should be unreachable — the draft was
      // checked before it was offered — but a refusal here must read as "not
      // saved" rather than as an exception through the dock.
      return false;
    }
    await _refreshHome();
    return true;
  }

  /// Writes a revision the runner approved in the conversation.
  Future<bool> _applyRevision(TrainingWeek week) async {
    final plan = await _loadedPlan();
    if (plan == null) return false;
    try {
      await _plans.saveRevisedWeek(plan, week);
    } on PlanStoreException {
      return false;
    }
    await _refreshHome();
    return true;
  }

  /// The stored plan, or null when there is not one. Read rather than cached:
  /// the shell does not draw the plan, so holding a copy would only give it
  /// something to go stale.
  Future<StoredPlan?> _loadedPlan() async {
    try {
      return await _plans.load();
    } on PlanStoreException {
      return null;
    }
  }

  /// Opens the conversation on a question already written — the hand-off from
  /// a session brief.
  ///
  /// **The gate lives here rather than at the call sites**, and that is the
  /// whole fix. Six callers reached this method -- adjust-this-week, the
  /// plan-finish screen, ask-about-this-run from both a finished run and the
  /// log, the missed-session card, the Plan tab and Profile -- and not one of
  /// them checked the tier. Only the coach mark and `HomeTab.onOpenCoach` went
  /// through [_openCoach], which does. So a free runner had six doors into the
  /// paid half, every one of which opened onto an Edge Function 402 rendered as
  /// *"The coach hit a problem. Please try again."* -- the exact sentence
  /// `CoachGateSheet` was built to delete (ADR-0030).
  ///
  /// Found by the build 12 field test, where it looked like the coach briefly
  /// unlocking after a purchase that had in fact granted nothing.
  void _askCoach(String opener) {
    if (!_access.isSubscribed) {
      _showCoachGate();
      return;
    }
    final chat = _chat;
    if (chat == null) return;
    unawaited(
      CoachConversationSheet.show(
        context,
        controller: chat,
        unit: _unit,
        suggestions: _coachSuggestions,
      ),
    );
    unawaited(chat.ask(opener));
    setState(() => _coachSeen = true);
  }

  /// Opens the conversation, wherever the runner is.
  ///
  /// At the shell rather than on the Plan tab, which is the whole point of a
  /// floating mark: the dock it replaces could only ever exist on one screen,
  /// so the coach was present on a third of the app and absent from the rest.
  /// Watches for a sign-in that happens while this shell stays mounted.
  StreamSubscription<AuthChange>? _authWatch;

  /// Who the last handled `signedIn` was for, so gotrue re-announcing the
  /// session already in hand is not mistaken for somebody arriving.
  String? _lastAuthUserId;

  /// The tier the UI draws with. Starts at whatever a caller pinned, or free,
  /// and is replaced once `core.entitlements` has been read.
  late CoachAccess _access = widget.access ?? CoachAccess.free;

  Future<void> _resolveAccess() async {
    final source = widget.entitlements;
    // A pinned tier wins: tests and the plate board set one deliberately, and
    // a network read would race them.
    if (source == null || widget.access != null) return;
    final resolved = await source.access();
    if (mounted && resolved != _access) setState(() => _access = resolved);
  }

  /// Tells RevenueCat who this is, so a purchase can be attributed.
  ///
  /// **The webhook keys `core.entitlements` on this id** and refuses an
  /// `RCAnonymousID:` rather than writing a row to nobody, so a purchase made
  /// before this call is money taken for an entitlement that never arrives.
  /// Fired whenever there is both a session and an SDK, which is why it sits
  /// beside the access read rather than in `main()`: the app opens with no
  /// account at all (ADR-0019), and the id only exists once one does.
  Future<void> _identifyForPurchases() async {
    final client = widget.purchases;
    final id = widget.auth.currentUser?.id;
    if (client == null || id == null) return;
    await client.identify(id);
  }

  /// The door a free runner meets, from either end.
  ///
  /// Two callers: the coach mark, and the locked last-run card's offer. One
  /// method because they should open the same thing -- a second surface saying
  /// the same words differently is how two paywalls drift apart.
  void _showCoachGate() {
    unawaited(
      CoachGateSheet.show(
        context,
        purchases: widget.purchases,
        entitlements: widget.entitlements,
        // Re-read rather than assume. The screen only reports success once the
        // server agrees, so by here the row exists -- but the shell's own copy
        // of the tier is what the tabs draw from, and it is still stale.
        onUnlocked: _refreshAccess,
      ),
    );
  }

  /// Re-reads the tier after a purchase, ignoring the pin guard in
  /// [_resolveAccess]: a test that pinned `free` and then bought something
  /// wants to see the result.
  Future<void> _refreshAccess() async {
    final source = widget.entitlements;
    if (source == null) return;
    final resolved = await source.access();
    if (mounted && resolved != _access) setState(() => _access = resolved);
  }

  void _openCoach() {
    // The door, before the sheet. The Edge Function refuses an unentitled
    // request anyway (ADR-0030), so this is not the gate — it is the difference
    // between being told what something costs and watching the app fail.
    if (!_access.isSubscribed) {
      _showCoachGate();
      return;
    }
    final chat = _chat;
    if (chat == null) return;
    final note = _note;
    unawaited(
      CoachConversationSheet.show(
        context,
        controller: chat,
        unit: _unit,
        suggestions: _coachSuggestions,
        // The coach's latest observation becomes its first turn, so the
        // conversation starts on something rather than on nothing.
        opener: note == null ? null : '${note.headline} ${note.detail}',
      ),
    );
    setState(() => _coachSeen = true);
  }

  /// Openers for an empty conversation — the questions a runner has whether or
  /// not they have a plan.
  static const List<String> _coachSuggestions = <String>[
    'How has my training been going?',
    'What could I run a half marathon in?',
    'My calf is sore — can we move today’s run?',
  ];

  /// The summarise seam, found the same way as the chat seam: [CoachService]
  /// implements all three surfaces, so one injected coach lights up talking,
  /// planning and remembering.
  CoachSummariseClient? get _summariser {
    final chat = _chatClient;
    if (chat is CoachSummariseClient) return chat as CoachSummariseClient;
    final coach = widget.coach;
    return coach is CoachSummariseClient ? coach as CoachSummariseClient : null;
  }

  /// Metric until the stored choice arrives. [UnitSettings.load] is contractually
  /// non-throwing and prefers its local cache, so this is a fast no-op on every
  /// launch after the first.
  Future<void> _loadUnit() async {
    final unit = await _unitSettings.load();
    if (!mounted || unit == _unit) return;
    setState(() => _unit = unit);
  }

  /// The restore in flight, or null.
  ///
  /// **Structural rather than a boolean**, for two reasons.
  /// [_doRestoreThenLoad] has four exit paths and a flag has to be cleared on
  /// every one of them; and a second caller arriving mid-pull should *join* the
  /// one already running rather than be turned away, which a flag cannot
  /// express. Both matter on the launch path, where `initState` and the auth
  /// stream's `initialSession` reach here within a frame of each other -- which
  /// is how build 13 stacked two restores, and behind them two consent dialogs.
  Future<void>? _restoring;

  /// Loads what the phone already holds, then restores what it does not.
  ///
  /// **The local read comes first, and that is the whole of the ordering.** It
  /// used to come last, behind a modal consent dialog and an unbounded network
  /// call -- so a runner with three years of running on the device watched a
  /// blank Profile until the server answered, or indefinitely if it did not.
  /// Everything Profile and the log draw comes from `_allRuns`, which only
  /// [_refreshHome] fills.
  ///
  /// The argument this replaces was that painting twice "reads as data
  /// appearing out of nowhere". That is true, and it is now only *reached* when
  /// data genuinely did appear out of nowhere -- the second paint happens only
  /// if the restore actually inserted something.
  Future<void> _restoreThenLoad({bool askConsent = true}) =>
      _restoring ??= _doRestoreThenLoad(
        askConsent: askConsent,
      ).whenComplete(() => _restoring = null);

  Future<void> _doRestoreThenLoad({bool askConsent = true}) async {
    // The phone's own log, before anything that can block or fail.
    await _refreshHome();

    // **A new account takes a different road.** There is nothing on the server
    // to restore — the account was made seconds ago — so the restore is a
    // no-op, and the consent question in front of it would be asking permission
    // to store data that does not exist yet, before the runner had seen the app
    // do anything at all (ADR-0012).
    //
    // Nothing else happens here any more. This used to push the plan flow the
    // instant the shell mounted, which made a plan the price of finishing
    // sign-up; a plan is now something a runner goes and asks for (ADR-0019).
    //
    // The consent question is therefore not asked in this session at all. It is
    // picked up by the ordinary path on the next launch, by which time they
    // have had a chance to use the app — which is what ADR-0012 wanted in the
    // first place. Asking it after the first *recorded run* would be better
    // still, and wants a hook that does not exist yet.
    if (widget.justSignedUp) return;

    // Ask before anything moves. The answer decides whether there is a restore
    // at all, and asking afterwards would mean either uploading first and
    // apologising, or restoring nothing and never saying why.
    if (askConsent) await _askConsentIfNeeded();

    final RestoreResult? restored = await widget.restore?.restoreAll();
    // **Said out loud, because a silent restore and a broken one look the
    // same.** The result used to be discarded here, and every step inside
    // `SupabaseRestore` swallows its own throws by design -- so a runner
    // signing in on a new phone watched an empty log and had no way to tell
    // whether their history was gone, still coming, or never asked for.
    if (mounted && restored != null && restored.restoredAnything) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_restoredSentence(restored))));
    }
    // Then send anything this phone has that the backup does not: runs from
    // before the mirror existed, or from a spell with backup switched off.
    // After the restore, so a run that just came down is not pushed back up.
    //
    // Not awaited — it pushes every run the server is missing, and Home has no
    // business waiting behind that — but not fired into the void either. This
    // was a bare `unawaited(...)` with no error handler, which makes a throwing
    // backfill an unhandled async error: nobody catches it, nothing records it,
    // and the runner is simply never backed up (ADR-0023 counts this as one of
    // the three ways a run used to go missing in silence).
    //
    // Nothing is reported from here because there is nothing left to report by
    // the time it arrives: every push inside a backfill goes through
    // `ReportedRunBackup`, so the failure is already written down where
    // Settings will show it. This handler exists so the error ends somewhere
    // deliberate rather than in the zone.
    unawaited(
      widget.runEditor?.backfill().catchError((Object _) => 0) ??
          Future<int>.value(0),
    );
    // Only when something arrived. `_refreshHome` already ran at the top, so
    // this is the repaint for new data rather than the first paint.
    if (mounted && (restored?.restoredAnything ?? false)) await _refreshHome();
  }

  /// What came back, in the runner's terms rather than a row count per table.
  String _restoredSentence(RestoreResult r) {
    final parts = <String>[
      if (r.runs > 0) '${r.runs} ${r.runs == 1 ? 'run' : 'runs'}',
      if (r.plans > 0) 'your plan',
      if (r.turns > 0) 'what the coach remembers',
    ];
    if (parts.length == 1) return 'Restored ${parts.first}.';
    final last = parts.removeLast();
    return 'Restored ${parts.join(', ')} and $last.';
  }

  Future<void> _askConsentIfNeeded() async {
    final store = widget.consentStore;
    if (store == null) return;
    // **Not asked of somebody with no account.** The question is what to do
    // with data leaving the phone, and there is nowhere for it to go until
    // there is a user to attribute it to — so a yes here could not be honoured,
    // and honouring it would mean raising a sign-up at launch, which is the
    // exact intrusion the app stopped making when it stopped requiring an
    // account. They are asked by [_offerBackupIfEarned] instead, once they have
    // something worth keeping.
    if (!widget.auth.isSignedIn) return;
    if (!(await store.read()).needsAsking) return;
    if (!mounted) return;
    final answer = await askBackupConsent(context);
    // A null answer cannot happen (the dialog is not dismissible), but writing
    // only a real answer keeps "unknown" meaning "still unasked" if it ever does.
    if (answer != null) await store.write(answer);
  }

  /// How many recorded runs it takes before backup is worth raising.
  ///
  /// **Two, not one.** A single run is a trial — somebody walking to the end of
  /// the road to see whether the app works — and interrupting it with a
  /// consent dialog and a sign-up is how a tracker becomes a thing that wants
  /// something. By the second run there is a log rather than an experiment, and
  /// the sentence "lose the phone and they go with it" is about something the
  /// runner would actually mind.
  static const int _runsBeforeOfferingBackup = 2;

  /// Whether this session has already put the question, so a *later* refresh
  /// does not raise it twice.
  ///
  /// The consent store is the durable record — a decline writes [BackupConsent
  /// .declined] and `needsAsking` is false forever after — but the store is
  /// written *after* the dialog closes, and [_refreshHome] can easily run again
  /// while it is still open.
  ///
  /// **This flag cannot answer for two refreshes that overlap**, and that is
  /// what [_offering] is for. It is set after `await store.read()`, so two
  /// callers arriving together both passed it and both opened a dialog — E1 on
  /// the build 13 sheet, and a guaranteed pair once the launch path was running
  /// the restore twice.
  bool _offeredBackup = false;

  /// The offer in flight, or null. The concurrent half of the guard; see
  /// [_offeredBackup] for the sequential half, and [_restoring] for why this
  /// shape rather than another boolean.
  Future<void>? _offering;

  /// Offers backup to a runner with no account, once they have a log worth
  /// keeping.
  ///
  /// **This is the prompt the account removal left owing.** Taking the sign-in
  /// wall down meant a runner could record for months with everything on one
  /// phone and never be told, because the only consent question in the app was
  /// asked at launch to people who were already signed in. The obligation did
  /// not go away with the wall: ADR-0012 wants the question asked once the
  /// runner has seen the app do something, and this is that moment.
  ///
  /// Saying yes raises sign-up, because the mirror needs somebody to attribute
  /// rows to. Abandoning that sign-up writes nothing at all: the question stays
  /// unanswered and is put again next time, which is right — they did not
  /// decline, they were interrupted.
  Future<void> _offerBackupIfEarned() => _offering ??= _doOfferBackupIfEarned()
      .whenComplete(() => _offering = null);

  Future<void> _doOfferBackupIfEarned() async {
    final store = widget.consentStore;
    if (store == null || _offeredBackup) return;
    if (widget.auth.isSignedIn) return;
    if (_allRuns.length < _runsBeforeOfferingBackup) return;
    if (!(await store.read()).needsAsking) return;
    if (!mounted) return;

    _offeredBackup = true;
    final answer = await askKeepRunsSafe(context, runs: _allRuns.length);
    if (answer == null || !mounted) return;

    if (answer == BackupConsent.declined) {
      // Recorded as the decision it is. "Not now" was never offered, so this
      // is a considered no and must not come back next launch.
      await store.write(answer);
      return;
    }

    // Consent given; now the account it needs. Nothing is written unless one
    // arrives — consent to store data somewhere that does not exist is not a
    // state worth persisting, and it would leave the switch reading On.
    //
    // **The question stays open, but it is not asked again in this session.**
    // Backing out of the sign-up used to clear [_offeredBackup], which meant
    // every later [_refreshHome] raised the dialog afresh — after a finished
    // run, after an edit, after a unit change — and `_refreshHome` runs often.
    // That is E1 on the build 13 sheet: "the backup prompt appears repeatedly".
    // Writing nothing to the store is what keeps it open for next launch, which
    // is the whole of ADR-0012's "they did not decline, they were interrupted";
    // re-raising it thirty seconds later is badgering, not asking.
    if (!await _ensureAccount()) return;
    await store.write(BackupConsent.granted);
    // The account is new, so this phone's runs are the only copy there is.
    // Pushing them is the thing the runner just said yes to; without it the
    // switch reads On and the server stays empty until the next launch.
    if (!mounted) return;
    unawaited(
      widget.runEditor?.backfill().catchError((Object _) => 0) ??
          Future<int>.value(0),
    );
    setState(() {});
  }

  /// Reloads everything Home displays. Called on open, and whenever the plan
  /// changes underneath it, so the front page is never stale.
  Future<void> _refreshHome() async {
    // The log and the plan are independent sources, so a failure in one must
    // not cost the other. This read used to be bare, and a throwing history
    // source took the whole refresh with it from `initState` — Home kept its
    // empty state and never got as far as loading the plan, so a runner with a
    // block on disk was shown "No plan yet" because their *run log* was
    // offline. Home without its recent runs is still Home.
    List<RunSummary> runs;
    try {
      runs = await widget.historySource?.call() ?? const <RunSummary>[];
    } catch (_) {
      runs = const <RunSummary>[];
    }
    final sorted = <RunSummary>[...runs]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

    TodayView? today;
    TrainingWeek? thisWeek;
    RunnerProfile? planProfile;
    var outcomes = const <int, DayOutcome>{};
    MissedPrompt? missed;
    WeekStanding? standing;
    // One reading of the clock for everything derived from it, the same reason
    // [PlanRepository.today] takes one: a countdown and a week number that
    // disagree about the day are worse than either being absent.
    final now = DateTime.now();
    try {
      var plan = await _plans.load();
      // **The runner who never races.** A block whose race is long past and
      // which nobody ever closed out is closed here, from the log, before
      // anything is derived from it — otherwise Home would spend the rest of
      // the year counting down to a marathon that happened in April. Done on
      // the refresh rather than inside [PlanRepository.load] because a read
      // that writes is a read nobody can reason about, and half a dozen other
      // callers of `load` have no business closing anything.
      if (plan != null && await _plans.closeIfOverdue(plan, sorted) != null) {
        plan = null;
      }
      if (plan != null) {
        planProfile = plan.profile;
        today = await _plans.today(plan, unit: _unit);
        thisWeek = await _plans.weekFor(plan, today.slot);
        // Computed here rather than in the widget, like every other line that
        // depends on the plan's shape (ADR-0011). Home takes two strings.
        // What actually became of the week, read off the run log rather than
        // off anything the runner asserted by tapping (ADR-0017).
        final weekStart = plan.dateFor(
          weekIndex: today.slot.index,
          weekday: 1,
          on: now,
        );
        outcomes = weekOutcomes(
          week: thisWeek,
          weekStart: weekStart,
          now: now,
          runs: sorted,
          since: today.slot.index == 1 ? now : plan.startDate,
        );
        // **Nothing is chased about during race week.** A taper is deliberately
        // small and deliberately easy to skip, and the morning after a marathon
        // is the single worst moment in the product to open with "3 sessions
        // missed this week — Tuesday, Thursday, Saturday". It is technically
        // true, it is about a week that ended at the finish line, and it sits
        // directly under a card asking how the race went (ADR-0027).
        //
        // Gated on the race being in view rather than on the phase being a
        // taper: `race` is null for a horizon, a rhythm and a log, and for
        // every ordinary day of a block, so this suppresses exactly the ten
        // days either side of a date and nothing else.
        missed = today.race != null
            ? null
            : missedPromptFor(
                week: thisWeek,
                weekStart: weekStart,
                now: now,
                runs: sorted,
                unit: _unit,
                // **A plan cannot be behind on days that predate it**, and in
                // its first week we cannot tell which those are: `startDate` is
                // the *Monday week 1 aligns to*, not the day the runner
                // committed, so a plan built on a Thursday claims Monday and
                // then reports three days it was never asked about. Nothing is
                // stored that would tell us which; until a creation timestamp
                // exists, week 1 raises nothing.
                //
                // Under-reporting on purpose. A genuine week-1 miss waits until
                // week 2 to be mentioned, which is a far smaller wrong than a
                // brand-new plan opening with a list of failures.
                since: today.slot.index == 1 ? now : plan.startDate,
              );
        standing = weekStanding(
          week: thisWeek,
          weekStart: weekStart,
          now: now,
          runs: sorted,
        );
      }
    } on PlanStoreException {
      today = null; // Home still stands without a plan.
      thisWeek = null;
      planProfile = null; // As does Profile — a goal is optional there.
      outcomes = const <int, DayOutcome>{};
      missed = null;
      standing = null;
    }

    // Off the log alone, so they survive a plan that cannot be read — a runner
    // whose plan row is corrupt has still been running, and the charts are the
    // part of Home that can still say so.
    //
    // **Except for a plan that does not build.** A rhythm holds the same week
    // forever by design, so its volume chart is seven identical bars — noise
    // with a title on it. Resolved here rather than in the widget, like every
    // other shape question (ADR-0011): Home draws the chart it is given and
    // asks nothing.
    final progresses = planProfile == null || shapeOf(planProfile).progresses;
    final volumes = progresses
        ? weeklyVolumes(runs: sorted, now: now)
        : const <WeekVolume>[];
    final consistency = consistencyGrid(runs: sorted, now: now);
    // With no plan there is nothing prescribed to measure against, but the
    // distance is still true.
    standing ??= weekStanding(
      week: null,
      weekStart: mondayOf(now),
      now: now,
      runs: sorted,
    );
    // Read alongside the plan so the Profile tab and the coach's brief are
    // describing the same load. `history()` swallows a store failure itself, so
    // an unreadable old plan cannot take Home down with it.
    final history = await _plans.history();

    if (!mounted) return;
    setState(() {
      _allRuns = sorted;
      _note = CoachNote.forRuns(runs);
      _coachSeen = false;
      _noteDelivered = false;
      _todayView = today;
      _thisWeek = thisWeek;
      _planProfile = planProfile;
      _outcomes = outcomes;
      _missed = missed;
      _volumes = volumes;
      _consistency = consistency;
      _standing = standing;
      // Only the ones behind them; the active plan is the Coach tab's subject.
      _pastPlans = history.where((p) => !p.record.isActive).toList();
    });

    // After the frame, never before it: the coming week's sessions are written
    // by the model while the runner reads this one. Deliberately not awaited by
    // anything on screen — if it fails, or they are offline, the week is simply
    // still unwritten and whoever needs it next builds it in Dart.
    unawaited(_fillNextWeek());
    // Here rather than in `_restoreThenLoad`, so it sees the log as it stands
    // *now*: the moment worth asking at is the one just after a run is saved,
    // which refreshes Home without going near the launch path.
    unawaited(_offerBackupIfEarned());
  }

  /// Writes the coming week's sessions ahead of the runner reaching it.
  ///
  /// Runs on every load and costs nothing after the first: [PlanRepository
  /// .lookAhead] returns immediately once the week is on disk. That is what
  /// makes it safe to call from a refresh rather than from a scheduler.
  Future<void> _fillNextWeek() async {
    try {
      final plan = await _plans.load();
      if (plan == null) return;
      await _plans.lookAhead(plan);
    } on PlanStoreException {
      // Nothing to say: the runner did not ask for this and cannot see it.
    }
  }

  // No `_markToday` here any more. Completion is read off the run log, so the
  // shell has nothing to assert on the runner's behalf — `PlanRepository`
  // keeps `markToday`/`setStatusOn` for the explicit skip the coach records
  // for them, which is a thing the runner said rather than a button they
  // tapped (ADR-0017).

  // No `_currentWeekMeters` here any more. It read the week in progress off the
  // volume series for the in-run screen's THIS WEEK band; the band went, and a
  // getter computing an argument nothing takes is how a screen ends up with
  // dead parameters. Home's chart still folds the same series.

  /// Starts a run from Home. Recording is an action here, not a tab.
  /// Starts a run, with or without today's session attached.
  ///
  /// **The two are different runs and this is the seam.** A session start hands
  /// the recorder the prescription, so the in-run screen counts down what is
  /// left of it and the band judges the pace it asked for. A free start hands
  /// it nothing — deliberately, because a runner who chose not to do today's
  /// session should not spend the next half hour being measured against it, and
  /// a countdown to a distance nobody agreed to is worse than no countdown.
  void _startRun(BuildContext context, {bool withSession = true}) {
    final factory = widget.recorderFactory;
    if (factory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recording is unavailable here.')),
      );
      return;
    }
    // Read before the recorder exists, and kept for after it is gone: this is
    // how the finished run is found again. A run that ends from here on is the
    // run this screen recorded, and nothing else is — see
    // [RunDetailSource.runFinishedSince] for why it is not simply "the newest
    // run in the log".
    final openedAt = DateTime.now();
    final PlannedSession? session = withSession
        ? _thisWeek?.runOn(DateTime.now().weekday)
        : null;
    Navigator.of(context)
        .push<bool>(
          MaterialPageRoute<bool>(
            // **The clock no longer starts on the tap that opens the screen.**
            // It used to, so the first seconds of every run were spent putting
            // a phone away and were recorded as running — at whatever pace a
            // pocket happens to be. The count-in screen comes first now, and
            // `RecordingScreen` is pushed by it, replacing it so Back from a
            // run does not land on a Start button for the run still going.
            builder: (routeContext) => RunStartScreen(
              unit: _unit,
              plannedSession: session,
              onCancel: () => Navigator.of(routeContext).pop(false),
              // **Pushed and forwarded, not replaced.** `pushReplacement`
              // completes the *replaced* route's future the moment it happens,
              // so the `.then` below fired with null at the end of the
              // count-in and the summary screen never opened at all. The run's
              // own result is carried back out through this route instead.
              onStart: () async {
                final bool? finished = await Navigator.of(routeContext)
                    .push<bool>(
                      MaterialPageRoute<bool>(
                        // The recorder is built here rather than above, so it
                        // starts when the count-in ends rather than when the
                        // screen opened.
                        builder: (recordContext) =>
                            _recordingScreen(recordContext, session, factory()),
                      ),
                    );
                if (!routeContext.mounted) return;
                Navigator.of(routeContext).pop(finished ?? false);
              },
            ),
          ),
        )
        // A finished run changes the log, the note and possibly today's status.
        // Refreshed first either way, so the summary opens over a Home that
        // already knows about the run behind it.
        .then((finished) async {
          await _refreshHome();
          if (finished == true && mounted) await _showFinishedRun(openedAt);
        });
  }

  /// The in-run screen itself, built once the count-in has finished.
  ///
  /// A method rather than an inline builder because it is now constructed from
  /// a *different* route than the one Home pushed — the count-in screen
  /// replaces itself with this — and the arguments it needs are the same ones
  /// they always were.
  Widget _recordingScreen(
    BuildContext routeContext,
    PlannedSession? session,
    RunRecorder recorder,
  ) {
    final profile = _planProfile;
    return RecordingScreen(
      recorder: recorder,
      unit: _unit,
      // Today's prescribed run, so the in-run screen can show how far through
      // the coach's session they are. Null on a rest day, an unplanned day, or
      // with no plan at all — and then the block is simply absent rather than
      // an empty one.
      plannedSession: session,
      // The coach's numbers, so the screen can say whether the runner is inside
      // the band today's session asked for. Derived in Dart from the profile's
      // time trial and null without one, which the screen renders as no verdict
      // rather than a guessed one.
      paces: profile == null ? null : pacesFor(profile),
      // **Finished and discarded are not the same exit.** They both used to pop
      // with nothing, so the shell could not tell an hour of running from a
      // mistap on the close button — which is part of why finishing led
      // nowhere. The result says which happened.
      onFinish: () => Navigator.of(routeContext).pop(true),
      onCancel: () => Navigator.of(routeContext).pop(false),
    );
  }

  /// The run just recorded, on the screen built to receive it.
  ///
  /// **This is the whole of what Phase 1 was about.** `onFinish` popped, so an
  /// hour of effort ended with the display going away and the runner back on
  /// Home with nothing to look at — the first field test's own words for it
  /// were that the run "was recorded, displayed, and then disappeared".
  ///
  /// Read back out of the database rather than handed along in memory, which is
  /// deliberate and is the cheap end-to-end check ADR-0023 says the log stopped
  /// being: if the write path is broken, the completion screen is the first
  /// thing to say so, in front of the person who just ran.
  ///
  /// Silent when there is nothing to show. A recorder that never started —
  /// permission refused, location off — finishes without a run, and there is no
  /// summary to open for a run that did not happen.
  Future<void> _showFinishedRun(DateTime openedAt) async {
    final reads = _runDetails;
    RunSummary? run;
    if (reads != null) {
      try {
        run = await reads.runFinishedSince(openedAt);
      } catch (_) {
        run = null; // Handled below, along with "there was no run".
      }
    }
    // No detail source — a build with no editor, which is the preview and most
    // widget tests. The log has just been reloaded, so fall back to it, still
    // asking the same question: a run that started before this screen opened is
    // not the run that was recorded on it.
    run ??= _allRuns.where((r) => !r.startedAt.isBefore(openedAt)).firstOrNull;
    if (run == null || !mounted) return;
    await _openSummary(run, justFinished: true);
  }

  /// Takes a question from Profile to the coach.

  /// Opens one run's summary. Shared by Home's recent list and the Profile
  /// tab's log: both hand the whole log along, because the summary's note has
  /// to compare the run against everything to call it a record.
  void _openRun(RunSummary run) => unawaited(_openSummary(run));

  /// The summary screen, for a run from the log or a run just finished.
  ///
  /// One method for both, because it is one screen: the difference is
  /// [RunSummaryScreen.justFinished] and what there is to do afterwards.
  Future<void> _openSummary(RunSummary run, {bool justFinished = false}) async {
    // The trace, when it is not already loaded. A run opened from the log has
    // only ever been a summary — `fetchRuns` reads the columns and leaves the
    // thousands of trace rows alone, which is right for a list — so the map on
    // the screen below had nothing to draw. Loaded on the way in rather than
    // inside the screen, so the route is there in the first frame instead of
    // appearing under the reader a moment later.
    final full = run.hasRoute ? run : await _withTrace(run);
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (routeContext) => RunSummaryScreen(
          summary: full,
          unit: _unit,
          history: _allRuns,
          justFinished: justFinished,
          // What was asked for on the day, so the coach's note can say whether
          // this was the session. Only on the run just finished: an older run
          // needs the week it fell in, and only this week's is loaded.
          plannedSession: justFinished
              ? _thisWeek?.runOn(full.startedAt.weekday)
              : null,
          // Somewhere for it to go, which is the rule this button already had:
          // a summary opened from the log is dismissed with back, and its Done
          // was a dead control.
          onDone: justFinished ? () => Navigator.of(routeContext).pop() : null,
          // No id means nothing to edit: a summary built from a recording in
          // progress or from seeded demo data is not a row yet.
          onEdit: widget.runEditor == null || full.id == null
              ? null
              : () => _editRun(full),
          onAskCoach: _chat == null
              ? null
              : () => _askAboutRun(full, justFinished: justFinished),
        ),
      ),
    );
  }

  /// One run in full, or the summary unchanged when the trace cannot be had.
  ///
  /// Failure here costs a map and nothing else: every figure on the screen came
  /// from the row that is already loaded, so a summary without its route is a
  /// poorer screen rather than a broken one — the same call the log makes when
  /// it cannot read (`_refreshHome`), for the same reason.
  Future<RunSummary> _withTrace(RunSummary run) async {
    final reads = _runDetails;
    final id = run.id;
    if (reads == null || id == null) return run;
    try {
      return await reads.runDetail(id) ?? run;
    } catch (_) {
      return run;
    }
  }

  /// Reading one run in full, when the injected editor can also do it.
  ///
  /// Found by cast, the same way the coach's seams are: `RunEditor` implements
  /// it and the preview's stand-ins do not, so a build without a database gets
  /// null and the screens fall back to what they were handed rather than to an
  /// error.
  RunDetailSource? get _runDetails {
    final editor = widget.runEditor;
    return editor is RunDetailSource ? editor as RunDetailSource : null;
  }

  /// Takes the run on screen to the coach.
  ///
  /// The sentence carries the run's own numbers and, for a run out of the log,
  /// **the day it happened on**. The coach is never told a run's id and reads
  /// one endless transcript, which is how it once answered a question about a
  /// week-old 10 km by placing it yesterday. Naming the date in the question is
  /// the cheap half of that fix, and it costs nothing while the other half —
  /// conversations with ends, Phase 4 of the 1.0.0 plan — is unbuilt.
  void _askAboutRun(RunSummary run, {required bool justFinished}) {
    final distance = Distance.meters(run.distanceMeters).format(_unit);
    final time = run.duration.hoursMinutesSeconds;
    _askCoach(
      justFinished
          ? 'I have just finished a run: $distance in $time. '
                'What do you make of it?'
          : 'About my run on ${shortRunDate(run.startedAt)} — '
                '$distance in $time. What do you make of it?',
    );
  }

  /// A run the runner did somewhere this app was not: a treadmill session, a
  /// race, anything the phone did not see.
  Future<void> _addRun() async {
    final editor = widget.runEditor;
    if (editor == null) return;
    final saved = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => RunFormScreen(editor: editor, unit: _unit),
      ),
    );
    // Only reload on a real save. Backing out of the form should not cost a
    // round trip through the database and a rebuild of every tab.
    if (saved != null) await _refreshHome();
  }

  Future<void> _editRun(RunSummary run) async {
    final editor = widget.runEditor;
    final id = run.id;
    if (editor == null || id == null) return;
    final draft = await editor.draftOf(id);
    if (!mounted || draft == null) return;
    final saved = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => RunFormScreen(
          editor: editor,
          runId: id,
          initial: draft,
          unit: _unit,
        ),
      ),
    );
    if (saved != null) await _refreshHome();
  }

  /// Signs the runner in, or up, when something actually needs an account.
  ///
  /// Returns true if there is a session by the end. Pushed as a route rather
  /// than swapping the subtree, because they are in the middle of doing
  /// something and must land back where they were - `AuthGate` swapping the
  /// shell out underneath them would lose the tab, the scroll and the intent.
  Future<bool> _ensureAccount() async {
    if (widget.auth.isSignedIn) return true;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (routeContext) => SignInScreen(
          auth: widget.auth,
          initialSignUp: true,
          introName: _runnerName,
          onBack: () => Navigator.of(routeContext).maybePop(),
          // **Nothing else would dismiss this.** In the signed-out flow the
          // sign-in screen is a state of `AuthGate` and a session swaps the
          // subtree for the shell; here the shell is already underneath and
          // stays put, so the route has to close itself. Without it a runner
          // signed up successfully and sat on the completed form, with the plan
          // they asked for waiting behind a back gesture nobody mentioned.
          onAuthenticated: () => Navigator.of(routeContext).maybePop(),
        ),
      ),
    );
    if (!mounted) return false;
    return widget.auth.isSignedIn;
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          unit: _unit,
          settings: _unitSettings,
          auth: widget.auth,
          // The first run on record: what "since" on the account means here.
          memberSince: RunnerStats.from(_allRuns).firstRunAt,
          // The name row edits both homes through this, so it works for a
          // runner with no account - which is now most of them.
          introStore: _introStore,
          onNameChanged: (name) {
            if (!mounted) return;
            setState(() => _runnerName = name);
          },
          // **The second gate an account sits at**, and the one this shell
          // already owns for the first. Backup is the entire thing an account
          // does for a database that already works offline, so switching it on
          // with nobody signed in is a promise with no server behind it.
          ensureAccount: _ensureAccount,
          consentStore: widget.consentStore,
          eraser: widget.eraser,
          // The same backfill launch runs, from the other moment it matters.
          // Never throws (`RunEditor.backfill` guarantees it), and every push
          // inside reports its own failure where Settings already shows it.
          onBackupGranted: () async {
            await widget.runEditor?.backfill();
          },
          onUnitChanged: (unit) {
            if (!mounted) return;
            setState(() => _unit = unit);
            // Home's headline is written in the display unit ("Building toward
            // a marathon" vs a distance), so it is re-derived rather than left
            // reading in the unit the runner just changed away from.
            unawaited(_refreshHome());
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // One fold over the log for the whole shell. Home's tiles and Profile's
    // lifetime card are the same figures at two depths, and deriving them twice
    // is how they end up disagreeing.
    final stats = RunnerStats.from(_allRuns);

    return Scaffold(
      body: Stack(
        children: <Widget>[
          // **No bottom reserve injected here, and there never should have
          // been one.**
          //
          // The shell used to add 64pt of fake `MediaQuery` bottom padding
          // around this stack, to stop the floating mark sitting on whatever a
          // tab had scrolled to its floor. That job was already done, in the
          // one place that can do it: every tab pads the foot of its own scroll
          // by `kCoachMarkClearance`, which is the mark's own size plus its
          // margins and predates the reserve. So the 64 was a second mechanism
          // for a solved problem — and on two of the three tabs it did nothing
          // at all, because a `ListView` with explicit padding and a
          // `CustomScrollView` both ignore `MediaQuery.padding` outright.
          //
          // The one widget that read it was Plan's `SafeArea`, which does not
          // opt out of the bottom. There it was not scroll padding at all: it
          // shortened the scroll **viewport** by 64pt, so the last card was
          // sliced through mid-row and the strip below it showed the photo
          // backdrop's own foot — nearly opaque under `ScrimStrength.grounded`
          // — as a full-width black band above the nav bar, beside the mark
          // (IMG_4700). Home, whose `SafeArea` passes `bottom: false`, has no
          // band; Profile, which has no `SafeArea`, has none either. That is
          // the whole difference between the three screenshots.
          //
          // Verified by reading, not on a device: nobody here has an iPhone.
          IndexedStack(
            index: _index,
            children: <Widget>[
              HomeTab(
                access: _access,
                onRecord: () => _startRun(context, withSession: false),
                onStartSession: () => _startRun(context),
                // Two destinations, not one. These were a single
                // `onOpenCoach` that switched to the tab — so the coach's own
                // note opened a plan screen, and the button offering to talk
                // to a coach did too. Only one of them was ever about the
                // plan (ADR-0017).
                onOpenPlan: () => setState(() => _index = _planTab),
                onOpenCoach: _chat == null ? null : _openCoach,
                // The same door the coach mark opens (ADR-0030), reached from
                // the other end. The locked last-run tile tells a free runner
                // to upgrade, and `onUpgrade` is what turns that sentence into
                // something tappable — null hides the offer, so until this was
                // passed the shipping app said "upgrade" and gave nobody a way
                // to. Only `last_run_test.dart` ever supplied one.
                onUpgrade: _showCoachGate,
                today: _todayView,
                thisWeek: _thisWeek,
                note: _note,
                outcomes: _outcomes,
                volumes: _volumes,
                consistency: _consistency,
                standing: _standing,
                // The same fold Profile is given below, computed once here so
                // the two tabs cannot report different lifetime figures for the
                // same log.
                stats: stats,
                // Newest first — the shell sorts the log on load, so the head
                // of it is the last run. Home reads it to answer "have they run
                // today" and to fill the last-run tile.
                lastRun: _allRuns.firstOrNull,
                // What that run was measured against, when it answered a
                // session. Worked out here rather than on Home because it
                // needs the plan and the log together, and Home is handed one
                // of them.
                lastRunAgainst: _againstLastRun,
                hasRuns: _allRuns.isNotEmpty,
                missed: _missed,
                onOpenRun: _openRun,
                onAskCoach: _chat == null ? null : _askCoach,
                // Only with a plan to bend and a coach to bend it.
                onAdjustWeek: widget.planClient == null || _todayView == null
                    ? null
                    : _adjustThisWeek,
                // Only when there is a race in view at all; the card decides
                // which of its states actually offers the door, since the run
                // up to a race has nothing to close out yet. Needs no coach
                // and no network behind it — a runner offline on the train
                // home from their marathon can still record what they ran,
                // because everything it writes is local (rule 1).
                onCloseRace: _todayView?.race == null ? null : _closeRace,
                unit: _unit,
              ),
              _PlanTab(
                plans: _plans,
                coach: widget.coach,
                chat: _chatClient,
                runs: widget.historySource,
                planClient: widget.planClient,
                memory: _memory,
                summariser: _summariser,
                unit: _unit,
                onPlanChanged: _refreshHome,
                onAskCoach: _askCoach,
                runnerName: _runnerName,
                ensureAccount: _ensureAccount,
              ),
              // The runner and their record, on one page: totals, bests, the goal,
              // then every run. Reads the shell's own log rather than calling the
              // source again, so the totals and the rows they come from are always
              // the same load.
              ProfileScreen(
                stats: stats,
                profile: _planProfile,
                // Derived here rather than cached, exactly like the stats above:
                // it reads the display unit, and a stored copy stayed in kilometres
                // after the runner switched to miles. Both are a fold over the log,
                // which is cheaper than a staleness bug.
                //
                // No plan goes in. Where they are in a block is the Plan tab's
                // subject and today is Home's; this is the long view of the runner.
                standing: TrainingStanding.read(runs: _allRuns, unit: _unit),
                // Past plans only — the current one is the Coach tab's subject.
                pastPlans: _pastPlans,
                runs: _allRuns,
                unit: _unit,
                onOpenRun: _openRun,
                onAddRun: widget.runEditor == null ? null : _addRun,
                onAskCoach: _chatClient == null ? null : _askCoach,
                onOpenSettings: _openSettings,
              ),
            ],
          ),
          // Floating over every tab, which is the whole point of it: the dock
          // this replaces could only exist on the Plan tab, so the coach was
          // present on a third of the app and absent from the rest.
          // Absent rather than inert when there is no coach behind it. A mark
          // that cannot open anything is worse than no mark.
          if (_chat != null)
            Positioned(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              bottom: AppSpacing.lg,
              child: CoachReveal(
                // Only an observation the runner has not been shown. Once it
                // has played the mark rests, and it does not play again until
                // the coach notices something new.
                //
                // **And only for somebody who has bought it.** `_note` is
                // derived on the device from the run log, so it cost nothing to
                // compute and was shown to everybody -- which handed a free
                // runner the coach's reading of them, the thing
                // `coach_access.dart` says the subscription is. The mark itself
                // stays: it is the door to the gate sheet, and a door is not
                // the room.
                note: _access.isSubscribed && !_noteDelivered ? _note : null,
                hasUnread: _access.isSubscribed && _note != null && !_coachSeen,
                onTap: _openCoach,
                onFinished: () {
                  if (mounted) setState(() => _noteDelivered = true);
                },
              ),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          // "Plan", not "Coach". The tab was named for a conversation that
          // moved out of it — the dock it was built around became a mark
          // floating over all three tabs. What is left under the label is the
          // headline, this week, the arc and the calendar (ADR-0017).
          //
          // Not the sparkle either, for the reason `CoachButton` gives for
          // avoiding it: `Icons.auto_awesome` is on every AI feature shipped in
          // the last three years, and this tab is not even the AI one.
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
}

/// The Plan tab: an empty state that launches the coach flow, then the plan arc.
///
/// The plan is **owned by the repository, not this widget** — it is read from
/// storage on first build and every change (a new plan, a week filled in, today
/// marked done) is written through before the UI reflects it. Force-quitting the
/// app loses nothing. The plan is built deterministically for now; the LLM
/// refinement lights up once the coach Edge Function is deployed.
class _PlanTab extends StatefulWidget {
  const _PlanTab({
    required this.plans,
    required this.unit,
    required this.onPlanChanged,
    this.coach,
    this.chat,
    this.runs,
    this.planClient,
    this.memory,
    this.summariser,
    this.onAskCoach,
    this.runnerName,
    this.ensureAccount,
  });

  /// Raises sign-up when a plan is asked for without an account, and reports
  /// whether there is a session afterwards. Null means do not gate, which is
  /// what a widget test wiring this tab directly wants.
  final Future<bool> Function()? ensureAccount;

  final PlanRepository plans;
  final UnitSystem unit;

  /// What the coach calls this runner, from the intro. Passed down rather than
  /// re-read here so this tab keeps knowing nothing about auth; it is used for
  /// one line of dialogue at the front of the plan flow.
  final String? runnerName;

  /// Told whenever the plan is created, replaced or marked, so Home can reload.
  final Future<void> Function() onPlanChanged;
  final CoachClient? coach;

  /// The open conversation's backend. Null docks the chat as offline.
  final CoachChatClient? chat;

  /// The run log, read fresh for every brief. Not the shell's cached three:
  /// the brief counts the last seven days, and a coach that could only see
  /// three runs would tell a runner they had done less than they had.
  final Future<List<RunSummary>> Function()? runs;

  final PlanClient? planClient;

  /// Where the conversation and the rolling summary are kept. Null keeps the
  /// coach's memory to this session.
  final CoachMemoryRepository? memory;

  /// Rewrites the rolling summary when the conversation sheet closes.
  final CoachSummariseClient? summariser;

  /// Opens the conversation with an opener already written — the hand-off from
  /// a session brief. Owned by the shell now that the coach floats over every
  /// tab rather than being docked to this one.
  final void Function(String opener)? onAskCoach;

  @override
  State<_PlanTab> createState() => _PlanTabState();
}

class _PlanTabState extends State<_PlanTab> {
  bool _loading = true;

  /// The run log, for the measures a plan cannot supply — how often a rhythm
  /// runner has actually turned up.
  List<RunSummary> _runLog = const <RunSummary>[];
  Map<int, TrainingWeek> _horizonWeeks = const <int, TrainingWeek>{};

  /// Set when the stored plan could not be read. Shown as a problem rather than
  /// as "no plan yet", which would invite the runner to build a second one over
  /// the top of a block that is still there.
  String? _error;

  StoredPlan? _plan;
  TodayView? _today;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// Reads the plan from local storage. No network involved, so this works
  /// offline (CLAUDE.md rule 1).
  Future<void> _load() async {
    // Loaded here rather than only per-brief: a rhythm's headline counts how
    // many times the runner has turned up, and that has to be on screen rather
    // than only in the coach's context.
    //
    // Guarded rather than bare: this read used to sit outside the try below, so
    // a failing run log threw straight out of `_load` and left `_loading` true
    // — the tab span for good because of a number in the headline, with the
    // plan it exists to show sitting readable on disk the whole time. The log
    // is context here, so losing it costs a count, not the screen.
    List<RunSummary> log;
    try {
      log = await widget.runs?.call() ?? const <RunSummary>[];
    } catch (_) {
      log = const <RunSummary>[];
    }
    if (mounted) setState(() => _runLog = log);
    try {
      final plan = await widget.plans.load();
      if (plan == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _plan = null;
          _today = null;
          _error = null;
        });
        return;
      }
      await _show(plan);
    } on PlanStoreException catch (e) {
      _fail(e.message);
    }
  }

  Future<void> _show(StoredPlan plan) async {
    final today = await widget.plans.today(plan);

    // Only the weeks the calendar actually draws. Materialising the whole block
    // would generate sessions for weeks that are still going to move.
    final first = plan.weekIndexOn(DateTime.now());
    final last = (first + kPlannedWeekHorizon - 1).clamp(
      1,
      plan.skeleton.weeks.length,
    );
    final loaded = <int, TrainingWeek>{};
    for (var i = first; i <= last; i++) {
      loaded[i] = await widget.plans.weekFor(plan, plan.skeleton.weeks[i - 1]);
    }

    if (!mounted) return;
    setState(() {
      _plan = plan;
      _today = today;
      _horizonWeeks = loaded;
      _loading = false;
      _error = null;
    });
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = message;
    });
  }

  Future<void> _retry() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await _load();
  }

  /// The plan flow, behind the one gate an account still has to sit at.
  ///
  /// **This is where an account earns itself.** The app opens on a working
  /// tracker with nothing signed in, because the on-device database has always
  /// been the source of truth and asking for credentials to use it was asking
  /// for nothing in return. A plan is different: it is built by the coach, the
  /// coach is an Edge Function calling a model, and that costs money per
  /// request. There has to be somebody to attribute it to.
  ///
  /// So the ask lands here, where a runner has just said they want the thing it
  /// pays for, rather than ninety seconds after install when they have not.
  /// Backing out returns them to a Plan tab that still works.
  Future<void> _startCoaching() async {
    final coach = widget.coach;
    if (coach == null) return;
    if (!await (widget.ensureAccount?.call() ?? Future<bool>.value(true))) {
      return;
    }
    // The gate above pushed a route and awaited it, so this state may have gone
    // away while somebody was signing up.
    if (!mounted) return;
    // The flow builds the plan itself and hands it back built, so there is no
    // spinner to own here any more: the wait belongs to the screen that
    // explains it, and a plan that arrives on this tab unannounced was the
    // whole reason onboarding had no ending (ADR-0019).
    //
    // `create` persists the plan (superseding any earlier one) and its current
    // week before returning, so nothing handed back here is unsaved.
    final plan = await Navigator.of(context).push<StoredPlan>(
      MaterialPageRoute<StoredPlan>(
        builder: (_) => CoachFlow(
          coach: coach,
          name: widget.runnerName,
          unit: widget.unit,
          buildPlan: widget.plans.create,
        ),
      ),
    );
    if (plan == null || !mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    await _show(plan);
    unawaited(widget.onPlanChanged());
  }

  /// Starts a fresh plan over the top of the current one. Confirmed first: the
  /// existing block is superseded and its recorded sessions stop being the plan
  /// the runner is following, so this is not a tap to make by accident.
  Future<void> _replacePlan() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Start a new plan?'),
        content: const Text(
          'Your current plan is replaced by the one your coach builds next. '
          'Runs you have already recorded are kept.',
        ),
        actions: <Widget>[
          AppTextButton(
            label: 'Keep it',
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Start over'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _startCoaching();
  }

  /// Opens a week, filling it in from the skeleton and storing it the first time
  /// it is asked for, focused on the day the runner tapped.
  Future<void> _openWeek(
    StoredPlan plan,
    TrainingPaces paces,
    SkeletonWeek slot,
    int weekday,
  ) async {
    final TrainingWeek week;
    try {
      week = await widget.plans.weekFor(plan, slot);
    } on PlanStoreException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!mounted) return;
    final planClient = widget.planClient;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WeekDetailScreen(
          unit: widget.unit,
          week: week,
          slot: slot,
          paces: paces,
          focusedWeekday: weekday,
          profile: plan.profile,
          // **Without `soFar`, unlike the chat path, and knowingly so.** This
          // reaches `WeekAdjustSheet`, which holds a week, a slot and a
          // profile — no runs and no dates — so carrying what has already
          // happened means threading it through two more screens. The sheet is
          // also the surface `_adjustThisWeek` deliberately moved away from:
          // the conversation is where a change is asked for now, and that path
          // does refit. Written down rather than left to be discovered,
          // because an argument nobody passed is the shape of three separate
          // defects this release has already had.
          adaptation: planClient == null
              ? null
              : AdaptationService(client: planClient),
          onRevised: (revised) => widget.plans.saveRevisedWeek(plan, revised),
        ),
      ),
    );
    // Today's card may name a session this week just revised, so re-read it
    // from the store rather than leaving a stale card behind.
    if (mounted) unawaited(_show(plan));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final error = _error;
    if (error != null) return _PlanUnreadable(onRetry: _retry);

    final plan = _plan;
    final today = _today;

    // No plan is a normal state, not an error — the coach is still available.
    if (plan == null) {
      return PlanScreen(
        unit: widget.unit,
        onBuildPlan: widget.coach == null
            ? null
            : () => unawaited(_startCoaching()),
      );
    }

    final paces = pacesFor(plan.profile);
    return PlanScreen(
      unit: widget.unit,
      plan: plan,
      paces: paces,
      onAskAboutSession: widget.onAskCoach,
      // Every run, not a cached handful: a rhythm counts how many times the
      // runner has turned up since the plan began, and a short list would
      // undercount it.
      runs: _runLog,
      weeks: _horizonWeeks,
      statusFor: (weekday) => today != null && today.session?.weekday == weekday
          ? today.status
          : null,
      onOpenWeek: paces == null
          ? null
          : (slot, weekday) => unawaited(_openWeek(plan, paces, slot, weekday)),
      onReplacePlan: widget.coach == null
          ? null
          : () => unawaited(_replacePlan()),
      onOpenCalendar: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlanCalendarScreen(
            plan: plan,
            weeks: _horizonWeeks,
            unit: widget.unit,
            statusFor: (weekday) =>
                today != null && today.session?.weekday == weekday
                ? today.status
                : null,
            onOpenWeek: paces == null
                ? null
                : (slot, weekday) =>
                      unawaited(_openWeek(plan, paces, slot, weekday)),
          ),
        ),
      ),
      onOpenBlock: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlanBlockScreen(
            plan: plan,
            unit: widget.unit,
            // The shell is the side that holds the log, so it is the side that
            // can answer this. Read here rather than inside the screen for the
            // reason the screen's own comment gives: readiness is a fact about
            // what the runner has actually done, and a screen handed only a
            // plan would have to fall back on the profile, which ages.
            readiness: assessReadiness(
              plan.profile,
              _runLog,
              now: DateTime.now(),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when a plan is on disk but could not be read — a schema mismatch or a
/// corrupt row. Deliberately distinct from [_PlanEmpty]: the runner's block may
/// still be recoverable, so this must not read as "you have no plan".
class _PlanUnreadable extends StatelessWidget {
  const _PlanUnreadable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Plan')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.warning_amber_outlined,
                size: 40,
                color: AppColors.textTertiary,
              ),
              const SizedBox(height: 12),
              Text(
                "Couldn't open your plan",
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Your plan is still saved. Try again, and if it keeps failing '
                'your coach can rebuild it.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      ),
    );
  }
}
