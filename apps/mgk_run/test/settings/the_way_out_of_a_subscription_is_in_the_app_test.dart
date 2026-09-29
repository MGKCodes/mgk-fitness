import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/preview/fake_purchases.dart';
import 'package:mgk_run/src/features/coaching/data/entitlement_repository.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_subscription.dart';
import 'package:mgk_run/src/features/coaching/domain/manage_subscription.dart';
import 'package:mgk_run/src/features/legal/domain/account_deleter.dart';
import 'package:mgk_run/src/features/settings/presentation/account_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// **The account screen said "cancel it in Google Play" and linked nowhere.**
///
/// Google Play's subscriptions policy wants a link to its Subscription Center
/// from inside the app, and Apple's account-deletion guidance wants the way to
/// manage a subscription offered too. And the sentence named the wrong store
/// for anybody who had subscribed on one platform and signed in on the other:
/// it asked `defaultTargetPlatform`, which is where the app is running, not who
/// is charging.
void main() {
  final now = DateTime.utc(2026, 9, 29);

  CoachSubscription row({
    String status = 'active',
    String? platform,
    String product = 'paid',
  }) => CoachSubscription.fromRow(<String, dynamic>{
    'product': product,
    'status': status,
    'platform': ?platform,
  }, now: now);

  group('which store bills them is read off the row', () {
    test('apple and google, and nothing guessed from anything else', () {
      expect(row(platform: 'apple').store, BillingStore.appStore);
      expect(row(platform: 'google').store, BillingStore.googlePlay);
      expect(row().store, isNull);
      expect(row(platform: 'stripe').store, isNull);
    });

    test('and the read asks for it', () {
      final asked = SupabaseEntitlements.columns
          .split(',')
          .map((c) => c.trim());
      expect(asked, contains('platform'));
    });

    test("the row's store wins over the phone's", () {
      expect(
        billingStoreFor(row(platform: 'apple'), TargetPlatform.android),
        BillingStore.appStore,
      );
      expect(
        billingStoreFor(row(platform: 'google'), TargetPlatform.iOS),
        BillingStore.googlePlay,
      );
      // A hand-granted row says nothing, and the phone's store is the answer
      // for nearly everybody.
      expect(
        billingStoreFor(row(), TargetPlatform.android),
        BillingStore.googlePlay,
      );
      expect(billingStoreFor(row(), TargetPlatform.iOS), BillingStore.appStore);
    });
  });

  group('the links', () {
    test("Play opens this app's subscription in the Subscription Center", () {
      expect(
        manageSubscriptionUri(
          BillingStore.googlePlay,
          tier: CoachTier.coach,
        ).toString(),
        'https://play.google.com/store/account/subscriptions'
        '?package=com.mgkcodes.fitness.run&sku=run.coach.monthly',
      );
      expect(
        manageSubscriptionUri(
          BillingStore.googlePlay,
          tier: CoachTier.premiumCoach,
        ).queryParameters['sku'],
        'run.coach.premium.monthly',
      );
    });

    test('and the list when it does not know which', () {
      expect(
        manageSubscriptionUri(BillingStore.googlePlay).toString(),
        'https://play.google.com/store/account/subscriptions'
        '?package=com.mgkcodes.fitness.run',
      );
    });

    test("Apple's is the subscriptions page on the Apple ID", () {
      expect(
        manageSubscriptionUri(BillingStore.appStore).toString(),
        'https://apps.apple.com/account/subscriptions',
      );
    });
  });

  group('the account screen', () {
    late List<Uri> opened;
    late FakePurchases purchases;

    Future<void> pumpAccount(
      WidgetTester tester,
      CoachSubscription subscription, {
      bool browserOpens = true,
    }) async {
      opened = <Uri>[];
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: AccountScreen(
            auth: FakeAuthRepository(signedIn: true, email: 'a@example.com'),
            deleter: _NoDeleter(),
            subscription: subscription,
            memberSince: null,
            name: 'Alex',
            photo: null,
            onSignOut: () async {},
            onEditName: () async {},
            onPickPhoto: () async {},
            onRemovePhoto: null,
            onCreateAccount: () {},
            purchases: purchases,
            openUrl: (uri) async {
              opened.add(uri);
              return browserOpens;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    setUp(() => purchases = FakePurchases(managePageOpens: false));

    testWidgets('a Play subscriber gets a link to Play', (tester) async {
      await pumpAccount(tester, row(platform: 'google'));

      await tester.tap(find.text('Manage subscription'));
      await tester.pumpAndSettle();

      expect(opened.single.host, 'play.google.com');
      expect(opened.single.queryParameters['package'], kPlayPackage);
      expect(opened.single.queryParameters['sku'], 'run.coach.monthly');
    });

    testWidgets('an App Store subscriber on Android is sent to Apple', (
      tester,
    ) async {
      // The test runner is Android. This screen used to tell this runner to
      // cancel in Google Play, where there is nothing to cancel.
      await pumpAccount(tester, row(platform: 'apple'));

      expect(find.textContaining('Google Play'), findsNothing);
      expect(find.textContaining('the App Store'), findsWidgets);

      await tester.tap(find.text('Manage subscription'));
      await tester.pumpAndSettle();
      expect(opened.single.toString(), kAppleSubscriptionsUrl);
      expect(
        purchases.managePages,
        0,
        reason: "Apple's page is not on this phone's store",
      );
    });

    testWidgets("on an iPhone the store's own page is tried first", (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      purchases = FakePurchases();
      await pumpAccount(tester, row(platform: 'apple'));

      await tester.tap(find.text('Manage subscription'));
      await tester.pumpAndSettle();

      expect(purchases.managePages, 1);
      expect(opened, isEmpty, reason: 'it opened, so nothing else is needed');
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets("and Apple's page is opened when that cannot", (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await pumpAccount(tester, row(platform: 'apple'));

      await tester.tap(find.text('Manage subscription'));
      await tester.pumpAndSettle();

      expect(purchases.managePages, 1);
      expect(opened.single.toString(), kAppleSubscriptionsUrl);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('offered while paying, failing, or over', (tester) async {
      for (final status in <String>['active', 'grace', 'expired']) {
        await pumpAccount(tester, row(status: status, platform: 'google'));
        expect(
          find.text('Manage subscription'),
          findsOneWidget,
          reason: status,
        );
      }
    });

    testWidgets('and not to somebody who never subscribed', (tester) async {
      await pumpAccount(tester, CoachSubscription.none);
      expect(find.text('Manage subscription'), findsNothing);
    });

    testWidgets('a link that will not open says where it is', (tester) async {
      await pumpAccount(tester, row(platform: 'google'), browserOpens: false);

      await tester.tap(find.text('Manage subscription'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not open Google Play'), findsOneWidget);
      expect(
        find.textContaining('play.google.com/store/account/subscriptions'),
        findsOneWidget,
      );
    });
  });
}

class _NoDeleter implements AccountDeleter {
  @override
  Future<AccountDeletionResult> deleteAccount() async =>
      const AccountDeletionResult(accountDeleted: true);
}
