import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/coaching/data/adaptation_service.dart';
import 'package:mgk_run/src/features/coaching/data/drift_plan_store.dart';
import 'package:mgk_run/src/features/coaching/data/plan_client.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/features/coaching/data/plan_service.dart';
import 'package:mgk_run/src/features/coaching/data/plan_store.dart';
import 'package:mgk_run/src/features/coaching/domain/pace_model.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_headline.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_validator.dart';
import 'package:mgk_run/src/features/coaching/domain/race_day.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/session_status.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/presentation/week_calendar.dart';
import 'package:mgk_run/src/features/coaching/presentation/week_detail_screen.dart';
import 'package:mgk_run/src/features/coaching/presentation/week_list.dart';
import 'package:mgk_units/mgk_units.dart';

/// **Race week is a week of its own** (ADR-0044).
///
/// Found on a phone ten days before a race: the Plan tab showed a 7 km run on
/// the Sunday the race was on, and nothing anywhere in the week said "race".
/// Three separate things were wrong and each is pinned here.
///
/// - The plan's own screens never drew race day. Home has since ADR-0027.
/// - A stored week is never regenerated, so a race week written by an earlier
///   build kept its run on race day for good.
/// - Even a freshly built one was an ordinary week with a day blocked out: a
///   quality session, and the long run on the last free day, which for a
///   Sunday race is the Saturday.

/// Counts what the model was asked for. Answers with the builder's ordinary
/// week, long run and all, which is what a model that knows nothing about race
/// week gives back.
class _CountingModel implements PlanClient {
  int weeks = 0;

  @override
  Future<PlanSkeleton?> proposeSkeleton({
    required RunnerProfile profile,
    List<String> violations = const <String>[],
  }) async => null;

  @override
  Future<TrainingWeek?> proposeWeek({
    required SkeletonWeek slot,
    required RunnerProfile profile,
    List<String> violations = const <String>[],
    int? raceWeekday,
  }) async {
    weeks++;
    return buildFallbackWeek(slot, profile);
  }

  @override
  Future<TrainingWeek?> proposeAdaptation({
    required TrainingWeek week,
    required SkeletonWeek slot,
    required RunnerProfile profile,
    required String request,
  }) async => null;
}

/// Counts the weeks mirrored to the backup, which is one per write.
class _CountingBackup implements PlanBackup {
  int weeks = 0;

  @override
  Future<void> pushPlan(StoredPlan plan) async {}

  @override
  Future<void> pushWeek(StoredPlan plan, TrainingWeek week) async => weeks++;

  @override
  Future<void> pushStatus({
    required StoredPlan plan,
    required int weekIndex,
    required int weekday,
    required DateTime date,
    required SessionStatus status,
  }) async {}
}

void main() {
  // A Sunday. The plan below is built on Tuesday 29 September and starts on
  // Monday 5 October, so race week is its last.
  final DateTime race = DateTime(2026, 11, 15);
  final DateTime built = DateTime(2026, 9, 29, 9);

  RunnerProfile runner({
    int days = 5,
    Set<int> available = const <int>{1, 2, 3, 4, 5, 6, 7},
    DateTime? on,
    bool timeTrial = true,
  }) => RunnerProfile(
    goalDistanceMeters: 21097.5,
    eventDate: on ?? race,
    currentWeeklyMeters: 30000,
    longestRecentMeters: 14000,
    daysPerWeek: days,
    availableWeekdays: available,
    timeTrialDistanceMeters: timeTrial ? 5000 : null,
    timeTrialDuration: timeTrial ? const Duration(minutes: 22) : null,
  );

  SkeletonWeek lastSlot(RunnerProfile profile) =>
      buildSkeleton(profile, now: built).weeks.last;

  group('the week of the race', () {
    test('is easy running that gets shorter, with the day before off', () {
      final profile = runner();
      final slot = lastSlot(profile);

      final week = buildRaceWeek(slot, profile, raceWeekday: DateTime.sunday);

      expect(week.sessions, isNotEmpty);
      expect(
        week.sessions.map((s) => s.kind).toSet(),
        <SessionKind>{SessionKind.easy},
        reason: 'no long run and nothing hard in the week of a race',
      );
      expect(
        week.sessions.map((s) => s.weekday),
        everyElement(lessThan(DateTime.saturday)),
        reason: 'nothing on race day, and nothing the day before',
      );
      final metres = <double>[for (final s in week.sessions) s.distanceMeters];
      for (var i = 1; i < metres.length; i++) {
        expect(
          metres[i],
          lessThan(metres[i - 1]),
          reason: 'each run is shorter than the one before: $metres',
        );
      }
    });

    test('runs one day fewer than usual, because the race is one', () {
      final profile = runner(days: 4);
      final week = buildRaceWeek(
        lastSlot(profile),
        profile,
        raceWeekday: DateTime.sunday,
      );
      expect(week.sessions, hasLength(3));
    });

    test('holds what the taper week held outside its long run', () {
      final profile = runner();
      final slot = lastSlot(profile);
      final week = buildRaceWeek(slot, profile, raceWeekday: DateTime.sunday);

      expect(slot.beforeRaceMeters, slot.volumeMeters - slot.longRunMeters);
      // Whole kilometres, so within one per session of the exact figure.
      expect(
        week.volumeMeters,
        closeTo(slot.beforeRaceMeters, 1000.0 * week.sessions.length),
      );
    });

    test('keeps to the days the runner can run', () {
      final profile = runner(days: 3, available: const <int>{2, 4, 6, 7});
      final week = buildRaceWeek(
        lastSlot(profile),
        profile,
        raceWeekday: DateTime.sunday,
      );
      // Saturday is the day before, so Tuesday and Thursday are all there is.
      expect(week.sessions.map((s) => s.weekday), <int>[2, 4]);
    });

    test('is empty when the race is on a Monday', () {
      final profile = runner();
      final week = buildRaceWeek(
        lastSlot(profile),
        profile,
        raceWeekday: DateTime.monday,
      );
      expect(week.sessions, isEmpty);
    });

    test('is what the builder gives however it is reached', () {
      // The model never sees race week: the service answers from the rule.
      final profile = runner();
      final slot = lastSlot(profile);
      final model = _CountingModel();

      return PlanService(client: model, now: () => built)
          .generateWeek(slot, profile, raceWeekday: DateTime.sunday)
          .then((result) {
            expect(model.weeks, 0, reason: 'race week is not proposed');
            expect(result.source, PlanSource.rule);
            expect(result.isFallback, isFalse, reason: 'so it is kept');
            expect(
              isRaceWeekShaped(result.plan, raceWeekday: DateTime.sunday),
              isTrue,
            );
          });
    });
  });

  group('a plan built by an earlier build', () {
    late AppDatabase db;
    late PlanStore store;
    late _CountingBackup backup;
    late DateTime clock;

    PlanRepository repo() => PlanRepository(
      store: store,
      backup: backup,
      now: () => clock,
      newId: () => 'plan-race',
    );

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      store = DriftPlanStore(db);
      backup = _CountingBackup();
      clock = built;
    });
    tearDown(() => db.close());

    /// The plan, with its race week on disk the way the old builder wrote it:
    /// an ordinary week, long run on the Sunday the race is on.
    Future<(StoredPlan, SkeletonWeek)> withAnOldRaceWeek() async {
      final plan = await repo().create(runner());
      final slot = plan.skeleton.weeks.last;
      expect(raceWeekdayIn(plan, slot), DateTime.sunday);
      final old = buildFallbackWeek(slot, plan.profile);
      expect(old.runOn(DateTime.sunday), isNotNull, reason: 'the defect');
      await store.saveWeek(plan, old);
      return (plan, slot);
    }

    test('has its race week rebuilt before the week begins', () async {
      final (plan, slot) = await withAnOldRaceWeek();

      final week = await repo().weekFor(plan, slot);

      expect(week.runOn(DateTime.sunday), isNull, reason: 'race day is clear');
      expect(week.runOn(DateTime.saturday), isNull);
      expect(week.sessions.any((s) => s.kind == SessionKind.long), isFalse);
      // And it is on disk, not only on this screen.
      final stored = await store.loadWeek(plan, slot.index);
      expect(stored!.runOn(DateTime.sunday), isNull);
    });

    test('keeps the days already run when the week is under way', () async {
      final (plan, slot) = await withAnOldRaceWeek();
      final before = (await store.loadWeek(plan, slot.index))!;
      // Thursday of race week: Monday to Wednesday are behind the runner.
      clock = plan
          .dateFor(weekIndex: slot.index, weekday: DateTime.thursday)
          .add(const Duration(hours: 9));

      final week = await repo().weekFor(plan, slot);

      for (final day in <int>[1, 2, 3]) {
        expect(
          week.runOn(day)?.distanceMeters,
          before.runOn(day)?.distanceMeters,
          reason: 'weekday $day happened, and is left as it was',
        );
      }
      expect(week.runOn(DateTime.sunday), isNull);
      expect(week.runOn(DateTime.saturday), isNull);
    });

    test('is written once, not on every read', () async {
      final (plan, slot) = await withAnOldRaceWeek();
      final writes = backup.weeks;

      await repo().weekFor(plan, slot);
      await repo().weekFor(plan, slot);
      await repo().weekFor(plan, slot);

      expect(backup.weeks, writes + 1);
    });

    test(
      'leaves alone a short run the runner asked for the day before',
      () async {
        final (plan, slot) = await withAnOldRaceWeek();
        final rebuilt = await repo().weekFor(plan, slot);
        // What the coach writes when asked for a shake-out on the Saturday.
        final adjusted = TrainingWeek(
          skeletonIndex: slot.index,
          sessions: <PlannedSession>[
            ...rebuilt.sessions,
            const PlannedSession(
              weekday: DateTime.saturday,
              kind: SessionKind.easy,
              distanceMeters: 3000,
            ),
          ],
        );
        await repo().saveRevisedWeek(plan, adjusted);

        final week = await repo().weekFor(plan, slot);

        expect(week.runOn(DateTime.saturday)?.distanceMeters, 3000);
      },
    );

    test(
      'has its race week written ahead by rule, never by the model',
      () async {
        final model = _CountingModel();
        final withModel = PlanRepository(
          store: store,
          generator: PlanService(client: model, now: () => clock),
          now: () => clock,
          newId: () => 'plan-race',
        );
        final plan = await withModel.create(runner());
        final slot = plan.skeleton.weeks.last;
        final asked = model.weeks;
        // The week before race week, which is when Home looks ahead to it.
        clock = plan
            .dateFor(weekIndex: slot.index - 1, weekday: DateTime.tuesday)
            .add(const Duration(hours: 9));

        final wrote = await withModel.lookAhead(plan);

        expect(wrote, isTrue);
        expect(model.weeks, asked, reason: 'the model is not asked for it');
        final stored = (await store.loadWeek(plan, slot.index))!;
        expect(isRaceWeekShaped(stored, raceWeekday: DateTime.sunday), isTrue);
        expect(stored.runOn(DateTime.saturday), isNull);
      },
    );
  });

  group('adjusting race week', () {
    final profile = runner();
    final slot = lastSlot(profile);
    final DateTime weekStart = mondayOf(race);
    final week = buildRaceWeek(slot, profile, raceWeekday: DateTime.sunday);

    List<String> codes(TrainingWeek w) => validateWeek(
      w,
      slot,
      profile,
      rules: const PlanRules.adaptation(),
      weekStart: weekStart,
    ).violations.map((v) => v.code).toList();

    test('the week the rule builds is one the validator accepts', () {
      // It departs from its slot on purpose: no long run, and the volume the
      // long run would have carried is gone. Judged as an ordinary week, a
      // runner could not change anything in race week at all.
      expect(codes(week), isEmpty);
    });

    test('a short run the day before is allowed', () {
      final shakeOut = TrainingWeek(
        skeletonIndex: slot.index,
        sessions: <PlannedSession>[
          ...week.sessions.take(week.sessions.length - 1),
          const PlannedSession(
            weekday: DateTime.saturday,
            kind: SessionKind.easy,
            distanceMeters: 3000,
          ),
        ],
      );
      expect(codes(shakeOut), isEmpty);
    });

    test('a long run is not, and the runner is told why', () {
      final withLong = TrainingWeek(
        skeletonIndex: slot.index,
        sessions: <PlannedSession>[
          ...week.sessions.take(1),
          PlannedSession(
            weekday: DateTime.friday,
            kind: SessionKind.long,
            distanceMeters: slot.longRunMeters,
          ),
        ],
      );
      final found = validateWeek(
        withLong,
        slot,
        profile,
        rules: const PlanRules.adaptation(),
        weekStart: weekStart,
      ).violations;

      expect(found.map((v) => v.code), contains('long_run_in_race_week'));
      expect(AdaptationRefused(found).message, contains('race week'));
    });

    test('nothing changes for a week the race is not in', () {
      final earlier = buildSkeleton(profile, now: built).weeks[2];
      final ordinary = buildFallbackWeek(earlier, profile);
      final found = validateWeek(
        ordinary,
        earlier,
        profile,
        weekStart: DateTime(2026, 10, 19),
      ).violations.map((v) => v.code);
      expect(found, isNot(contains('long_run_in_race_week')));
      expect(found, isEmpty);
    });
  });

  group('race day on the plan', () {
    StoredPlan planFor(RunnerProfile profile) => StoredPlan(
      id: 'p',
      profile: profile,
      skeleton: buildSkeleton(profile, now: built),
      // So the last week ends on the race.
      startDate: addDays(
        mondayOf(race),
        -7 * (buildSkeleton(profile, now: built).weeks.length - 1),
      ),
    );

    test('is the race, with its distance and a time to expect', () {
      final plan = planFor(runner());
      final entry = raceDayIn(plan, plan.skeleton.weeks.last)!;

      expect(entry.weekday, DateTime.sunday);
      expect(entry.raceName, 'Half marathon');
      expect(entry.distanceLabel(UnitSystem.metric), '21.1 km');
      // 22:00 for 5 km, carried to the half by Riegel: an hour and forty-one.
      expect(
        entry.expected,
        riegelPredict(
          Distance.meters(5000),
          const Duration(minutes: 22),
          Distance.meters(21097.5),
        ),
      );
      expect(entry.detail(), 'Half marathon · about 1 h 41 min');
    });

    test('makes no promise about time without a time trial', () {
      final plan = planFor(runner(timeTrial: false));
      final entry = raceDayIn(plan, plan.skeleton.weeks.last)!;
      expect(entry.expected, isNull);
      expect(entry.detail(), 'Half marathon');
    });

    test('is in the last week and no other', () {
      final plan = planFor(runner());
      for (final slot in plan.skeleton.weeks) {
        expect(
          raceDayIn(plan, slot) != null,
          slot.index == plan.skeleton.weeks.length,
          reason: 'week ${slot.index}',
        );
      }
    });

    test('a time is said as loosely as it is known', () {
      expect(aboutRaceTime(const Duration(minutes: 48, seconds: 20)), '48 min');
      expect(aboutRaceTime(const Duration(hours: 2)), '2 h');
      expect(
        aboutRaceTime(const Duration(hours: 3, minutes: 27, seconds: 40)),
        '3 h 28 min',
      );
    });

    test('the week says it is race week, and how far before the race', () {
      final plan = planFor(runner());
      final slot = plan.skeleton.weeks.last;
      final week = draftWeekFor(plan, slot);

      final line = weekSubtitle(plan, slot, week: week);

      expect(line, startsWith('Race week · '));
      expect(line, contains('before the race'));
      expect(line, isNot(contains('Taper')));
    });

    test('a week nothing is stored for is still drawn as race week', () {
      final plan = planFor(runner());
      final draft = draftWeekFor(plan, plan.skeleton.weeks.last);
      expect(isRaceWeekShaped(draft, raceWeekday: DateTime.sunday), isTrue);
      expect(draft.runOn(DateTime.saturday), isNull);
      // And an ordinary week is still the ordinary fill.
      final earlier = draftWeekFor(plan, plan.skeleton.weeks[2]);
      expect(earlier.sessions.any((s) => s.kind == SessionKind.long), isTrue);
    });

    Future<void> pump(WidgetTester tester, Widget child) async {
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
      await tester.pumpAndSettle();
    }

    testWidgets('the week list draws it instead of whatever the week holds', (
      tester,
    ) async {
      final plan = planFor(runner());
      final slot = plan.skeleton.weeks.last;
      // The old week, run on race day and all: the row must still be the race.
      final old = buildFallbackWeek(slot, plan.profile);

      await pump(
        tester,
        WeekList(
          week: old,
          weekStart: mondayOf(race),
          paces: pacesFor(plan.profile)!,
          raceDay: raceDayIn(plan, slot),
        ),
      );

      expect(find.text('Race day'), findsOneWidget);
      expect(find.text('Half marathon · about 1 h 41 min'), findsOneWidget);
      expect(find.text('21.1 km'), findsOneWidget);
      expect(find.text('Long run'), findsNothing);
    });

    testWidgets('the calendar marks the day', (tester) async {
      final plan = planFor(runner());
      final slot = plan.skeleton.weeks.last;

      await pump(
        tester,
        WeekCalendar(
          week: draftWeekFor(plan, slot),
          weekStart: mondayOf(race),
          raceWeekday: raceWeekdayIn(plan, slot),
        ),
      );

      expect(find.text('Race'), findsOneWidget);
    });

    testWidgets("the week's own screen is titled for it", (tester) async {
      final plan = planFor(runner());
      final slot = plan.skeleton.weeks.last;

      await pump(
        tester,
        WeekDetailScreen(
          week: draftWeekFor(plan, slot),
          slot: slot,
          paces: pacesFor(plan.profile)!,
          raceDay: raceDayIn(plan, slot),
        ),
      );

      expect(find.text('Week ${slot.index} · Race week'), findsOneWidget);
      expect(find.text('Race day'), findsOneWidget);
      expect(
        find.text('Half marathon · about 1 h 41 min, on your time trial'),
        findsOneWidget,
      );
    });
  });
}
