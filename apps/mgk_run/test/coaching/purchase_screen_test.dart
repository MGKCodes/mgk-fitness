import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_purchases.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/coaching/data/entitlement_repository.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_access.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_subscription.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_offer.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_gate_copy.dart';
import 'package:mgk_run/src/features/coaching/presentation/coach_gate_sheet.dart';
import 'package:mgk_run/src/features/coaching/presentation/purchase_screen.dart';

/// Answers a scripted sequence, then repeats the last answer forever.
///
/// The sequence is the point. A purchase and the entitlement it produces do
/// **not** arrive together: RevenueCat tells our Edge Function
/// server-to-server while the store's sheet is still dismissing, so the first
/// read after a successful payment usually says `free`. A repository that
/// answered `subscribed` immediately would test a race that does not happen.
class _ScriptedEntitlements implements EntitlementRepository {
  _ScriptedEntitlements(this._answers);

  final List<CoachAccess> _answers;
  int reads = 0;

  @override
  Future<CoachAccess> access() async {
    final CoachAccess answer = _answers[reads.clamp(0, _answers.length - 1)];
    reads++;
    return answer;
  }

  @override
  Future<CoachSubscription> subscription() async =>
      (await access()).isSubscribed
      ? const CoachSubscription(
          tier: CoachTier.coach,
          standing: SubscriptionStanding.active,
        )
      : CoachSubscription.none;
}

void main() {
  Future<bool?> pump(
    WidgetTester tester, {
    required FakePurchases purchases,
    required EntitlementRepository entitlements,
  }) async {
    // Tall, because a ListView only builds what is near the viewport and the
    // three things Guideline 3.1.2 cares about most -- terms, privacy and the
    // renewal disclosure -- are at the bottom of the screen. At the default
    // 800x600 they are not merely off-screen, they do not exist, and a test
    // asserting on them would fail for a reason that has nothing to do with
    // whether the app shows them to anybody.
    await tester.binding.setSurfaceSize(const Size(430, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await PurchaseScreen.show(
                    context,
                    purchases: purchases,
                    entitlements: entitlements,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  /// Read these as a checklist rather than as tests. Every one of them is a
  /// documented App Review requirement for an auto-renewing subscription, and
  /// the cost of finding out by rejection is a review cycle.
  group('Guideline 3.1.2 wants four things on a purchase surface', () {
    testWidgets('the price and the duration, from the store', (tester) async {
      final purchases = FakePurchases();
      await pump(
        tester,
        purchases: purchases,
        entitlements: _ScriptedEntitlements(<CoachAccess>[CoachAccess.free]),
      );

      // The fixture's figures, not the app's. `FakePurchases.demoOffers` is a
      // stand-in for a storefront, and the assertion is that whatever it says
      // reaches the screen -- which is why it is priced at the real points
      // rather than the round numbers ADR-0029 reasoned with.
      expect(find.textContaining('£0.99 / month'), findsOneWidget);
      expect(find.textContaining('£2.99 / month'), findsOneWidget);
    });

    testWidgets('a link to the terms of use', (tester) async {
      await pump(
        tester,
        purchases: FakePurchases(),
        entitlements: _ScriptedEntitlements(<CoachAccess>[CoachAccess.free]),
      );
      expect(find.text('Terms of use'), findsOneWidget);
      // **Ours now, not Apple's.** This pinned `apple.com` and `stdeula` until
      // 2026-09-10, when the app got terms of its own — Google Play does not
      // accept a store's EULA from a listing selling a subscription, and
      // Apple's has nothing to say about a product that prescribes exercise.
      //
      // Pinned on our own host so that a revert to the EULA, or a typo in the
      // path, fails here rather than at App Review. Guideline 3.1.2 requires
      // this link to work from the purchase surface.
      expect(kTermsOfUseUrl, contains('mgkfitness.mgkcodes.com'));
      expect(kTermsOfUseUrl, endsWith('/run/terms'));
    });

    testWidgets('a link to the privacy policy', (tester) async {
      await pump(
        tester,
        purchases: FakePurchases(),
        entitlements: _ScriptedEntitlements(<CoachAccess>[CoachAccess.free]),
      );
      expect(find.text('Privacy policy'), findsOneWidget);
    });

    testWidgets('and a restore that needs no purchase first', (tester) async {
      final purchases = FakePurchases();
      await pump(
        tester,
        purchases: purchases,
        entitlements: _ScriptedEntitlements(<CoachAccess>[CoachAccess.free]),
      );

      await tester.tap(find.text('Restore purchases'));
      await tester.pumpAndSettle();

      expect(purchases.restores, 1, reason: 'Apple requires this to work');
      expect(find.textContaining('No previous subscription'), findsOneWidget);
    });

    testWidgets('plus the auto-renew disclosure', (tester) async {
      await pump(
        tester,
        purchases: FakePurchases(),
        entitlements: _ScriptedEntitlements(<CoachAccess>[CoachAccess.free]),
      );
      // The facts Guideline 3.1.2 and Play both require, in whichever wording
      // this platform gets. **This asserted 'charged to your Apple ID' until
      // 2026-09-11**, which passed for the wrong reason: flutter_test runs with
      // defaultTargetPlatform == android, so the test was rendering the Android
      // paywall and checking it named an Apple ID — and it agreed, because the
      // disclosure was one const string that named Apple on both platforms.
      //
      // Which store gets which wording is pinned in
      // `the_paywall_names_the_right_store_test.dart`, where the platform is
      // stated rather than inherited from the test runner.
      for (final phrase in <String>[
        'renew every month until cancelled',
        'auto-renew is turned off at least 24',
      ]) {
        expect(find.textContaining(phrase), findsOneWidget, reason: phrase);
      }
      expect(
        find.text(renewalWording(defaultTargetPlatform)),
        findsOneWidget,
        reason:
            'the screen must show the disclosure for the store it is '
            'actually running on',
      );
    });
  });

  testWidgets('no price is compiled into the screen', (tester) async {
    // The storefront decides, so a fixture priced in dollars must render in
    // dollars. A screen that showed the ADR's pounds here would be reading a
    // const, and would be wrong in every storefront but one.
    await pump(
      tester,
      purchases: FakePurchases(
        offers: const <CoachOffer>[
          CoachOffer(
            id: 'run.coach.monthly',
            title: 'Coach',
            description: 'A plan, kept honest.',
            price: r'$1.29',
          ),
        ],
      ),
      entitlements: _ScriptedEntitlements(<CoachAccess>[CoachAccess.free]),
    );

    expect(find.textContaining(r'$1.29 / month'), findsOneWidget);
    expect(find.textContaining(kCoachPrice), findsNothing);
    expect(find.textContaining(kPremiumCoachPrice), findsNothing);
  });

  group('buying', () {
    testWidgets('waits for the server before reporting success', (
      tester,
    ) async {
      // free, free, then the webhook lands. The screen must not give up on the
      // first answer, and must not report success on the payment alone.
      final entitlements = _ScriptedEntitlements(<CoachAccess>[
        CoachAccess.free,
        CoachAccess.free,
        CoachAccess.subscribed,
      ]);
      final purchases = FakePurchases();
      await pump(tester, purchases: purchases, entitlements: entitlements);

      await tester.tap(find.text('Subscribe').first);
      await tester.pump();
      // Two waits from the backoff: 1s then 2s.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(purchases.bought.single.id, 'run.coach.monthly');
      expect(
        entitlements.reads,
        greaterThan(1),
        reason: 'one read after a purchase is a race, not a check',
      );
      expect(find.byType(PurchaseScreen), findsNothing, reason: 'it closed');
    });

    testWidgets('a payment the server never confirms is not called a failure', (
      tester,
    ) async {
      final purchases = FakePurchases();
      await pump(
        tester,
        purchases: purchases,
        entitlements: _ScriptedEntitlements(<CoachAccess>[CoachAccess.free]),
      );

      await tester.tap(find.text('Subscribe').first);
      await tester.pump();
      for (final s in <int>[1, 2, 3, 5]) {
        await tester.pump(Duration(seconds: s));
      }
      await tester.pumpAndSettle();

      // The money moved. Saying "something went wrong" here invites a second
      // purchase, which is the one outcome worse than waiting.
      expect(find.textContaining('Payment went through'), findsOneWidget);
      expect(find.textContaining('wrong'), findsNothing);
      expect(find.byType(PurchaseScreen), findsOneWidget);
    });

    testWidgets('cancelling says nothing at all', (tester) async {
      await pump(
        tester,
        purchases: FakePurchases(buyOutcome: PurchaseOutcome.cancelled),
        entitlements: _ScriptedEntitlements(<CoachAccess>[CoachAccess.free]),
      );

      await tester.tap(find.text('Subscribe').first);
      await tester.pumpAndSettle();

      // Backing out is a decision, not an error.
      expect(find.textContaining('did not go through'), findsNothing);
      expect(find.textContaining('Payment went through'), findsNothing);
      expect(find.byType(PurchaseScreen), findsOneWidget);
    });

    testWidgets('and a real failure does not claim what it cannot know', (
      tester,
    ) async {
      // It said "Nothing has been charged" to every refusal the store gave,
      // and a refusal does not say that. The cases it can say more about have
      // their own sentences; see what_a_failed_purchase_says_about_money_test.
      await pump(
        tester,
        purchases: FakePurchases(buyOutcome: PurchaseOutcome.failed),
        entitlements: _ScriptedEntitlements(<CoachAccess>[CoachAccess.free]),
      );

      await tester.tap(find.text('Subscribe').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('did not go through'), findsOneWidget);
      expect(find.textContaining('Nothing has been charged'), findsNothing);
    });

    // Build 12's first real sandbox purchase went through on an
    // `RCAnonymousID:`. The webhook refused it (`unknown_app_user_id`), no
    // entitlement row was ever written, and the runner was left having paid
    // with a coach that no relaunch would unlock. `RevenueCatPurchases.buy`
    // now refuses before reaching the store; this pins what the screen says
    // when it does.
    testWidgets('an unattributable purchase is refused, not reported as a '
        'failed payment', (tester) async {
      await pump(
        tester,
        purchases: FakePurchases(buyOutcome: PurchaseOutcome.notIdentified),
        entitlements: _ScriptedEntitlements(<CoachAccess>[CoachAccess.free]),
      );

      await tester.tap(find.text('Subscribe').first);
      await tester.pumpAndSettle();

      // It names the fix, because retrying without signing in refuses again.
      expect(find.textContaining('Sign in first'), findsOneWidget);
      expect(find.textContaining('Nothing has been charged'), findsOneWidget);

      // And it is not dressed up as a payment problem: nothing reached the
      // store, so "that did not go through" would be describing an attempt
      // that never happened.
      expect(find.textContaining('did not go through'), findsNothing);
      expect(find.textContaining('Payment went through'), findsNothing);
      expect(find.byType(PurchaseScreen), findsOneWidget);
    });
  });

  testWidgets('an empty shop says so, and does not look broken', (
    tester,
  ) async {
    // A build with no key, a storefront with no products, and a dead network
    // are the same fact to a runner, and none of them is their problem.
    await pump(
      tester,
      purchases: FakePurchases(offers: const <CoachOffer>[]),
      entitlements: _ScriptedEntitlements(<CoachAccess>[CoachAccess.free]),
    );

    expect(find.text('Not available to buy yet'), findsOneWidget);
    expect(find.text('Subscribe'), findsNothing);
    // Still reachable, because somebody who paid on another device needs it.
    expect(find.text('Restore purchases'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('it lays out on the narrowest phone worth supporting', (
    tester,
  ) async {
    // 320 is what `test/plates/plate.dart` calls kSmallPhone, and it is where
    // the terms and privacy links overflowed as a Row. Both are required to be
    // present and functional, so clipping one is a rejection rather than a
    // cosmetic complaint.
    await tester.binding.setSurfaceSize(const Size(320, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: PurchaseScreen(
          purchases: FakePurchases(),
          entitlements: _ScriptedEntitlements(<CoachAccess>[CoachAccess.free]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Terms of use'), findsOneWidget);
    expect(find.text('Privacy policy'), findsOneWidget);
  });

  /// The sheet in front of the paywall, and the reason it is conditional.
  group('the coach gate', () {
    Future<void> pumpGate(WidgetTester tester, {required bool canSell}) async {
      await tester.binding.setSurfaceSize(const Size(430, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: CoachGateSheet(
            purchases: canSell ? FakePurchases() : null,
            entitlements: canSell
                ? _ScriptedEntitlements(<CoachAccess>[CoachAccess.free])
                : null,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('offers a way through when there is something to buy', (
      tester,
    ) async {
      await pumpGate(tester, canSell: true);
      expect(find.text('See the plans'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
      expect(find.textContaining('Not available to buy'), findsNothing);
    });

    testWidgets('and says so plainly when there is not', (tester) async {
      // A build with no RevenueCat key. The alternative is a button that
      // cannot take money, which fails at the moment somebody has decided to
      // pay -- the worst moment available.
      await pumpGate(tester, canSell: false);
      expect(find.text('See the plans'), findsNothing);
      expect(
        find.textContaining('Not available to buy in this build yet'),
        findsOneWidget,
      );
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('quotes no price either way', (tester) async {
      await pumpGate(tester, canSell: true);
      expect(find.textContaining(kCoachPrice), findsNothing);
      expect(find.textContaining(kPremiumCoachPrice), findsNothing);
    });
  });
}
