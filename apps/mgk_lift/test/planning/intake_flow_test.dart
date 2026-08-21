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
      const p = IntakeProgress(declined: <IntakeField>{IntakeField.weight});
      expect(p.has(IntakeField.weight), isTrue);
      expect(p.next, IntakeField.days);
    });

    test('body questions come last', () {
      const p = IntakeProgress(
        plan: PlanIntake(
          daysPerWeek: 4,
          equipment: 'A full gym',
          injuryNotes: 'none',
          goal: 'Get stronger',
        ),
      );
      expect(p.next, IntakeField.yearOfBirth);
    });

    test('progress counts answers, not position', () {
      const p = IntakeProgress(plan: PlanIntake(daysPerWeek: 4));
      expect(p.answered, 1);
      expect(p.total, 7);
      expect(p.isComplete, isFalse);
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
