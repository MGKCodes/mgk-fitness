import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/core/config/app_config.dart';
import 'package:mgk_lift/src/features/entitlement/domain/entitlement.dart';
import 'package:mgk_lift/src/features/purchases/data/revenuecat_purchases.dart';

/// The parts of the RevenueCat seam that are decisions rather than SDK calls.
/// The calls themselves need a store, and meet one in the sandbox pass.
void main() {
  group('which products are Lift\'s', () {
    test('the new tiers, on both stores', () {
      for (final id in <String>[
        'lift.coach.monthly',
        'lift.coach.premium.monthly',
        // Play reports a subscription as product:basePlan.
        'lift.coach.monthly:monthly',
        'lift.coach.premium.monthly:monthly',
      ]) {
        expect(RevenueCatPurchases.isLiftProduct(id), isTrue, reason: id);
      }
    });

    test("not Liftio's legacy pair, though it shares the bundle", () {
      // Those subscriptions are ended, not carried over, and nothing maps them
      // to an entitlement. Counting one as Lift's would make Restore say
      // "restored" in front of a screen that stays locked.
      expect(RevenueCatPurchases.isLiftProduct('liftio_monthly'), isFalse);
      expect(RevenueCatPurchases.isLiftProduct('liftio_annual'), isFalse);
    });

    test("not Run's, though one RevenueCat customer holds both", () {
      // A Run subscriber pressing Restore in Lift must hear "nothing to
      // restore", not "restored" followed by a paywall that never lifts.
      for (final id in <String>[
        'run.coach.monthly',
        'run.coach.premium.monthly:monthly',
      ]) {
        expect(RevenueCatPurchases.isLiftProduct(id), isFalse, reason: id);
      }
    });
  });

  test('a product id names its tier the way the webhook maps it', () {
    expect(
      RevenueCatPurchases.tierOf('lift.coach.monthly'),
      EntitlementTier.paid,
    );
    expect(
      RevenueCatPurchases.tierOf('lift.coach.premium.monthly:monthly'),
      EntitlementTier.premium,
    );
  });

  test('a store period reads as a word after a price', () {
    expect(RevenueCatPurchases.periodOf('P1M'), 'month');
    expect(RevenueCatPurchases.periodOf('P1Y'), 'year');
    expect(RevenueCatPurchases.periodOf('P1W'), 'week');
    // Unknown is monthly, which is every product this app sells.
    expect(RevenueCatPurchases.periodOf(null), 'month');
  });

  test('a build with no store key sells nothing, on purpose', () {
    const config = AppConfig(
      supabaseUrl: 'https://x.supabase.co',
      supabasePublishableKey: 'sb_publishable_x',
    );
    expect(config.canSell, isFalse);
    const keyed = AppConfig(
      supabaseUrl: 'https://x.supabase.co',
      supabasePublishableKey: 'sb_publishable_x',
      revenueCatKey: 'appl_x',
      revenueCatGoogleKey: 'goog_x',
    );
    // flutter_test runs as Android, so the Play key is the one chosen.
    expect(keyed.storeKey, 'goog_x');
    expect(keyed.canSell, isTrue);
  });
}
