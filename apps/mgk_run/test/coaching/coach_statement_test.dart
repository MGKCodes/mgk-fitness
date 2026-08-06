import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_statement.dart';

/// The validator's whole job is to decide whether a generated line is safe to
/// put in front of a runner. Every case here is a sentence a model could
/// plausibly produce — fluent, confident, and in three of them, wrong in a way
/// the runner could never detect.
void main() {
  // What the app handed the model: 64.0 km this window against 36.0 before,
  // four weeks, averaging 5:03 against 5:30. No records.
  // `final`, not `const`: a Set literal holding doubles has no primitive
  // equality, so Dart refuses to build it at compile time.
  final facts = StatementFacts(
    allowedNumbers: <num>{64.0, 36.0, 4},
    allowedSeconds: const <int>{303, 330},
  );

  const fallback =
      'Running more than you were. 64.0 km in the last four '
      'weeks, up from 36.0 km the four before.';

  StatementResult choose(String? generated) => CoachStatement.choose(
    generated: generated,
    facts: facts,
    fallback: fallback,
  );

  group('accepts', () {
    test('a line that only uses the numbers it was given', () {
      final result = choose(
        'You are running more than you were: 64.0 km over the last four weeks '
        'against 36.0 km before that. Nice steady build.',
      );

      expect(result.usedModel, isTrue);
      expect(result.problems, isEmpty);
    });

    test('a number rounded to fewer digits, which is what a coach says', () {
      final result = choose('You have put in 64 km over four weeks.');

      expect(result.usedModel, isTrue);
    });

    test('paces it was given, written as clock times', () {
      final result = choose(
        'You are averaging 5:03 against 5:30, so the work is showing.',
      );

      expect(result.usedModel, isTrue);
    });

    test('a comparative, which is a comparison the app supplied', () {
      final result = choose('You are quicker than you were four weeks ago.');

      expect(result.usedModel, isTrue);
    });
  });

  group('refuses', () {
    test('a number it was never given', () {
      // 100 km is not in the facts. Fluent, plausible, and invented.
      final result = choose('That is 100 km in the last four weeks.');

      expect(result.usedModel, isFalse);
      expect(result.text, fallback);
      expect(result.problems.single, contains('100'));
    });

    test('a total it worked out for itself', () {
      // 64 + 36. The arithmetic is right, which is exactly what makes it
      // dangerous: the app never said it, so nothing has checked it.
      final result = choose('You have run 100.0 km across the two months.');

      expect(result.usedModel, isFalse);
    });

    test('a pace it was never given', () {
      final result = choose('You are averaging 4:45 now.');

      expect(result.usedModel, isFalse);
      expect(result.problems.single, contains('4:45'));
    });

    test('a personal best the runner did not set', () {
      final result = choose('64.0 km, and the fastest you have ever run.');

      expect(result.usedModel, isFalse);
      expect(result.problems.single, contains('fastestPace'));
    });

    test('a distance record the runner did not set', () {
      final result = choose('Your longest run yet, at 64.0 km.');

      expect(result.usedModel, isFalse);
      expect(result.problems.single, contains('longestRun'));
    });

    test('ranking the runner against other people', () {
      final result = choose(
        'That puts you faster than 60% of runners at your level.',
      );

      expect(result.usedModel, isFalse);
      expect(
        result.problems,
        contains('ranks the runner against other people'),
      );
    });

    test('grading the runner by age', () {
      final result = choose('That is a solid figure for a runner your age.');

      expect(result.usedModel, isFalse);
      expect(result.problems, contains('grades the runner by age'));
    });

    test('citing research it cannot show', () {
      final result = choose(
        'Studies show that easy running builds the engine.',
      );

      expect(result.usedModel, isFalse);
      expect(result.problems, contains('cites research it cannot show'));
    });

    test('naming a copyrighted training system', () {
      // Rule 5, enforced at runtime rather than hoped for: a model reciting
      // VDOT from memory is a licensing problem in a public repo.
      final result = choose('Your VDOT is coming up nicely.');

      expect(result.usedModel, isFalse);
      expect(result.problems, contains('names a copyrighted training system'));
    });

    test('prescribing training the validator never saw', () {
      final result = choose('Try 6 x 400 this week to sharpen up.');

      expect(result.usedModel, isFalse);
    });

    test('a wall of text where one line belongs', () {
      final result = choose('You are building. ${'Very steady. ' * 40}');

      expect(result.usedModel, isFalse);
      expect(result.problems.first, contains('too long'));
    });

    test('a list, which is not what this card is', () {
      final result = choose(
        'Here is where you are:\n- 64.0 km this month\n- 36.0 km before',
      );

      expect(result.usedModel, isFalse);
      expect(result.problems, contains(anyOf(contains('list'))));
    });
  });

  group('falls back', () {
    test('when there is no coach configured, or the call failed', () {
      expect(choose(null).text, fallback);
      expect(choose(null).usedModel, isFalse);
      expect(choose('   ').text, fallback);
    });

    test('and says why, so a retry can be told what to fix', () {
      final result = choose(
        'Your fastest ever, 100 km, faster than 60% of runners.',
      );

      // Every problem, not just the first — same as the plan validator.
      expect(result.problems.length, greaterThanOrEqualTo(3));
    });
  });

  group('earned claims', () {
    test('a superlative is allowed once Dart has established it', () {
      final withRecord = StatementFacts(
        allowedNumbers: <num>{18.4},
        claims: const <StatementClaim>{StatementClaim.longestRun},
      );

      final result = CoachStatement.choose(
        generated: 'Your longest run yet, at 18.4 km. Recover properly.',
        facts: withRecord,
        fallback: 'Longest one yet.',
      );

      expect(result.usedModel, isTrue);
    });
  });

  group('does not cry wolf', () {
    test('"record a run" is an invitation, not a boast', () {
      // The verb, not the noun. This exact line is the computed empty state,
      // and a validator that refuses our own fallback is broken.
      final result = CoachStatement.choose(
        generated: 'Record a run and there will be something to compare.',
        facts: const StatementFacts(),
        fallback: 'Nothing recorded yet.',
      );

      expect(result.usedModel, isTrue);
    });

    test('but "a new record" still needs to be earned', () {
      final result = CoachStatement.choose(
        generated: 'That is a new record for you.',
        facts: const StatementFacts(),
        fallback: 'Nothing recorded yet.',
      );

      expect(result.usedModel, isFalse);
    });
  });
}
