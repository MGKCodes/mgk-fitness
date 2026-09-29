import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/auth/data/fake_auth.dart';
import 'package:mgk_lift/src/features/auth/domain/account.dart';
import 'package:mgk_lift/src/features/entitlement/domain/entitlement.dart';
import 'package:mgk_lift/src/features/home/presentation/lift_shell.dart';
import 'package:mgk_lift/src/features/legal/presentation/legal_document_screen.dart';
import 'package:mgk_lift/src/features/purchases/domain/purchases.dart';
import 'package:mgk_lift/src/features/purchases/presentation/purchase_sheet.dart';

/// The affordances, and the wire from a tap to what the screen then shows.
///
/// `onSubscribe` existed on both paywalls and nothing ever passed one, so these
/// cover the join rather than the widgets: a paywall that renders a button is
/// not the same as a paywall that can sell anything. Since 2026-09-29 the
/// button opens the purchase sheet, where either tier can be bought — the
/// paywall had shown Premium Coach for a month with no way to buy it.
void main() {
  Future<void> openPlan(WidgetTester tester, Widget shell) async {
    tester.view
      ..physicalSize = const Size(1179, 2556)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
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

  Future<void> openSheet(WidgetTester tester) =>
      tapVisible(tester, find.text('Start coaching'));

  const signedIn = Account(id: 'user-1', email: 'lifter@mgkcodes.com');

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

  testWidgets('the sheet offers both tiers, priced by the store', (
    tester,
  ) async {
    await openPlan(
      tester,
      LiftShell(
        entitlements: EntitlementGate(
          source: FakeEntitlements(Entitlement.none),
        ),
        purchases: FakePurchases(),
      ),
    );
    await openSheet(tester);

    final sheet = find.byType(PurchaseSheet);
    expect(sheet, findsOneWidget);
    for (final text in <String>['£1.00 / month', '£3.00 / month']) {
      expect(
        find.descendant(of: sheet, matching: find.text(text)),
        findsOneWidget,
      );
    }
    expect(find.text('Subscribe to Coach'), findsOneWidget);
  });

  testWidgets('Coach is what the sheet opens on, and what it buys', (
    tester,
  ) async {
    final store = FakePurchases();
    await openPlan(
      tester,
      LiftShell(
        entitlements: EntitlementGate(source: _EntitledOnce(store)),
        purchases: store,
      ),
    );
    await openSheet(tester);
    await tapVisible(tester, find.text('Subscribe to Coach'));

    expect(store.bought.single.tier, EntitlementTier.paid);
  });

  testWidgets('Premium Coach can actually be bought', (tester) async {
    // The gap this sheet exists to close: the tier table showed Premium Coach
    // and the only button bought Coach.
    final store = FakePurchases();
    await openPlan(
      tester,
      LiftShell(
        entitlements: EntitlementGate(source: _EntitledOnce(store)),
        purchases: store,
      ),
    );
    await openSheet(tester);

    await tapVisible(
      tester,
      find.descendant(
        of: find.byType(PurchaseSheet),
        matching: find.text('£3.00 / month'),
      ),
    );
    await tapVisible(tester, find.text('Subscribe to Premium Coach'));

    expect(store.bought.single.tier, EntitlementTier.premium);
  });

  testWidgets('a completed purchase closes the sheet and the paywall', (
    tester,
  ) async {
    // The whole seam, end to end: tap, store, server, screen. Before this the
    // pitch stayed on screen after paying, because nothing read the
    // entitlement and nothing passed onSubscribe.
    final store = FakePurchases();
    await openPlan(
      tester,
      LiftShell(
        entitlements: EntitlementGate(source: _EntitledOnce(store)),
        purchases: store,
      ),
    );
    await openSheet(tester);
    await tapVisible(tester, find.text('Subscribe to Coach'));

    expect(find.byType(PurchaseSheet), findsNothing);
    expect(
      find.text('Start coaching'),
      findsNothing,
      reason: 'still being sold the thing that was just bought',
    );
    expect(find.text('You are all set.'), findsOneWidget);
  });

  testWidgets('cancelling says nothing, sells nothing, and stays put', (
    tester,
  ) async {
    // Opening a paywall to look at the price is the commonest use of one, and
    // backing out of the store's own sheet must not read as an error.
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
    await openSheet(tester);
    await tapVisible(tester, find.text('Subscribe to Coach'));

    expect(find.byType(PurchaseSheet), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('Nothing has been charged'), findsNothing);
  });

  testWidgets('signed out, the sheet asks for an account rather than money', (
    tester,
  ) async {
    // The webhook refuses an anonymous customer, so a purchase made signed out
    // takes the money and unlocks nothing. Run shipped that once.
    final store = FakePurchases();
    await openPlan(
      tester,
      LiftShell(
        auth: FakeAuth(),
        entitlements: EntitlementGate(
          source: FakeEntitlements(Entitlement.none),
        ),
        purchases: store,
      ),
    );
    await openSheet(tester);

    expect(find.text('Sign in to subscribe'), findsOneWidget);
    expect(find.textContaining('Subscribe to'), findsNothing);
    expect(store.bought, isEmpty);
  });

  testWidgets('a store that refuses for want of an account says so, and that '
      'nothing was charged', (tester) async {
    final store = FakePurchases(onBuy: PurchaseStatus.notSignedIn);
    await openPlan(
      tester,
      LiftShell(
        auth: FakeAuth(account: signedIn),
        entitlements: EntitlementGate(
          source: FakeEntitlements(Entitlement.none),
        ),
        purchases: store,
      ),
    );
    await openSheet(tester);
    await tapVisible(tester, find.text('Subscribe to Coach'));

    expect(find.byType(PurchaseSheet), findsOneWidget);
    expect(find.textContaining('Sign in first'), findsOneWidget);
    expect(find.textContaining('Nothing has been charged'), findsOneWidget);
  });

  testWidgets('the store is told who is buying, and forgets on sign-out', (
    tester,
  ) async {
    // The user id is the only join between RevenueCat and core.entitlements.
    final store = FakePurchases();
    final auth = FakeAuth(account: signedIn);
    await openPlan(
      tester,
      LiftShell(
        auth: auth,
        entitlements: EntitlementGate(
          source: FakeEntitlements(Entitlement.none),
        ),
        purchases: store,
      ),
    );
    expect(store.identified, 'user-1');

    await auth.signOut();
    await tester.pumpAndSettle();
    expect(store.identified, isNull);

    await auth.signIn(email: 'next@mgkcodes.com', password: 'x');
    await tester.pumpAndSettle();
    expect(store.identified, 'fake-user');
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

  group('the sheet on its own', () {
    Future<void> pumpSheet(
      WidgetTester tester, {
      required TargetPlatform platform,
      FakePurchases? store,
      List<PurchaseOffer> offers = const <PurchaseOffer>[
        FakePurchases.coach,
        FakePurchases.premiumCoach,
      ],
    }) async {
      final purchases = store ?? FakePurchases(offers: offers);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PurchaseSheet(
              flow: PurchaseFlow(
                purchases: purchases,
                gate: EntitlementGate(
                  source: FakeEntitlements(Entitlement.none),
                ),
                settleDelay: Duration.zero,
              ),
              offers: offers,
              platform: platform,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('carries the auto-renew terms in Apple\'s words on iOS', (
      tester,
    ) async {
      // Guideline 3.1.2(a): at the point of purchase, in full.
      await pumpSheet(tester, platform: TargetPlatform.iOS);
      expect(
        find.textContaining('Payment is charged to your Apple ID'),
        findsOneWidget,
      );
      expect(
        find.textContaining('unless auto-renew is turned off at least 24 hours'),
        findsOneWidget,
      );
      expect(find.textContaining('Google Play'), findsNothing);
    });

    testWidgets('and never names the Apple ID on Android', (tester) async {
      // Run's paywall told a Play customer their Apple ID would be charged.
      await pumpSheet(tester, platform: TargetPlatform.android);
      expect(
        find.textContaining('your Google Play account at confirmation'),
        findsOneWidget,
      );
      expect(find.textContaining('Apple ID'), findsNothing);
    });

    testWidgets('links the terms and the privacy policy, and both open', (
      tester,
    ) async {
      await pumpSheet(tester, platform: TargetPlatform.iOS);
      for (final link in <String>['Terms of use', 'Privacy policy']) {
        await tester.ensureVisible(find.text(link));
        await tester.pumpAndSettle();
        await tester.tap(find.text(link));
        await tester.pumpAndSettle();
        expect(find.byType(LegalDocumentScreen), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('a store with nothing to sell says so rather than going quiet', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        platform: TargetPlatform.iOS,
        offers: const <PurchaseOffer>[],
      );
      expect(find.text('Not available to buy yet'), findsOneWidget);
      // Restore still works for somebody who already paid.
      expect(find.text('Restore purchases'), findsOneWidget);
    });

    testWidgets('prices are the store\'s strings, printed as given', (
      tester,
    ) async {
      // Decision 6: tiers are named, never priced, by the app.
      await pumpSheet(
        tester,
        platform: TargetPlatform.iOS,
        offers: const <PurchaseOffer>[
          PurchaseOffer(
            id: 'lift.coach.monthly',
            tier: EntitlementTier.paid,
            price: '1,09 €',
            period: 'month',
          ),
        ],
      );
      expect(find.text('1,09 € / month'), findsOneWidget);
      expect(find.textContaining('£'), findsNothing);
    });
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
      : Entitlement(
          tier: store.bought.last.tier,
          status: 'active',
        );
}
