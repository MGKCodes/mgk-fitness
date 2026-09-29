import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/preview/fake_purchases.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_subscription.dart';
import 'package:mgk_run/src/features/legal/domain/account_deleter.dart';
import 'package:mgk_run/src/features/legal/presentation/delete_account_screen.dart';

/// **Deleting the account said nothing about the subscription, which goes on
/// charging.**
///
/// The subscription is between the runner and Apple or Google, and deleting
/// the data the coach runs on does not end it -- nothing on this side can.
/// Apple's account-deletion guidance asks for that to be said, with the way to
/// cancel offered where it is said. So it is said before the runner confirms,
/// and again on the done screen, which is when they will act on it.
void main() {
  late List<Uri> opened;

  Future<void> pumpScreen(
    WidgetTester tester,
    CoachSubscription subscription,
  ) async {
    opened = <Uri>[];
    await tester.binding.setSurfaceSize(const Size(420, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: DeleteAccountScreen(
          auth: FakeAuthRepository(signedIn: true, email: 'a@example.com'),
          deleter: _Deleter(),
          entitlements: FakeEntitlements.of(subscription),
          purchases: FakePurchases(managePageOpens: false),
          openUrl: (uri) async {
            opened.add(uri);
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> deleteIt(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), 'DELETE');
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete my data'));
    await tester.pumpAndSettle();
  }

  const playActive = CoachSubscription(
    tier: CoachTier.coach,
    standing: SubscriptionStanding.active,
    store: BillingStore.googlePlay,
  );

  const warning =
      'Deleting your account does not cancel your subscription. Cancel it in '
      'Google Play, or it will keep renewing.';

  testWidgets('a paying subscriber is told before they confirm', (
    tester,
  ) async {
    await pumpScreen(tester, playActive);

    expect(find.text(warning), findsOneWidget);
    await tester.tap(find.text('Manage subscription'));
    await tester.pumpAndSettle();
    expect(opened.single.host, 'play.google.com');
    expect(opened.single.queryParameters['sku'], 'run.coach.monthly');
  });

  testWidgets('and again once it is done, when they will act on it', (
    tester,
  ) async {
    await pumpScreen(tester, playActive);
    await deleteIt(tester);

    expect(find.text('Your data is deleted'), findsOneWidget);
    expect(
      find.text(warning),
      findsOneWidget,
      reason: 'read when the screen opened; the account is gone by now',
    );
    await tester.tap(find.text('Manage subscription'));
    await tester.pumpAndSettle();
    expect(opened, hasLength(1));
  });

  testWidgets('a payment the store is chasing is still billing', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const CoachSubscription(
        tier: CoachTier.premiumCoach,
        standing: SubscriptionStanding.billingRetry,
        store: BillingStore.appStore,
      ),
    );

    expect(
      find.text(
        'Deleting your account does not cancel your subscription. Cancel it '
        'in the App Store, or it will keep renewing.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('an ended subscription, or none, charges nothing to warn of', (
    tester,
  ) async {
    for (final subscription in <CoachSubscription>[
      const CoachSubscription(
        tier: CoachTier.coach,
        standing: SubscriptionStanding.ended,
      ),
      CoachSubscription.none,
    ]) {
      await pumpScreen(tester, subscription);
      expect(
        find.textContaining('does not cancel your subscription'),
        findsNothing,
        reason: subscription.standing.name,
      );
      expect(find.text('Manage subscription'), findsNothing);
    }
  });
}

class _Deleter implements AccountDeleter {
  @override
  Future<AccountDeletionResult> deleteAccount() async =>
      const AccountDeletionResult(accountDeleted: true);
}
