import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_purchases.dart';
import 'package:mgk_run/src/features/coaching/data/revenuecat_purchases.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_offer.dart';
import 'package:mgk_run/src/features/coaching/presentation/purchase_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// **Every refusal from the store was "Nothing has been charged."**
///
/// A payment still pending, a dropped connection, a subscription the runner
/// already owned and a receipt attached to another account all mapped to one
/// outcome, and the paywall answered all of them with the same sentence. Two
/// of those are claims about money the app cannot make -- a pending payment
/// may well be charged, and a connection that died mid-purchase does not say
/// where the purchase got to -- and the third sent somebody who had already
/// paid to buy it again. A restore, meanwhile, finished on "Payment went
/// through", which after a restore reads as a second charge.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("RevenueCat's errors, in the runner's terms", () {
    test('pending is pending', () {
      expect(
        outcomeForError(PurchasesErrorCode.paymentPendingError),
        PurchaseOutcome.pending,
      );
    });

    test('no connection is no connection', () {
      for (final code in <PurchasesErrorCode>[
        PurchasesErrorCode.networkError,
        PurchasesErrorCode.offlineConnectionError,
      ]) {
        expect(outcomeForError(code), PurchaseOutcome.offline, reason: '$code');
      }
    });

    test('already owned, however the store puts it', () {
      for (final code in <PurchasesErrorCode>[
        PurchasesErrorCode.productAlreadyPurchasedError,
        PurchasesErrorCode.receiptAlreadyInUseError,
        PurchasesErrorCode.receiptInUseByOtherSubscriberError,
      ]) {
        expect(
          outcomeForError(code),
          PurchaseOutcome.alreadyOwned,
          reason: '$code',
        );
      }
    });

    test('cancelling is still not an error, and the rest are failures', () {
      expect(
        outcomeForError(PurchasesErrorCode.purchaseCancelledError),
        PurchaseOutcome.cancelled,
      );
      expect(
        outcomeForError(PurchasesErrorCode.storeProblemError),
        PurchaseOutcome.failed,
      );
    });

    test('and a restore that loses its connection says so', () async {
      final sdk = _Sdk()..install();
      addTearDown(sdk.uninstall);
      final purchases = RevenueCatPurchases(apiKey: 'test_key');
      await purchases.identify('alex');

      sdk.restoreError = PurchasesErrorCode.networkError;
      expect(await purchases.restore(), PurchaseOutcome.offline);
    });
  });

  group('the paywall', () {
    Future<void> pump(WidgetTester tester, FakePurchases purchases) async {
      await tester.binding.setSurfaceSize(const Size(430, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: PurchaseScreen(
            purchases: purchases,
            entitlements: FakeEntitlements(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> subscribe(WidgetTester tester) async {
      await tester.tap(find.text('Subscribe').first);
      await tester.pumpAndSettle();
    }

    testWidgets('a pending payment is pending, not refused', (tester) async {
      await pump(tester, FakePurchases(buyOutcome: PurchaseOutcome.pending));
      await subscribe(tester);

      // The test runner is Android, so the store is Google Play.
      expect(
        find.text(
          'Your payment is pending with Google Play. The coach unlocks when it '
          'completes.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Nothing has been charged'), findsNothing);
      expect(find.textContaining('did not go through'), findsNothing);
    });

    testWidgets('no connection claims nothing about money', (tester) async {
      await pump(tester, FakePurchases(buyOutcome: PurchaseOutcome.offline));
      await subscribe(tester);

      expect(
        find.text("No connection — try again when you're online."),
        findsOneWidget,
      );
      expect(find.textContaining('Nothing has been charged'), findsNothing);
    });

    testWidgets('an owned subscription is restored, not bought again', (
      tester,
    ) async {
      await pump(
        tester,
        FakePurchases(buyOutcome: PurchaseOutcome.alreadyOwned),
      );
      await subscribe(tester);

      expect(
        find.text(
          'This Google Play account already has a subscription. Tap Restore '
          'purchases.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a restore ends on its own sentence, not a payment', (
      tester,
    ) async {
      // The server has not caught up inside the wait: the same place a
      // purchase ends on "Payment went through".
      await pump(
        tester,
        FakePurchases(restoreOutcome: PurchaseOutcome.purchased),
      );
      await tester.tap(find.text('Restore purchases'));
      await tester.pump();
      for (final s in <int>[1, 2, 3, 5]) {
        await tester.pump(Duration(seconds: s));
      }
      await tester.pumpAndSettle();

      expect(
        find.text('Restored. The coach can take a minute to unlock.'),
        findsOneWidget,
      );
      expect(find.textContaining('Payment went through'), findsNothing);
    });

    testWidgets('a restore that finds nothing says so', (tester) async {
      await pump(tester, FakePurchases());
      await tester.tap(find.text('Restore purchases'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'No previous subscription found on this Google Play account.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a restore with no connection says that, and only that', (
      tester,
    ) async {
      await pump(
        tester,
        FakePurchases(restoreOutcome: PurchaseOutcome.offline),
      );
      await tester.tap(find.text('Restore purchases'));
      await tester.pumpAndSettle();

      expect(
        find.text("No connection — try again when you're online."),
        findsOneWidget,
      );
    });

    testWidgets('and one that fails otherwise does not blame the network', (
      tester,
    ) async {
      await pump(tester, FakePurchases(restoreOutcome: PurchaseOutcome.failed));
      await tester.tap(find.text('Restore purchases'));
      await tester.pumpAndSettle();

      expect(
        find.text('Restoring did not work. Try again in a moment.'),
        findsOneWidget,
      );
      expect(find.textContaining('Could not reach'), findsNothing);
    });
  });
}

/// RevenueCat's platform side, as far as a restore uses it.
class _Sdk {
  static const _channel = MethodChannel('purchases_flutter');

  String user = r'$RCAnonymousID:install';
  PurchasesErrorCode? restoreError;

  static Map<String, Object?> _customerInfo(String user) => <String, Object?>{
    'entitlements': <String, Object?>{
      'all': <String, Object?>{},
      'active': <String, Object?>{},
      'verification': 'NOT_REQUESTED',
    },
    'allPurchaseDates': <String, Object?>{},
    'activeSubscriptions': <Object?>[],
    'allPurchasedProductIdentifiers': <Object?>[],
    'nonSubscriptionTransactions': <Object?>[],
    'firstSeen': '2026-09-01T00:00:00Z',
    'originalAppUserId': user,
    'allExpirationDates': <String, Object?>{},
    'requestDate': '2026-09-29T00:00:00Z',
  };

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          switch (call.method) {
            case 'getAppUserID':
              return user;
            case 'isAnonymous':
              return user.startsWith(r'$RCAnonymousID');
            case 'logIn':
              user =
                  (call.arguments as Map<Object?, Object?>)['appUserID']!
                      as String;
              return <String, Object?>{
                'customerInfo': _customerInfo(user),
                'created': false,
              };
            case 'restorePurchases':
              final error = restoreError;
              if (error != null) {
                throw PlatformException(code: '${error.index}');
              }
              return _customerInfo(user);
          }
          return null;
        });
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  }
}
