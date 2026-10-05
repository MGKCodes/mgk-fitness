import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/auth/data/fake_auth.dart';
import 'package:mgk_lift/src/features/auth/domain/account.dart';
import 'package:mgk_lift/src/features/entitlement/domain/entitlement.dart';
import 'package:mgk_lift/src/features/home/presentation/lift_shell.dart';
import 'package:mgk_lift/src/features/legal/presentation/legal_document_screen.dart';
import 'package:mgk_lift/src/features/purchases/domain/purchases.dart';
import 'package:mgk_lift/src/features/auth/presentation/sign_in_screen.dart';
import 'package:mgk_lift/src/features/purchases/presentation/sales_screen.dart';

/// The affordances, and the wire from a tap to what the screen then shows.
///
/// `onSubscribe` existed on both paywalls and nothing ever passed one, so these
/// cover the join rather than the widgets: a paywall that renders a button is
/// not the same as a paywall that can sell anything. Every door now opens the
/// sales screen (R6), where choosing a tier is the purchase.
/// The one button, on each tier, at FakePurchases' prices.
const String _buyCoach = 'Subscribe · £1.00/month';
const String _buyPremium = 'Subscribe · £3.00/month';

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

  Future<void> openSales(WidgetTester tester) =>
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

  testWidgets('the sales screen offers both tiers, priced by the store', (
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
    await openSales(tester);

    final sheet = find.byType(SalesScreen);
    expect(sheet, findsOneWidget);
    // What sets the second apart, as an amount (ADR-0041, 3.1.2(c)).
    expect(find.text('3× the coaching, sharper model'), findsOneWidget);
    for (final price in <String>['£1.00', '£3.00']) {
      expect(
        find.descendant(
          of: sheet,
          matching: find.textContaining(price, findRichText: true),
        ),
        findsWidgets,
      );
    }
    // One button, on the tier chosen, which starts as the first.
    expect(find.text(_buyCoach), findsOneWidget);
  });

  testWidgets('Subscribe to Coach buys Coach', (tester) async {
    final store = FakePurchases();
    await openPlan(
      tester,
      LiftShell(
        entitlements: EntitlementGate(source: _EntitledOnce(store)),
        purchases: store,
      ),
    );
    await openSales(tester);
    await tapVisible(tester, find.text(_buyCoach));

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
    await openSales(tester);
    // Choosing the tier moves the one button onto it.
    await tapVisible(tester, find.text('Premium Coach'));
    expect(find.text(_buyCoach), findsNothing);
    await tapVisible(tester, find.text(_buyPremium));

    expect(store.bought.single.tier, EntitlementTier.premium);
  });

  testWidgets('a completed purchase closes the screen and the paywall', (
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
    await openSales(tester);
    await tapVisible(tester, find.text(_buyCoach));

    expect(find.byType(SalesScreen), findsNothing);
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
    await openSales(tester);
    await tapVisible(tester, find.text(_buyCoach));

    expect(find.byType(SalesScreen), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.textContaining('Nothing has been charged'), findsNothing);
  });

  testWidgets('signed out, the offer shows in full', (tester) async {
    // R6: the account is asked for when a tier is chosen, not before the
    // offer is seen.
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
    await openSales(tester);

    expect(find.text(_buyCoach), findsOneWidget);
    expect(find.text('Premium Coach'), findsOneWidget);
    expect(find.textContaining("You'll sign in first"), findsOne);
    expect(store.bought, isEmpty);
  });

  testWidgets('signed out, choosing a tier asks for the account, then buys', (
    tester,
  ) async {
    // The webhook refuses an anonymous customer, so a purchase made signed
    // out takes the money and unlocks nothing. Run shipped that once.
    final store = FakePurchases();
    final auth = FakeAuth();
    addTearDown(auth.dispose);
    await openPlan(
      tester,
      LiftShell(
        auth: auth,
        entitlements: EntitlementGate(source: _EntitledOnce(store)),
        purchases: store,
      ),
    );
    await openSales(tester);
    await tapVisible(tester, find.text(_buyCoach));

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(store.bought, isEmpty, reason: 'nothing before the account');

    await tapVisible(tester, find.text('Continue with Apple'));

    // Attached before the store is asked, then bought.
    expect(store.identified, 'fake-user');
    expect(store.bought.single.tier, EntitlementTier.paid);
    expect(find.byType(SalesScreen), findsNothing);
  });

  testWidgets('signed out, backing out of signing in buys nothing', (
    tester,
  ) async {
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
    await openSales(tester);
    await tapVisible(tester, find.text(_buyCoach));
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(SalesScreen), findsOneWidget);
    expect(store.bought, isEmpty);
    expect(find.text(_buyCoach), findsOneWidget);
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
    await openSales(tester);
    await tapVisible(tester, find.text(_buyCoach));

    expect(find.byType(SalesScreen), findsOneWidget);
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

  group('the sales screen on its own', () {
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
      tester.view
        ..physicalSize = const Size(1179, 2556)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: SalesScreen(
            flow: PurchaseFlow(
              purchases: purchases,
              gate: EntitlementGate(source: FakeEntitlements(Entitlement.none)),
              settleDelay: Duration.zero,
            ),
            offers: offers,
            platform: platform,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('says who charges, how often and where to stop it, on iOS', (
      tester,
    ) async {
      // Guideline 3.1.2(a), at the point of purchase, at the length of a
      // glance: the full wording is in the terms.
      await pumpSheet(tester, platform: TargetPlatform.iOS);
      expect(
        find.textContaining('Charged to your Apple ID every month'),
        findsOneWidget,
      );
      expect(find.textContaining('until you cancel'), findsOneWidget);
      expect(find.textContaining('Google Play'), findsNothing);
    });

    testWidgets('and never names the Apple ID on Android', (tester) async {
      // Run's paywall told a Play customer their Apple ID would be charged.
      await pumpSheet(tester, platform: TargetPlatform.android);
      expect(
        find.textContaining('Charged to your Google Play account'),
        findsOneWidget,
      );
      expect(find.textContaining('Apple ID'), findsNothing);
    });

    testWidgets('links the terms and the privacy policy, and both open', (
      tester,
    ) async {
      await pumpSheet(tester, platform: TargetPlatform.iOS);
      for (final link in <String>['Terms', 'Privacy']) {
        await tester.ensureVisible(find.text(link));
        await tester.pumpAndSettle();
        await tester.tap(find.text(link));
        await tester.pumpAndSettle();
        expect(find.byType(LegalDocumentScreen), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    });

    testWidgets(
      'a store with nothing to sell says so rather than going quiet',
      (tester) async {
        await pumpSheet(
          tester,
          platform: TargetPlatform.iOS,
          offers: const <PurchaseOffer>[],
        );
        expect(find.text('Not available to buy yet'), findsOneWidget);
        // Restore still works for somebody who already paid.
        expect(find.text('Restore'), findsOneWidget);
      },
    );

    testWidgets('each tier says what it adds, and only what ships', (
      tester,
    ) async {
      await pumpSheet(tester, platform: TargetPlatform.iOS);
      // A few words each, to scan.
      for (final title in <String>[
        'Your own training plan',
        'A coach on call',
        'Weekly progress photos',
        'Smart exercise swaps',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
      expect(find.text('3× the coaching, sharper model'), findsOneWidget);
      // And the sentence behind one, a tap away.
      expect(find.textContaining('reads your recent sessions'), findsNothing);
      await tester.tap(find.text('A coach on call'));
      await tester.pumpAndSettle();
      expect(find.textContaining('reads your recent sessions'), findsOneWidget);
      // Nothing moves a planned session, and the coach reads nothing of Run.
      expect(find.textContaining('Thursday'), findsNothing);
      expect(find.textContaining('running'), findsNothing);
      // And tracking is never what is being sold.
      expect(find.textContaining('Tracking stays free'), findsOneWidget);
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
      expect(find.textContaining('1,09 €', findRichText: true), findsWidgets);
      expect(find.text('Subscribe · 1,09 €/month'), findsOneWidget);
      expect(find.textContaining('£', findRichText: true), findsNothing);
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
      : Entitlement(tier: store.bought.last.tier, status: 'active');
}
