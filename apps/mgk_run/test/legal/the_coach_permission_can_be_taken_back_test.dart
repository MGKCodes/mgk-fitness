import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/features/coaching/domain/ai_consent.dart';
import 'package:mgk_run/src/features/legal/domain/account_deleter.dart';
import 'package:mgk_run/src/features/legal/presentation/legal_screen.dart';

class _NeverDeleter implements AccountDeleter {
  @override
  Future<AccountDeletionResult> deleteAccount({
    required DeletionScope scope,
  }) async => throw StateError('the test must not reach deletion');
}

/// **A permission is only consent if it can be taken back as easily as it was
/// given.** One row in Privacy & legal, one confirmation, and the coach asks
/// again before it next sends anything.
void main() {
  late InMemoryAiConsentStore consent;

  setUp(() => consent = InMemoryAiConsentStore());

  Future<void> pumpLegal(WidgetTester tester, {bool signedIn = true}) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: LegalScreen(
          auth: FakeAuthRepository(
            signedIn: signedIn,
            email: 'a@mgkfitness.mgkcodes.com',
          ),
          deleter: _NeverDeleter(),
          aiConsent: consent,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('withdrawing clears the answer, and says what happens next', (
    tester,
  ) async {
    await consent.grant();
    await pumpLegal(tester);

    expect(find.text('Coach and AI'), findsOneWidget);
    expect(find.textContaining('You agreed'), findsOneWidget);

    await tester.tap(find.text('Coach and AI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Withdraw'));
    await tester.pumpAndSettle();

    expect(await consent.isGranted(), isFalse);
    expect(consent.withdrawals, 1);
    expect(
      find.text('Withdrawn. Your coach will ask before it sends anything.'),
      findsOneWidget,
    );
    expect(find.textContaining('Not agreed'), findsOneWidget);
  });

  testWidgets('"Keep it" keeps it', (tester) async {
    await consent.grant();
    await pumpLegal(tester);

    await tester.tap(find.text('Coach and AI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();

    expect(await consent.isGranted(), isTrue);
    expect(consent.withdrawals, 0);
  });

  testWidgets('nothing to withdraw offers no withdrawal', (tester) async {
    await pumpLegal(tester);

    expect(find.textContaining('Not agreed'), findsOneWidget);
    await tester.tap(find.text('Coach and AI'));
    await tester.pumpAndSettle();

    expect(find.text('Withdraw'), findsNothing);
  });

  testWidgets('signed out, there is no account to hold an answer', (
    tester,
  ) async {
    await pumpLegal(tester, signedIn: false);

    expect(find.text('Coach and AI'), findsNothing);
  });
}
