import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_gate_copy.dart';

/// What the coach says at the gate in front of a plan.
///
/// These moved from `test/onboarding/intro_script_test.dart` with the copy
/// itself (ADR-0019). The cost conversation used to happen before the sign-up
/// form; it happens before the purchase now, which is the commitment ADR-0018
/// actually cared about getting in front of.
void main() {
  group('the gate says what is free and what is not', () {
    test('recording runs is named as the free half', () {
      // The whole point of the split: a runner who never wants a plan owes
      // nothing, and should be told so at the only moment money comes up.
      expect(planGateCostsCopy.toLowerCase(), contains('free'));
    });

    test('and a plan is named as the paid one', () {
      expect(planGateCostsCopy.toLowerCase(), contains('subscription'));
    });

    test('the runner keeps their data either way', () {
      // Said here because this is where somebody decides not to pay, and
      // "what happens to my runs if I don't" is the question that decides it.
      expect(planGateCostsCopy.toLowerCase(), contains('yours'));
    });
  });

  /// Replaced, not deleted, when pricing landed — which is what the PRICING
  /// block in `plan_gate_copy.dart` asked for. It used to assert that **no**
  /// figure was quoted, because a price in onboarding is a commercial claim and
  /// none had been agreed. [ADR-0029](../../docs/decisions/0029-what-a-tier-costs-and-buys.md)
  /// agreed them, so it now asserts the opposite: that the figures are there,
  /// and that they are the consts rather than numbers typed into a sentence.
  group('quotes the agreed price, from the one place it is written', () {
    test('both tiers appear, and via the consts', () {
      expect(planGateCostsCopy, contains(kCoachPrice));
      expect(planGateCostsCopy, contains(kSharpCoachPrice));
    });

    test('no other figure has crept in', () {
      // A second price in the sentence means somebody typed one rather than
      // interpolating, and the two will part company at the next change.
      final quoted = RegExp(r'[£$€]\s?\d+(?:\.\d+)?')
          .allMatches(planGateCostsCopy)
          .map((m) => m.group(0))
          .toSet();
      expect(quoted, <String>{kCoachPrice, kSharpCoachPrice});
    });

    test('the prices are what ADR-0029 settled', () {
      // limits.ts sizes every spend ceiling as a fraction of these, so a change
      // here that is not mirrored there makes the ceilings the wrong size.
      expect(kCoachPrice, '£1');
      expect(kSharpCoachPrice, '£3');
    });

    test('still quotes no quota, because none has been agreed', () {
      expect(
        RegExp(
          r'\d+\s*(runs?|messages?|plans?)',
        ).hasMatch(planGateCostsCopy.toLowerCase()),
        isFalse,
        reason: 'a usage quota is a commercial claim and the tiers name none',
      );
    });
  });

  test('the coach never uses an em dash, scripted or not', () {
    expect(planGateCostsCopy, isNot(contains('—')));
  });
}
