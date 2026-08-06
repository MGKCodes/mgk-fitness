import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/coaching/data/drift_plan_store.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_shape.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
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
}
