import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/planning/domain/intake_flow.dart';
import 'package:mgk_lift/src/features/planning/domain/plan_intake.dart';
import 'package:mgk_lift/src/features/planning/domain/training_split.dart';

void main() {
  group('what to ask next', () {
    test('opens on days, which is the one the split is chosen from', () {
      expect(const IntakeProgress().next, IntakeField.days);
    });

    test('answering three at once skips all three', () {
      // The whole reason this asks for the first MISSING field rather than the
      // next in a script: somebody who types "4 days, home gym, bad shoulder"
      // must not then be asked those three separately.
      const p = IntakeProgress(
        plan: PlanIntake(
          daysPerWeek: 4,
          equipment: 'Home, with weights',
          injuryNotes: 'left shoulder',
        ),
      );
      expect(p.next, IntakeField.goal);
      expect(p.answered, 3);
    });

    test('a declined question counts as answered', () {
      // Otherwise the flow asks for ever, and asking twice is not accepting an
      // answer somebody already gave.
      const p = IntakeProgress(declined: <IntakeField>{IntakeField.goal});
      expect(p.has(IntakeField.goal), isTrue);
      expect(p.next, IntakeField.days);
    });

    test('declining the last one finishes the intake', () {
      const p = IntakeProgress(
        plan: PlanIntake(
          daysPerWeek: 4,
          equipment: 'A full gym',
          injuryNotes: 'none',
        ),
      );
      expect(p.isComplete, isFalse);
      expect(p.decline(IntakeField.goal).isComplete, isTrue);
    });

    test('progress counts answers, not position', () {
      const p = IntakeProgress(plan: PlanIntake(daysPerWeek: 4));
      expect(p.answered, 1);
      expect(p.total, 4);
      expect(p.isComplete, isFalse);
    });

    test('merging is a fold, so an earlier answer survives a later turn', () {
      // Every intake turn returns every field, and a null means "not learned
      // this turn". Replacing rather than merging would erase the days as soon
      // as the next question was asked.
      final p = const IntakeProgress(
        plan: PlanIntake(daysPerWeek: 4),
      ).merge(const PlanIntake(goal: 'Get stronger'));
      expect(p.plan.daysPerWeek, 4);
      expect(p.plan.goal, 'Get stronger');
    });
  });

  group('the questions that are not asked', () {
    test('no body facts, because core has nowhere to put them', () {
      // docs/coach-profile.md puts height, weight and year of birth in `core`
      // and opens by saying none of it is built. This flow asked for all three
      // and the answers had no table to land in. If that schema arrives, this
      // is the test that should fail.
      expect(IntakeField.values, <IntakeField>[
        IntakeField.days,
        IntakeField.equipment,
        IntakeField.injuries,
        IntakeField.goal,
      ]);
    });

    test('only days is required', () {
      expect(IntakeField.values.where((f) => f.required), <IntakeField>[
        IntakeField.days,
      ]);
    });
  });

  group('what is offered under a question', () {
    test('days offers no way out, because a plan needs it', () {
      expect(IntakeField.days.skip, isNull);
      expect(IntakeField.days.offered, IntakeField.days.options);
    });

    test('a skippable field carries its way out last', () {
      expect(IntakeField.goal.offered.last, 'Prefer not to say');
      expect(
        IntakeField.goal.offered.length,
        IntakeField.goal.options.length + 1,
      );
    });

    test('injuries decline by answering, and are not offered twice', () {
      // "Nothing to work around" is a real reply rather than a refusal, so a
      // "prefer not to say" underneath it would be two rows for one intention.
      expect(IntakeField.injuries.skip, 'Nothing to work around');
      expect(IntakeField.injuries.offered, IntakeField.injuries.options);
    });

    test('every field can be answered by tapping', () {
      for (final f in IntakeField.values) {
        expect(f.offered, isNotEmpty, reason: '${f.name} has no options');
        expect(f.question, isNotEmpty, reason: '${f.name} has no question');
      }
    });
  });

  group('the split follows the days', () {
    test('two or three days is full body', () {
      // Splitting at this frequency trains each part once a week, which is the
      // one arrangement the evidence is consistently against.
      expect(TrainingSplit.forDays(2), TrainingSplit.fullBody);
      expect(TrainingSplit.forDays(3), TrainingSplit.fullBody);
    });

    test('five days gets its own arrangement, not a cycle', () {
      // Neither split divides into five, and both failures are real: cycling
      // PPL trains legs once, cycling upper/lower runs Upper three times and
      // puts direct back volume past the cap. PlanShape caught both.
      expect(TrainingSplit.forDays(4), TrainingSplit.upperLower);
      expect(TrainingSplit.forDays(6), TrainingSplit.pushPullLegs);
      expect(TrainingSplit.forDays(5).weekFor(5), <String>[
        'Push',
        'Pull',
        'Legs',
        'Upper',
        'Lower',
      ]);
    });

    test('the week is trimmed to the days there are', () {
      expect(TrainingSplit.forDays(4).weekFor(4), <String>[
        'Upper',
        'Lower',
        'Upper',
        'Lower',
      ]);
      // Six days over a three-day cycle wraps rather than running out.
      expect(TrainingSplit.forDays(6).weekFor(6), <String>[
        'Push',
        'Pull',
        'Legs',
        'Push',
        'Pull',
        'Legs',
      ]);
    });
  });
}
