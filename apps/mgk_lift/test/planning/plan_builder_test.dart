import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/planning/domain/plan_intake.dart';
import 'package:mgk_lift/src/features/planning/domain/plan_builder.dart';
import 'package:mgk_lift/src/features/planning/domain/plan_template.dart';

/// A four-day Upper/Lower that clears every check, as JSON from the surface.
Map<String, Object?> goodJson() => <String, Object?>{
  'reply': 'Four days splits cleanly in half.',
  'name': 'Upper / Lower',
  'days': <Object?>[
    for (final day in <String>['Upper', 'Lower', 'Upper', 'Lower'])
      <String, Object?>{
        'day': day,
        'movements': day == 'Upper'
            ? <Object?>[
                mv('horizontal press', 'Barbell Bench Press', main: true),
                mv('vertical pull', 'Wide Grip Lat Pull Down', main: true),
                mv('horizontal row', 'Barbell Row'),
                mv('triceps', 'Cable Tricep Pushdown'),
              ]
            : <Object?>[
                mv('squat', 'Barbell Back Squat', main: true),
                mv('hinge', 'Barbell Romanian Deadlift', main: true),
                mv('quad accessory', 'Leg Press'),
                mv('calf', 'Calf Raise Machine'),
              ],
      },
  ],
};

Map<String, Object?> mv(String role, String movement, {bool main = false}) =>
    <String, Object?>{
      'role': role,
      'movement': movement,
      'is_main': main,
      'sets': main ? 4 : 3,
      'reps': main ? 6 : 10,
    };

const weekdays = <int>[1, 2, 4, 5];

void main() {
  test('a plan that clears the checks is used as the coach wrote it', () async {
    var calls = 0;
    final built =
        await PlanBuilder(
          propose:
              ({
                required intake,
                required weekdays,
                required catalogue,
                List<String> violations = const <String>[],
              }) async {
                calls++;
                return PlanProposal.fromJson(goodJson());
              },
        ).build(
          id: 'p',
          intake: const PlanIntake(),
          weekdays: weekdays,
          catalogue: const <String>[],
        );

    expect(built.fromCoach, isTrue);
    expect(calls, 1);
    expect(built.plan.name, 'Upper / Lower');
    expect(built.plan.rationale, contains('splits cleanly'));
    expect(built.plan.dayOrder, <String>['Upper', 'Lower', 'Upper', 'Lower']);
  });

  test('a rejected plan is retried with what was wrong', () async {
    // Violations go back verbatim, which is why PlanShape phrases them as
    // instructions rather than complaints.
    final handed = <List<String>>[];
    var calls = 0;
    final built =
        await PlanBuilder(
          propose:
              ({
                required intake,
                required weekdays,
                required catalogue,
                List<String> violations = const <String>[],
              }) async {
                handed.add(violations);
                calls++;
                if (calls == 1) {
                  // Legs trained once: the check that fires most often.
                  final bad = goodJson();
                  (bad['days'] as List)[3] = (bad['days'] as List)[0];
                  bad['days'] = (bad['days'] as List).sublist(0, 4);
                  return PlanProposal.fromJson(bad);
                }
                return PlanProposal.fromJson(goodJson());
              },
        ).build(
          id: 'p',
          intake: const PlanIntake(),
          weekdays: weekdays,
          catalogue: const <String>[],
        );

    expect(calls, 2);
    expect(handed.first, isEmpty);
    expect(handed[1], isNotEmpty);
    expect(built.fromCoach, isTrue);
  });

  test(
    'two failures fall back to a plan that clears the same checks',
    () async {
      // A duller plan beats no plan, and the floor is held to the same bar.
      final built =
          await PlanBuilder(
            propose:
                ({
                  required intake,
                  required weekdays,
                  required catalogue,
                  List<String> violations = const <String>[],
                }) async => PlanProposal.fromJson(<String, Object?>{
                  'reply': '',
                  'name': 'Nonsense',
                  'days': <Object?>[
                    <String, Object?>{
                      'day': 'Everything',
                      'movements': <Object?>[
                        mv('press', 'Not A Real Movement'),
                      ],
                    },
                  ],
                }),
          ).build(
            id: 'p',
            intake: const PlanIntake(),
            weekdays: weekdays,
            catalogue: const <String>[],
          );

      expect(built.fromCoach, isFalse);
      expect(built.violations, isNotEmpty);
      expect(built.plan.slots, isNotEmpty);
      expect(built.plan.dayOrder.length, weekdays.length);
    },
  );

  test('an unreachable coach goes straight to the floor', () async {
    // Not a reason to leave somebody without a plan, and not worth a retry.
    var calls = 0;
    final built =
        await PlanBuilder(
          propose:
              ({
                required intake,
                required weekdays,
                required catalogue,
                List<String> violations = const <String>[],
              }) async {
                calls++;
                throw StateError('no network');
              },
        ).build(
          id: 'p',
          intake: const PlanIntake(),
          weekdays: weekdays,
          catalogue: const <String>[],
          equipment: Equipment.homeWeights,
        );

    expect(calls, 1);
    expect(built.fromCoach, isFalse);
    expect(built.violations.single, contains('unavailable'));
  });

  test('a repeated day name is merged, first occurrence winning', () async {
    // Upper/Lower has two 'Upper' days by design. A coach that describes the
    // same day twice differently has contradicted itself, and taking the later
    // one would silently prefer whatever it wrote last.
    final built =
        await PlanBuilder(
          propose:
              ({
                required intake,
                required weekdays,
                required catalogue,
                List<String> violations = const <String>[],
              }) async => PlanProposal.fromJson(goodJson()),
        ).build(
          id: 'p',
          intake: const PlanIntake(),
          weekdays: weekdays,
          catalogue: const <String>[],
        );

    expect(built.plan.slots.keys.toSet(), <String>{'Upper', 'Lower'});
    expect(built.plan.slots['Upper']!.first.movement, 'Barbell Bench Press');
  });

  test('sets and reps survive the round trip', () async {
    final built =
        await PlanBuilder(
          propose:
              ({
                required intake,
                required weekdays,
                required catalogue,
                List<String> violations = const <String>[],
              }) async => PlanProposal.fromJson(goodJson()),
        ).build(
          id: 'p',
          intake: const PlanIntake(),
          weekdays: weekdays,
          catalogue: const <String>[],
        );

    final main = built.plan.slots['Upper']!.first;
    expect(main.sets, 4);
    expect(main.reps, 6);
  });

  test('a movement with no sets given is defaulted, not dropped', () async {
    // A plan worth checking rather than one worth throwing away.
    final m = ProposedSlot.fromJson(<String, Object?>{
      'role': 'r',
      'movement': 'Barbell Row',
      'is_main': false,
    });
    expect(m.sets, 3);
    expect(m.reps, 10);
  });
}
