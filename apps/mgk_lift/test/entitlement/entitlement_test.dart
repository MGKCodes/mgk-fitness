import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/entitlement/domain/entitlement.dart';
import 'package:mgk_lift/src/features/home/presentation/lift_shell.dart';

/// The gate that decides whether the app shows the paid half.
///
/// These exist because the gap they cover was not a bug in this logic — it was
/// the absence of any. `LiftShell.isEntitled` defaulted to `false`, `main.dart`
/// never passed it, and nothing in `lib/` read `core.entitlements` at all, so
/// the account holding `lift` / `paid` / `active` saw the sales pitch. The last
/// test here is the one that would have caught it.
void main() {
  group('reading a tier', () {
    test('knows the three the table allows', () {
      expect(EntitlementTier.parse('paid'), EntitlementTier.paid);
      expect(EntitlementTier.parse('premium'), EntitlementTier.premium);
      expect(EntitlementTier.parse('free'), EntitlementTier.free);
    });

    test('a tier this client has never heard of is free, not a crash', () {
      // The server can grow a tier in a deployment; this client finds out in a
      // release. Parsing has to survive the gap between the two, and the safe
      // side of that gap is "no paid features", not an exception on launch.
      expect(EntitlementTier.parse('platinum'), EntitlementTier.free);
      expect(EntitlementTier.parse(null), EntitlementTier.free);
    });
  });

  group('what grants the paid half', () {
    Entitlement at(
      String status, [
      EntitlementTier tier = EntitlementTier.paid,
    ]) => Entitlement(tier: tier, status: status);

    test('active, and a tier above free', () {
      expect(at('active').grantsPaid, isTrue);
      expect(at('active', EntitlementTier.premium).grantsPaid, isTrue);
    });

    test('an active free row grants nothing', () {
      // A real shape: the table allows product = 'free', and it is not a
      // subscription. Status alone is not the answer.
      expect(at('active', EntitlementTier.free).grantsPaid, isFalse);
      expect(Entitlement.none.grantsPaid, isFalse);
    });

    test('every other status grants nothing, grace included', () {
      // The rule `core.entitlements` states about itself: active is the only
      // value that grants anything. `grace` is the one to revisit when the
      // RevenueCat webhook starts producing it — the store's intent there is
      // that access continues through a failed payment — and it is pinned here
      // so that change is deliberate rather than accidental.
      for (final status in <String>[
        'expired',
        'grace',
        'refunded',
        'revoked',
        'unknown',
      ]) {
        expect(at(status).grantsPaid, isFalse, reason: 'status $status');
      }
    });
  });

  group('the gate', () {
    test('a live answer wins, and is remembered for next time', () async {
      final cache = InMemoryEntitlementCache();
      final gate = EntitlementGate(
        source: FakeEntitlements(
          const Entitlement(tier: EntitlementTier.paid, status: 'active'),
        ),
        cache: cache,
      );

      expect(await gate.isEntitled(), isTrue);
      expect(await cache.lastKnownPaid(), isTrue);
    });

    test('no answer falls back to what this device last knew', () async {
      // The case the cache exists for. Without it a paying customer on a train
      // is shown the pitch, because "cannot say" and "has not paid" render
      // identically.
      final gate = EntitlementGate(
        source: FakeEntitlements(null),
        cache: InMemoryEntitlementCache(paid: true),
      );

      expect(await gate.isEntitled(), isTrue);
    });

    test('no answer and nothing remembered is the free half', () async {
      // Fail closed at the end. A device that has never once been told this
      // account pays should not assume it does.
      final gate = EntitlementGate(
        source: FakeEntitlements(null),
        cache: InMemoryEntitlementCache(),
      );

      expect(await gate.isEntitled(), isFalse);
      expect(
        await EntitlementGate(source: FakeEntitlements(null)).isEntitled(),
        isFalse,
        reason: 'no cache at all is the same answer',
      );
    });

    test('losing the entitlement overwrites the remembered yes', () async {
      final cache = InMemoryEntitlementCache(paid: true);
      final source = FakeEntitlements(
        const Entitlement(tier: EntitlementTier.paid, status: 'revoked'),
      );

      expect(
        await EntitlementGate(source: source, cache: cache).isEntitled(),
        isFalse,
      );
      expect(
        await cache.lastKnownPaid(),
        isFalse,
        reason: 'otherwise the next offline launch restores access that ended',
      );
    });

    test('forgetting leaves "never been told", not "has not paid"', () async {
      // Sign-out. The distinction matters: false would claim this device knows
      // something about the next person to use it.
      final cache = InMemoryEntitlementCache(paid: true);
      await EntitlementGate(
        source: FakeEntitlements(null),
        cache: cache,
      ).forget();

      expect(await cache.lastKnownPaid(), isNull);
    });
  });

  group('the shell', () {
    testWidgets('renders the paid half from the gate, not from the default', (
      WidgetTester tester,
    ) async {
      // The regression. `isEntitled` defaults to false, so before the gate
      // existed this is what every production account got regardless of what
      // the server said about them.
      await tester.pumpWidget(
        MaterialApp(
          home: LiftShell(
            entitlements: EntitlementGate(
              source: FakeEntitlements(
                const Entitlement(tier: EntitlementTier.paid, status: 'active'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plan'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Start coaching'),
        findsNothing,
        reason: 'an entitled account was still being sold the thing it owns',
      );
    });

    testWidgets('and still sells to an account with no entitlement', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LiftShell(
            entitlements: EntitlementGate(
              source: FakeEntitlements(Entitlement.none),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plan'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Start coaching'), findsOneWidget);
    });

    testWidgets('no gate leaves the caller\'s answer alone', (
      WidgetTester tester,
    ) async {
      // What the preview and every other widget test rely on: state the tier
      // you want to render rather than standing up a server to be told it.
      await tester.pumpWidget(
        const MaterialApp(home: LiftShell(isEntitled: true)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Plan'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Start coaching'), findsNothing);
    });
  });
}
