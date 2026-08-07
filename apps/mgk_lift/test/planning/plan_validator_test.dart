import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/planning/domain/plan_proposal.dart';
import 'package:mgk_lift/src/features/planning/domain/plan_validator.dart';
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

ProposedMovement move(
  String name, {
  int sets = 3,
  int reps = 5,
  int? pct,
  String? note,
}) => ProposedMovement(
  name: name,
  sets: sets,
  reps: reps,
  intensityPct: pct,
  note: note,
);

ProposedSession session(int weekday, List<ProposedMovement> movements) =>
    ProposedSession(
      weekday: weekday,
      kind: 'push',
      movements: movements,
      rationale: 'Because your bench has not moved in three weeks.',
    );

const PlanProfile twoDays = PlanProfile(
  daysPerWeek: 2,
  availableWeekdays: <int>[1, 4],
);

const validator = PlanValidator();

void main() {
  swapTests();
  group('the weight is derived, never taken from the model', () {
    test('an intensity resolves against their own best set', () {
      // 100kg x 5 -> Epley e1RM 116.67. 80% is 93.3, rounded to 92.5 because
      // that is a bar somebody can actually load.
      final verdict = validator.check(
        WeekProposal(
          sessions: <ProposedSession>[
            session(1, <ProposedMovement>[
              move('Barbell Bench Press', pct: 80),
            ]),
            session(4, <ProposedMovement>[
              move('Barbell Bench Press', pct: 80),
            ]),
          ],
        ),
        profile: twoDays,
        log: <Session>[logged('Barbell Bench Press', kg: 100, reps: 5)],
      );

      expect(verdict.isAccepted, isTrue, reason: verdict.violations.join('; '));
      expect(verdict.sessions.first.movements.first.target?.kilograms, 92.5);
    });

    test('a movement they have never done gets no number at all', () {
      // The honest answer, and the one the whole design exists to protect. A
      // lifter two weeks in has almost no qualifying sets, so most of their
      // first plan is legitimately targetless.
      final verdict = validator.check(
        WeekProposal(
          sessions: <ProposedSession>[
            session(1, <ProposedMovement>[move('Barbell Back Squat', pct: 80)]),
            session(4, <ProposedMovement>[move('Barbell Back Squat', pct: 80)]),
          ],
        ),
        profile: twoDays,
        log: <Session>[logged('Barbell Bench Press', kg: 100, reps: 5)],
      );

      expect(verdict.isAccepted, isTrue, reason: verdict.violations.join('; '));
      expect(verdict.sessions.first.movements.first.target, isNull);
    });

    test('no intensity means no weight, without consulting the log', () {
      final verdict = validator.check(
        WeekProposal(
          sessions: <ProposedSession>[
            session(1, <ProposedMovement>[
              move(
                'Barbell Bench Press',
                reps: 12,
                note: 'leave two in the tank',
              ),
            ]),
            session(4, <ProposedMovement>[
              move('Barbell Bench Press', reps: 12),
            ]),
          ],
        ),
        profile: twoDays,
        log: <Session>[logged('Barbell Bench Press', kg: 100, reps: 5)],
      );

      expect(verdict.isAccepted, isTrue, reason: verdict.violations.join('; '));
      expect(verdict.sessions.first.movements.first.target, isNull);
      expect(
        verdict.sessions.first.movements.first.note,
        'leave two in the tank',
      );
    });

    test('a target is always a weight somebody can load', () {
      // 84.7kg is not a target, it is a number nobody can put on a bar, and it
      // makes the whole plan read as generated.
      for (final pct in <int>[72, 77, 83, 88]) {
        final verdict = validator.check(
          WeekProposal(
            sessions: <ProposedSession>[
              session(1, <ProposedMovement>[
                move('Barbell Bench Press', reps: 6, pct: pct),
              ]),
              session(4, <ProposedMovement>[
                move('Barbell Bench Press', reps: 6, pct: pct),
              ]),
            ],
          ),
          profile: twoDays,
          log: <Session>[logged('Barbell Bench Press', kg: 102.5, reps: 4)],
        );
        expect(
          verdict.isAccepted,
          isTrue,
          reason: verdict.violations.join('; '),
        );
        final kg = verdict.sessions.first.movements.first.target!.kilograms;
        expect(
          (kg / 2.5) % 1,
          0,
          reason: '$pct% resolved to ${kg}kg, which is not loadable',
        );
      }
    });

    test('a set too heavy to estimate from leaves no target', () {
      // estimateOneRepMax refuses above 12 reps, because Epley drifts badly
      // there and a confidently wrong PB is worse than none. That refusal has
      // to survive all the way to the plan rather than being papered over.
      final verdict = validator.check(
        WeekProposal(
          sessions: <ProposedSession>[
            session(1, <ProposedMovement>[
              move('Barbell Bench Press', reps: 5, pct: 80),
            ]),
            session(4, <ProposedMovement>[
              move('Barbell Bench Press', reps: 5, pct: 80),
            ]),
          ],
        ),
        profile: twoDays,
        log: <Session>[logged('Barbell Bench Press', kg: 40, reps: 20)],
      );
      expect(verdict.sessions.first.movements.first.target, isNull);
    });
  });

  group('the shape of a week', () {
    test('it has exactly as many sessions as they train', () {
      final verdict = validator.check(
        WeekProposal(
          sessions: <ProposedSession>[
            session(1, <ProposedMovement>[move('Barbell Bench Press')]),
          ],
        ),
        profile: twoDays,
        log: const <Session>[],
      );
      expect(verdict.isAccepted, isFalse);
      expect(verdict.violations.first, contains('exactly 2 sessions'));
    });

    test('it never lands on a day they said they cannot train', () {
      final verdict = validator.check(
        WeekProposal(
          sessions: <ProposedSession>[
            session(1, <ProposedMovement>[move('Barbell Bench Press')]),
            session(3, <ProposedMovement>[move('Barbell Bench Press')]),
          ],
        ),
        profile: twoDays,
        log: const <Session>[],
      );
      expect(verdict.isAccepted, isFalse);
      expect(
        verdict.violations.join(' '),
        contains('Move the Wednesday session'),
      );
    });

    test('it does not put two sessions on one day', () {
      final verdict = validator.check(
        WeekProposal(
          sessions: <ProposedSession>[
            session(1, <ProposedMovement>[move('Barbell Bench Press')]),
            session(1, <ProposedMovement>[move('Barbell Bench Press')]),
          ],
        ),
        profile: twoDays,
        log: const <Session>[],
      );
      expect(verdict.isAccepted, isFalse);
      expect(
        verdict.violations.join(' '),
        contains('Only one session on Monday'),
      );
    });

    test('a violation says what to do, so it can be sent straight back', () {
      // The list is the next attempt's brief, not a log line. "Give exactly 2
      // sessions" is actionable; "sessions.length != daysPerWeek" is not.
      final verdict = validator.check(
        WeekProposal(sessions: const <ProposedSession>[]),
        profile: twoDays,
        log: const <Session>[],
      );
      expect(verdict.isAccepted, isFalse);
      for (final v in verdict.violations) {
        expect(v, isNot(contains('_')), reason: 'reads like code: $v');
        expect(v.endsWith('.'), isTrue, reason: 'not a sentence: $v');
      }
    });
  });

  group('sets that are not sets', () {
    test('twelve reps at ninety percent is rejected', () {
      final verdict = validator.check(
        WeekProposal(
          sessions: <ProposedSession>[
            session(1, <ProposedMovement>[
              move('Barbell Bench Press', reps: 12, pct: 90),
            ]),
            session(4, <ProposedMovement>[move('Barbell Bench Press')]),
          ],
        ),
        profile: twoDays,
        log: const <Session>[],
      );
      expect(verdict.isAccepted, isFalse);
      expect(verdict.violations.join(' '), contains('is not a set'));
    });

    test('impossible sets and reps are rejected', () {
      final verdict = validator.check(
        WeekProposal(
          sessions: <ProposedSession>[
            session(1, <ProposedMovement>[
              move('Barbell Bench Press', sets: 40, reps: 60),
            ]),
            session(4, <ProposedMovement>[move('Barbell Bench Press')]),
          ],
        ),
        profile: twoDays,
        log: const <Session>[],
      );
      expect(verdict.isAccepted, isFalse);
      expect(verdict.violations.join(' '), contains('sets must be between'));
      expect(verdict.violations.join(' '), contains('reps must be between'));
    });

    test('a deload week is actually lighter, not just called one', () {
      // A deload that is only lighter in its intent sentence is not a deload,
      // and the whole point of the phase is that the week after it can be hard.
      const deload = PlanProfile(
        daysPerWeek: 2,
        availableWeekdays: <int>[1, 4],
        isDeload: true,
      );
      final verdict = validator.check(
        WeekProposal(
          sessions: <ProposedSession>[
            session(1, <ProposedMovement>[
              move('Barbell Bench Press', reps: 3, pct: 90),
            ]),
            session(4, <ProposedMovement>[move('Barbell Bench Press')]),
          ],
        ),
        profile: deload,
        log: const <Session>[],
      );
      expect(verdict.isAccepted, isFalse);
      expect(verdict.violations.join(' '), contains('deload week'));
    });
  });

  group('movements the app does not know', () {
    test('an invented variation is rejected by name', () {
      final verdict = validator.check(
        WeekProposal(
          sessions: <ProposedSession>[
            session(1, <ProposedMovement>[
              move('Reverse Banded Zercher Complex'),
            ]),
            session(4, <ProposedMovement>[move('Barbell Bench Press')]),
          ],
        ),
        profile: twoDays,
        log: const <Session>[],
      );
      expect(verdict.isAccepted, isFalse);
      expect(
        verdict.violations.join(' '),
        contains('not a movement this app knows'),
      );
    });
  });

  group('reading what the model sent', () {
    test('an integer that arrived as a double is still an integer', () {
      // Providers occasionally encode 3 as 3.0. Failing a whole week over a
      // JSON encoder's choice would be rejecting the training for the syntax.
      final proposal = WeekProposal.fromJson(<String, Object?>{
        'sessions': <Object?>[
          <String, Object?>{
            'weekday': 1.0,
            'kind': 'push',
            'rationale': 'ok',
            'movements': <Object?>[
              <String, Object?>{
                'name': 'Barbell Bench Press',
                'sets': 3.0,
                'reps': 5.0,
                'intensity_pct': 80.0,
              },
            ],
          },
        ],
      });
      expect(proposal.sessions.single.weekday, 1);
      expect(proposal.sessions.single.movements.single.sets, 3);
      expect(proposal.sessions.single.movements.single.intensityPct, 80);
    });

    test('junk becomes something the validator can refuse in words', () {
      // Rather than an exception three layers below the screen that has to
      // explain it.
      final proposal = WeekProposal.fromJson(<String, Object?>{
        'sessions': <Object?>[null, 'nope', 3],
      });
      expect(proposal.sessions, isEmpty);
      expect(WeekProposal.fromJson(<String, Object?>{}).sessions, isEmpty);
    });
  });
}

/// Mid-session substitution: "I don't like barbell bench press, swap it."
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
