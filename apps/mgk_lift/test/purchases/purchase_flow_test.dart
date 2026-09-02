import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/entitlement/domain/entitlement.dart';
import 'package:mgk_lift/src/features/purchases/domain/purchases.dart';

/// The join between "money moved" and "the app may show it".
///
/// Those are two different systems answering at two different times, and every
/// test here is about the gap: the store is synchronous and the webhook that
/// writes `core.entitlements` is not.
void main() {
  /// Grants only after [after] fetches, standing in for the webhook arriving a
  /// moment behind the purchase.
  EntitlementSource lagging({required int after}) {
    var calls = 0;
    return _CallCountingSource(() {
      calls++;
      return calls > after
          ? const Entitlement(tier: EntitlementTier.paid, status: 'active')
          : Entitlement.none;
    });
  }

  PurchaseFlow flowOver(
    EntitlementSource source, {
    FakePurchases? store,
    int attempts = 6,
  }) => PurchaseFlow(
    purchases: store ?? FakePurchases(),
    gate: EntitlementGate(source: source),
    settleAttempts: attempts,
    // Nothing here is testing that waiting works.
    settleDelay: Duration.zero,
  );

  group('buying', () {
    test('the server agreeing is what makes it entitled', () async {
      final result = await flowOver(
        FakeEntitlements(
          const Entitlement(tier: EntitlementTier.paid, status: 'active'),
        ),
      ).buy(FakePurchases.coaching);

      expect(result.status, PurchaseStatus.entitled);
      expect(result.changedEntitlement, isTrue);
    });

    test('waits for the webhook rather than believing the store', () async {
      // The realistic case: the store returns before core.entitlements exists.
      final result = await flowOver(
        lagging(after: 3),
      ).buy(FakePurchases.coaching);

      expect(result.status, PurchaseStatus.entitled);
    });

    test('a webhook that never lands is pending, not failed', () async {
      // The distinction the whole class exists for. Somebody has been charged;
      // telling them it failed would be false and would invite a second attempt.
      final result = await flowOver(
        FakeEntitlements(Entitlement.none),
        attempts: 3,
      ).buy(FakePurchases.coaching);

      expect(result.status, PurchaseStatus.pending);
      expect(result.changedEntitlement, isFalse);
    });

    test('backing out is cancelled, and never asks the server', () async {
      // Opening a paywall to look at the price is the commonest thing anybody
      // does with one, and it must not produce an error or a round trip.
      final source = _CallCountingSource(() => Entitlement.none);
      final result = await flowOver(
        source,
        store: FakePurchases(onBuy: PurchaseStatus.cancelled),
      ).buy(FakePurchases.coaching);

      expect(result.status, PurchaseStatus.cancelled);
      expect(source.calls, isZero, reason: 'nothing can have changed');
    });

    test('a throwing store is a failed purchase, not a crash', () async {
      final result = await flowOver(
        FakeEntitlements(Entitlement.none),
        store: FakePurchases(throwOnBuy: true),
      ).buy(FakePurchases.coaching);

      expect(result.status, PurchaseStatus.failed);
      expect(result.message, isNotNull);
      expect(
        result.message,
        contains('Nothing has been charged'),
        reason: 'the sentence has to answer the question the person will ask',
      );
    });

    test('the offer chosen is the offer bought', () async {
      // Guards the bug where a paywall with two tiers sends whichever one the
      // button was written against.
      final store = FakePurchases();
      await flowOver(
        FakeEntitlements(
          const Entitlement(tier: EntitlementTier.premium, status: 'active'),
        ),
        store: store,
      ).buy(FakePurchases.premium);

      expect(store.bought.single.id, FakePurchases.premium.id);
    });
  });

  group('restoring', () {
    test(
      'finding a subscription settles the same way a purchase does',
      () async {
        final result = await flowOver(lagging(after: 2)).restore();
        expect(result.status, PurchaseStatus.entitled);
      },
    );

    test('nothing to restore is its own answer, not a failure', () async {
      // Apple exercises this path, and "something went wrong" would be a lie
      // about an account that simply has no subscription on it.
      final source = _CallCountingSource(() => Entitlement.none);
      final result = await flowOver(
        source,
        store: FakePurchases(onRestore: PurchaseStatus.nothingToRestore),
      ).restore();

      expect(result.status, PurchaseStatus.nothingToRestore);
      expect(source.calls, isZero);
    });
  });
}

class _CallCountingSource implements EntitlementSource {
  _CallCountingSource(this._answer);

  final Entitlement? Function() _answer;
  int calls = 0;

  @override
  Future<Entitlement?> fetch() async {
    calls++;
    return _answer();
  }
}
