import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_subscription.dart';

/// Fixed, so nothing here reads the wall clock. None of these rows carries an
/// expiry, so the instant only has to exist.
final DateTime _now = DateTime.utc(2026, 9, 28, 12);

/// **There was nowhere in the app to see what you were paying for.**
///
/// Found 2026-09-11, within a minute of the first Google Play purchase
/// succeeding: the coach unlocked, which is evidence, but it is *indirect*
/// evidence and it was the only kind on offer. A runner who wanted to know
/// which tier they were on, or whether their subscription was still paid up,
/// had to leave the app and ask the store.
///
/// The shape that fixes it is the point of these tests. [CoachAccess] is a
/// boolean and should stay one — a gate wants to fail closed and needs nothing
/// else. But a boolean cannot tell "you are on the free app" apart from "your
/// card was declined", and those are the same locked coach with very different
/// sentences behind them.
void main() {
  group('the tier is read off the row, by the name it was sold under', () {
    test('paid is Coach, premium is Premium Coach', () {
      expect(
        CoachSubscription.fromRow(<String, dynamic>{
          'product': 'paid',
          'status': 'active',
        }, now: _now).tier.label,
        'Coach',
      );
      expect(
        CoachSubscription.fromRow(<String, dynamic>{
          'product': 'premium',
          'status': 'active',
        }, now: _now).tier.label,
        'Premium Coach',
      );
    });

    test('an unknown product is the cheapest tier, never the dearest', () {
      // Same direction as `tierFor` on the server and `accessFrom` beside it:
      // a typo, or a SKU written by a future version of the receipt validator,
      // must not be able to print — or bill at — the Premium tier.
      final s = CoachSubscription.fromRow(<String, dynamic>{
        'product': 'premium_coach_v2',
        'status': 'active',
      }, now: _now);
      expect(s.tier, CoachTier.none);
      expect(s.isSubscribed, isFalse);
    });
  });

  group('standing is the half a boolean cannot carry', () {
    test('grace is its own state, and it keeps the tier', () {
      // The case this type exists for. The coach is locked, the runner has
      // cancelled nothing, and flattening this to "free" is how somebody
      // concludes the app lost their subscription.
      final s = CoachSubscription.fromRow(<String, dynamic>{
        'product': 'premium',
        'status': 'grace',
      }, now: _now);
      expect(s.standing, SubscriptionStanding.billingRetry);
      expect(
        s.tier,
        CoachTier.premiumCoach,
        reason: 'they are still a Premium subscriber; the payment failed',
      );
      expect(
        s.isSubscribed,
        isFalse,
        reason:
            'the server refuses grace, so an unlocked coach here would '
            'draw a door that 402s the moment it is opened',
      );
    });

    test('expired, refunded and revoked all read as ended', () {
      // They differ enormously to us and not at all to the person reading.
      for (final status in <String>['expired', 'refunded', 'revoked']) {
        final s = CoachSubscription.fromRow(<String, dynamic>{
          'product': 'paid',
          'status': status,
        }, now: _now);
        expect(s.standing, SubscriptionStanding.ended, reason: status);
        expect(s.isSubscribed, isFalse, reason: status);
      }
    });

    test('an unknown status is ended, not active', () {
      expect(
        CoachSubscription.fromRow(<String, dynamic>{
          'product': 'paid',
          'status': 'ACTIVE',
        }, now: _now).standing,
        SubscriptionStanding.ended,
        reason: 'the column is lower case; a case mismatch must not grant',
      );
    });

    test('no row is none, which is not the same as ended', () {
      expect(
        CoachSubscription.fromRow(null, now: _now),
        CoachSubscription.none,
      );
      expect(CoachSubscription.none.standing, SubscriptionStanding.none);
    });
  });

  test('only an active row of a known tier is subscribed', () {
    expect(
      CoachSubscription.fromRow(<String, dynamic>{
        'product': 'paid',
        'status': 'active',
      }, now: _now).isSubscribed,
      isTrue,
    );
    expect(
      CoachSubscription.fromRow(<String, dynamic>{
        'product': 'premium',
        'status': 'active',
      }, now: _now).isSubscribed,
      isTrue,
    );
  });
}
