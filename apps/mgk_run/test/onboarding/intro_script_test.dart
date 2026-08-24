import 'package:mgk_run/src/core/brand.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_script.dart';

/// The conversation the app opens with, before there is an account.
///
/// **Moment one** of two (ADR-0019). It ends with a free account and a working
/// run tracker. What it used to also do — ask what the runner was training for,
/// and state a price — moved to the plan flow; those tests moved with it, to
/// `test/coaching/shape_question_test.dart` and
/// `test/coaching/plan_gate_copy_test.dart`.
void main() {
  /// Every line the runner can see in moment one, both with a name and
  /// without. Several tests want the whole set.
  final everything = <String>[
    for (final step in IntroStep.values) introPrompt(step, name: 'Sam'),
    for (final step in IntroStep.values) introPrompt(step),
    introWhoIAm,
    introHowItWorks,
  ];

  group('the coach introduces itself like a person', () {
    test('it says hello and thanks them for turning up', () {
      // This is the first sentence anybody reads. It used to be "I'm your
      // coach." full stop, which is a job title, not a greeting.
      final greeting = introPrompt(IntroStep.greeting).toLowerCase();
      expect(greeting, contains('hey'));
      expect(greeting, contains('thanks'));
    });

    test('and tells them what to call it', () {
      // The coach has no name and no gender. It is the role, not a character,
      // so "Coach" is the whole of its identity and this is where a runner
      // learns that.
      expect(introWhoIAm.toLowerCase(), contains('coach'));
    });

    test('without announcing itself as an AI', () {
      // It said "I'm an AI" briefly. That is not how a coach talks, and a
      // first impression is not a disclosure notice — the store listing, the
      // README and the privacy policy are where that question gets answered.
      expect(
        RegExp(r'\bai\b').hasMatch(introWhoIAm.toLowerCase()),
        isFalse,
        reason: 'the coach introduces a role, not an implementation',
      );
    });

    test('then says what the app does, before it asks for anything', () {
      // A runner who has been told what the thing does has a reason to give a
      // name and a reason to grant a permission.
      expect(introHowItWorks.toLowerCase(), contains('track'));
      expect(introHowItWorks.toLowerCase(), contains('plan'));
    });

    test('and describes what it does rather than how it is worked', () {
      // This line briefly explained the mechanics — "press start", telling the
      // coach about a run done without a phone. Both are true and neither
      // means anything to somebody who has not seen a screen of the app yet.
      // Mechanics are learned by using the thing.
      for (final mechanic in <String>[
        'press start',
        'tap',
        'button',
        'swipe',
      ]) {
        expect(
          introHowItWorks.toLowerCase(),
          isNot(contains(mechanic)),
          reason: '"$mechanic" names an affordance they have not seen yet',
        );
      }
    });
  });

  group('what the coach says', () {
    test('greets by name once it has one', () {
      expect(introPrompt(IntroStep.permissions, name: 'Sam'), contains('Sam'));
    });

    test('and does not invent one where the runner skipped it', () {
      final said = introPrompt(IntroStep.permissions);
      expect(said, isNot(contains('null')));
      expect(said, isNotEmpty);
    });

    test('the form is asked for as one profile across both apps', () {
      // ADR-0008: the two apps share an identity. A runner finding that out
      // later, from a delete-account screen, is finding it out too late.
      final said = introPrompt(IntroStep.signUp);
      expect(said, contains(kPlatformName));
      expect(said, contains('Lift'));
    });

    test('and the account is not sold as a second phone', () {
      // It used to say an account "keeps all of this yours on any phone",
      // which is a sync pitch, and sync is not why anybody makes an account
      // ninety seconds into a running app. Worse, it is not even true by
      // default: backup is opt-in and off until asked for (ADR-0012).
      expect(
        introPrompt(IntroStep.signUp).toLowerCase(),
        isNot(contains('any phone')),
      );
    });
  });

  /// Moment one is free. It creates an account and a run tracker, and nothing
  /// in it is billable, so there is nothing here to have a price conversation
  /// about — that belongs at the plan gate (ADR-0019). This guards the
  /// regression of the cost copy drifting back to where it used to live.
  test('moment one never mentions money', () {
    for (final line in everything) {
      expect(
        RegExp(r'[£$€]\s?\d').hasMatch(line),
        isFalse,
        reason: 'a price before the gate is a price in the wrong place: $line',
      );
      for (final word in <String>['subscription', 'subscribe', 'free trial']) {
        expect(
          line.toLowerCase(),
          isNot(contains(word)),
          reason: '"$word" belongs at the plan gate, not here: $line',
        );
      }
    }
  });

  /// `PERSONA` in `supabase/functions/coach/surfaces.ts` says the coach never
  /// uses an em dash. A scripted line that breaks the model's own voice rule is
  /// a seam between the two halves of onboarding that a runner can see.
  test('the coach never uses an em dash, scripted or not', () {
    for (final line in everything) {
      expect(line, isNot(contains('—')), reason: 'em dash in: $line');
    }
  });
}
