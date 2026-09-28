import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/data/entitlement_repository.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_access.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_subscription.dart';

/// **A subscription that had run out still opened the coach.**
///
/// Found 2026-09-28: a Google test subscription whose row still said `active`
/// seventeen days after its `expires_at`. The webhook leaves a cancelled
/// subscription `active` until an `EXPIRATION` event ends it, that event never
/// came, and nothing else reads the date — so nothing ever ended it.
///
/// `tierFor` now refuses an `active` row a day past its expiry, and that half
/// is pinned in `supabase/functions/coach/entitlements_test.ts` against the
/// same instants. This is the client half, and it has to agree in both
/// directions: an open coach the server refuses is a 402 the moment somebody
/// taps, and a locked one the server would serve is a paying runner turned
/// away at a door that was never shut.
void main() {
  final now = DateTime.utc(2026, 9, 28, 12);

  /// A paid `active` row whose period ends [offset] after [now] — negative is
  /// the past — with the expiry written as PostgREST returns a timestamp.
  Map<String, dynamic> endingIn(Duration offset, {String product = 'paid'}) =>
      <String, dynamic>{
        'product': product,
        'status': 'active',
        'expires_at': now.add(offset).toIso8601String(),
      };

  group('an active row past its expiry reads exactly like an expired one', () {
    test('more than a day past is ended, and the coach is locked', () {
      final lapsed = CoachSubscription.fromRow(
        endingIn(const Duration(hours: -25)),
        now: now,
      );
      final expired = CoachSubscription.fromRow(<String, dynamic>{
        'product': 'paid',
        'status': 'expired',
      }, now: now);

      expect(lapsed, expired);
      expect(lapsed.standing, SubscriptionStanding.ended);
      expect(lapsed.isSubscribed, isFalse);
      expect(
        SupabaseEntitlements.accessFrom(
          endingIn(const Duration(hours: -25), product: 'premium'),
          now: now,
        ),
        CoachAccess.free,
      );
    });

    test('the subscription that was found reads as ended', () {
      // As it stood on 2026-09-28: still `active`, expired 2026-09-11 15:39
      // UTC, and not written since a minute after that.
      final s = CoachSubscription.fromRow(<String, dynamic>{
        'product': 'paid',
        'status': 'active',
        'expires_at': '2026-09-11T15:39:32+00:00',
      }, now: now);

      expect(s.standing, SubscriptionStanding.ended);
      expect(s.isSubscribed, isFalse);
      expect(
        s.tier,
        CoachTier.coach,
        reason: 'they bought Coach and it ended; Settings says which',
      );
    });

    test('a day to the millisecond is over, as it is on the server', () {
      expect(
        CoachSubscription.fromRow(
          endingIn(const Duration(hours: -24)),
          now: now,
        ).isSubscribed,
        isFalse,
      );
    });
  });

  group('and not before the server says so', () {
    test('inside the paid period is subscribed', () {
      for (final product in <String>['paid', 'premium']) {
        expect(
          SupabaseEntitlements.accessFrom(
            endingIn(const Duration(days: 30), product: product),
            now: now,
          ),
          CoachAccess.subscribed,
          reason: product,
        );
      }
    });

    test('less than a day past is still subscribed', () {
      // A renewal in flight. RevenueCat retries a failed delivery for hours,
      // and a renewal can land just after the period it extends has ended;
      // until it does, the row carries the old expiry and the server still
      // serves it.
      for (final hours in <int>[1, 23]) {
        final s = CoachSubscription.fromRow(
          endingIn(Duration(hours: -hours)),
          now: now,
        );
        expect(s.standing, SubscriptionStanding.active, reason: '$hours h');
        expect(s.isSubscribed, isTrue, reason: '$hours h');
      }
    });

    test('no expiry is subscribed, because a hand-granted row has none', () {
      // The App Review demo account and the TestFlight sheet's grant are
      // inserted with no expires_at. Absent and null are the same answer.
      for (final row in <Map<String, dynamic>>[
        <String, dynamic>{'product': 'paid', 'status': 'active'},
        <String, dynamic>{
          'product': 'paid',
          'status': 'active',
          'expires_at': null,
        },
      ]) {
        expect(CoachSubscription.fromRow(row, now: now).isSubscribed, isTrue);
        expect(
          SupabaseEntitlements.accessFrom(row, now: now),
          CoachAccess.subscribed,
        );
      }
    });
  });

  test('an expiry that cannot be read is ended rather than trusted', () {
    // Reading it as "no end date" would open the coach for good on a value
    // nobody can check. The server refuses the same row outright.
    for (final expiresAt in <Object>['', 'soon', 1789141172000, true]) {
      final s = CoachSubscription.fromRow(<String, dynamic>{
        'product': 'paid',
        'status': 'active',
        'expires_at': expiresAt,
      }, now: now);
      expect(s.standing, SubscriptionStanding.ended, reason: '$expiresAt');
      expect(s.isSubscribed, isFalse, reason: '$expiresAt');
    }
  });

  test('an expiry cannot make any other status subscribed', () {
    // The rule only takes away. A month left on a `grace` row is still a
    // payment the store is chasing.
    final s = CoachSubscription.fromRow(<String, dynamic>{
      'product': 'premium',
      'status': 'grace',
      'expires_at': now.add(const Duration(days: 30)).toIso8601String(),
    }, now: now);
    expect(s.standing, SubscriptionStanding.billingRetry);
    expect(s.isSubscribed, isFalse);
  });

  test('the read asks for every column the rule reads', () {
    // A column dropped from the select is not an error. The key is absent,
    // absent reads as no end date, and no end date is subscribed — the lapse
    // rule would switch itself off without a single test above failing.
    final asked = SupabaseEntitlements.columns.split(',').map((c) => c.trim());
    expect(asked, containsAll(<String>['product', 'status', 'expires_at']));
  });
}
