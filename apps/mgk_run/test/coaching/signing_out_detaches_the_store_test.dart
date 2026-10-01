import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/preview/fake_purchases.dart';
import 'package:mgk_run/src/features/auth/presentation/auth_gate.dart';
import 'package:mgk_run/src/features/auth/presentation/sign_in_screen.dart';
import 'package:mgk_run/src/features/coaching/data/revenuecat_purchases.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_offer.dart';
import 'package:mgk_run/src/features/coaching/presentation/purchase_screen.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_store.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// **Signing out never logged out of RevenueCat.**
///
/// Nothing called `Purchases.logOut`, `RevenueCatPurchases` never cleared the
/// id it had been given, and its guard asked only whether the SDK was
/// anonymous -- so once anybody had been identified it said yes for good. A
/// purchase made signed out, or as somebody whose identify had not landed, was
/// attributed to the account that had left, and the person who paid got
/// nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const offer = CoachOffer(
    id: 'run.coach.monthly',
    title: 'Coach',
    description: 'A plan.',
    price: '£0.99',
  );

  group('the RevenueCat client', () {
    late _Sdk sdk;

    setUp(() => sdk = _Sdk()..install());
    tearDown(() => sdk.uninstall());

    test(
      'with nobody signed in, nothing is bought and nothing restored',
      () async {
        final purchases = RevenueCatPurchases(apiKey: 'test_key');

        expect(await purchases.buy(offer), PurchaseOutcome.notIdentified);
        expect(await purchases.restore(), PurchaseOutcome.notIdentified);
        expect(sdk.calls, isNot(contains('purchasePackage')));
        expect(sdk.calls, isNot(contains('restorePurchases')));
      },
    );

    test(
      'signing out detaches the account, and the next sale is refused',
      () async {
        final purchases = RevenueCatPurchases(apiKey: 'test_key');
        await purchases.identify('alex');
        expect(sdk.user, 'alex');
        expect(await purchases.restore(), PurchaseOutcome.nothingToRestore);

        await purchases.logOut();

        expect(sdk.calls, contains('logOut'));
        expect(sdk.anonymous, isTrue);
        sdk.calls.clear();
        expect(await purchases.buy(offer), PurchaseOutcome.notIdentified);
        expect(await purchases.restore(), PurchaseOutcome.notIdentified);
        expect(sdk.calls, isNot(contains('restorePurchases')));
      },
    );

    test('it asks who the store is attached to, not whether', () async {
      // Alex was identified; Sam signs in and Sam's identify does not land.
      // The store is still Alex's -- not anonymous -- and the old guard waved
      // the restore through onto Alex's account.
      final purchases = RevenueCatPurchases(apiKey: 'test_key');
      await purchases.identify('alex');
      sdk.refuseLogIn = true;
      await purchases.identify('sam');
      expect(sdk.user, 'alex');

      expect(await purchases.restore(), PurchaseOutcome.notIdentified);
      expect(sdk.calls, isNot(contains('restorePurchases')));
    });

    test('logging out an SDK nobody set up touches nothing', () async {
      // The launch replays a signed-out state to every listener; that must not
      // configure a network-touching SDK just to detach nobody.
      final purchases = RevenueCatPurchases(apiKey: 'test_key');
      await purchases.logOut();
      expect(sdk.calls, isEmpty);
    });

    test('an anonymous store is not asked to log out', () async {
      // RevenueCat throws for that, and there is nothing to detach.
      final purchases = RevenueCatPurchases(apiKey: 'test_key');
      await purchases.identify('alex');
      await purchases.logOut();
      sdk.calls.clear();

      await purchases.logOut();
      expect(sdk.calls, isNot(contains('logOut')));
    });
  });

  group('the app', () {
    testWidgets('signing out detaches the store', (tester) async {
      final auth = FakeAuthRepository(signedIn: true, email: 'a@example.com')
        ..userId = 'alex';
      final purchases = FakePurchases();
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: AuthGate(
            auth: auth,
            introStore: InMemoryIntroStore(done: true),
            purchases: purchases,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(purchases.identifiedAs, 'alex');

      await auth.signOut();
      await tester.pumpAndSettle();

      expect(purchases.logOuts, 1);
      expect(purchases.identifiedAs, isNull);
    });

    Future<FakeAuthRepository> pumpPaywall(
      WidgetTester tester,
      FakePurchases purchases,
    ) async {
      final auth = FakeAuthRepository()..userId = 'alex';
      await tester.binding.setSurfaceSize(const Size(430, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: PurchaseScreen(
            purchases: purchases,
            entitlements: FakeEntitlements(),
            auth: auth,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return auth;
    }

    testWidgets('a purchase refused for want of an account offers one', (
      tester,
    ) async {
      final purchases = FakePurchases(
        buyOutcome: PurchaseOutcome.notIdentified,
      );
      final auth = await pumpPaywall(tester, purchases);
      expect(auth.isSignedIn, isFalse);

      await tester.tap(find.text('Subscribe').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Sign in first'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.byType(SignInScreen), findsOneWidget);

      // The form is the second step since build 27.
      await tester.tap(find.text('Continue with email'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'a@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'password',
      );
      await tester.tap(find.widgetWithText(PrimaryButton, 'Sign in'));
      // Fixed pumps: a submitting PrimaryButton draws a spinner that never
      // settles.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(SignInScreen), findsNothing, reason: 'it closed');
      expect(auth.isSignedIn, isTrue);
      expect(purchases.identifiedAs, 'alex', reason: 'attached straight away');
      expect(find.textContaining('Sign in first'), findsNothing);
    });

    testWidgets('and so does a restore', (tester) async {
      await pumpPaywall(
        tester,
        FakePurchases(restoreOutcome: PurchaseOutcome.notIdentified),
      );

      await tester.tap(find.text('Restore purchases'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Sign in first, then restore'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'Sign in'), findsOneWidget);
      expect(find.textContaining('Could not reach'), findsNothing);
    });
  });
}

/// RevenueCat's platform side, as far as this client uses it.
class _Sdk {
  static const _channel = MethodChannel('purchases_flutter');

  final List<String> calls = <String>[];
  String user = r'$RCAnonymousID:install';
  bool anonymous = true;
  bool refuseLogIn = false;

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
          calls.add(call.method);
          switch (call.method) {
            case 'setupPurchases':
              return null;
            case 'getAppUserID':
              return user;
            case 'isAnonymous':
              return anonymous;
            case 'logIn':
              if (refuseLogIn) {
                throw PlatformException(code: '10', message: 'network');
              }
              user =
                  (call.arguments as Map<Object?, Object?>)['appUserID']!
                      as String;
              anonymous = false;
              return <String, Object?>{
                'customerInfo': _customerInfo(user),
                'created': false,
              };
            case 'logOut':
              user = r'$RCAnonymousID:after';
              anonymous = true;
              return _customerInfo(user);
            case 'restorePurchases':
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
