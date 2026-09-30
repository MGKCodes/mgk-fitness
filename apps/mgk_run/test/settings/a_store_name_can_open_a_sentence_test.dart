import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_subscription.dart';
import 'package:mgk_run/src/features/legal/domain/account_deleter.dart';
import 'package:mgk_run/src/features/settings/presentation/account_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// Account, payment failed (screen board T8): "Your last payment did not go
/// through. the App Store is retrying it". The store's name is written for
/// the middle of a sentence, and this one opens with it.
void main() {
  test('the sentence form capitalises the article and nothing else', () {
    expect(BillingStore.appStore.sentenceLabel, 'The App Store');
    expect(BillingStore.googlePlay.sentenceLabel, 'Google Play');
    // Mid-sentence it stays as it was.
    expect(BillingStore.appStore.label, 'the App Store');
  });

  for (final (store, opens, within) in <(BillingStore, String, String)>[
    (BillingStore.appStore, 'The App Store is retrying it', 'in the App Store'),
    (BillingStore.googlePlay, 'Google Play is retrying it', 'in Google Play'),
  ]) {
    testWidgets('a failed payment opens its sentence with ${store.label}', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: AccountScreen(
            auth: FakeAuthRepository(signedIn: true, email: 'a@example.com'),
            deleter: _NoDeleter(),
            subscription: CoachSubscription(
              tier: CoachTier.coach,
              standing: SubscriptionStanding.billingRetry,
              store: store,
            ),
            memberSince: null,
            name: 'Alex',
            photo: null,
            onSignOut: () async {},
            onEditName: () async {},
            onPickPhoto: () async {},
            onRemovePhoto: null,
            onCreateAccount: () {},
            openUrl: (_) async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sentence = find.textContaining('did not go through');
      expect(sentence, findsOneWidget);
      final text = tester.widget<Text>(sentence).data!;
      expect(text, contains('did not go through. $opens'));
      expect(text, contains('payment method $within is the fix'));
      expect(text, isNot(contains('. the ')));
    });
  }
}

class _NoDeleter implements AccountDeleter {
  @override
  Future<AccountDeletionResult> deleteAccount() async =>
      const AccountDeletionResult(accountDeleted: true);
}
