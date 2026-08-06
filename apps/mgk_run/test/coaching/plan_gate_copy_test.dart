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

  /// **Delete-and-replace this test when pricing is decided**, do not just
  /// delete it — see the PRICING block in `plan_gate_copy.dart`. It exists so a
  /// figure cannot reach the app before somebody has agreed it.
  test('and quotes no figure, because none has been agreed yet', () {
    expect(
      RegExp(r'[£$€]\s?\d').hasMatch(planGateCostsCopy),
      isFalse,
      reason: 'a price in onboarding is a commercial claim, not copy',
    );
    expect(
      RegExp(
        r'\b\d+\s*(runs?|messages?|per month|a month)\b',
      ).hasMatch(planGateCostsCopy.toLowerCase()),
      isFalse,
      reason: 'a quota is a commercial claim too',
    );
  });

  test('the coach never uses an em dash, scripted or not', () {
    expect(planGateCostsCopy, isNot(contains('—')));
  });
}
