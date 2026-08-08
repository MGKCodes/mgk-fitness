import 'dart:async';

import 'package:flutter/material.dart';

import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/preview/fake_coach_service.dart';
import 'package:mgk_run/preview/coach_button_preview.dart'
    show coachButtonPreviewScreens;
import 'package:mgk_run/preview/glass_preview.dart' show glassPreviewScreens;
import 'package:mgk_run/preview/legal_preview.dart' show legalPreviewScreens;
import 'package:mgk_run/preview/fake_plan_client.dart';
import 'package:mgk_run/preview/fake_run_recorder.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mgk_run/src/features/history/domain/run_draft.dart';
import 'package:mgk_run/src/features/coaching/data/plan_client.dart';
import 'package:mgk_run/src/features/coaching/data/coach_service.dart';
import 'package:mgk_run/src/features/coaching/data/adaptation_service.dart';
import 'package:mgk_run/src/features/coaching/data/coach_client.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_memory.dart';
import 'package:mgk_run/src/features/coaching/data/coach_memory_store.dart';
import 'package:mgk_run/src/features/coaching/data/coach_memory_repository.dart';
import 'package:mgk_run/src/features/coaching/data/plan_store.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/core/config/app_config.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import 'package:mgk_run/src/features/auth/presentation/auth_gate.dart';
import 'package:mgk_run/src/features/auth/presentation/sign_in_screen.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_brief.dart';
import 'package:mgk_run/src/features/coaching/domain/training_standing.dart';
import 'package:mgk_run/src/features/coaching/domain/intake_slots.dart';
import 'package:mgk_run/src/features/coaching/domain/pace_model.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/goal_draft.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_history.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_shape.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/session_status.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/presentation/chat_controller.dart';
import 'package:mgk_run/src/features/coaching/presentation/chat_entry.dart';
import 'package:mgk_run/src/features/coaching/presentation/plan_screen.dart';
import 'package:mgk_run/src/features/coaching/presentation/coach_conversation.dart';
import 'package:mgk_run/src/features/coaching/presentation/coach_button.dart';
import 'package:mgk_run/src/features/coaching/presentation/onboarding_controller.dart';
import 'package:mgk_run/src/features/coaching/presentation/onboarding_screen.dart';
import 'package:mgk_run/src/features/coaching/presentation/plan_block_screen.dart';
import 'package:mgk_run/src/features/coaching/presentation/plan_calendar_screen.dart';
import 'package:mgk_run/src/features/coaching/presentation/plan_arc_screen.dart';
import 'package:mgk_run/src/features/coaching/presentation/session_brief_sheet.dart';
import 'package:mgk_run/src/features/coaching/presentation/profile_confirmation_screen.dart';
import 'package:mgk_run/src/features/coaching/presentation/today_card.dart';
import 'package:mgk_run/src/features/coaching/presentation/week_detail_screen.dart';
import 'package:mgk_run/src/features/profile/domain/runner_stats.dart';
import 'package:mgk_run/src/features/profile/presentation/profile_screen.dart';
import 'package:mgk_run/src/features/settings/domain/unit_settings.dart';
import 'package:mgk_run/src/features/settings/presentation/settings_screen.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';
import 'package:mgk_run/src/features/onboarding/presentation/welcome_screen.dart';
import 'package:mgk_run/src/features/recording/domain/run_split.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';
import 'package:mgk_run/src/features/recording/presentation/recording_screen.dart';
import 'package:mgk_run/src/features/recording/presentation/route_map.dart';
import 'package:mgk_run/src/features/recording/presentation/run_summary_screen.dart';

/// Preview harness — renders Runio against fakes, with **no Supabase and no
/// device plugins**, so the UI can be built and screenshotted on Flutter web
/// from any machine (including this Windows box). A developer tool, never
/// shipped.
///
/// It is **URL-driven**: append `?screen=<key>` to the URL. There are two kinds
/// of entry, and they don't overlap:
///  - **Isolated screens** (`welcome`, `signin`, `signup`, `home`) render one
///    screen for a quick visual/design check. No navigation, no backend.
///  - **`app`** mounts the *real* [AuthGate] flow against a fake backend, so
///    the whole welcome → sign-in → home path — including the debug
///    quick-sign-in buttons — runs through the real routing, not a re-wired
///    copy. This is where interactions are exercised.
///
/// ```
/// flutter run -t lib/preview/main.dart -d web-server --web-port 8888
/// #   http://localhost:8888/?screen=app
/// ```
///
/// Map surfaces (`recording`, `summary`) draw on the charcoal base with no
/// basemap unless a tile provider is configured, since the app only ever calls
/// the provider its privacy policy names. To design against real tiles, pass a
/// template on the command line — a dev basemap is fine here, this is not the
/// shipped app:
///
/// ```
/// flutter run -t lib/preview/main.dart -d web-server --web-port 8888 \
///   --dart-define=MAP_TILE_URL_TEMPLATE=https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png
/// ```
/// The harness runs offline against fakes by default. It also brings up
/// Supabase when the build was given real config
/// (`--dart-define-from-file=config/app_config.json`), because the `*-live`
/// routes below talk to the deployed coach rather than to a script.
///
/// Initialising unconditionally-if-configured is safe: nothing reads the client
/// unless a live route is opened, and an unconfigured build skips it entirely.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.current;
  if (config.isConfigured) {
    await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabasePublishableKey,
    );
  }
  runApp(const PreviewApp());
}

/// Fake accounts injected into the `app` flow so the debug quick-sign-in
/// buttons appear without a backend. Not real credentials.
const List<DevAccount> _sampleDevAccounts = <DevAccount>[
  DevAccount(label: 'Runner A', email: 'a@runio.app', password: 'password'),
  DevAccount(label: 'Runner B', email: 'b@runio.app', password: 'password'),
];

const String _fakeEmail = 'dev@runio.app';

/// A keyless basemap for the harness **only**, so map surfaces can be designed
/// and screenshotted without a MapTiler key on every dev machine. The app never
/// uses this: it reads `AppConfig.mapTileUrlTemplate`, which is the provider the
/// privacy policy names. This file is a dev tool and is never shipped.
const String _devTiles =
    'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';

final Map<String, WidgetBuilder> _screens = <String, WidgetBuilder>{
  // Isolated single screens — visual checks only.
  'welcome': (_) => WelcomeScreen(onGetStarted: () {}, onHaveAccount: () {}),
  'signin': (_) => const SignInScreen(),
  'signup': (_) => const SignInScreen(initialSignUp: true),
  'home': (_) => HomeShell(
    auth: FakeAuthRepository(signedIn: true, email: _fakeEmail),
    recorderFactory: () => FakeRunRecorder(),
    historySource: () async => _demoRuns(),
    coach: FakeCoachService(),
    planClient: FakePlanClient(),
  ),
  // The Coach and Profile tabs of the real shell, addressable by URL.
  'coach': (_) => HomeShell(
    auth: FakeAuthRepository(signedIn: true, email: _fakeEmail),
    recorderFactory: () => FakeRunRecorder(),
    historySource: () async => _demoRuns(),
    coach: FakeCoachService(),
    planClient: FakePlanClient(),
    initialTab: 1,
  ),
  'history-tab': (_) => HomeShell(
    auth: FakeAuthRepository(signedIn: true, email: _fakeEmail),
    recorderFactory: () => FakeRunRecorder(),
    historySource: () async => _demoRuns(),
    coach: FakeCoachService(),
    planClient: FakePlanClient(),
    initialTab: 2,
  ),
  // The Plan tab with a plan already on disk, so the week calendar and the
  // planning horizon are visible.
  ...coachButtonPreviewScreens,
  'coach-planned': (_) => const _SeededCoach(),
  // The same plan read in miles. The prescription is round in whichever unit
  // the runner thinks in, which is the whole point of rounding it.
  'coach-miles': (_) => const _SeededCoach(unit: UnitSystem.imperial),
  // The runner ADR-0011 exists for: parkrun every Saturday, no race, no block.
  // Their Plan tab must be a week worth opening, not a block with the numbers
  // filed off.
  'coach-rhythm': (_) => const _SeededCoach(shape: _DemoShape.rhythm),
  // A distance to reach with no race entered: ramps, never tapers, counts no
  // days.
  'coach-horizon': (_) => const _SeededCoach(shape: _DemoShape.horizon),
  // The full block, week by week — what the Plan tab's week header opens.
  'plan-calendar': (_) => const _SeededPlanScreen(calendar: true),
  // The whole block as one arc, grouped by phase.
  'plan-block': (_) => const _SeededPlanScreen(calendar: false),
  // The coach on one session: effort first, the pace band behind it, and the
  // hand-off to the conversation. Opened on a tap in the app, so it needs its
  // own entry to be looked at.
  'session-brief': (_) => const _SessionBriefPreview(),
  'session-brief-rest': (_) => const _SessionBriefPreview(rest: true),
  // Home with a plan on disk, so the week ribbon and today's session render.
  'home-planned': (_) => const _SeededCoach(tab: 0),
  // The docked conversation, opened, with nothing said yet — the state a new
  // runner meets. The suggestions below the invitation are tappable.
  // The conversation against the DEPLOYED coach, so intents can be seen being
  // raised and confirmed. The only chat route that spends money.
  'coach-chat-live': (_) => const _LiveChat(),
  'coach-chat': (_) => const _ChatPreview(),
  // A conversation that outlived a relaunch: the transcript is restored from
  // stored turns and the coach is briefed with the rolling summary, which is
  // the whole point of the memory loop.
  'coach-remembered': (_) => const _ChatPreview(remembered: true),
  // The same dock over an empty Plan tab: using the coach without a plan is
  // supported, and the invitation must not read as "come back with a goal".
  'coach-chat-noplan': (_) => const _ChatPreview(withPlan: false),
  // A turn round-trip: the runner's bubble, the typing dots, then the reply.
  'coach-chat-turn': (_) =>
      const _ChatPreview(opener: 'What could I run a half marathon in?'),
  // The runner has spent their allowance. The reason has to be the real one —
  // "try rephrasing" is useless advice when rephrasing cannot help.
  'coach-chat-limited': (_) => _ChatPreview(
    client: _LimitedChatClient(),
    opener: 'How has my training been going?',
  ),
  // The adaptation hand-off: a niggle in the chat comes back as an intent, and
  // the request goes through the real propose → validate → diff → approve path.
  'coach-chat-adapt': (_) => const _ChatPreview(
    adapt: true,
    opener: 'My calf is sore — can we move today’s run?',
  ),
  // No coach configured for this build: the dock says so rather than offering a
  // field that cannot send.
  'coach-chat-offline': (_) => const _ChatPreview(client: null, offline: true),
  // Home with a run history that earns a coach note — the demo set deliberately
  // does not, so both states are visible.
  'home-noted': (_) => HomeShell(
    auth: FakeAuthRepository(signedIn: true, email: _fakeEmail),
    recorderFactory: () => FakeRunRecorder(),
    historySource: () async => _notableRuns(),
    coach: FakeCoachService(),
    planClient: FakePlanClient(),
  ),
  // In-run recording hero, driven by a fake recorder replaying a canned trace.
  'recording': (context) => RecordingScreen(
    recorder: FakeRunRecorder(),
    onCancel: () => ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Run discarded.'))),
  ),
  // Post-run route view: the demo trace drawn on the dark basemap.
  'map': (_) => Scaffold(
    body: RouteMap(points: demoRunTrace(), tileUrlTemplate: _devTiles),
  ),
  // Post-run summary: map, headline distance, stats, and per-split pace.
  'summary': (_) =>
      RunSummaryScreen(summary: _demoSummary(), history: _demoRuns()),
  // The onboarding conversation against the REAL deployed coach. This is the
  // only route that spends money, and the only one that can tell you whether
  // intake actually works — 'onboarding' below is a script that ignores what
  // you type, which is useful for animations and useless for the model.
  'onboarding-live': (context) => const _LiveOnboarding(),
  // The onboarding conversation, driven by a scripted offline coach. Reaching
  // the end unlocks the editable confirmation screen.
  'onboarding': (context) => OnboardingScreen(
    controller: OnboardingController(coach: FakeCoachService()),
    onReview: (slots) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfileConfirmationScreen(
          slots: slots,
          onConfirm: (_) => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile confirmed — plan generation is next.'),
            ),
          ),
        ),
      ),
    ),
  ),
  // The editable confirmation screen alone, pre-filled with a sane profile.
  'confirm': (context) => ProfileConfirmationScreen(
    slots: _demoIntakeSlots(),
    onConfirm: (_) => ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Profile confirmed.'))),
  ),
  // The plan arc + today's session card, built deterministically. Tap a week to
  // see its sessions and paces; mark today's session done or skipped.
  'plan': (_) => const _PlanPreview(),
  // One week's sessions + target paces (a mid-plan build week).
  'week': (_) => _weekDetail(),
  // The same week as it opens when the runner taps Thursday in the calendar:
  // that row raised, and scrolled into view. Here because the treatment has to
  // be *looked at* — a test can only say the colour is the one that was asked
  // for, not whether it reads.
  'week-focused': (_) => _weekDetail(focusedWeekday: DateTime.thursday),
  // The week calendar with a session completed and one skipped, so the two
  // marks can be compared against a plain day side by side.
  'coach-marks': (_) {
    final profile = _demoProfile();
    final skeleton = buildSkeleton(profile, now: DateTime.now());
    return PlanScreen(
      now: DateTime.now(),
      plan: StoredPlan(
        id: 'preview',
        profile: profile,
        skeleton: skeleton,
        startDate: mondayOf(DateTime.now()),
      ),
      weeks: {
        1: buildFallbackWeek(skeleton.weeks[0], profile),
        2: buildFallbackWeek(skeleton.weeks[1], profile),
      },
      statusFor: (weekday) => switch (weekday) {
        1 => SessionStatus.completed,
        2 => SessionStatus.skipped,
        _ => null,
      },
      onOpenWeek: (_, _) {},
    );
  },
  // The training log, which lives on the Profile page rather than on one of its
  // own. Kept as a key so the log can be reviewed directly.
  'history': (context) => _demoProfileScreen(context),
  // The real routing flow against a fake backend: welcome → sign-in (with the
  // debug quick-sign-in buttons) → home, all through the actual AuthGate.
  'app': (_) => AuthGate(
    auth: FakeAuthRepository(),
    devAccounts: _sampleDevAccounts,
    recorderFactory: () => FakeRunRecorder(),
    historySource: () async => _demoRuns(),
    coach: FakeCoachService(),
    planClient: FakePlanClient(),
  ),
  // Settings: the account block, the display-unit toggle, the compliance
  // surfaces, deleting the account and the version — everything about the app
  // rather than about the running.
  'settings': (_) => SettingsScreen(
    unit: UnitSystem.metric,
    settings: InMemoryUnitSettings(),
    auth: FakeAuthRepository(signedIn: true, email: _fakeEmail),
    memberSince: RunnerStats.from(_demoRuns()).firstRunAt,
  ),
  // Profile: lifetime totals, what the coach makes of them, records, the goal,
  // then the whole log. The demo set deliberately earns no coach note, so this
  // is the invitation state.
  'profile': (context) => _demoProfileScreen(context),
  // A runner with a past. Every plan Runio built was already on disk and
  // nothing showed them, so three blocks in read as a beginner.
  'profile-history': (context) => _standingPreview(
    context,
    runs: _demoRuns(),
    profile: _demoProfile(),
    pastPlans: _demoPastPlans(),
  ),
  // Building: more in the last four weeks than the four before, and quicker
  // with it. That comparison is the whole point of the card.
  'profile-building': (context) =>
      _standingPreview(context, runs: _buildingRuns(), profile: _demoProfile()),
  // Holding: the same month twice over, which must not read as progress.
  'profile-holding': (context) => _standingPreview(
    context,
    runs: _steadyRuns(),
    profile: _parkrunProfile(),
  ),
  // A log too short to have a direction. Two points make a trend; one does not.
  'profile-new': (context) => _standingPreview(
    context,
    runs: _steadyRuns().take(2).toList(),
    profile: _demoProfile(),
  ),
  // The same screen with nothing recorded — the empty state is the common one
  // for a new runner, so it gets its own key rather than being imagined.
  'profile-empty': (_) => ProfileScreen(
    stats: RunnerStats.from(const <RunSummary>[]),
    profile: _demoProfile(),
    standing: TrainingStanding.read(runs: const <RunSummary>[]),
    onAskCoach: (_) {},
    onOpenSettings: () {},
  ),
  // A log long enough to scroll properly, so the backdrop's parallax clamp and
  // the stagger cap can be seen doing their job rather than assumed.
  'profile-long': (context) => _standingPreview(
    context,
    runs: _parkrunHistory(),
    profile: _parkrunProfile(),
  ),
  // The legal / compliance surfaces (`legal`, `disclaimer-gate`, `disclaimer`,
  // `delete`). Folded in so this one harness serves every screen — they also
  // still have their own entry point in `legal_preview.dart`.
  ...legalPreviewScreens,
  // The glass material bench (`glass`, `glass-flat`).
  ...glassPreviewScreens,
};

ProfileScreen _demoProfileScreen(BuildContext context) =>
    _standingPreview(context, runs: _demoRuns(), profile: _demoProfile());

/// Profile with the standing read from the log, so the coach card shows what it
/// actually says rather than a hand-written line.
///
/// No plan is passed: the standing is the long view of the runner, and where
/// they are in a block belongs to the Plan tab.
ProfileScreen _standingPreview(
  BuildContext context, {
  required List<RunSummary> runs,
  required RunnerProfile profile,
  List<LabelledPlan> pastPlans = const <LabelledPlan>[],
}) => ProfileScreen(
  stats: RunnerStats.from(runs),
  profile: profile,
  standing: TrainingStanding.read(runs: runs),
  pastPlans: pastPlans,
  runs: runs,
  onOpenRun: (run) => _openDemoRun(context, run, runs),
  onAskCoach: (_) {},
  onOpenSettings: () {},
);

/// A runner with a past: one marathon block seen through, one stopped at week 9,
/// and a spell of just keeping a rhythm.
///
/// The mixed set is the point. All three outcomes render differently, and the
/// numbering has to survive a rhythm sitting between two marathons.
List<LabelledPlan> _demoPastPlans() => labelPlans(<PlanRecord>[
  PlanRecord(
    id: 'past-1',
    startDate: DateTime(2024, 9, 2),
    weeks: 16,
    isActive: false,
    goalDistanceMeters: 42195,
    eventDate: DateTime(2024, 12, 15),
    endedAt: DateTime(2025, 1, 6),
  ),
  PlanRecord(
    id: 'past-2',
    startDate: DateTime(2025, 1, 6),
    weeks: 12,
    isActive: false,
    endedAt: DateTime(2025, 4, 7),
  ),
  PlanRecord(
    id: 'past-3',
    startDate: DateTime(2025, 4, 7),
    weeks: 16,
    isActive: false,
    goalDistanceMeters: 42195,
    eventDate: DateTime(2025, 8, 3),
    endedAt: DateTime(2025, 6, 9),
  ),
  PlanRecord(
    id: 'current',
    startDate: DateTime(2026, 7, 27),
    weeks: 16,
    isActive: true,
    goalDistanceMeters: 21097,
    eventDate: DateTime(2026, 11, 15),
  ),
]).where((p) => !p.record.isActive).toList();

/// A run whose duration actually matches its pace.
///
/// Written as a helper because the first version of these fixtures set the two
/// independently, and the standing reads pace from duration over distance — so
/// the card cheerfully reported an average of 84:10 /km. Preview data that does
/// not obey arithmetic is worse than none: it makes correct code look broken.
RunSummary _paced({
  required DateTime at,
  required double meters,
  required double secondsPerKm,
}) => RunSummary(
  startedAt: at,
  duration: Duration(seconds: (meters / 1000 * secondsPerKm).round()),
  distanceMeters: meters,
  avgPaceSecondsPerKm: secondsPerKm,
);

/// Two months of running where the recent month is the bigger one, and the
/// recent pace the quicker one. The card should say both.
List<RunSummary> _buildingRuns() {
  final now = DateTime.now();
  return <RunSummary>[
    // The last four weeks: eight runs, longer and quicker.
    for (var i = 0; i < 8; i++)
      _paced(
        at: now.subtract(Duration(days: 2 + i * 3)),
        meters: 8000,
        secondsPerKm: 303,
      ),
    // The four before: six shorter, slower ones.
    for (var i = 0; i < 6; i++)
      _paced(
        at: now.subtract(Duration(days: 30 + i * 4)),
        meters: 6000,
        secondsPerKm: 330,
      ),
  ];
}

/// The same month twice: a runner holding station rather than progressing.
List<RunSummary> _steadyRuns() {
  final now = DateTime.now();
  return <RunSummary>[
    for (var i = 0; i < 16; i++)
      _paced(
        at: now.subtract(Duration(days: 2 + i * 3)),
        meters: 6000,
        secondsPerKm: 305,
      ),
  ];
}

/// Opens a run's summary from a preview log, so tapping a row goes somewhere.
void _openDemoRun(
  BuildContext context,
  RunSummary run,
  List<RunSummary> history,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => RunSummaryScreen(summary: run, history: history),
  ),
);

/// A sane, complete runner profile for the plan-screen previews.
RunnerProfile _demoProfile() => RunnerProfile(
  goalDistanceMeters: 42195,
  eventDate: DateTime.now().add(const Duration(days: 112)),
  currentWeeklyMeters: 40000,
  longestRecentMeters: 18000,
  daysPerWeek: 5,
  // Six available days for five runs, so the demo has one free day — which is
  // where the strength session lands, and what makes it visible in the harness.
  availableWeekdays: const <int>{1, 2, 3, 4, 6, 7},
  strengthDaysPerWeek: 1,
  timeTrialDistanceMeters: 5000,
  timeTrialDuration: const Duration(minutes: 22),
);

/// The parkrun regular: Saturdays, 5 km, timed, and no race anywhere.
RunnerProfile _parkrunProfile() => const RunnerProfile(
  currentWeeklyMeters: 20000,
  longestRecentMeters: 9000,
  daysPerWeek: 3,
  availableWeekdays: <int>{2, 4, 6},
  commitments: <PlanCommitment>[
    PlanCommitment(
      weekday: DateTime.saturday,
      distanceMeters: 5000,
      label: 'parkrun',
      timed: true,
    ),
  ],
  timeTrialDistanceMeters: 5000,
  timeTrialDuration: Duration(minutes: 26, seconds: 40),
);

/// A marathon they want to run one day, with nothing entered.
RunnerProfile _horizonProfile() => const RunnerProfile(
  goalDistanceMeters: 42195,
  currentWeeklyMeters: 32000,
  longestRecentMeters: 16000,
  daysPerWeek: 4,
  availableWeekdays: <int>{1, 3, 5, 7},
  timeTrialDistanceMeters: 5000,
  timeTrialDuration: Duration(minutes: 23),
);

/// Saturdays going back a few months, so the consistency count has something
/// real to count.
List<RunSummary> _parkrunHistory() {
  final now = DateTime.now();
  final saturday = now.subtract(Duration(days: (now.weekday - 6) % 7));
  return <RunSummary>[
    for (var i = 0; i < 11; i++)
      RunSummary(
        startedAt: saturday.subtract(Duration(days: 7 * i)),
        duration: Duration(seconds: 1600 - i * 4),
        distanceMeters: 5000,
        avgPaceSecondsPerKm: (1600 - i * 4) / 5,
      ),
  ];
}

/// A sane, complete profile for the confirmation-screen preview.
IntakeSlots _demoIntakeSlots() => IntakeSlots(
  goalDistanceMeters: 42195,
  eventDate: DateTime.now().add(const Duration(days: 112)),
  currentWeeklyMeters: 40000,
  longestRecentMeters: 18000,
  daysPerWeek: 5,
  availableWeekdays: const <int>{1, 2, 4, 6, 7},
  timeTrialDistanceMeters: 5000,
  timeTrialDuration: const Duration(minutes: 22),
);

/// A chat backend that has nothing left to give — the runner's own rate limit.
/// Exists so the harness can show that a refusal states its real reason.
class _LimitedChatClient implements CoachChatClient {
  @override
  Future<ChatTurn> chat({
    required String brief,
    required List<ChatMessage> history,
    required String message,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    throw const CoachLimitException(
      scope: 'daily_requests',
      retryAfterSeconds: 900,
      spendCapped: false,
    );
  }
}

/// The Plan tab with the conversation open, addressable by URL.
///
/// The dock's expanded states cannot be reached by tapping — Playwright drives
/// Flutter web through the URL, not the canvas — so each one is a key here. An
/// [opener] is sent on mount, which is how a transcript, a typing indicator, an
/// error line or the adaptation sheet gets on screen without a click.
class _ChatPreview extends StatefulWidget {
  const _ChatPreview({
    this.client = const _UnsetClient(),
    this.opener,
    this.withPlan = true,
    this.adapt = false,
    this.offline = false,
    this.remembered = false,
    this.onLogRunRequest,
    this.onApplyRun,
    this.editClient,
    this.livePlanClient,
    this.goalClient,
  });

  /// The chat backend. Defaults to the scripted fake.
  final CoachChatClient? client;

  /// Sent on mount, so a state that needs a turn can be reached by URL.
  final String? opener;

  final bool withPlan;

  /// Wires the adaptation hand-off, so an `adapt_week` intent opens the real
  /// diff sheet over the tab.
  final bool adapt;

  /// Docks the chat with no backend at all.
  final bool offline;

  /// Seeds a prior conversation and a rolling summary, so the dock opens on a
  /// restored transcript rather than on a blank one.
  final bool remembered;

  /// Reads a run out of what the runner said. Null keeps the route offline.
  final Future<RunProposal?> Function(String request)? onLogRunRequest;

  /// Confirms a run. Null means the card cannot be applied.
  final Future<bool> Function(RunProposal proposal)? onApplyRun;

  /// Reads a correction. Given one, the preview resolves the day against its
  /// own demo runs, exactly as the shell resolves against the real log.
  final CoachEditRunClient? editClient;

  /// A real plan client, so `adapt_week` can be exercised against the deployed
  /// coach rather than the scripted one.
  final PlanClient? livePlanClient;

  /// Reads a new target. The preview validates it against its own demo profile,
  /// exactly as the shell validates against the stored plan.
  final CoachSetGoalClient? goalClient;

  @override
  State<_ChatPreview> createState() => _ChatPreviewState();
}

/// A stand-in for "not passed", so `client: null` can mean offline.
class _UnsetClient implements CoachChatClient {
  const _UnsetClient();

  @override
  Future<ChatTurn> chat({
    required String brief,
    required List<ChatMessage> history,
    required String message,
  }) => throw UnimplementedError();
}

class _ChatPreviewState extends State<_ChatPreview> {
  late final RunnerProfile _profile = _demoProfile();
  late final PlanSkeleton _skeleton = buildSkeleton(
    _profile,
    now: DateTime.now(),
  );
  late final StoredPlan _plan = StoredPlan(
    id: 'preview',
    profile: _profile,
    skeleton: _skeleton,
    startDate: mondayOf(DateTime.now()),
  );

  /// The coach's memory for this preview. In memory rather than on disk — the
  /// harness has no database — but it is the real repository over the real
  /// store interface, so the loop it drives is the app's.
  final CoachMemoryRepository _memory = CoachMemoryRepository(
    store: InMemoryCoachMemoryStore(),
  );

  ChatController? _chat;

  /// A conversation from last week, and what the coach took from it.
  Future<void> _seedMemory() async {
    const said = <(CoachRole, String)>[
      (CoachRole.user, 'I can only really run before work, is that a problem?'),
      (
        CoachRole.assistant,
        'Not at all — early is fine, and consistent beats ideal. Just give '
            'yourself a few minutes to warm up when it is cold.',
      ),
      (CoachRole.user, 'My left calf tightens on the faster stuff.'),
      (
        CoachRole.assistant,
        'Then we keep the threshold work honest rather than hard, and I would '
            'rather you cut a rep than push through it. Tell me if it lingers '
            'past the warm-up.',
      ),
    ];
    for (final (role, text) in said) {
      await _memory.appendTurn(
        conversationId: 'preview-last-week',
        role: role,
        text: text,
      );
    }
    await _memory.replaceSummary(
      'They run before work and would rather not run in the dark. A left calf '
      'that tightens on faster sessions. Training for a first marathon and '
      'more anxious about the distance than the time.',
      turnsCovered: said.length,
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.offline) return;
    final client = widget.client is _UnsetClient
        ? FakeCoachService()
        : widget.client!;
    _chat = ChatController(
      client: client,
      brief: () async => CoachBrief.write(
        recentRuns: _demoRuns(),
        plan: widget.withPlan ? _plan : null,
        profile: _profile,
        // The always-loaded tier. Read from the store rather than hard-coded so
        // the preview exercises the same path the app does.
        rollingSummary: (await _memory.summary())?.text,
      ).text,
      onAdaptRequest: widget.adapt ? _propose : null,
      onApplyRevision: widget.adapt ? _apply : null,
      onLogRunRequest: widget.onLogRunRequest,
      onEditRunRequest: widget.editClient == null ? null : _proposeEdit,
      onSetGoalRequest: widget.goalClient == null ? null : _proposeGoal,
      // Applying is simulated: rebuilding a plan needs the on-device database,
      // and Drift's native backend is dart:io. What the harness is for is
      // seeing the card, and the card is real.
      onApplyGoal: widget.goalClient == null ? null : (_) async => true,
      onApplyRun: widget.onApplyRun,
      memory: _memory,
      summariser: client is CoachSummariseClient
          ? client as CoachSummariseClient
          : null,
    );
    if (widget.remembered) {
      unawaited(_seedMemory().then((_) => _chat!.restore()));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _openSheet();
      final opener = widget.opener;
      if (opener != null) unawaited(_chat!.send(opener));
    });
  }

  @override
  void dispose() {
    _chat?.dispose();
    super.dispose();
  }

  /// Proposes a validated revision the way the app does — no sheet. The dock
  /// offers it inside the conversation.
  /// The same resolution the shell does: the model names a day, and exactly
  /// one run on that day is required. Two, or none, and the card is refused.
  Future<RunProposal?> _proposeEdit(String request) async {
    final correction = await widget.editClient?.editRun(request);
    if (correction == null || !correction.isUsable) return null;

    final run = soleRunOn<RunSummary>(
      _demoRuns(),
      correction.on!,
      startedAt: (r) => r.startedAt,
    );
    if (run == null) return null;

    final existing = RunDraft(
      startedAt: run.startedAt,
      duration: run.duration,
      distanceMeters: run.distanceMeters,
      type: run.type,
      avgHr: run.avgHr,
    );
    final changed = correction.changes.onto(existing);
    if (!changed.isValid(DateTime.now())) return null;
    return RunProposal(draft: changed, runId: run.id ?? 'demo');
  }

  /// The same three refusals the shell makes: nothing usable read, a target the
  /// validator rejects, or one identical to what they already have.
  Future<GoalProposal?> _proposeGoal(String request) async {
    final change = await widget.goalClient?.setGoal(request);
    if (change == null || !change.isSomething) return null;

    final draft = change.onto(GoalDraft.from(_profile));
    if (!draft.isValid(DateTime.now())) return null;
    if (!draft.changes(_profile)) return null;

    return GoalProposal(
      draft: draft,
      shape: draft.shape,
      supersedes: _plan.weekIndexOn(DateTime.now()),
    );
  }

  Future<ChatProposal?> _propose(String request) async {
    final slot = _plan.weekOn(DateTime.now());
    final proposal =
        await AdaptationService(
          client: widget.livePlanClient ?? FakePlanClient(),
        ).propose(
          week: buildFallbackWeek(slot, _profile),
          slot: slot,
          profile: _profile,
          request: request,
        );
    if (proposal == null) return null;
    return ChatProposal(week: proposal.week, changes: proposal.changes);
  }

  Future<bool> _apply(TrainingWeek week) async => true;

  @override
  Widget build(BuildContext context) => Stack(
    children: <Widget>[
      PlanScreen(
        now: DateTime.now(),
        plan: widget.withPlan ? _plan : null,
        weeks: widget.withPlan
            ? <int, TrainingWeek>{
                1: buildFallbackWeek(_skeleton.weeks[0], _profile),
                2: buildFallbackWeek(_skeleton.weeks[1], _profile),
              }
            : const <int, TrainingWeek>{},
        onOpenWeek: (_, _) {},
        onBuildPlan: widget.withPlan ? null : () {},
      ),
      // The mark, so the harness shows what the tab actually carries. The real
      // one lives on the shell; this stands in for it in the isolated preview.
      if (!widget.offline)
        Positioned(
          right: AppSpacing.lg,
          bottom: AppSpacing.lg,
          child: CoachButton(onTap: _openSheet),
        ),
    ],
  );

  /// Opens the conversation the way the shell does, so the previews address the
  /// sheet rather than a dock that no longer exists.
  void _openSheet() => unawaited(
    CoachConversationSheet.show(
      context,
      controller: _chat,
      suggestions: <String>[
        if (widget.withPlan)
          'My calf is sore — can we move today’s run?'
        else
          'How should I get back into running?',
        'What could I run a half marathon in?',
        'How has my training been going?',
      ],
    ),
  );
}

/// Mounts the shell over an in-memory store that already holds a plan.
///
/// The coach tab's calendar only exists when a plan does, and a plan is created
/// through a conversation — which the harness cannot drive. Seeding the store
/// directly is the only way to review that state.
/// Which kind of plan the seeded coach is standing up.
enum _DemoShape { block, rhythm, horizon }

class _SeededCoach extends StatefulWidget {
  const _SeededCoach({
    this.tab = 1,
    this.shape = _DemoShape.block,
    this.unit = UnitSystem.metric,
  });

  /// Which unit the whole shell renders in.
  final UnitSystem unit;

  /// Which tab to open on — the Plan tab by default, Home for the ribbon.
  final int tab;

  final _DemoShape shape;

  @override
  State<_SeededCoach> createState() => _SeededCoachState();
}

class _SeededCoachState extends State<_SeededCoach> {
  final PlanStore _store = InMemoryPlanStore();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    PlanRepository(store: _store)
        .create(switch (widget.shape) {
          _DemoShape.block => _demoProfile(),
          _DemoShape.rhythm => _parkrunProfile(),
          _DemoShape.horizon => _horizonProfile(),
        })
        .then((_) => setState(() => _ready = true));
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return HomeShell(
      auth: FakeAuthRepository(signedIn: true, email: _fakeEmail),
      recorderFactory: () => FakeRunRecorder(),
      // Notable runs, so the dock shows what the coach has actually noticed
      // rather than its fallback copy. The plain set stays reachable through
      // the chat previews.
      historySource: () async => widget.shape == _DemoShape.rhythm
          ? _parkrunHistory()
          : _notableRuns(),
      coach: FakeCoachService(),
      planClient: FakePlanClient(),
      planStore: _store,
      unitSettings: InMemoryUnitSettings(unit: widget.unit),
      initialTab: widget.tab,
    );
  }
}

/// The calendar and block screens, seeded with the demo plan.
///
/// Both are pushed from the Plan tab in the app, so neither is reachable from
/// a URL without this — which is exactly how they went a design pass without
/// ever being looked at.
class _SeededPlanScreen extends StatefulWidget {
  const _SeededPlanScreen({required this.calendar});

  final bool calendar;

  @override
  State<_SeededPlanScreen> createState() => _SeededPlanScreenState();
}

class _SeededPlanScreenState extends State<_SeededPlanScreen> {
  final PlanStore _store = InMemoryPlanStore();
  StoredPlan? _plan;
  Map<int, TrainingWeek> _weeks = const <int, TrainingWeek>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = PlanRepository(store: _store);
    final plan = await repo.create(_demoProfile());
    final weeks = <int, TrainingWeek>{};
    final current = plan.weekIndexOn(DateTime.now());
    for (var i = current; i < current + kPlannedWeekHorizon; i++) {
      if (i < 1 || i > plan.skeleton.weeks.length) continue;
      weeks[i] = await repo.weekFor(plan, plan.skeleton.weeks[i - 1]);
    }
    if (mounted) setState(() => (_plan = plan, _weeks = weeks));
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    if (plan == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return widget.calendar
        ? PlanCalendarScreen(plan: plan, weeks: _weeks)
        : PlanBlockScreen(plan: plan);
  }
}

/// The session brief, opened over the Plan tab so the sheet has a page behind
/// it rather than floating on nothing.
class _SessionBriefPreview extends StatefulWidget {
  const _SessionBriefPreview({this.rest = false});

  final bool rest;

  @override
  State<_SessionBriefPreview> createState() => _SessionBriefPreviewState();
}

class _SessionBriefPreviewState extends State<_SessionBriefPreview> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final profile = _demoProfile();
      SessionBriefSheet.show(
        context,
        session: widget.rest
            ? null
            : const PlannedSession(
                weekday: 1,
                kind: SessionKind.threshold,
                distanceMeters: 6800,
              ),
        date: DateTime.now(),
        paces: profile.timeTrialDistanceMeters == null
            ? null
            : TrainingPaces.fromRace(
                Distance.meters(profile.timeTrialDistanceMeters!),
                profile.timeTrialDuration!,
              ),
        onAskCoach: (opener) => ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Asked: $opener'))),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const _SeededCoach();
}

/// A history whose latest run is a distance record, so Home shows a note.
List<RunSummary> _notableRuns() {
  final now = DateTime.now();
  return <RunSummary>[
    RunSummary(
      startedAt: now.subtract(const Duration(days: 1)),
      duration: const Duration(minutes: 96, seconds: 20),
      distanceMeters: 18400,
      avgPaceSecondsPerKm: 314,
      elevationGainMeters: 140,
      avgHr: 152,
      points: demoRunTrace(),
    ),
    ..._demoRuns(),
  ];
}

/// A canned finished run for the summary preview.
RunSummary _demoSummary() => RunSummary(
  startedAt: DateTime(2026, 7, 21, 7, 32),
  duration: const Duration(minutes: 27, seconds: 45),
  distanceMeters: 5230,
  avgPaceSecondsPerKm: (27 * 60 + 45) / 5.23,
  elevationGainMeters: 42,
  avgHr: 148,
  maxHr: 167,
  caloriesEst: 358,
  points: demoRunTrace(),
  splits: const <RunSplit>[
    RunSplit(
      index: 1,
      distanceMeters: 1000,
      duration: Duration(seconds: 322),
      avgHr: 141,
    ),
    RunSplit(
      index: 2,
      distanceMeters: 1000,
      duration: Duration(seconds: 316),
      avgHr: 146,
    ),
    RunSplit(
      index: 3,
      distanceMeters: 1000,
      duration: Duration(seconds: 330),
      avgHr: 149,
    ),
    RunSplit(
      index: 4,
      distanceMeters: 1000,
      duration: Duration(seconds: 312),
      avgHr: 152,
    ),
    RunSplit(
      index: 5,
      distanceMeters: 1000,
      duration: Duration(seconds: 305),
      avgHr: 158,
    ),
    RunSplit(
      index: 6,
      distanceMeters: 230,
      duration: Duration(seconds: 70),
      avgHr: 160,
    ),
  ],
);

/// A canned training log for the history preview. Distinct thumbnails come from
/// slicing/reversing the one demo trace; treadmill and manual runs have none.
List<RunSummary> _demoRuns() {
  final trace = demoRunTrace();
  return <RunSummary>[
    _demoSummary(),
    RunSummary(
      startedAt: DateTime(2026, 7, 18, 8, 5),
      duration: const Duration(minutes: 54, seconds: 12),
      distanceMeters: 10120,
      avgPaceSecondsPerKm: (54 * 60 + 12) / 10.12,
      elevationGainMeters: 88,
      avgHr: 151,
      points: trace.reversed.toList(),
    ),
    RunSummary(
      startedAt: DateTime(2026, 7, 14, 18, 20),
      duration: const Duration(minutes: 38, seconds: 2),
      distanceMeters: 8000,
      avgPaceSecondsPerKm: (38 * 60 + 2) / 8,
      elevationGainMeters: 55,
      avgHr: 165,
      points: trace.sublist(0, 250),
    ),
    RunSummary(
      startedAt: DateTime(2026, 7, 10, 7),
      duration: const Duration(minutes: 26, seconds: 40),
      distanceMeters: 5000,
      avgPaceSecondsPerKm: 320,
      avgHr: 150,
      type: 'treadmill',
    ),
    RunSummary(
      startedAt: DateTime(2026, 7, 8, 7, 15),
      duration: const Duration(minutes: 33, seconds: 30),
      distanceMeters: 6000,
      avgPaceSecondsPerKm: 335,
      elevationGainMeters: 30,
      avgHr: 145,
      points: trace.sublist(120),
    ),
    RunSummary(
      startedAt: DateTime(2026, 7, 5, 9),
      duration: const Duration(minutes: 57, seconds: 30),
      distanceMeters: 10000,
      avgPaceSecondsPerKm: 345,
      type: 'manual',
    ),
  ];
}

/// One week's sessions, optionally opened on the day the runner tapped.
WeekDetailScreen _weekDetail({int? focusedWeekday}) {
  final profile = _demoProfile();
  final slot = buildSkeleton(profile, now: DateTime.now()).weeks[5];
  return WeekDetailScreen(
    week: buildFallbackWeek(slot, profile),
    slot: slot,
    profile: profile,
    focusedWeekday: focusedWeekday,
    adaptation: AdaptationService(client: FakePlanClient()),
    paces: TrainingPaces.fromRace(
      Distance.meters(profile.timeTrialDistanceMeters!),
      profile.timeTrialDuration!,
    ),
  );
}

/// Stateful preview of the plan + today card, so marking today's session done /
/// skipped is interactive without going through onboarding.
class _PlanPreview extends StatefulWidget {
  const _PlanPreview();

  @override
  State<_PlanPreview> createState() => _PlanPreviewState();
}

class _PlanPreviewState extends State<_PlanPreview> {
  SessionStatus _status = SessionStatus.planned;

  @override
  Widget build(BuildContext context) {
    final profile = _demoProfile();
    final skeleton = buildSkeleton(profile, now: DateTime.now());
    final paces = TrainingPaces.fromRace(
      Distance.meters(profile.timeTrialDistanceMeters!),
      profile.timeTrialDuration!,
    );
    // A build-week session so the card shows a real workout, not a rest day.
    final slot = skeleton.weeks[5];
    final today = buildFallbackWeek(slot, profile).runs.first;

    return PlanArcScreen(
      skeleton: skeleton,
      profile: profile,
      onReplacePlan: () => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Would confirm, then rebuild the plan.')),
      ),
      onOpenWeek: (week) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => WeekDetailScreen(
            week: buildFallbackWeek(week, profile),
            slot: week,
            profile: profile,
            adaptation: AdaptationService(client: FakePlanClient()),
            paces: paces,
          ),
        ),
      ),
      todayCard: TodayCard(
        session: today,
        phase: slot.phase,
        status: _status,
        paces: paces,
        onComplete: () => setState(() => _status = SessionStatus.completed),
        onSkip: () => setState(() => _status = SessionStatus.skipped),
        onReset: _status == SessionStatus.planned
            ? null
            : () => setState(() => _status = SessionStatus.planned),
      ),
    );
  }
}

class PreviewApp extends StatelessWidget {
  const PreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    final params = Uri.base.queryParameters;
    final key = params['screen'];
    final builder = _screens[key];
    final content = builder ?? (_) => _Index(keys: _screens.keys.toList());

    // Whether the screen is mounted *on top of* a route rather than as the root.
    //
    // An AppBar only draws a back arrow when `Navigator.canPop()` is true, so a
    // screen previewed at the root of the stack shows none however correctly it
    // is configured — the harness, not the screen, was hiding it. Screens the
    // app pushes (settings, profile, a run summary) should be reviewed this way;
    // tabs and the welcome screen should not, since they *are* roots.
    // **On by default**, and that is a change from `&pushed=1`. Opt-in put the
    // burden on whoever remembered the flag, and Lift's harness — written after
    // this comment, and without it — defaulted to root-mounted screens and
    // reported a screen with a perfectly good back arrow as a dead end during
    // the 2026-08-08 exit sweep. A default that hides a whole class of fault is
    // not a default worth keeping. `&pushed=0` opts out, for checking how a
    // screen behaves when it genuinely is the root.
    final pushed = params['pushed'] != '0';

    return MaterialApp(
      title: 'Runio Preview',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      // A multi-segment initialRoute makes Flutter build one route per segment,
      // so '/pushed' yields an underlay with the screen on top of it — a real
      // two-entry stack, which is what makes the back arrow appear. Named routes
      // rather than onGenerateInitialRoutes: MaterialApp still requires a home
      // or a route table, and supplying only the initial-route generator leaves
      // it with nothing to build (which rendered a blank page).
      initialRoute: pushed ? '/pushed' : '/',
      routes: <String, WidgetBuilder>{
        '/': pushed ? (_) => const _PreviewUnderlay() : content,
        if (pushed) '/pushed': content,
      },
    );
  }
}

/// What sits beneath a pushed preview, so back has somewhere to land.
class _PreviewUnderlay extends StatelessWidget {
  const _PreviewUnderlay();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Text(
        'Preview underlay — the screen above was pushed onto this.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
      ),
    ),
  );
}

class _Index extends StatelessWidget {
  const _Index({required this.keys});

  final List<String> keys;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Runio · screen preview')),
      body: ListView(
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Append ?screen=<key> to the URL to preview a screen:'),
          ),
          for (final k in keys)
            ListTile(dense: true, title: Text(k), subtitle: Text('?screen=$k')),
        ],
      ),
    );
  }
}

/// Onboarding against the **deployed** coach, signed in as the first dev
/// account in `config/app_config.json`.
///
/// This route exists because the harness could not previously tell you anything
/// about intake. `FakeCoachService` is a step counter: it returns the next
/// scripted line whatever you type, which is exactly right for checking the
/// typing animation and exactly wrong for checking whether the model can hold a
/// conversation. Rhythm and horizon were proven from the domain down and had
/// never been walked through this screen.
///
/// It signs in rather than assuming a session: the harness is a fresh browser
/// profile most times it is opened, and an unauthenticated call is a 401 that
/// looks like a broken coach.
class _LiveOnboarding extends StatefulWidget {
  const _LiveOnboarding();

  @override
  State<_LiveOnboarding> createState() => _LiveOnboardingState();
}

class _LiveOnboardingState extends State<_LiveOnboarding> {
  String? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_signIn());
  }

  Future<void> _signIn() async {
    final config = AppConfig.current;
    if (!config.isConfigured) {
      setState(
        () => _error =
            'No Supabase config. Run the harness with\n'
            '--dart-define-from-file=config/app_config.json',
      );
      return;
    }
    final accounts = config.devAccounts;
    if (accounts.isEmpty) {
      setState(
        () => _error =
            'No DEV_ACCOUNT_1_EMAIL / _PASSWORD in config/app_config.json.',
      );
      return;
    }
    try {
      final auth = Supabase.instance.client.auth;
      if (auth.currentSession == null) {
        await auth.signInWithPassword(
          email: accounts.first.email,
          password: accounts.first.password,
        );
      }
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Sign-in failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
        ),
      );
    }
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return OnboardingScreen(
      controller: OnboardingController(coach: CoachService()),
      onReview: (slots) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProfileConfirmationScreen(
            slots: slots,
            onConfirm: (_) => ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Profile confirmed.'))),
          ),
        ),
      ),
    );
  }
}

/// The coach conversation against the **deployed** function, signed in as the
/// first dev account.
///
/// The only chat route that spends money, and the only one that can show an
/// intent actually being raised: `_ChatPreview` drives a scripted client, so it
/// can show what a proposal card looks like but never that the model produced
/// one.
///
/// **Applying is simulated here.** The real path writes through `RunEditor`
/// into Drift, and Drift's native backend is `dart:io` — unavailable on web.
/// So this returns success and shows the applied state; whether the row lands
/// is covered by the editor's own tests, not by this.
class _LiveChat extends StatefulWidget {
  const _LiveChat();

  @override
  State<_LiveChat> createState() => _LiveChatState();
}

class _LiveChatState extends State<_LiveChat> {
  String? _error;
  bool _ready = false;
  CoachService? _coach;

  @override
  void initState() {
    super.initState();
    unawaited(_signIn());
  }

  Future<void> _signIn() async {
    final config = AppConfig.current;
    if (!config.isConfigured) {
      setState(
        () => _error =
            'No Supabase config. Run with\n'
            '--dart-define-from-file=config/app_config.json',
      );
      return;
    }
    final accounts = config.devAccounts;
    if (accounts.isEmpty) {
      setState(() => _error = 'No DEV_ACCOUNT_1_* in config/app_config.json.');
      return;
    }
    try {
      final auth = Supabase.instance.client.auth;
      if (auth.currentSession == null) {
        await auth.signInWithPassword(
          email: accounts.first.email,
          password: accounts.first.password,
        );
      }
      if (mounted) {
        setState(() {
          _coach = CoachService();
          _ready = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Sign-in failed: $e');
    }
  }

  /// The same shape as the shell's handler: read the run, validate it, and only
  /// then offer it. An invalid draft becomes null so the dock says it could not
  /// make a run out of that, rather than offering one that would be refused.
  Future<RunProposal?> _proposeRun(String request) async {
    final draft = await _coach?.logRun(request);
    if (draft == null || !draft.isValid(DateTime.now())) return null;
    return RunProposal(draft: draft);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
        ),
      );
    }
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _ChatPreview(
      client: _coach,
      onLogRunRequest: _proposeRun,
      editClient: _coach,
      livePlanClient: _coach,
      goalClient: _coach,
      // adapt against the real coach, not the scripted plan client.
      adapt: true,
      // Simulated — see the class doc.
      onApplyRun: (_) async => true,
    );
  }
}
