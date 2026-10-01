import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/features/legal/domain/account_deleter.dart';
import 'package:mgk_run/src/features/legal/domain/legal_urls.dart';
import 'package:mgk_run/src/features/legal/presentation/legal_screen.dart';

class _NeverDeleter implements AccountDeleter {
  @override
  Future<AccountDeletionResult> deleteAccount() async =>
      throw StateError('the test must not reach deletion');
}

void main() {
  Future<void> pumpLegal(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: LegalScreen(
          auth: FakeAuthRepository(
            signedIn: true,
            email: 'a@mgkfitness.mgkcodes.com',
          ),
          deleter: _NeverDeleter(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('offers all four compliance surfaces', (tester) async {
    await pumpLegal(tester);

    expect(find.text('Privacy & legal'), findsOneWidget);
    expect(find.text('Medical disclaimer'), findsOneWidget);
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('Terms of use'), findsOneWidget);
    expect(find.text('Delete account'), findsOneWidget);
  });

  // Guideline 3.1.2 is satisfied by the paywall's copy of this link, and
  // `purchase_screen_test.dart` pins it there. This row exists for the person
  // who is *not* mid-purchase — a reviewer looking through Settings, or a
  // runner who wants to read what they agreed to after the fact. A link
  // reachable only from a paywall is unreachable to both of them.
  testWidgets('the terms are reachable without opening the paywall', (
    tester,
  ) async {
    await pumpLegal(tester);

    expect(find.text('Terms of use'), findsOneWidget);
    expect(
      find.text('How the subscription works, and what it is not'),
      findsOneWidget,
    );

    // Published rather than embedded, so the row opens a URL rather than
    // pushing a document. Assert the destination rather than mocking the
    // launcher, which is what the paywall's own test does with the same
    // constant.
    //
    // This asserted `apple.com` and `stdeula` until 2026-09-10. The terms are
    // ours now — Play will not take a store's EULA from a subscription
    // listing, and section 3 of ours carries the medical disclaimer that
    // Apple's could never have covered.
    expect(kTermsOfUseUrl, contains('mgkfitness.mgkcodes.com'));
    expect(kTermsOfUseUrl, endsWith('/run/terms'));
  });

  testWidgets('the disclaimer opens read-only, with no accept button', (
    tester,
  ) async {
    await pumpLegal(tester);

    await tester.tap(find.text('Medical disclaimer'));
    await tester.pumpAndSettle();

    expect(find.textContaining('is not medical advice'), findsOneWidget);
    // Reference mode: acknowledging again would be meaningless.
    expect(find.text('I understand'), findsNothing);
    expect(find.text('Not now'), findsNothing);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
  });

  testWidgets('the privacy policy renders, down to the sub-processors', (
    tester,
  ) async {
    await pumpLegal(tester);

    await tester.tap(find.text('Privacy policy'));
    await tester.pumpAndSettle();

    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.textContaining('We do not sell your data'), findsOneWidget);

    // The sub-processor list is below the fold, and the ListView is lazy, so
    // scroll to it rather than asserting on widgets that were never built.
    // (Which processor is named is asserted against the constant and the doc in
    // legal_copy_test.dart, where it cannot pass by simply not rendering.)
    // Each is scrolled to in its own right rather than assuming two named
    // processors share a screenful. They did until the OpenRouter entry grew to
    // spell out what actually goes to the model, at which point the Supabase
    // bullet above it had left the viewport and the assertion failed on lazy
    // rendering rather than on anything being wrong.
    for (final processor in <String>['Supabase', 'OpenRouter', 'Esri']) {
      await tester.scrollUntilVisible(
        find.textContaining(processor),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining(processor), findsWidgets);
    }
  });

  testWidgets('delete account opens the confirmation, not a deletion', (
    tester,
  ) async {
    await pumpLegal(tester);

    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();

    // Reaching the screen must never itself delete: _NeverDeleter would throw.
    expect(find.text('This cannot be undone.'), findsOneWidget);
    expect(find.textContaining('Type DELETE to confirm'), findsOneWidget);
  });
}
