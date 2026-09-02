import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_purchases.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/coaching/data/entitlement_repository.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_access.dart';
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

      expect(find.textContaining('£1.00 / month'), findsOneWidget);
      expect(find.textContaining('£3.00 / month'), findsOneWidget);
    });

    testWidgets('a link to the terms of use', (tester) async {
      await pump(
        tester,
        purchases: FakePurchases(),
        entitlements: _ScriptedEntitlements(<CoachAccess>[CoachAccess.free]),
      );
      expect(find.text('Terms of use'), findsOneWidget);
      // Apple's own, hosted by Apple. ADR-0005 is why that is available to an
      // AGPL app: sole copyright holder, the Signal position.
      expect(kTermsOfUseUrl, contains('apple.com'));
      expect(kTermsOfUseUrl, contains('stdeula'));
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
      for (final phrase in <String>[
        'renew every month until cancelled',
        'charged to your Apple ID',
        'auto-renew is switched off at least 24',
      ]) {
        expect(find.textContaining(phrase), findsOneWidget, reason: phrase);
      }
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
    expect(find.textContaining(kSharpCoachPrice), findsNothing);
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

    testWidgets('and a real failure says nothing was charged', (tester) async {
      await pump(
        tester,
        purchases: FakePurchases(buyOutcome: PurchaseOutcome.failed),
        entitlements: _ScriptedEntitlements(<CoachAccess>[CoachAccess.free]),
      );

      await tester.tap(find.text('Subscribe').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('Nothing has been charged'), findsOneWidget);
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
      expect(find.textContaining(kSharpCoachPrice), findsNothing);
    });
  });
}
