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

  /// Reversed once already, and now settled the other way.
  ///
  /// It first asserted that **no** figure was quoted, because none had been
  /// agreed. [ADR-0029](../../docs/decisions/0029-what-a-tier-costs-and-buys.md)
  /// agreed them and this flipped to assert they were present. That was the
  /// wrong conclusion from a right decision: agreeing a price settles what to
  /// charge, not where the number is rendered. A figure compiled into the
  /// binary is correct in one storefront and wrong in every other, so it goes
  /// back to asserting the copy quotes nothing, and the consts are checked as
  /// what they are: the record `limits.ts` is sized against.
  group('the copy names the tier, and the store will name the price', () {
    test('no figure is quoted, in any currency', () {
      final quoted = RegExp(
        r'[£$€]\s?\d+(?:\.\d+)?|\d+(?:\.\d+)?\s?(?:p|pence|GBP|USD|EUR)',
      ).allMatches(planGateCostsCopy).map((m) => m.group(0)).toList();
      expect(
        quoted,
        isEmpty,
        reason:
            'a price belongs to the storefront, not to the binary; StoreKit '
            'hands back the localised one once RevenueCat is wired',
      );
    });

    test('and the consts are still the record ADR-0029 settled', () {
      // Not shown to anybody. limits.ts sizes every spend ceiling as a fraction
      // of these, so a change here that is not mirrored there makes the
      // ceilings the wrong size.
      expect(kCoachPrice, '£1');
      expect(kSharpCoachPrice, '£3');
    });

    test('still quotes no quota, because none has been agreed', () {
      expect(
        RegExp(
          r'\d+\s*(runs?|messages?|plans?)',
        ).hasMatch(planGateCostsCopy.toLowerCase()),
        isFalse,
        reason: 'a usage quota is a commercial claim and the tiers name none',
      );
    });

    test('and stays short enough to be a sentence in a conversation', () {
      // The sheet is a door, not a pricing page. It ran to four sentences the
      // day the figures went in, which is how a gate turns into a brochure.
      expect(planGateCostsCopy.split('. ').length, lessThanOrEqualTo(3));
    });
  });

  test('the coach never uses an em dash, scripted or not', () {
    expect(planGateCostsCopy, isNot(contains('—')));
  });
}
