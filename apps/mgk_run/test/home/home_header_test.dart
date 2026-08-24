import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/coaching/data/coach_client.dart';
import 'package:mgk_run/src/features/coaching/data/drift_plan_store.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_shape.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

/// The top of Home used to be the time of day — the one line on the screen a
/// runner already knew before they opened it — while what they were training
/// for lived a tab away. These pin the swap.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  RunnerProfile marathoner() => RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: DateTime.now().add(const Duration(days: 112)),
    currentWeeklyMeters: 40000,
    longestRecentMeters: 18000,
    daysPerWeek: 5,
    availableWeekdays: const <int>{1, 2, 3, 4, 5, 6, 7},
  );

  /// A parkrun habit: no goal, no date, so its weeks repeat (ADR-0011).
  RunnerProfile parkrunner() => const RunnerProfile(
    currentWeeklyMeters: 5000,
    longestRecentMeters: 5000,
    daysPerWeek: 1,
    availableWeekdays: <int>{DateTime.saturday},
    commitments: <PlanCommitment>[
      PlanCommitment(
        weekday: DateTime.saturday,
        distanceMeters: 5000,
        label: 'parkrun',
      ),
    ],
  );

  final greetings = <String>['Morning', 'Afternoon', 'Evening'];

  Future<void> pump(WidgetTester tester, {RunnerProfile? profile}) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = DriftPlanStore(db);
    if (profile != null) await PlanRepository(store: store).create(profile);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeShell(
          auth: FakeAuthRepository(signedIn: true, email: 'dev@runio.app'),
          historySource: () async => const [],
          planStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a runner in a block is headed with the block', (tester) async {
    await pump(tester, profile: marathoner());

    expect(find.text('Marathon'), findsOneWidget);
    // "112 days · week 1 of 16" — the countdown and the position, not the hour.
    expect(find.textContaining('days · week'), findsOneWidget);
    for (final greeting in greetings) {
      expect(
        find.text(greeting),
        findsNothing,
        reason: 'the hour is not the most useful thing this space can hold',
      );
    }
  });

  testWidgets('a rhythm is headed with what the runner calls it', (
    tester,
  ) async {
    await pump(tester, profile: parkrunner());

    expect(find.text('Your parkrun week'), findsOneWidget);
    expect(find.textContaining('1 run a week'), findsOneWidget);
  });

  testWidgets('with no plan there is genuinely nothing to count down to', (
    tester,
  ) async {
    await pump(tester);

    // The greeting survives exactly where it is the best thing available — a
    // blank here would be colder than a hello.
    expect(
      greetings.where((g) => find.text(g).evaluate().isNotEmpty),
      hasLength(1),
    );
  });

  testWidgets('Home never explains the app — that moved to the Plan tab', (
    tester,
  ) async {
    // "How this works" belongs where the runner it is written for actually is:
    // someone with no plan opens Plan to get one.
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeShell(
          auth: FakeAuthRepository(signedIn: true, email: 'dev@runio.app'),
          historySource: () async => <RunSummary>[
            RunSummary(
              startedAt: DateTime.now().subtract(const Duration(days: 2)),
              duration: const Duration(minutes: 30),
              distanceMeters: 6000,
            ),
          ],
          planStore: DriftPlanStore(db),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // **No plan-shaped hole.** This used to assert `No plan yet` was the
    // headline of the today card, which was the counter-signal ADR-0019 names
    // in as few words as it is possible to put it: a free screen headed with
    // the name of the thing the runner has not bought. Today is answered off
    // the log now — they last ran two days ago, so today has no run in it yet.
    expect(find.text('No plan yet'), findsNothing);
    expect(find.text('No run yet today'), findsOneWidget);
    expect(find.text('A plan built round your week'), findsNothing);
  });

  testWidgets('today says how to run it, not only how far', (tester) async {
    // **Seven days a week**, so today is a session whatever day the suite runs
    // on. It used to use the five-day profile with the note "every weekday is
    // available, so today is a session" — which confused *available* with
    // *prescribed*: five runs across seven days leaves two rest days, and the
    // test duly failed the first time it ran on one of them.
    await pump(
      tester,
      profile: RunnerProfile(
        goalDistanceMeters: 42195,
        eventDate: DateTime.now().add(const Duration(days: 112)),
        currentWeeklyMeters: 40000,
        longestRecentMeters: 18000,
        daysPerWeek: 7,
        availableWeekdays: const <int>{1, 2, 3, 4, 5, 6, 7},
      ),
    );

    expect(find.textContaining('km'), findsWidgets);
    // The effort cue that used to be two taps into the Coach tab. Which one
    // depends on the day, so this asserts that one of them is present.
    final cues = <String>[
      'conversational the whole way',
      'easy effort, longer distance',
      'comfortably hard, an hour’s worth',
      'slower than feels natural',
      'as hard as you can hold',
      'whatever your session calls for',
    ];
    expect(
      cues.where((c) => find.text(c).evaluate().isNotEmpty),
      isNotEmpty,
      reason: 'today should carry its effort, whichever session it is',
    );
  });

  testWidgets('a strength day is not called a rest day', (tester) async {
    // `runs` filters to running, so a day carrying only strength came back null
    // and Home said "Rest day · Nothing scheduled" over it — while the Coach
    // tab, reading the same stored week, listed Strength on that day.
    final store = DriftPlanStore(db);
    final plan = await PlanRepository(store: store).create(
      RunnerProfile(
        goalDistanceMeters: 42195,
        eventDate: DateTime.now().add(const Duration(days: 112)),
        currentWeeklyMeters: 40000,
        longestRecentMeters: 18000,
        daysPerWeek: 3,
        strengthDaysPerWeek: 2,
        availableWeekdays: const <int>{1, 2, 3, 4, 5, 6, 7},
      ),
    );

    final repo = PlanRepository(store: store);
    final week = await repo.weekFor(plan, plan.weekOn(DateTime.now()));
    final today = await repo.today(plan);

    final runToday = week.runOn(DateTime.now().weekday);
    final anyToday = week.sessionOn(DateTime.now().weekday);

    if (runToday == null && anyToday != null) {
      expect(
        today.support,
        isNotNull,
        reason: 'a day with support and no run must report the support',
      );
    } else {
      // Whichever day the suite runs on, the two must never disagree: support
      // is only ever set when there is no run.
      expect(today.support, isNull);
    }
  });

  /// No dev persona can reach this state — every seeded log runs each past day
  /// of the current week — so the card that exists *for* being behind has to be
  /// covered here rather than on a device.
  testWidgets(
    'a missed key session is raised, and both answers are sentences',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final store = DriftPlanStore(db);
      // Trains every day, so whatever weekday the suite runs on there is a
      // prescribed session behind today with no run against it.
      //
      // **Created three weeks ago.** A plan in its first week raises nothing,
      // because `startDate` is the Monday week 1 aligns to and nothing stored
      // says which day the runner actually committed — so a week-1 fixture
      // would be asserting a state the app deliberately stays quiet in.
      await PlanRepository(
        store: store,
        now: () => DateTime.now().subtract(const Duration(days: 21)),
      ).create(
        RunnerProfile(
          goalDistanceMeters: 42195,
          eventDate: DateTime.now().add(const Duration(days: 112)),
          currentWeeklyMeters: 40000,
          longestRecentMeters: 18000,
          daysPerWeek: 7,
          availableWeekdays: const <int>{1, 2, 3, 4, 5, 6, 7},
        ),
      );

      final chat = _SilentChat();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: HomeShell(
            auth: FakeAuthRepository(signedIn: true, email: 'dev@runio.app'),
            historySource: () async => const <RunSummary>[],
            chatClient: chat,
            planStore: store,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Monday is the one day with nothing behind it.
      if (DateTime.now().weekday == DateTime.monday) return;

      expect(find.textContaining('missed'), findsWidgets);
      expect(find.text('I ran it'), findsOneWidget);
      expect(find.text('Adjust'), findsOneWidget);

      // Neither button writes anything: both put a sentence to the coach.
      await tester.tap(find.text('I ran it'));
      await tester.pumpAndSettle();
      expect(chat.asked, hasLength(1));
      expect(chat.asked.single.toLowerCase(), contains('did run'));
    },
  );
  testWidgets('a runner with nothing gets a way out, not a dead end', (
    tester,
  ) async {
    await pump(tester);

    // This was a lone text link out to the Plan tab, which was defensible
    // while every runner was on their way to a plan. A plan is opted into now
    // (ADR-0019), so this screen is where most runners live and it says what
    // the app does with a run before there is one.
    // `SectionLabel` upper-cases what it is given.
    expect(find.text('ONCE YOU RUN'), findsOneWidget);
    expect(
      find.textContaining('route, pace and splits'),
      findsOneWidget,
      reason: 'the free product has to be described, not implied',
    );

    // Still a way out, and still only a pointer — the explainer itself lives
    // on the Plan tab, and saying it in both places is how the coach note
    // ended up reading out its own charts (ADR-0017).
    expect(
      find.text('Training for something? See how plans work'),
      findsOneWidget,
    );
    expect(find.text('A plan built round your week'), findsNothing);
  });

  testWidgets('and it never sells the plan as though it were included', (
    tester,
  ) async {
    // Everything named on this card is free. A runner reading it has not been
    // offered a plan and must not be shown one as part of the furniture; the
    // only mention is the way out, which goes to the tab that sells it.
    await pump(tester);
    expect(find.textContaining('Totals, records'), findsOneWidget);
    expect(find.textContaining('coach that answers'), findsOneWidget);
  });

  testWidgets('and it goes once they have a plan', (tester) async {
    await pump(tester, profile: marathoner());
    expect(find.text('ONCE YOU RUN'), findsNothing);
  });

  /// Through the shell, not through the domain function directly — the first
  /// version of this fix passed its unit test and did nothing in the app,
  /// because the value the shell handed in could never trigger the guard.
  testWidgets('a plan built today does not open by listing failures', (
    tester,
  ) async {
    await pump(
      tester,
      profile: RunnerProfile(
        goalDistanceMeters: 21097.5,
        eventDate: DateTime.now().add(const Duration(days: 100)),
        currentWeeklyMeters: 40000,
        longestRecentMeters: 18000,
        daysPerWeek: 7,
        availableWeekdays: const <int>{1, 2, 3, 4, 5, 6, 7},
      ),
    );

    // Seven sessions a week and no runs at all, so every past day of this week
    // would be a miss if the plan were entitled to claim them.
    expect(
      find.textContaining('missed this week'),
      findsNothing,
      reason: 'week one cannot say which of its days predate the plan',
    );
    expect(find.text('I ran it'), findsNothing);
  });
}

/// Answers nothing useful; these tests are about what reaches the coach.
class _SilentChat implements CoachChatClient {
  final List<String> asked = <String>[];

  @override
  Future<ChatTurn> chat({
    required String brief,
    required List<ChatMessage> history,
    required String message,
  }) async {
    asked.add(message);
    return const ChatTurn(reply: 'Noted.');
  }
}
