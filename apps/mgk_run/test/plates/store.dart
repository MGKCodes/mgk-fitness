/// **The store's screenshots: the six listed screens, drawn with the real map
/// and a runner whose figures the shipped app could have produced.**
///
/// The board's plates are not usable in a shop window, for two reasons this
/// file exists to remove.
///
/// **They have no map.** The test framework answers every network request with
/// a 400, which is right for a board and wrong here: the map is half of what
/// the in-run shot is for. The stub is taken off in this file only, and each
/// shot waits for its tiles the way a phone does.
///
/// **Their fixtures show what the app does not do.** The board's finished run
/// carries elevation, because the layout has to be judged with every tile in
/// it. A listing is read as a promise, and the app records no elevation and no
/// heart rate (`docs/app-store-listing.md`, "What the app may not claim"). The
/// runner here has neither, has steps and cadence on iPhone only, and ran this
/// week's sessions as the plan set them.
///
/// Written to `store-assets/derived/screens/`, not to `plates/`: these are
/// inputs to the captioned mockups (`design/store-shots`), not board plates.
///
/// Needs the app's real configuration, for the tile address:
///
///     flutter test test/plates/store.dart \
///       --dart-define-from-file=config/app_config.json
///
/// Without it the maps are drawn on a plain ground, as everywhere else.
///
/// **Home's greeting follows the real clock**, so a set drawn in the evening
/// says "Evening". The status bar is drawn afterwards, by the mockups, and has
/// to agree: this file writes the time it should show to `clock.json` beside
/// the screens, and `render.sh` hands it on.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_run_recorder.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/coaching/data/coach_client.dart';
import 'package:mgk_run/src/features/coaching/data/drift_plan_store.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/features/coaching/domain/pace_model.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/presentation/session_labels.dart';
import 'package:mgk_run/src/features/history/domain/run_draft.dart';
import 'package:mgk_run/src/features/profile/presentation/year_grid.dart';
import 'package:mgk_run/src/features/recording/domain/best_effort.dart';
import 'package:mgk_run/src/features/recording/domain/live_metrics.dart';
import 'package:mgk_run/src/features/recording/domain/route_metrics.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';
import 'package:mgk_run/src/features/recording/presentation/recording_screen.dart';
import 'package:mgk_run/src/features/recording/presentation/run_summary_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';

import 'fixture.dart';
import 'plate.dart';
import 'store_route.dart';

/// Where the screens are written, from `apps/mgk_run`.
const String kStoreScreens = '../../store-assets/derived/screens';

/// **A phone a store asks for.**
///
/// The iPhone is the 6.9" size App Store Connect takes (1290x2796). The
/// Android one is 1080x2160: Play refuses a screenshot whose long side is more
/// than twice its short side, which rules out the shape most Android phones
/// actually are.
class StorePhone {
  const StorePhone({
    required this.name,
    required this.size,
    required this.pixelRatio,
    required this.platform,
    required this.safeArea,
  });

  final String name;
  final Size size;
  final double pixelRatio;
  final TargetPlatform platform;
  final EdgeInsets safeArea;

  bool get isIphone => platform == TargetPlatform.iOS;
}

const List<StorePhone> kStorePhones = <StorePhone>[
  StorePhone(
    name: 'iphone',
    size: kMaxPhone,
    pixelRatio: 3,
    platform: TargetPlatform.iOS,
    safeArea: EdgeInsets.only(top: 59, bottom: 34),
  ),
  StorePhone(
    name: 'android',
    size: Size(432, 864),
    pixelRatio: 2.5,
    platform: TargetPlatform.android,
    safeArea: EdgeInsets.only(top: 40, bottom: 20),
  ),
];

/// Lets real requests finish: a tile is fetched and decoded on the real
/// clock, which the test's own clock never advances.
///
/// **Many short turns, not one long wait.** A request started inside a test
/// lives in the test's zone, so each step of it (the connection, the headers,
/// every chunk of the body, the decode) is handed on only when the test
/// pumps. One ten-second wait is one step.
Future<void> letTheMapLoad(WidgetTester tester, {int turns = 160}) async {
  for (var i = 0; i < turns; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Takes the screen down and runs out whatever it left on the test's clock,
/// so a shot that drew a live screen does not fail on a timer still pending.
Future<void> putAway(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(minutes: 2));
}

/// **The runner in the pictures.** A marathon sixteen weeks out, five days a
/// week, off a 22-minute 5k: the same numbers as the board's runner, on the
/// number of days most people actually train.
///
/// Today is always a running day, whichever day the set is drawn on. A rest
/// day is a real screen and not the one that says what the app is for.
RunnerProfile storeProfile() {
  final int today = DateTime.now().weekday;
  final Set<int> rest = <int>[
    DateTime.monday,
    DateTime.friday,
    DateTime.wednesday,
  ].where((d) => d != today).take(2).toSet();
  return RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: dateOnly(DateTime.now().add(const Duration(days: 112))),
    currentWeeklyMeters: 40000,
    longestRecentMeters: 18000,
    daysPerWeek: 5,
    availableWeekdays: <int>{
      for (var d = 1; d <= 7; d++)
        if (!rest.contains(d)) d,
    },
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 22),
  );
}

/// Seconds a kilometre this runner holds for each kind of session, inside the
/// bands their 5k sets (`pace_model.dart`).
double _paceFor(SessionKind kind) => switch (kind) {
  SessionKind.recovery => 398,
  SessionKind.long => 371,
  SessionKind.marathonPace => 318,
  // A threshold or interval session is warmed up and cooled down, so the
  // average over the whole run is well short of the pace of the hard part.
  SessionKind.threshold => 312,
  SessionKind.interval => 318,
  SessionKind.timeTrial => 264,
  _ => 366,
};

RunSummary _run({
  required int n,
  required DateTime day,
  required double meters,
  SessionKind kind = SessionKind.easy,
  bool treadmill = false,
}) {
  final math.Random random = math.Random(n * 7919);
  // Nobody stops on the kilometre. A little over, and a pace a few seconds
  // either side of the one they meant.
  final double ran = meters + 20 + random.nextInt(160);
  final double pace = _paceFor(kind) - 5 + random.nextInt(11);
  final Duration duration = Duration(seconds: (ran / 1000 * pace).round());
  final bool weekend = day.weekday >= DateTime.saturday;
  return RunSummary(
    id: 'store-$n',
    startedAt: DateTime(
      day.year,
      day.month,
      day.day,
      weekend ? 8 : 18,
      5 + random.nextInt(40),
    ),
    duration: duration,
    distanceMeters: ran,
    avgPaceSecondsPerKm: pace,
    type: treadmill ? kTypeTreadmill : kTypeOutdoor,
    points: treadmill ? const <RunPoint>[] : plateRoute(n),
    bestEfforts: <BestEffort>[
      for (final double d in const <double>[5000, 10000, 21097.5])
        if (ran >= d)
          BestEffort(
            distanceMeters: d,
            // The quickest stretch of a steady run is a little quicker than
            // the whole of it.
            duration: Duration(seconds: (d / 1000 * (pace - 4)).round()),
          ),
    ],
  );
}

/// **A year of running that leads up to the plan, and the plan run as set.**
///
/// Before the block: three runs a week growing to four, a long run that
/// lengthens through the year, a fortnight missed over Christmas and a week in
/// the spring, some winter runs on a treadmill. During it: each session the
/// plan has asked for so far, on its day, at about its distance. That is what
/// lets Home say "2 of 5" and the last run answer the session it was for.
Future<List<RunSummary>> storeLog(StoredPlan plan, PlanRepository repo) async {
  final DateTime today = dateOnly(DateTime.now());
  final List<RunSummary> runs = <RunSummary>[];
  var n = 0;

  for (final SkeletonWeek slot in plan.skeleton.weeks) {
    if (slot.index > plan.weekIndexOn(today)) break;
    final TrainingWeek week = await repo.weekFor(plan, slot);
    for (final PlannedSession session in week.runs) {
      final DateTime day = plan.dateFor(
        weekIndex: slot.index,
        weekday: session.weekday,
      );
      if (!day.isBefore(today)) continue;
      runs.add(
        _run(
          n: ++n,
          day: day,
          meters: session.distanceMeters,
          kind: session.kind,
        ),
      );
    }
  }

  // The 5k the plan's paces came from, the weekend before it began.
  runs.add(
    RunSummary(
      id: 'store-time-trial',
      startedAt: addDays(plan.startDate, -2).add(const Duration(hours: 9)),
      duration: const Duration(minutes: 22),
      distanceMeters: 5000,
      avgPaceSecondsPerKm: 264,
      points: plateRoute(3),
      bestEfforts: const <BestEffort>[
        BestEffort(distanceMeters: 5000, duration: Duration(minutes: 22)),
      ],
    ),
  );

  final DateTime firstMonday = addDays(mondayOf(plan.startDate), -7 * 48);
  for (var w = 0; w < 48; w++) {
    final DateTime monday = addDays(firstMonday, w * 7);
    final bool christmas =
        (monday.month == 12 && monday.day >= 20) ||
        (monday.month == 1 && monday.day <= 3);
    final bool spring = w == 27;
    if (christmas || spring) continue;
    // 0 at the start of the year, 1 at the start of the plan.
    final double grown = w / 47;
    final bool winter = monday.month == 12 || monday.month <= 2;
    final double easy = 4000 + 3000 * grown;
    runs.add(
      _run(
        n: ++n,
        day: addDays(monday, 1),
        meters: easy,
        treadmill: winter && w.isEven,
      ),
    );
    runs.add(_run(n: ++n, day: addDays(monday, 3), meters: easy + 1000));
    if (w > 20 && w % 5 != 0) {
      runs.add(_run(n: ++n, day: addDays(monday, 5), meters: easy - 1000));
    }
    // The last week of the forty-eight ended in the time trial instead.
    if (w < 47) {
      runs.add(
        _run(
          n: ++n,
          day: addDays(monday, 6),
          meters: 8000 + 10000 * grown,
          kind: SessionKind.long,
        ),
      );
    }
  }

  runs.sort((a, b) => b.startedAt.compareTo(a.startedAt));
  return runs;
}

/// The run in the two map shots: [kStoreRoute], an easy six kilometres round
/// Regent's Park, as the recorder would have written it.
List<RunPoint> storeTrace(DateTime start) => <RunPoint>[
  for (var i = 0; i < kStoreRoute.length; i++)
    RunPoint(
      latitude: kStoreRoute[i][0],
      longitude: kStoreRoute[i][1],
      accuracyMeters: 5,
      timestamp: start.add(Duration(seconds: i * 3)),
    ),
];

/// **The finished run, with only what a recorded run has.** No elevation and
/// no heart rate on either phone. Steps, and the cadence drawn from them, on
/// iPhone only: they are read from Apple Health, and Android reads nothing.
RunSummary storeRun({required bool withSteps}) {
  final DateTime now = DateTime.now();
  final List<RunPoint> points = storeTrace(
    now.subtract(Duration(seconds: kStoreRoute.length * 3 + 40)),
  );
  final double meters = processedDistanceMeters(points);
  final Duration duration = points.last.timestamp.difference(
    points.first.timestamp,
  );
  return RunSummary(
    id: 'store-today',
    startedAt: points.first.timestamp,
    duration: duration,
    distanceMeters: meters,
    avgPaceSecondsPerKm: duration.inSeconds / (meters / 1000),
    // 166 steps a minute: an easy run's cadence.
    steps: withSteps ? (duration.inSeconds / 60 * 166).round() : null,
    points: points,
    splits: splitsFor(points),
    bestEfforts: bestEffortsFor(points),
  );
}

/// **The coach in picture 5. Scripted, and said to be.**
///
/// Nothing here can reach the real coach, so the reply is written by hand, the
/// way the preview's fake writes its own. That fake says "the last few miles"
/// to a runner whose app is in kilometres, which the real coach would not, and
/// a shop window is the wrong place for it. Same answer, the runner's units.
///
/// The time is not invented: a 22-minute 5k predicts 1:41 for a half by the
/// same rule the plan's paces come from (`pace_model.dart`).
///
/// The test sheet's H3 asks for a reply the real coach gave to this question.
/// When there is one, it goes here word for word.
class StoreCoach implements CoachChatClient {
  const StoreCoach();

  @override
  Future<ChatTurn> chat({
    required String brief,
    required List<ChatMessage> history,
    required String message,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 650));
    return const ChatTurn(
      reply:
          'Off your recent 5k, a half around 1:42 looks right today, and '
          'that comes down as the long runs stack up. The number to watch is '
          'how the last few kilometres feel, not the split.',
    );
  }
}

const PlannedSession kStoreSession = PlannedSession(
  weekday: DateTime.thursday,
  kind: SessionKind.easy,
  distanceMeters: 6000,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The framework stubs every HTTP request with a 400. Off, for this file
  // only.
  setUp(() => HttpOverrides.global = null);

  // The map keeps the tiles it draws in the app's cache directory, and a
  // test has no app. A scratch folder stands in for it.
  final Directory scratch = Directory.systemTemp.createTempSync('run-tiles');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => scratch.path,
      );

  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// The runner's plan, three weeks in, and the log that goes with it.
  Future<(DriftPlanStore, StoredPlan, List<RunSummary>)> runner() async {
    final DriftPlanStore store = DriftPlanStore(db);
    final DateTime builtOn = dateOnly(
      DateTime.now().subtract(const Duration(days: 21)),
    );
    await PlanRepository(
      store: store,
      now: () => builtOn,
    ).create(storeProfile());
    final PlanRepository repo = PlanRepository(store: store);
    final StoredPlan plan = (await repo.load())!;
    return (store, plan, await storeLog(plan, repo));
  }

  // The status bar is not the app's to draw, so it is not in these pictures.
  // What it should read is, because Home says "Morning", "Afternoon" or
  // "Evening" off the real clock and a status bar at 18:41 over "Morning" is
  // the kind of thing a reviewer sees first. One time for each, read off the
  // same function Home's greeting uses.
  test('the clock the set was drawn by', () {
    final String time = switch (timeOfDayName(DateTime.now())) {
      'Morning' => '09:41',
      'Afternoon' => '14:41',
      _ => '18:41',
    };
    Directory(kStoreScreens).createSync(recursive: true);
    File('$kStoreScreens/clock.json').writeAsStringSync('{"time": "$time"}\n');
  });

  for (final StorePhone phone in kStorePhones) {
    Future<void> shot(
      WidgetTester tester,
      String name,
      Widget child, {
      Future<void> Function(WidgetTester tester)? drive,
    }) => plate(
      tester,
      name,
      child,
      size: phone.size,
      pixelRatio: phone.pixelRatio,
      platform: phone.platform,
      safeArea: phone.safeArea,
      into: '$kStoreScreens/${phone.name}',
      drive: drive,
    );

    group(phone.name, () {
      testWidgets('1. home, with a plan and today\'s session', (tester) async {
        final (store, _, runs) = await runner();
        await shot(tester, '1-home', plateApp(db, store, runs), drive: rest);
      });

      testWidgets('2. a run in progress, map drawn', (tester) async {
        var clock = DateTime(2026, 10, 1, 18, 4);
        // Cut where the picture is taken, so the replay stops there and the
        // figures hold still while the map loads: 4.3 km of the six.
        final List<RunPoint> trace = storeTrace(clock).sublist(0, 530);
        final FakeRunRecorder rec = FakeRunRecorder(
          trace: trace,
          interval: const Duration(milliseconds: 20),
          now: () => clock,
        );
        await shot(
          tester,
          '2-run',
          RecordingScreen(
            recorder: rec,
            plannedSession: kStoreSession,
            paces: pacesFor(storeProfile()),
            onCancel: () {},
          ),
          drive: (t) async {
            await t.pump();
            for (var i = 0; i < trace.length + 4; i++) {
              if (i < trace.length) {
                clock = clock.add(const Duration(seconds: 3));
              }
              await t.pump(const Duration(milliseconds: 20));
            }
            await letTheMapLoad(t);
          },
        );
        await rec.stop();
        await putAway(tester);
      });

      testWidgets('3. the finished run', (tester) async {
        final (_, _, runs) = await runner();
        await shot(
          tester,
          '3-finished',
          pushed(
            RunSummaryScreen(
              summary: storeRun(withSteps: phone.isIphone),
              history: runs,
              plannedSession: kStoreSession,
              justFinished: true,
              onDone: () {},
              onAskCoach: () {},
            ),
          ),
          drive: (t) async {
            // Past the route's reveal, then the tiles.
            for (var i = 0; i < 30; i++) {
              await t.pump(const Duration(milliseconds: 100));
            }
            await letTheMapLoad(t);
          },
        );
        await putAway(tester);
      });

      testWidgets('4. the plan', (tester) async {
        final (store, _, runs) = await runner();
        await shot(
          tester,
          '4-plan',
          plateApp(db, store, runs, initialTab: 1),
          drive: rest,
        );
      });

      testWidgets('5. the coach answering', (tester) async {
        final (store, _, runs) = await runner();
        await shot(
          tester,
          '5-coach',
          plateApp(db, store, runs, chatClient: const StoreCoach()),
          drive: (t) async {
            await rest(t);
            await t.tap(find.byType(CoachMarkGlyph));
            await settle(t);
            await settle(t);
            await t.tap(find.textContaining('half marathon').last);
            await settle(t);
            await settle(t);
          },
        );
      });

      testWidgets('6. the year, on the profile', (tester) async {
        final (store, _, runs) = await runner();
        await shot(
          tester,
          '6-year',
          plateApp(db, store, runs, initialTab: 2),
          drive: (t) async {
            await rest(t);
            // Down to the records, so the year sits in the middle of the
            // picture with the figures that go with it above and below.
            final Finder records = find.textContaining(
              RegExp(r'^records$', caseSensitive: false),
            );
            final double from = t.getTopLeft(records).dy;
            final double to = phone.safeArea.top + kToolbarHeight + 20;
            final ScrollPosition position = Scrollable.of(
              t.element(find.byType(YearGrid)),
            ).position;
            position.jumpTo(position.pixels + from - to);
            await settle(t);
          },
        );
      });
    });
  }
}
