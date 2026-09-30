/// **The one runner every shell-driven plate is built around.**
///
/// Lifted out of `shell.dart` when `flows.dart` needed the same seed. Two
/// copies of a fixture is the same failure as two copies of a derivation: the
/// board would keep drawing, and the screen behind `A1` would quietly stop
/// being the screen behind `X3`. The header on `shell.dart` explains at length
/// why a thin fixture makes a board lie; a *forked* one lies more slowly and is
/// harder to notice.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/preview/fake_coach_service.dart';
import 'package:mgk_run/preview/fake_purchases.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/auth/data/auth_repository.dart';
import 'package:mgk_run/src/features/coaching/data/drift_plan_store.dart';
import 'package:mgk_run/src/features/coaching/data/purchase_client.dart';
import 'package:mgk_run/src/features/coaching/domain/ai_consent.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_access.dart';
import 'package:mgk_run/src/features/history/data/run_editor.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';
import 'package:mgk_run/src/features/legal/domain/disclaimer_store.dart';
import 'package:mgk_run/src/features/settings/domain/unit_settings.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/features/coaching/data/plan_store.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_offer.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:mgk_run/src/features/recording/domain/best_effort.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';
import 'package:mgk_run/src/features/recording/domain/run_recorder.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

/// A runner training for a marathon, available every day so today always has a
/// session — the plate would otherwise show a rest day about half the time it
/// was regenerated, which is a board that changes what it claims depending on
/// when you look at it.
///
/// [racingIn] moves race day relative to today, which is the whole of what
/// separates an ordinary Tuesday from the taper, the day itself and the morning
/// after (ADR-0027). Everything downstream is derived by the app.
RunnerProfile plateProfile({int racingIn = 112}) => RunnerProfile(
  goalDistanceMeters: 42195,
  eventDate: dateOnly(DateTime.now().add(Duration(days: racingIn))),
  currentWeeklyMeters: 40000,
  longestRecentMeters: 18000,
  daysPerWeek: 7,
  availableWeekdays: const <int>{1, 2, 3, 4, 5, 6, 7},
  timeTrialDistanceMeters: 5000,
  timeTrialDuration: const Duration(minutes: 22),
);

/// Runs behind them, so the log, the records and the year all have something
/// real to draw rather than their empty states.
List<RunSummary> plateLog() {
  final now = DateTime.now();
  return <RunSummary>[
    for (var i = 1; i < 40; i++)
      if (i % 2 == 1)
        RunSummary(
          id: 'plate-$i',
          startedAt: now.subtract(Duration(days: i)),
          duration: Duration(minutes: 28 + (i % 9) * 6),
          distanceMeters: 5200 + (i % 9) * 1800,
          avgPaceSecondsPerKm:
              (28 + (i % 9) * 6) * 60 / ((5200 + (i % 9) * 1800) / 1000),
          // Its own shape, so the log tells two runs apart before a word of it
          // is read — see [plateRoute].
          points: plateRoute(i),
          bestEfforts: <BestEffort>[
            if (5200 + (i % 9) * 1800 >= 5000)
              BestEffort(
                distanceMeters: 5000,
                duration: Duration(seconds: 1500 + (i % 7) * 20),
              ),
          ],
        ),
  ];
}

/// Pumps rather than settles.
///
/// The shell loads its plan, its log and its coach asynchronously and then the
/// coach mark plays a 3.4-second reveal, so `pumpAndSettle` would either hang
/// on the animation or land on whichever frame it stopped at. Fixed pumps put
/// the picture at a chosen moment instead.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// Pumps until the coach mark has finished saying its piece and rests.
///
/// **A plate of a tab is a plate of the tab, not of the mark mid-sentence.**
/// The mark plays its line for 3.4 seconds after the shell loads — the
/// observation for a subscriber, the locked line for everybody else — and
/// [settle] stops at 1.4 seconds, so every shell plate on the September board
/// had a half-typed coach line lying across the card at the fold. The line has
/// plates of its own (`C1`, `C6`); everywhere else waits for it to finish.
Future<void> rest(WidgetTester tester) async {
  await settle(tester);
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// **A runner three weeks into their block**, rather than one who built it
/// this morning.
///
/// A plan starts on the coming Monday (ADR-0034), so a plan created "now" is a
/// plan that has not started — and that is a real, separate state with its own
/// plate (`H6`). The ordinary Tuesday of a runner on a plan is somebody some
/// weeks in, so the repository's clock is wound back to build it then.
Future<StoredPlan> seedPlan(
  PlanStore store, {
  int racingIn = 112,
  int weeksIn = 3,
}) {
  final builtOn = dateOnly(
    DateTime.now().subtract(Duration(days: 7 * weeksIn)),
  );
  return PlanRepository(
    store: store,
    now: () => builtOn,
  ).create(plateProfile(racingIn: racingIn));
}

/// **What the stores will actually show on the paywall**, not the preview's
/// placeholder copy.
///
/// Titles and descriptions come from App Store Connect and the Play Console
/// (`docs/store-setup.md` §2, ADR-0041), and so do the prices. `FakePurchases`
/// still carries the September wording ("A better model behind every plan"),
/// which is the line the test sheet's G6 row says means the store was never
/// updated — drawing it here would put that failure on the board as the design.
const List<CoachOffer> plateOffers = <CoachOffer>[
  CoachOffer(
    id: 'run.coach.monthly',
    title: 'Coach',
    description: 'A training plan, adjusted every week.',
    price: '£0.99',
  ),
  CoachOffer(
    id: 'run.coach.premium.monthly',
    title: 'Premium Coach',
    description: 'A better AI model and a bigger allowance.',
    price: '£2.99',
  ),
];

/// **The seeded app with every seam a destination needs actually plugged in.**
///
/// Lifted out of `flows.dart` when `coach.dart` needed the same shell: the
/// shell hides a control it cannot honour — no `runEditor` and there is no
/// "Add a run", no chat client and the coach mark is absent rather than inert —
/// so a board built on a half-wired shell shows a smaller app than the one that
/// ships, and does it silently.
///
/// **The tier is pinned, never inferred.** For an unsubscribed runner the mark
/// is a door to the gate sheet rather than the conversation, and the shell
/// defaults to free — so a plate that forgot to say which tier it meant drew a
/// valid PNG of the wrong screen, which is the one failure a board cannot
/// notice about itself.
///
/// **So is the coach's permission.** Since build 26 every way into the coach
/// asks first ("Before your coach answers"), and the shell's default store is
/// the account's, which a test does not have — so a plate that did not say
/// drew the consent sheet in place of whatever it was about. [aiConsent] and
/// [disclaimer] default to already answered; the plates *about* asking pass
/// fresh ones.
HomeShell plateApp(
  AppDatabase db,
  DriftPlanStore store,
  List<RunSummary> runs, {
  int initialTab = 0,
  CoachAccess access = CoachAccess.subscribed,
  AuthRepository? auth,
  AiConsentStore? aiConsent,
  DisclaimerStore? disclaimer,
  PurchaseClient? purchases,
  RunRecorder Function()? recorderFactory,
  Future<List<RunSummary>> Function()? historySource,
}) => HomeShell(
  // With a name on it: the fake defaults to none, and Settings then correctly
  // draws "Nothing in particular" against the row that holds what the coach
  // was told — an empty state reported as the design.
  auth:
      auth ??
      FakeAuthRepository(
        signedIn: true,
        email: 'runner@example.com',
        name: 'Sam',
      ),
  planStore: store,
  historySource: historySource ?? () async => runs,
  recorderFactory: recorderFactory,
  coach: FakeCoachService(),
  runEditor: RunEditor(db: db),
  unitSettings: InMemoryUnitSettings(),
  initialTab: initialTab,
  access: access,
  aiConsent: aiConsent ?? InMemoryAiConsentStore.granted(),
  disclaimer: disclaimer ?? InMemoryDisclaimerStore(acknowledged: true),
  // A shop, so the gate draws the state that ships rather than the state a
  // build with no RevenueCat key falls back to.
  purchases: purchases ?? FakePurchases(offers: plateOffers),
  entitlements: FakeEntitlements(access),
);

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// **A different route for every run, because that is the feature.**
///
/// The log draws each run's trace as its thumbnail, so two runs are told apart
/// by their shape before a word is read. Every plate fixture on this board used
/// to build runs with no points at all, and `RouteThumbnail` correctly falls
/// back to a type glyph when a run has no route — so the board drew a column
/// of identical glyphs and reported a shipped feature as missing. It is the
/// thin-fixture failure exactly: the screen was right, the picture was not.
///
/// Runs somebody typed in still get no route, and should not: a treadmill
/// session has no shape, and the glyph is the correct answer for it.
///
/// The curve is a closed loop whose lobes, stretch and rotation all come off
/// [seed], so the shapes differ from each other the way real routes do rather
/// than being one route drawn at different sizes.
List<RunPoint> plateRoute(int seed, {int samples = 30}) {
  const double lat = 51.2300, lng = -0.2050;
  final int lobes = 2 + seed % 4;
  final double stretch = 0.6 + (seed % 5) * 0.18;
  final double turn = (seed % 7) * 0.9;
  final DateTime start = DateTime(2026, 8, 20, 7);
  return <RunPoint>[
    for (var i = 0; i <= samples; i++)
      () {
        final double t = i / samples * 2 * math.pi;
        final double r = 1 + 0.35 * math.sin(lobes * t);
        return RunPoint(
          latitude: lat + 0.010 * math.sin(t + turn) * stretch * r,
          longitude: lng + 0.015 * math.cos(t + turn) * r,
          accuracyMeters: 6,
          timestamp: start.add(Duration(seconds: i * 40)),
        );
      }(),
  ];
}

/// **[screen] as the app shows it: pushed, with a way back.**
///
/// A screen handed straight to a plate is the root route, so its app bar has
/// no back control — Settings, Privacy & legal and Delete account were all
/// drawn as if they were the first screen of the app, which none of them is.
/// This pushes [screen] over an empty page on the first frame, so the chrome
/// is the chrome a runner meets.
Widget pushed(Widget screen) => _Pushed(screen);

class _Pushed extends StatefulWidget {
  const _Pushed(this.screen);

  final Widget screen;

  @override
  State<_Pushed> createState() => _PushedState();
}

class _PushedState extends State<_Pushed> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => widget.screen));
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold();
}
