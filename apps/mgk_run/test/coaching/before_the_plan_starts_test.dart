import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/coaching/data/drift_plan_store.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/features/coaching/data/plan_store.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_shape.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/session_status.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/presentation/plan_calendar_screen.dart';
import 'package:mgk_run/src/features/coaching/presentation/plan_screen.dart';
import 'package:mgk_run/src/features/coaching/presentation/week_calendar.dart';
import 'package:mgk_run/src/features/coaching/presentation/week_list.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';
import 'package:mgk_run/src/features/home/presentation/home_today_tile.dart';

/// The week a plan is built (screen board H6 and P5).
///
/// A plan starts on the coming Monday (ADR-0034), and on the days between
/// building it and that Monday both screens read week 1 as though today were
/// in it. Home prescribed "5 km today" off next week's same weekday and
/// counted "0 of 7" against sessions not yet due; the Plan tab headed next
/// week "This week" and lit next Wednesday as today. Invisible on a Monday,
/// which is why these run across every day of the week.
void main() {
  // Tuesday 29 September to Sunday 4 October 2026: every day before the plan
  // built on it starts, which is Monday 5 October for all six.
  final buildDays = <DateTime>[
    for (var d = 29; d <= 34; d++) DateTime(2026, 9, d),
  ];
  final monday = DateTime(2026, 10, 5);

  RunnerProfile block() => RunnerProfile(
    goalDistanceMeters: 10000,
    eventDate: DateTime(2027, 1, 17),
    currentWeeklyMeters: 30000,
    longestRecentMeters: 12000,
    daysPerWeek: 5,
    availableWeekdays: const <int>{1, 2, 3, 4, 5, 6, 7},
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 25),
  );

  RunnerProfile rhythm() => const RunnerProfile(
    currentWeeklyMeters: 20000,
    longestRecentMeters: 8000,
    daysPerWeek: 3,
    availableWeekdays: <int>{2, 4, 6},
    commitments: <PlanCommitment>[
      PlanCommitment(
        weekday: DateTime.saturday,
        distanceMeters: 5000,
        label: 'parkrun',
      ),
    ],
  );

  group('the repository says the plan has not started', () {
    for (final day in buildDays) {
      test(
        'built on ${day.weekday == 7 ? 'a Sunday' : 'weekday ${day.weekday}'}'
        ' (${day.day}/${day.month})',
        () async {
          for (final profile in <RunnerProfile>[block(), rhythm()]) {
            final repo = PlanRepository(
              store: InMemoryPlanStore(),
              now: () => day,
            );
            final plan = await repo.create(profile);
            final today = await repo.today(plan);

            expect(plan.startDate, monday);
            expect(plan.hasStartedBy(day), isFalse);
            expect(today.startsOn, monday);
            expect(today.session, isNull, reason: 'nothing is asked of today');
            expect(today.support, isNull);
            expect(today.slot.index, 1, reason: 'the week it starts with');
            expect(today.firstSession, isNotNull);
            expect(today.firstSession!.kind.isRun, isTrue);
          }
        },
      );
    }

    test('and on the Monday it has', () async {
      final repo = PlanRepository(
        store: InMemoryPlanStore(),
        now: () => monday,
      );
      final plan = await repo.create(block());
      final today = await repo.today(plan);

      expect(plan.hasStartedBy(monday), isTrue);
      expect(today.startsOn, isNull);
      expect(today.firstSession, isNull);
    });

    test('hasStartedBy leaves weekIndexOn and its round trip alone', () async {
      // ADR-0034's consequence: the wrapped rhythm index is deliberate, and
      // dateFor has to stay its inverse. The new state sits beside it.
      final plan = await PlanRepository(
        store: InMemoryPlanStore(),
        now: () => buildDays[1],
      ).create(rhythm());
      final before = buildDays[1];
      final index = plan.weekIndexOn(before);
      expect(index, plan.skeleton.weeks.length, reason: 'still wraps');
      final back = plan.dateFor(
        weekIndex: index,
        weekday: before.weekday,
        on: before,
      );
      expect(plan.weekIndexOn(back), index);
    });
  });

  group("Home's today card", () {
    Future<void> pump(WidgetTester tester, TodayView today) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: HomeTodayTile(
                now: DateTime(2026, 9, 30, 8),
                unit: UnitSystem.metric,
                today: today,
                onFreeRun: () {},
                onStartSession: () {},
                onOpenPlan: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('says when the plan starts, and prescribes nothing', (
      tester,
    ) async {
      await pump(
        tester,
        TodayView(
          slot: const SkeletonWeek(
            index: 1,
            phase: Phase.base,
            volumeMeters: 30000,
            longRunMeters: 10000,
          ),
          session: null,
          status: SessionStatus.planned,
          heading: 'Today',
          startsOn: monday,
          firstSession: const PlannedSession(
            weekday: DateTime.tuesday,
            kind: SessionKind.easy,
            distanceMeters: 5000,
          ),
        ),
      );

      expect(find.text('Your plan starts Monday 5 Oct'), findsOneWidget);
      expect(
        find.text(
          'First up: easy run, 5 km, on Tuesday 6 Oct. '
          'Nothing is set before then.',
        ),
        findsOneWidget,
      );
      expect(find.text('Record a run'), findsOneWidget);
      // No session to start, and "5 km" nowhere as today's distance.
      expect(find.text('Start'), findsNothing);
      expect(find.text('5 km'), findsNothing);
      expect(find.text('Rest day'), findsNothing);
    });
  });

  group('the Plan tab', () {
    Future<void> pump(WidgetTester tester, DateTime day) async {
      final repo = PlanRepository(store: InMemoryPlanStore(), now: () => day);
      final plan = await repo.create(block());
      final weeks = <int, TrainingWeek>{
        1: await repo.weekFor(plan, plan.skeleton.weeks[0]),
        2: await repo.weekFor(plan, plan.skeleton.weeks[1]),
      };
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: PlanScreen(
            plan: plan,
            weeks: weeks,
            now: day,
            statusFor: (_) => SessionStatus.completed,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final day in buildDays) {
      testWidgets(
        'heads week 1 with its start, built on ${day.day}/${day.month}',
        (tester) async {
          await pump(tester, day);

          expect(find.text('STARTS MONDAY 5 OCT'), findsOneWidget);
          expect(find.textContaining('THIS WEEK'), findsNothing);
          final list = tester.widget<WeekList>(find.byType(WeekList));
          expect(list.today, isNull, reason: 'no day of next week is today');
          expect(list.statusFor, isNull);
          expect(list.weekStart, monday);
        },
      );
    }

    testWidgets('and from the Monday it is this week again', (tester) async {
      await pump(tester, monday);

      expect(find.text('THIS WEEK · 5 – 11 OCT'), findsOneWidget);
      final list = tester.widget<WeekList>(find.byType(WeekList));
      expect(list.today, monday);
    });

    testWidgets('the calendar opens on the same week, with nothing lit', (
      tester,
    ) async {
      final day = buildDays[1]; // Wednesday 30 September
      final repo = PlanRepository(store: InMemoryPlanStore(), now: () => day);
      final plan = await repo.create(block());
      await tester.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: PlanCalendarScreen(
            plan: plan,
            weeks: <int, TrainingWeek>{
              1: await repo.weekFor(plan, plan.skeleton.weeks[0]),
            },
            now: day,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final first = tester.widget<WeekCalendar>(
        find.byType(WeekCalendar).first,
      );
      expect(first.title, 'Starts Monday 5 Oct');
      expect(first.today, isNull);
      expect(find.textContaining('This week'), findsNothing);
    });
  });

  group('through the shell', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    testWidgets('Home and Plan agree the plan has not started', (tester) async {
      // Built "tomorrow", so its first Monday is still ahead whichever day
      // the suite runs on, including a Monday.
      final store = DriftPlanStore(db);
      final plan = await PlanRepository(
        store: store,
        now: () => DateTime.now().add(const Duration(days: 1)),
      ).create(block());
      final starts = plan.startDate;
      const days = <String>[
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      const months = <String>[
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final label =
          '${days[starts.weekday - 1]} ${starts.day} ${months[starts.month - 1]}';

      await tester.binding.setSurfaceSize(const Size(430, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: HomeShell(
            auth: FakeAuthRepository(signedIn: true, email: 'a@example.com'),
            planStore: store,
            historySource: () async => const [],
          ),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }

      expect(find.text('Your plan starts $label'), findsOneWidget);
      expect(find.text('Start'), findsNothing);
      // The week is counted off the log, not against sessions not yet due.
      expect(find.text('SESSIONS'), findsNothing);
      expect(find.textContaining(' of '), findsNothing);
      expect(find.text('RUNS'), findsOneWidget);

      await tester.tap(find.text('Plan'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      expect(find.text('STARTS ${label.toUpperCase()}'), findsOneWidget);
      expect(find.textContaining('THIS WEEK'), findsNothing);
    });
  });
}
