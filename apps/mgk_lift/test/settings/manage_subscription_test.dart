import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/auth/data/fake_auth.dart';
import 'package:mgk_lift/src/features/auth/domain/account.dart';
import 'package:mgk_lift/src/features/legal/data/account_deletion_service.dart';
import 'package:mgk_lift/src/features/legal/presentation/delete_account_screen.dart';
import 'package:mgk_lift/src/features/purchases/domain/manage_subscription.dart';
import 'package:mgk_lift/src/features/settings/presentation/account_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// **The way out of a subscription is in the app** (5 October 2026). Lift
/// 2.0.0 sells subscriptions and had no way to manage one, and its delete
/// screen did not say that deleting leaves the store billing. Run has had
/// both since build 26.
void main() {
  Future<void> pumpTall(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: child));
    await tester.pumpAndSettle();
  }

  group('the store page', () {
    test("Google Play opens Lift's own entry", () {
      final uri = manageSubscriptionUri(TargetPlatform.android);
      expect(uri.host, 'play.google.com');
      expect(uri.path, '/store/account/subscriptions');
      // The id Lift has always shipped under, Liftio's.
      expect(uri.queryParameters['package'], 'com.mgkcodes.liftio');
    });

    test("an iPhone opens the Apple ID's subscriptions", () {
      expect(
        manageSubscriptionUri(TargetPlatform.iOS).toString(),
        'https://apps.apple.com/account/subscriptions',
      );
    });
  });

  group('the account screen', () {
    testWidgets('a subscriber can manage it from here', (tester) async {
      var opened = 0;
      await pumpTall(
        tester,
        AccountScreen(
          email: 'lifter@example.com',
          planLabel: 'Subscribed',
          onManageSubscription: () => opened++,
        ),
      );

      await tester.tap(find.text('Manage subscription'));
      expect(opened, 1);
    });

    testWidgets('and somebody not subscribed is not offered it', (
      tester,
    ) async {
      await pumpTall(
        tester,
        const AccountScreen(email: 'lifter@example.com', planLabel: 'Free'),
      );
      expect(find.text('Manage subscription'), findsNothing);
    });
  });

  group('deleting while subscribed', () {
    Future<int Function()> pumpDelete(
      WidgetTester tester, {
      required bool subscribed,
    }) async {
      var managed = 0;
      final auth = FakeAuth(
        account: const Account(id: 'u1', email: 'lifter@example.com'),
      );
      addTearDown(auth.dispose);
      await pumpTall(
        tester,
        DeleteAccountScreen(
          auth: auth,
          deleter: FakeAccountDeleter(),
          onSignedOut: () {},
          onManageSubscription: subscribed ? () => managed++ : null,
          platform: TargetPlatform.android,
        ),
      );
      return () => managed;
    }

    testWidgets('says the store goes on billing, before and after', (
      tester,
    ) async {
      final managed = await pumpDelete(tester, subscribed: true);

      expect(
        find.text(
          'Deleting your account does not cancel your subscription. Cancel '
          'it in Google Play, or it will keep renewing.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Manage subscription'));
      expect(managed(), 1);

      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DestructiveButton));
      await tester.pumpAndSettle();

      // Again once it is done, which is when it will be acted on.
      expect(find.text('Your data is deleted'), findsOneWidget);
      expect(
        find.textContaining('does not cancel your subscription'),
        findsOneWidget,
      );
    });

    testWidgets('and says nothing about one there is not', (tester) async {
      await pumpDelete(tester, subscribed: false);
      expect(find.textContaining('does not cancel'), findsNothing);
      expect(find.text('Manage subscription'), findsNothing);
    });
  });
}
