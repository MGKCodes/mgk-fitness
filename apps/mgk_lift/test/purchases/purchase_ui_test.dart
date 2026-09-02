import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/entitlement/domain/entitlement.dart';
import 'package:mgk_lift/src/features/home/presentation/lift_shell.dart';
import 'package:mgk_lift/src/features/purchases/domain/purchases.dart';

/// The affordances, and the wire from a tap to what the screen then shows.
///
/// `onSubscribe` existed on both paywalls and nothing ever passed one, so these
/// cover the join rather than the widgets: a paywall that renders a button is
/// not the same as a paywall that can sell anything.
void main() {
  Future<void> openPlan(WidgetTester tester, Widget shell) async {
    await tester.pumpWidget(MaterialApp(home: shell));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
  }

  /// The paywall is longer than the viewport, and `tester.tap` only *warns*
  /// when a hit test misses rather than failing — so a tap on an off-screen
  /// button silently does nothing and the assertion afterwards is the thing
  /// that breaks, several lines from the cause.
  Future<void> tapVisible(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets('no store means no purchase affordances at all', (tester) async {
    // The rule this app applies everywhere: absent rather than inert. The offer
    // copy already says subscriptions are not open, so a dead button would be
    // both useless and a contradiction.
    await openPlan(
      tester,
      LiftShell(
        entitlements: EntitlementGate(
          source: FakeEntitlements(Entitlement.none),
        ),
      ),
    );

    expect(find.text('Restore purchases'), findsNothing);
  });

  testWidgets('a store puts Restore purchases on the paywall', (tester) async {
    // Guideline 3.1.1. Checked mechanically by review, so its absence is a
    // rejection rather than a risk.
    await openPlan(
      tester,
      LiftShell(
        entitlements: EntitlementGate(
          source: FakeEntitlements(Entitlement.none),
        ),
        purchases: FakePurchases(),
      ),
    );

    expect(find.text('Restore purchases'), findsOneWidget);
  });

  testWidgets('buying sends the tier the button names', (tester) async {
    // "Start coaching — £1/mo" must buy Coaching. The paywall renders a £3
    // Premium row too, and sending that one because it happened to be first in
    // the offerings is exactly the mix-up worth pinning.
    final store = FakePurchases();
    await openPlan(
      tester,
      LiftShell(
        entitlements: EntitlementGate(source: _EntitledOnce(store)),
        purchases: store,
      ),
    );

    await tapVisible(tester, find.textContaining('Start coaching').first);

    expect(store.bought.single.tier, EntitlementTier.paid);
  });

  testWidgets('a completed purchase changes what the screen shows', (
    tester,
  ) async {
    // The whole seam, end to end: tap, store, server, screen. Before this the
    // pitch stayed on screen after paying, because nothing read the entitlement
    // and nothing passed onSubscribe.
    final store = FakePurchases();
    await openPlan(
      tester,
      LiftShell(
        entitlements: EntitlementGate(source: _EntitledOnce(store)),
        purchases: store,
      ),
    );

    expect(find.textContaining('Start coaching'), findsOneWidget);

    await tapVisible(tester, find.textContaining('Start coaching').first);

    expect(
      find.textContaining('Start coaching'),
      findsNothing,
      reason: 'still being sold the thing that was just bought',
    );
  });

  testWidgets('cancelling says nothing and sells nothing', (tester) async {
    // Opening a paywall to look at the price is the commonest use of one, and
    // backing out must not read as an error.
    final store = FakePurchases(onBuy: PurchaseStatus.cancelled);
    await openPlan(
      tester,
      LiftShell(
        entitlements: EntitlementGate(
          source: FakeEntitlements(Entitlement.none),
        ),
        purchases: store,
      ),
    );

    await tapVisible(tester, find.textContaining('Start coaching').first);

    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('Start coaching'), findsOneWidget);
  });

  testWidgets('a restore that finds nothing says so, and is not an error', (
    tester,
  ) async {
    final store = FakePurchases(onRestore: PurchaseStatus.nothingToRestore);
    await openPlan(
      tester,
      LiftShell(
        entitlements: EntitlementGate(
          source: FakeEntitlements(Entitlement.none),
        ),
        purchases: store,
      ),
    );

    await tapVisible(tester, find.text('Restore purchases'));

    expect(find.textContaining('no subscription on this account'), findsOne);
  });
}

/// Entitled only once the store has actually sold something, so the fake server
/// and the fake store cannot disagree about whether a purchase happened.
class _EntitledOnce implements EntitlementSource {
  _EntitledOnce(this.store);

  final FakePurchases store;

  @override
  Future<Entitlement?> fetch() async => store.bought.isEmpty
      ? Entitlement.none
      : const Entitlement(tier: EntitlementTier.paid, status: 'active');
}
