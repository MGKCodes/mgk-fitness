import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/coaching/data/drift_plan_store.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_shape.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/presentation/session_labels.dart';

/// The runner's own word for their own session.
///
/// It survived on the plan's headline, which reads the profile, and died on the
/// week, which goes through storage — so one screen said "Your parkrun week"
/// over a Saturday labelled "Easy". Found by building a real rhythm plan; the
/// seeded persona hid it, because an in-memory store round-trips the object
/// without a schema in the way.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  RunnerProfile parkrunner() => const RunnerProfile(
    currentWeeklyMeters: 15000,
    longestRecentMeters: 8000,
    daysPerWeek: 3,
    availableWeekdays: <int>{
      DateTime.tuesday,
      DateTime.thursday,
      DateTime.saturday,
    },
    commitments: <PlanCommitment>[
      PlanCommitment(
        weekday: DateTime.saturday,
        distanceMeters: 5000,
        label: 'parkrun',
      ),
    ],
  );

  test('survives the trip to disk and back', () async {
    final store = DriftPlanStore(db);
    final repo = PlanRepository(store: store);
    final plan = await repo.create(parkrunner());

    // Read through the store, which is what every screen does — not the
    // in-memory object the builder just returned.
    final week = await repo.weekFor(plan, plan.weekOn(DateTime.now()));
    final saturday = week.runOn(DateTime.saturday);

    expect(saturday, isNotNull);
    expect(saturday!.label, 'parkrun');
    expect(
      sessionName(saturday),
      'parkrun',
      reason: 'the week must call it what the headline calls it',
    );
  });

  test('a session nobody named still reads as its kind', () async {
    final store = DriftPlanStore(db);
    final repo = PlanRepository(store: store);
    final plan = await repo.create(parkrunner());
    final week = await repo.weekFor(plan, plan.weekOn(DateTime.now()));

    final unnamed = week.runs.where((s) => s.weekday != DateTime.saturday);
    expect(unnamed, isNotEmpty);
    for (final session in unnamed) {
      expect(session.label, isNull);
      expect(sessionName(session), isNot('parkrun'));
    }
  });

  test('the plan is a rhythm, so this is the shape that needs it', () async {
    expect(shapeOf(parkrunner()), PlanShape.rhythm);
  });

  /// The activity, and an hour only where there is one.
  ///
  /// A runner recognises "Afternoon easy run" as a thing they did; "Easy" is
  /// the coach telling them how hard. The first half of that is unconditional.
  /// The second half is not: Strava can say "Afternoon Run" because the run
  /// already happened, and a Wednesday four days out has no hour attached to
  /// it — so putting one there would be the app stating a fact it does not
  /// hold.
  group('the activity, not the physiology', () {
    const easy = PlannedSession(
      weekday: DateTime.wednesday,
      kind: SessionKind.easy,
      distanceMeters: 5000,
    );
    const parkrun = PlannedSession(
      weekday: DateTime.saturday,
      kind: SessionKind.timeTrial,
      distanceMeters: 5000,
      label: 'parkrun',
    );
    final afternoon = DateTime(2026, 7, 20, 14, 2);

    test('every kind names something a person does', () {
      expect(kindLabel(SessionKind.easy), 'Easy run');
      expect(kindLabel(SessionKind.threshold), 'Threshold run');
      expect(kindLabel(SessionKind.recovery), 'Recovery run');
      expect(kindLabel(SessionKind.long), 'Long run');
      expect(kindLabel(SessionKind.marathonPace), 'Marathon pace run');
      // Already activities. Nothing to attach them to.
      expect(kindLabel(SessionKind.interval), 'Intervals');
      expect(kindLabel(SessionKind.timeTrial), 'Time trial');
    });

    test('except the two that are not runs', () {
      // "Rest run" is nonsense, and strength is a session this app does not
      // prescribe at all (ADR-0010).
      expect(kindLabel(SessionKind.rest), 'Rest');
      expect(kindLabel(SessionKind.strength), 'Strength');
    });

    // The rule this group exists for.
    test('a session with no hour yet is never given one', () {
      expect(sessionName(easy), 'Easy run');
      expect(
        sessionName(easy),
        isNot(
          matches(RegExp('morning|afternoon|evening', caseSensitive: false)),
        ),
        reason: 'a planned Wednesday has no time of day to report',
      );
    });

    test('and neither is any day of a real, built week', () async {
      // Through the store, like every screen: the week list is the surface that
      // would tempt someone into passing DateTime.now() for all seven rows.
      final repo = PlanRepository(store: DriftPlanStore(db));
      final plan = await repo.create(parkrunner());
      final week = await repo.weekFor(plan, plan.weekOn(DateTime.now()));

      expect(week.runs, isNotEmpty);
      for (final session in week.runs) {
        expect(
          sessionName(session),
          isNot(
            matches(RegExp('morning|afternoon|evening', caseSensitive: false)),
          ),
        );
      }
    });

    test('today and a recorded run do get one, because they have one', () {
      expect(sessionNameAt(easy, DateTime(2026, 7, 20, 9)), 'Morning easy run');
      expect(sessionNameAt(easy, afternoon), 'Afternoon easy run');
      expect(
        sessionNameAt(easy, DateTime(2026, 7, 20, 19)),
        'Evening easy run',
      );
      expect(runName(afternoon), 'Afternoon run');
    });

    test('the runner\'s own word takes no prefix and no rewrite', () {
      expect(sessionName(parkrun), 'parkrun');
      expect(
        sessionNameAt(parkrun, DateTime(2026, 7, 25, 9)),
        'parkrun',
        reason: 'a prefix on a name they chose is still renaming it',
      );
    });

    test('and rest is not an occasion', () {
      const restDay = PlannedSession(
        weekday: DateTime.thursday,
        kind: SessionKind.rest,
      );
      expect(sessionNameAt(restDay, afternoon), 'Rest');
    });

    test('the boundaries are the ones Home already greets on', () {
      // Two answers to "what time of day is it" in one app is a bug waiting
      // for six o'clock.
      expect(timeOfDayName(DateTime(2026, 7, 20, 0)), 'Morning');
      expect(timeOfDayName(DateTime(2026, 7, 20, 11, 59)), 'Morning');
      expect(timeOfDayName(DateTime(2026, 7, 20, 12)), 'Afternoon');
      expect(timeOfDayName(DateTime(2026, 7, 20, 17, 59)), 'Afternoon');
      expect(timeOfDayName(DateTime(2026, 7, 20, 18)), 'Evening');
      expect(timeOfDayName(DateTime(2026, 7, 20, 23, 59)), 'Evening');
    });
  });
}
