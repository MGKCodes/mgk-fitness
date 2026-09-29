import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/coaching/data/drift_plan_store.dart';
import 'package:mgk_run/src/features/coaching/data/plan_client.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_history.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/features/coaching/data/plan_service.dart';
import 'package:mgk_run/src/features/coaching/data/plan_store.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_validator.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/session_status.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';

/// A backup that always fails, standing in for no network / a dead endpoint.
/// Every write must still land locally: Supabase is a backup, not the source of
/// truth (CLAUDE.md rule 1).
class _BrokenBackup implements PlanBackup {
  int attempts = 0;

  @override
  Future<void> pushPlan(StoredPlan plan) async => _fail();

  @override
  Future<void> pushWeek(StoredPlan plan, TrainingWeek week) async => _fail();

  @override
  Future<void> pushStatus({
    required StoredPlan plan,
    required int weekIndex,
    required int weekday,
    required DateTime date,
    required SessionStatus status,
  }) async => _fail();

  Never _fail() {
    attempts++;
    throw Exception('no network');
  }
}

/// Records what was mirrored, to prove the backup is reached at all.
class _RecordingBackup implements PlanBackup {
  final List<String> calls = <String>[];

  @override
  Future<void> pushPlan(StoredPlan plan) async => calls.add('plan:${plan.id}');

  @override
  Future<void> pushWeek(StoredPlan plan, TrainingWeek week) async =>
      calls.add('week:${week.skeletonIndex}');

  @override
  Future<void> pushStatus({
    required StoredPlan plan,
    required int weekIndex,
    required int weekday,
    required DateTime date,
    required SessionStatus status,
  }) async => calls.add('status:$weekIndex/$weekday=${status.name}');
}

/// Counts what the model was asked for, and can be told to be unreachable.
///
/// Deliberately returns null rather than a week: what these tests care about is
/// **whether the network was touched at all**, and null exercises the same
/// fallback a real timeout would, without one.
class _CountingClient implements PlanClient {
  _CountingClient({this.dead = false, this.week});

  /// Throws instead of answering, standing in for a runner in a tunnel.
  final bool dead;

  /// Builds the week to answer with, or null to decline (the fallback path).
  final TrainingWeek Function(SkeletonWeek slot, RunnerProfile profile)? week;
  int skeletons = 0;
  int weeks = 0;
  int adaptations = 0;

  int get calls => skeletons + weeks + adaptations;

  @override
  Future<PlanSkeleton?> proposeSkeleton({
    required RunnerProfile profile,
    List<String> violations = const <String>[],
  }) async {
    skeletons++;
    if (dead) throw Exception('no network');
    return null;
  }

  @override
  Future<TrainingWeek?> proposeWeek({
    required SkeletonWeek slot,
    required RunnerProfile profile,
    List<String> violations = const <String>[],
    int? raceWeekday,
  }) async {
    weeks++;
    if (dead) throw Exception('no network');
    return week?.call(slot, profile);
  }

  @override
  Future<TrainingWeek?> proposeAdaptation({
    required TrainingWeek week,
    required SkeletonWeek slot,
    required RunnerProfile profile,
    required String request,
  }) async {
    adaptations++;
    return null;
  }
}

/// A week the model "produced" that the validator will accept.
///
/// The deterministic builder is used to make it, which is the point: what is
/// being tested is the *route* a week took, not whether the model is any good.
/// It arrives through `proposeWeek`, so `PlanResult.source` is `model`.
TrainingWeek buildsAWeek(SkeletonWeek slot, RunnerProfile profile) =>
    buildFallbackWeek(slot, profile);

void main() {
  late AppDatabase db;
  late PlanStore store;

  // A Wednesday, so "today" is mid-week and the Monday anchor is in the past.
  final DateTime today = DateTime(2026, 7, 29, 9, 30);

  RunnerProfile aProfile() => RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: DateTime(2026, 11, 15),
    currentWeeklyMeters: 40000,
    longestRecentMeters: 18000,
    daysPerWeek: 5,
    availableWeekdays: const <int>{1, 2, 4, 6, 7},
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 22),
  );

  PlanRepository repo({
    PlanBackup? backup,
    DateTime Function()? now,
    PlanRules? rules,
    PlanStore? on,
    PlanService? generator,
  }) => PlanRepository(
    store: on ?? store,
    backup: backup,
    generator: generator,
    now: now ?? () => today,
    rules: rules ?? const PlanRules(),
    newId: () => 'plan-fixed',
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    store = DriftPlanStore(db);
  });
  tearDown(() => db.close());

  group('create', () {
    test('starts on the coming Monday, whatever day it is built on', () async {
      // **The build 12 field test's other finding, and it is the anchor**
      // (ADR-0034). A plan built on a Friday opened with Monday to Thursday
      // already behind it — four days of a seven-day week gone, on the screen
      // a runner had just asked for a plan on.
      //
      // Excluding those days the way race day is excluded was tried and
      // reverted: it leaves week 1 with three usable days carrying a whole
      // week's volume, trading a week nobody can complete for one nobody
      // should. Every weekday is covered because the defect was invisible on
      // the two the fixtures happened to use.
      for (var day = 1; day <= 7; day++) {
        // 2026-08-03 is a Monday, so `day` is the weekday number.
        final built = DateTime(2026, 8, 2 + day, 9, 30);
        final plan = await repo(now: () => built).create(aProfile());

        expect(plan.startDate.weekday, DateTime.monday, reason: 'day $day');
        expect(
          plan.startDate.isBefore(DateTime(built.year, built.month, built.day)),
          isFalse,
          reason: 'a plan may not begin in the past — day $day',
        );
        for (var weekday = 1; weekday <= 7; weekday++) {
          expect(
            plan
                .dateFor(weekIndex: 1, weekday: weekday)
                .isBefore(plan.startDate),
            isFalse,
            reason: 'week 1 holds no day before the plan — day $day',
          );
        }
      }
    });

    test('and a Monday starts today rather than in a week', () async {
      // The boundary the helper exists for. "Coming Monday" on a Monday is
      // today: pushing it a week would make Monday the one day you cannot
      // start on, which is the opposite of the point.
      final monday = DateTime(2026, 8, 3, 9, 30);
      final plan = await repo(now: () => monday).create(aProfile());
      expect(plan.startDate, DateTime(2026, 8, 3));
    });

    test('persists the plan and its current week', () async {
      final plan = await repo().create(aProfile());

      // The **coming** Monday, not the one this Wednesday belongs to
      // (ADR-0034). Anchored to `mondayOf(now)` a plan built today would open
      // with Monday and Tuesday already spent.
      expect(plan.startDate, DateTime(2026, 8, 3));
      expect(plan.skeleton.weeks, isNotEmpty);

      // Read back through a completely fresh repository — a relaunch.
      final reloaded = await repo().load();
      expect(reloaded!.id, plan.id);

      // The current week was materialised eagerly, so today's card is backed by
      // a stored session from the moment the plan exists.
      expect(
        await store.loadWeek(reloaded, reloaded.weekIndexOn(today)),
        isNotNull,
      );
    });

    test('refuses to store a skeleton the validator rejects', () async {
      // Impossible rules: no ramp and no week-1 tolerance at all, so any real
      // skeleton violates them. The gate must refuse rather than persist.
      final strict = repo(
        rules: const PlanRules(maxWeeklyRampFraction: 0, week1Tolerance: 0),
      );

      await expectLater(
        strict.create(aProfile()),
        throwsA(isA<PlanStoreException>()),
      );

      // Nothing was written: a rejected plan leaves no trace.
      expect(await repo().load(), isNull);
      expect(await db.select(db.plans).get(), isEmpty);
    });

    test('running the coach again supersedes the first plan', () async {
      final first = await PlanRepository(
        store: store,
        now: () => today,
        newId: () => 'plan-a',
      ).create(aProfile());

      final second = await PlanRepository(
        store: store,
        now: () => today,
        newId: () => 'plan-b',
      ).create(aProfile());

      expect(first.id, 'plan-a');
      expect(second.id, 'plan-b');

      final active = await repo().load();
      expect(active!.id, 'plan-b');
      // Both rows survive; only one is active.
      expect(await db.select(db.plans).get(), hasLength(2));
    });

    test(
      'a stored plan still satisfies the validator it was gated on',
      () async {
        final plan = await repo().create(aProfile());
        final reloaded = (await repo().load())!;
        final result = validateSkeleton(reloaded.skeleton, reloaded.profile);
        expect(result.isValid, isTrue, reason: '${result.violations}');
        expect(reloaded.skeleton.weeks.length, plan.skeleton.weeks.length);
      },
    );
  });

  group('offline', () {
    test('reads need no network — a dead backup changes nothing', () async {
      final backup = _BrokenBackup();
      final plan = await repo(backup: backup).create(aProfile());

      // The backup was attempted and failed, and the plan is still on disk.
      expect(backup.attempts, greaterThan(0));

      final reloaded = await repo(backup: backup).load();
      expect(reloaded, isNotNull);
      expect(reloaded!.id, plan.id);

      final view = await repo(backup: backup).today(reloaded);
      expect(view.slot.index, reloaded.weekIndexOn(today));
    });

    test('a failing backup does not fail a mark', () async {
      final backup = _BrokenBackup();
      final r = repo(backup: backup);
      final plan = await r.create(aProfile());

      // Pick a day that actually has a session this week.
      final week = await r.weekFor(plan, plan.weekOn(today));
      final date = plan.dateFor(
        weekIndex: plan.weekIndexOn(today),
        weekday: week.runs.first.weekday,
      );
      final onDay = repo(backup: backup, now: () => date);

      expect(await onDay.markToday(plan, SessionStatus.completed), isTrue);
      expect((await onDay.today(plan)).status, SessionStatus.completed);
    });

    test('with no backup configured at all, everything still works', () async {
      final plan = await repo().create(aProfile());
      final view = await repo().today(plan);
      expect(view.slot, isNotNull);
    });
  });

  group('backup is reached', () {
    test('creating a plan mirrors the plan and its first week', () async {
      final backup = _RecordingBackup();
      await repo(backup: backup).create(aProfile());
      expect(backup.calls, contains('plan:plan-fixed'));
      expect(backup.calls.any((c) => c.startsWith('week:')), isTrue);
    });
  });

  group('today', () {
    test(
      'resolves the week from the calendar, not from plan creation',
      () async {
        final plan = await repo().create(aProfile());

        // Week 1 on creation day — which is now *before* the plan starts, and
        // still week 1: a progressing plan clamps at its own beginning.
        expect((await repo().today(plan)).slot.index, 1);

        // Nine days after the start the runner is in week 2 — the bug
        // persistence exposes: a stored plan must not keep insisting it is
        // week 1 forever. Counted from the start date rather than from
        // creation day, which since ADR-0034 are five days apart.
        final later = repo(now: () => DateTime(2026, 8, 12, 7));
        expect((await later.today(plan)).slot.index, 2);

        // Four weeks after that, week 5.
        final muchLater = repo(now: () => DateTime(2026, 9, 2, 7));
        expect((await muchLater.today(plan)).slot.index, 5);
      },
    );

    test(
      'a rest day reports no session, distinct from an ungenerated week',
      () async {
        final plan = await repo().create(aProfile());
        final week = await repo().weekFor(plan, plan.weekOn(today));
        final restDay = <int>[
          for (var d = 1; d <= 7; d++)
            if (week.runOn(d) == null) d,
        ].first;

        final onRest = repo(
          now: () => plan.dateFor(weekIndex: 1, weekday: restDay),
        );
        final view = await onRest.today(plan);
        expect(view.session, isNull);
        expect(view.status, SessionStatus.planned);
      },
    );

    test(
      'materialises a week the first time it is needed, then reuses it',
      () async {
        final plan = await repo().create(aProfile());
        final slot = plan.skeleton.weeks[6];
        expect(await store.loadWeek(plan, slot.index), isNull);

        final first = await repo().weekFor(plan, slot);
        expect(await store.loadWeek(plan, slot.index), isNotNull);

        // The stored week is returned verbatim next time, so a status set against
        // it is not quietly regenerated away.
        final second = await repo().weekFor(plan, slot);
        expect(
          second.runs.map((s) => s.weekday),
          first.runs.map((s) => s.weekday),
        );
      },
    );

    test('a plan run past its final week clamps to the last week', () async {
      final plan = await repo().create(aProfile());
      final wayLater = repo(now: () => DateTime(2027, 6, 1));
      expect(
        (await wayLater.today(plan)).slot.index,
        plan.skeleton.weeks.length,
      );
    });
  });

  group('markToday', () {
    test('is durable the moment it returns', () async {
      final r = repo();
      final plan = await r.create(aProfile());
      final week = await r.weekFor(plan, plan.weekOn(today));
      final day = week.runs.first.weekday;
      final date = plan.dateFor(weekIndex: 1, weekday: day);

      final onDay = repo(now: () => date);
      expect(await onDay.markToday(plan, SessionStatus.completed), isTrue);

      // Simulate a force-quit: everything in memory is gone, only rows remain.
      final afterRestart = PlanRepository(
        store: DriftPlanStore(db),
        now: () => date,
      );
      final reloaded = (await afterRestart.load())!;
      expect(
        (await afterRestart.today(reloaded)).status,
        SessionStatus.completed,
      );
    });

    test(
      'returns false on a rest day rather than pretending it saved',
      () async {
        final r = repo();
        final plan = await r.create(aProfile());
        final week = await r.weekFor(plan, plan.weekOn(today));
        final restDay = <int>[
          for (var d = 1; d <= 7; d++)
            if (week.runOn(d) == null) d,
        ].first;

        final onRest = repo(
          now: () => plan.dateFor(weekIndex: 1, weekday: restDay),
        );
        expect(await onRest.markToday(plan, SessionStatus.completed), isFalse);
      },
    );

    test('undo returns the session to planned, durably', () async {
      final r = repo();
      final plan = await r.create(aProfile());
      final week = await r.weekFor(plan, plan.weekOn(today));
      final date = plan.dateFor(weekIndex: 1, weekday: week.runs.first.weekday);
      final onDay = repo(now: () => date);

      await onDay.markToday(plan, SessionStatus.skipped);
      await onDay.markToday(plan, SessionStatus.planned);

      final afterRestart = PlanRepository(
        store: DriftPlanStore(db),
        now: () => date,
      );
      expect(
        (await afterRestart.today((await afterRestart.load())!)).status,
        SessionStatus.planned,
      );
    });
  });

  group('InMemoryPlanStore', () {
    // The default when nothing is injected, and what the preview harness uses.
    // It must honour the same contract so the tab has one code path.
    test('behaves like the durable store within a session', () async {
      final memory = InMemoryPlanStore();
      final r = repo(on: memory);
      final plan = await r.create(aProfile());

      expect((await r.load())!.id, plan.id);

      final week = await r.weekFor(plan, plan.weekOn(today));
      final date = plan.dateFor(weekIndex: 1, weekday: week.runs.first.weekday);
      final onDay = repo(on: memory, now: () => date);

      expect(await onDay.markToday(plan, SessionStatus.completed), isTrue);
      expect((await onDay.today(plan)).status, SessionStatus.completed);
    });

    test('a new plan clears the previous plan\'s weeks and marks', () async {
      final memory = InMemoryPlanStore();
      await PlanRepository(
        store: memory,
        now: () => today,
        newId: () => 'plan-a',
      ).create(aProfile());

      final second = await PlanRepository(
        store: memory,
        now: () => today,
        newId: () => 'plan-b',
      ).create(aProfile());

      expect((await repo(on: memory).load())!.id, 'plan-b');
      // Week 1 of the new plan was materialised by create; week 5 was not.
      expect(await memory.loadWeek(second, 5), isNull);
    });
  });

  group('the model generates the plan', () {
    // For a year nothing constructed PlanService outside its own tests, so
    // every plan Runio produced was the deterministic fallback wearing the
    // coach's name. These tests are what stops that being true again.
    test('create asks the model for the arc and the first two weeks', () async {
      final client = _CountingClient();
      await repo(generator: PlanService(client: client)).create(aProfile());

      expect(client.skeletons, greaterThan(0), reason: 'the arc is generated');
      // This week and the next, both under the one spinner — one week ahead is
      // what plan-generation.md asks for, and doing it here is what keeps the
      // render path off the network.
      expect(client.weeks, greaterThan(0));
    });

    test('a plan is still created when the model is unreachable', () async {
      // The runner does not get told "no plan" because a provider was down.
      final client = _CountingClient(dead: true);
      final plan = await repo(
        generator: PlanService(client: client),
      ).create(aProfile());

      expect(plan.skeleton.weeks, isNotEmpty);
      expect(
        await store.loadWeek(plan, plan.skeleton.weeks.first.index),
        isNotNull,
      );
    });

    test('no generator means a plan built entirely in Dart', () async {
      final plan = await repo().create(aProfile());
      expect(plan.skeleton.weeks, isNotEmpty);
    });
  });

  group('reading a plan never touches the network', () {
    // The load-bearing one (CLAUDE.md rule 1). Every caller of weekFor but
    // create and lookAhead is a screen already drawn: the Today card, the week
    // ribbon, the calendar. A model call on any of them hangs the Coach tab for
    // as long as the network takes to fail — and PlanService only falls back
    // after two attempts have timed out, so the runner in a tunnel waits twice
    // for an answer Dart could have given at once.
    test('weekFor does not reach the model by default', () async {
      final client = _CountingClient();
      final generator = PlanService(client: client);
      final plan = await repo(generator: generator).create(aProfile());

      final before = client.calls;
      // A week create did not materialise, asked for the way a screen asks.
      final far = plan.skeleton.weeks.last;
      final week = await repo(generator: generator).weekFor(plan, far);

      expect(week.sessions, isNotEmpty, reason: 'still a real week');
      expect(
        client.calls,
        before,
        reason: 'a screen that is already drawn must not wait on a provider',
      );
    });

    test('today() builds its week locally too', () async {
      final client = _CountingClient();
      final generator = PlanService(client: client);
      final plan = await repo(generator: generator).create(aProfile());

      final before = client.calls;
      // Three weeks on: a week create never wrote, reached through the Today
      // card rather than directly.
      final later = repo(
        generator: generator,
        now: () => today.add(const Duration(days: 21)),
      );
      final view = await later.today(plan);

      expect(view.slot, isNotNull);
      expect(client.calls, before);
    });

    test('weekFor(allowModel: true) is the one that may wait', () async {
      final client = _CountingClient();
      final generator = PlanService(client: client);
      final plan = await repo(generator: generator).create(aProfile());

      final before = client.calls;
      await repo(
        generator: generator,
      ).weekFor(plan, plan.skeleton.weeks.last, allowModel: true);

      expect(client.calls, greaterThan(before));
    });
  });

  group('history', () {
    // Every plan Runio ever built is on disk — savePlan supersedes rather than
    // deletes — and until now nothing read them back, so a runner two blocks in
    // looked exactly like one who had just arrived.
    test('a superseded plan is still in the history', () async {
      final first = await PlanRepository(
        store: store,
        now: () => today,
        newId: () => 'plan-a',
      ).create(aProfile());
      await PlanRepository(
        store: store,
        now: () => today.add(const Duration(days: 200)),
        newId: () => 'plan-b',
      ).create(aProfile());

      final history = await store.loadHistory();

      expect(history, hasLength(2));
      expect(history.first.id, first.id, reason: 'oldest first');
      expect(history.first.isActive, isFalse);
      expect(history.last.isActive, isTrue);
    });

    test("a plan's end is the next plan's creation", () async {
      // Derived rather than stored. A `supersededAt` column would be a second
      // copy of a fact the ordering already carries, and the two would drift.
      await PlanRepository(
        store: store,
        now: () => today,
        newId: () => 'plan-a',
      ).create(aProfile());
      await PlanRepository(
        store: store,
        now: () => today,
        newId: () => 'plan-b',
      ).create(aProfile());

      final history = await store.loadHistory();

      expect(history.first.endedAt, isNotNull);
      expect(
        history.last.endedAt,
        isNull,
        reason: 'nothing has replaced the current plan',
      );
    });

    test('one plan is a history of one, and it is the current one', () async {
      await repo().create(aProfile());
      final history = await store.loadHistory();

      expect(history, hasLength(1));
      expect(history.single.isActive, isTrue);
      expect(history.single.outcome, PlanOutcome.current);
    });

    test('no plans is an empty history, not an error', () async {
      expect(await store.loadHistory(), isEmpty);
    });

    test('the week count survives without loading the skeleton', () async {
      // History is read on the way into a screen, so it must stay cheap: the
      // count is on the row and the weeks are never touched.
      final plan = await repo().create(aProfile());
      final history = await store.loadHistory();

      expect(history.single.weeks, plan.skeleton.weeks.length);
      expect(history.single.weeks, greaterThan(1));
    });

    test('the in-memory store keeps a history too', () async {
      // Otherwise the preview and every widget test would show a runner who has
      // never had a plan, and the feature would look broken everywhere but on
      // a device.
      final memory = InMemoryPlanStore(now: () => today);
      await PlanRepository(
        store: memory,
        now: () => today,
        newId: () => 'plan-a',
      ).create(aProfile());
      await PlanRepository(
        store: memory,
        now: () => today,
        newId: () => 'plan-b',
      ).create(aProfile());

      final history = await memory.loadHistory();
      expect(history, hasLength(2));
      expect(history.first.id, 'plan-a');
      expect(history.last.isActive, isTrue);
    });

    test('labels come out stable and oldest-first', () async {
      await PlanRepository(
        store: store,
        now: () => today,
        newId: () => 'plan-a',
      ).create(aProfile());
      await PlanRepository(
        store: store,
        now: () => today,
        newId: () => 'plan-b',
      ).create(aProfile());

      final labelled = labelPlans(await store.loadHistory());
      expect(labelled.map((p) => p.label), <String>[
        'Marathon plan 1',
        'Marathon plan 2',
      ]);
    });
  });

  group('lookAhead', () {
    // create() already materialises this week and the next, so every test here
    // reads the clock three weeks on: current and next are then both weeks
    // nothing has written yet, which is the state a runner is in every Monday.
    DateTime laterOn() => today.add(const Duration(days: 21));

    /// The slot lookAhead would fill, three weeks after the plan was made.
    SkeletonWeek nextSlotFor(StoredPlan plan) {
      final current = plan.weekOn(laterOn());
      return plan.skeleton.weeks.firstWhere(
        (w) => w.index == current.index + 1,
      );
    }

    test('writes the coming week so the render path never has to', () async {
      // Answers with a real week, which is the only case that gets stored.
      final client = _CountingClient(week: buildsAWeek);
      final plan = await repo().create(aProfile());
      final slot = nextSlotFor(plan);
      expect(await store.loadWeek(plan, slot.index), isNull);

      final ahead = repo(
        // Both clocks have to agree, now that lookAhead hands the validator
        // a real weekStart (EDGE-17): PlanService's own `now` feeds
        // session_in_the_past, and defaults to the real wall clock if left
        // unset here, which would judge a week dated against `laterOn` by
        // a today it never claimed to be.
        generator: PlanService(client: client, now: laterOn),
        now: laterOn,
      );
      expect(await ahead.lookAhead(plan), isTrue);
      expect(await store.loadWeek(plan, slot.index), isNotNull);
    });

    test('is free once the week is on disk', () async {
      // Called on every load, so the second call must cost nothing — that is
      // what makes it safe to fire from a refresh rather than a scheduler.
      final client = _CountingClient(week: buildsAWeek);
      final plan = await repo().create(aProfile());
      final ahead = repo(
        generator: PlanService(client: client, now: laterOn),
        now: laterOn,
      );

      await ahead.lookAhead(plan);
      final after = client.calls;
      expect(await ahead.lookAhead(plan), isFalse);
      expect(client.calls, after);
    });

    test('a week the model did not write is not stored', () async {
      // The load-bearing one. A week on disk is never regenerated, so storing
      // the deterministic fallback here would make it the week the runner
      // trained — permanently, with nothing to say it was ever second choice.
      final plan = await repo().create(aProfile());
      final slot = nextSlotFor(plan);
      final dead = repo(
        generator: PlanService(client: _CountingClient(dead: true)),
        now: laterOn,
      );

      expect(
        await dead.lookAhead(plan),
        isFalse,
        reason: 'nothing was written',
      );
      expect(
        await store.loadWeek(plan, slot.index),
        isNull,
        reason: 'the slot stays open for the model to try again',
      );
    });

    test('no generator means no look-ahead at all', () async {
      final plan = await repo().create(aProfile());
      expect(await repo(now: laterOn).lookAhead(plan), isFalse);
    });
  });
}
