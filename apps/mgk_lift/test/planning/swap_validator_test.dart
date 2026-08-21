import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/planning/domain/plan_proposal.dart';
import 'package:mgk_lift/src/features/planning/domain/swap_validator.dart';
import 'package:mgk_lift/src/features/tracking/domain/session.dart';

/// A finished session with one movement and one working set.
Session logged(String movement, {required double kg, required int reps}) =>
    Session(
      id: 's-$movement-$kg-$reps',
      name: 'Session',
      startedAt: DateTime(2026, 8, 1),
      endedAt: DateTime(2026, 8, 1, 1),
      exercises: <SessionExercise>[
        SessionExercise(
          id: 'e',
          name: movement,
          orderIndex: 0,
          sets: <SessionSet>[
            SessionSet(
              id: 'set',
              setNumber: 1,
              reps: reps,
              weightKg: kg,
              isCompleted: true,
            ),
          ],
        ),
      ],
    );

const validator = SwapValidator();

/// The swap the coach was asked for, as it arrives: JSON, through fromJson,
/// because that is the only way it ever reaches the validator.
SwapProposal swap(List<Map<String, Object?>> options, {String? reply}) =>
    SwapProposal.fromJson(<String, Object?>{
      'reply': reply ?? 'Try one of these instead.',
      'swap': <String, Object?>{
        'replaces': 'Barbell Bench Press',
        'options': options,
      },
    });

/// One option, with the fields a sane one has.
Map<String, Object?> option(
  String name, {
  int sets = 3,
  int reps = 8,
  int? pct,
  String why = 'Same pattern',
}) => <String, Object?>{
  'name': name,
  'sets': sets,
  'reps': reps,
  'intensity_pct': pct,
  'why': why,
};

void main() {
  swapTests();

  group('an option that is not a set of reps', () {
    test('twelve reps at ninety percent is rejected', () {
      // Not impossible to type, and impossible to do. The intensity and the
      // rep count have to describe the same effort or one of them is noise.
      final verdict = validator.checkSwap(
        swap(<Map<String, Object?>>[
          option('Dumbbell Bench Press', reps: 12, pct: 90),
        ]),
        log: <Session>[logged('Dumbbell Bench Press', kg: 40, reps: 8)],
      );
      expect(verdict.options, isEmpty);
      expect(verdict.dropped, 1);
    });

    test('impossible sets and reps are rejected', () {
      final verdict = validator.checkSwap(
        swap(<Map<String, Object?>>[
          option('Dumbbell Bench Press', sets: 40),
          option('Cable Fly', reps: 90),
          option('Dumbbell Fly', sets: 0),
        ]),
        log: const <Session>[],
      );
      expect(verdict.options, isEmpty);
      expect(verdict.dropped, 3);
    });
  });

  group('movements the app does not know', () {
    test('an invented variation is rejected by name', () {
      // A model will happily offer a movement that sounds real. The catalogue
      // is the only thing standing between that and a lifter looking for a
      // machine their gym has never had.
      final verdict = validator.checkSwap(
        swap(<Map<String, Object?>>[
          option('Reverse Grip Hammer Incline Machine Press'),
          option('Dumbbell Bench Press'),
        ]),
        log: const <Session>[],
      );
      expect(verdict.options.map((m) => m.name), <String>[
        'Dumbbell Bench Press',
      ]);
      expect(verdict.dropped, 1);
    });
  });

  group('the weight is derived, never taken from the model', () {
    test('an intensity resolves against their own best set', () {
      // 100kg x 5 -> Epley e1RM 116.67. 80% is 93.3, rounded to 92.5 because
      // that is a bar somebody can actually load.
      final verdict = validator.checkSwap(
        swap(<Map<String, Object?>>[
          option('Barbell Bench Press', reps: 5, pct: 80),
        ]),
        log: <Session>[logged('Barbell Bench Press', kg: 100, reps: 5)],
      );
      expect(verdict.options.single.target?.kilograms, 92.5);
    });

    test('no intensity means no weight, without consulting the log', () {
      // The default, and deliberately so. Most of what a coach offers mid-set
      // is "three by eight, something you can control" — a number there would
      // be invented even though the log could supply one.
      final verdict = validator.checkSwap(
        swap(<Map<String, Object?>>[option('Barbell Bench Press', reps: 12)]),
        log: <Session>[logged('Barbell Bench Press', kg: 100, reps: 5)],
      );
      expect(verdict.options.single.target, isNull);
    });
  });
}

void swapTests() {
  SwapProposal swap(List<Map<String, Object?>> options, {String? reply}) =>
      SwapProposal.fromJson(<String, Object?>{
        'reply': reply ?? 'Try one of these instead.',
        'swap': <String, Object?>{
          'replaces': 'Barbell Bench Press',
          'options': options,
        },
      });

  group('swapping a movement mid-session', () {
    test('a usable option comes back with its target derived', () {
      final verdict = validator.checkSwap(
        swap(<Map<String, Object?>>[
          <String, Object?>{
            'name': 'Dumbbell Bench Press',
            'sets': 3,
            'reps': 8,
            'intensity_pct': 70,
            'why': 'Same pattern, kinder on the shoulder',
          },
        ]),
        log: <Session>[logged('Dumbbell Bench Press', kg: 40, reps: 8)],
      );

      expect(verdict.reply, 'Try one of these instead.');
      expect(verdict.replaces, 'Barbell Bench Press');
      expect(verdict.options.single.name, 'Dumbbell Bench Press');
      expect(verdict.why.single, 'Same pattern, kinder on the shoulder');
      // 40kg x 8 -> e1RM 50.67; 70% is 35.5, rounded to 35.
      expect(verdict.options.single.target?.kilograms, 35);
      expect(verdict.dropped, 0);
    });

    test('a substitute they have never done carries no number', () {
      // The common case, and the one the whole load rule protects: a swap is
      // usually to something new, which is exactly when a number would have to
      // be invented.
      final verdict = validator.checkSwap(
        swap(<Map<String, Object?>>[
          <String, Object?>{
            'name': 'Dumbbell Bench Press',
            'sets': 3,
            'reps': 8,
            'intensity_pct': 70,
            'why': 'Same pattern',
          },
        ]),
        log: <Session>[logged('Barbell Bench Press', kg: 100, reps: 5)],
      );
      expect(verdict.options.single.target, isNull);
    });

    test('a bad option is dropped and the good ones survive', () {
      // The trade that separates this from a week: the lifter is standing
      // between sets. Failing the whole answer because the second suggestion
      // was nonsense would be the worst reading of "the validator disposes".
      final verdict = validator.checkSwap(
        swap(<Map<String, Object?>>[
          <String, Object?>{
            'name': 'Dumbbell Bench Press',
            'sets': 3,
            'reps': 8,
            'intensity_pct': null,
            'why': 'Same pattern',
          },
          <String, Object?>{
            'name': 'Reverse Banded Zercher Complex',
            'sets': 3,
            'reps': 8,
            'intensity_pct': null,
            'why': 'Invented',
          },
          <String, Object?>{
            'name': 'Machine Chest Press',
            'sets': 99,
            'reps': 8,
            'intensity_pct': null,
            'why': 'Impossible',
          },
        ]),
        log: const <Session>[],
      );

      expect(verdict.options.map((m) => m.name), <String>[
        'Dumbbell Bench Press',
      ]);
      expect(verdict.why, <String>['Same pattern']);
      expect(verdict.dropped, 2);
      expect(verdict.hasOptions, isTrue);
    });

    test('the reply survives even when nothing else does', () {
      // "Just skip it today" is a complete answer, and so is a reply whose
      // every suggestion turned out to be unusable.
      final verdict = validator.checkSwap(
        swap(<Map<String, Object?>>[
          <String, Object?>{
            'name': 'Reverse Banded Zercher Complex',
            'sets': 3,
            'reps': 8,
            'intensity_pct': null,
            'why': 'Invented',
          },
        ], reply: 'Honestly, skip it today and come back to it Thursday.'),
        log: const <Session>[],
      );

      expect(verdict.hasOptions, isFalse);
      expect(verdict.dropped, 1);
      expect(
        verdict.reply,
        'Honestly, skip it today and come back to it Thursday.',
      );
    });

    test('an answer with no substitution at all is still an answer', () {
      final verdict = validator.checkSwap(
        SwapProposal.fromJson(<String, Object?>{
          'reply': 'That is soreness rather than pain, so I would keep it in.',
          'swap': null,
        }),
        log: const <Session>[],
      );
      expect(verdict.reply, startsWith('That is soreness'));
      expect(verdict.replaces, isNull);
      expect(verdict.hasOptions, isFalse);
      expect(verdict.dropped, 0);
    });

    test('an empty option list is not the same as no substitution', () {
      // The coach proposed a swap and then had nothing worth suggesting, which
      // the prompt permits. `replaces` is what tells them apart.
      final verdict = validator.checkSwap(
        swap(const <Map<String, Object?>>[]),
        log: const <Session>[],
      );
      expect(verdict.replaces, 'Barbell Bench Press');
      expect(verdict.hasOptions, isFalse);
      expect(verdict.dropped, 0);
    });
  });
}
