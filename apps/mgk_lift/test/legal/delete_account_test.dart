import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/auth/data/fake_auth.dart';
import 'package:mgk_lift/src/features/auth/domain/account.dart';
import 'package:mgk_lift/src/features/legal/data/account_deletion_service.dart';
import 'package:mgk_lift/src/features/legal/domain/account_deleter.dart';
import 'package:mgk_lift/src/features/legal/presentation/delete_account_screen.dart';
import 'package:mgk_lift/src/features/legal/presentation/legal_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';

const Account _signedIn = Account(id: 'u1', email: 'lifter@example.com');

Future<void> pumpTall(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1080, 4200);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

Future<void> pumpScreen(
  WidgetTester tester, {
  required FakeAccountDeleter deleter,
  FakeAuth? auth,
}) async {
  final service = auth ?? FakeAuth(account: _signedIn);
  addTearDown(service.dispose);
  await pumpTall(tester, DeleteAccountScreen(auth: service, deleter: deleter));
}

/// The two cards are the suite's [DeletionChoice] since 4 October 2026, the
/// same in both apps, keyed by what they erase rather than by Lift's enum.
Finder scopeCard(DeletionScope scope) => find.byKey(switch (scope) {
  DeletionScope.liftOnly => DeletionChoice.narrowKey,
  DeletionScope.everything => DeletionChoice.wideKey,
});

Future<void> arm(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), 'DELETE');
  await tester.pumpAndSettle();
}

void main() {
  group('the scope the server is asked for', () {
    test('lift only names the app; everything deliberately names nothing', () {
      // The absent `app` is not a forgotten field — the function reads it as
      // "everything, everywhere, and the login". Asserting the mapping is what
      // stops somebody "tidying" the null into a default of 'lift'.
      expect(DeletionScope.liftOnly.app, 'lift');
      expect(DeletionScope.everything.app, isNull);
    });
  });

  group('what the server said', () {
    test(
      'a kept login is reported with the reason the server actually uses',
      () {
        // `other_app_data` is the server's spelling. Run tests for
        // `sibling_app_data`, which the function never returns, so run's
        // retained-login message has never once been shown.
        const result = AccountDeletionResult(
          accountDeleted: false,
          retainedReason: 'other_app_data',
          remainingApps: <String>['run'],
        );

        expect(result.loginRetainedForOtherApp, isTrue);
        expect(result.loginCouldNotBeRemoved, isFalse);
      },
    );

    test('a failed login removal is not reported as a kept one', () {
      const result = AccountDeletionResult(
        accountDeleted: false,
        retainedReason: 'auth_delete_failed',
      );

      expect(result.loginRetainedForOtherApp, isFalse);
      expect(result.loginCouldNotBeRemoved, isTrue);
    });
  });

  group('the screen asks before it acts', () {
    testWidgets('offers both scopes and starts on the narrower one', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, deleter: FakeAccountDeleter());

      expect(scopeCard(DeletionScope.liftOnly), findsOneWidget);
      expect(scopeCard(DeletionScope.everything), findsOneWidget);

      // A destructive screen must not open with the widest option chosen, and
      // exactly one of the two must be.
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      expect(
        find.descendant(
          of: scopeCard(DeletionScope.liftOnly),
          matching: find.byIcon(Icons.radio_button_checked),
        ),
        findsOneWidget,
      );

      // The confirm button names the chosen scope, which is why it shares its
      // words with the card and has to be found by type.
      expect(
        find.descendant(
          of: find.byType(DestructiveButton),
          matching: find.text("Delete this app's data"),
        ),
        findsOneWidget,
      );
    });

    testWidgets('will not fire until DELETE is typed', (
      WidgetTester tester,
    ) async {
      final deleter = FakeAccountDeleter();
      await pumpScreen(tester, deleter: deleter);

      await tester.tap(find.byType(DestructiveButton));
      await tester.pumpAndSettle();
      expect(deleter.asked, isEmpty);

      await tester.enterText(find.byType(TextField), 'delet');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DestructiveButton));
      await tester.pumpAndSettle();
      expect(deleter.asked, isEmpty);
    });

    testWidgets('sends the narrow scope when the narrow one is chosen', (
      WidgetTester tester,
    ) async {
      final deleter = FakeAccountDeleter(
        result: const AccountDeletionResult(
          accountDeleted: false,
          retainedReason: 'other_app_data',
          remainingApps: <String>['run'],
        ),
      );
      await pumpScreen(tester, deleter: deleter);
      await arm(tester);

      await tester.tap(find.byType(DestructiveButton));
      await tester.pumpAndSettle();

      expect(deleter.asked, <DeletionScope>[DeletionScope.liftOnly]);
    });

    testWidgets('sends everything only when everything is chosen', (
      WidgetTester tester,
    ) async {
      final deleter = FakeAccountDeleter();
      await pumpScreen(tester, deleter: deleter);

      await tester.tap(scopeCard(DeletionScope.everything));
      await tester.pumpAndSettle();
      await arm(tester);

      // The button relabels itself, so the last thing read before the tap is
      // the scope that was chosen.
      await tester.tap(find.byType(DestructiveButton));
      await tester.pumpAndSettle();

      expect(deleter.asked, <DeletionScope>[DeletionScope.everything]);
    });
  });

  group('what the screen says happened', () {
    testWidgets('a kept login is explained by the app still using it', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        deleter: FakeAccountDeleter(
          result: const AccountDeletionResult(
            accountDeleted: false,
            retainedReason: 'other_app_data',
            remainingApps: <String>['run'],
          ),
        ),
      );
      await arm(tester);
      await tester.tap(find.byType(DestructiveButton));
      await tester.pumpAndSettle();

      expect(find.text('Your data is deleted'), findsOneWidget);
      expect(
        find.textContaining('still active because MGKFitness: Run is using it'),
        findsOneWidget,
      );
    });

    testWidgets('asking for the narrow one and losing the login says so', (
      WidgetTester tester,
    ) async {
      // The honesty case. Choosing "just Lift" can still take the login when
      // nothing else is using the profile, and glossing that would make the
      // screen a liar about the one thing it cannot take back.
      await pumpScreen(
        tester,
        deleter: FakeAccountDeleter(
          result: const AccountDeletionResult(accountDeleted: true),
        ),
      );
      await arm(tester);
      await tester.tap(find.byType(DestructiveButton));
      await tester.pumpAndSettle();

      expect(find.textContaining('nothing else was using it'), findsOneWidget);
    });

    testWidgets('a login that could not be removed is not called success', (
      WidgetTester tester,
    ) async {
      await pumpScreen(
        tester,
        deleter: FakeAccountDeleter(
          result: const AccountDeletionResult(
            accountDeleted: false,
            retainedReason: 'auth_delete_failed',
          ),
        ),
      );
      await arm(tester);
      await tester.tap(find.byType(DestructiveButton));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(
        find.textContaining('lift@mgkfitness.mgkcodes.com'),
        findsOneWidget,
      );
    });

    testWidgets('a failure leaves the session alone and says what went wrong', (
      WidgetTester tester,
    ) async {
      final auth = FakeAuth(account: _signedIn);
      addTearDown(auth.dispose);
      await pumpTall(
        tester,
        DeleteAccountScreen(
          auth: auth,
          deleter: FakeAccountDeleter(
            failWith: const AccountDeletionException(
              'The server could not complete the deletion.',
            ),
          ),
        ),
      );
      await arm(tester);
      await tester.tap(find.byType(DestructiveButton));
      await tester.pumpAndSettle();

      expect(
        find.text('The server could not complete the deletion.'),
        findsOneWidget,
      );
      // Still on the form, still signed in. A failed deletion that signed you
      // out would look exactly like a successful one.
      expect(find.text('Your data is deleted'), findsNothing);
      expect(auth.current, isNotNull);
    });
  });

  group("the phone's copy", () {
    Future<List<String>> finish(
      WidgetTester tester,
      AccountDeletionResult result,
    ) async {
      final calls = <String>[];
      final auth = FakeAuth(account: _signedIn);
      addTearDown(auth.dispose);
      await pumpTall(
        tester,
        DeleteAccountScreen(
          auth: auth,
          deleter: FakeAccountDeleter(result: result),
          onSignedOut: () {},
          onAccountGone: () async =>
              // Recorded with whether the session was still there, because
              // the order is the point: released first, then signed out.
              calls.add(auth.current == null ? 'after' : 'before sign-out'),
        ),
      );
      await arm(tester);
      await tester.tap(find.byType(DestructiveButton));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();
      return calls;
    }

    testWidgets('a deleted login leaves the phone to nobody', (
      WidgetTester tester,
    ) async {
      // Otherwise the phone stays recorded as the deleted account's, and the
      // same person making a new one is asked to erase their own sessions.
      final calls = await finish(
        tester,
        const AccountDeletionResult(accountDeleted: true),
      );
      expect(calls, <String>['before sign-out']);
    });

    testWidgets('a kept login keeps the phone', (WidgetTester tester) async {
      final calls = await finish(
        tester,
        const AccountDeletionResult(
          accountDeleted: false,
          retainedReason: 'other_app_data',
          remainingApps: <String>['run'],
        ),
      );
      expect(calls, isEmpty);
    });

    /// Deletes with an eraser on offer, as the shell gives one, and reports
    /// what was erased and released.
    Future<({int erased, int released})> deleteOffering(
      WidgetTester tester, {
      bool keep = false,
      bool eraseFails = false,
    }) async {
      var erased = 0;
      var released = 0;
      final auth = FakeAuth(account: _signedIn);
      addTearDown(auth.dispose);
      await pumpTall(
        tester,
        DeleteAccountScreen(
          auth: auth,
          deleter: FakeAccountDeleter(
            result: const AccountDeletionResult(accountDeleted: true),
          ),
          onSignedOut: () {},
          onAccountGone: () async => released++,
          eraseThisPhone: () async {
            if (eraseFails) throw StateError('disk');
            erased++;
          },
        ),
      );
      if (keep) {
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
      }
      await arm(tester);
      await tester.tap(find.byType(DestructiveButton));
      await tester.pumpAndSettle();
      return (erased: erased, released: released);
    }

    testWidgets('is offered, on by default, and erased with the account', (
      WidgetTester tester,
    ) async {
      // Somebody deleting their account has asked for their data to go, and
      // the copy on the phone is the part they are least likely to think of.
      final done = await deleteOffering(tester);

      expect(done.erased, 1);
      expect(find.text('Your data is deleted'), findsOneWidget);
      expect(
        find.text("This phone's copy has been erased too."),
        findsOneWidget,
      );

      // Erasing already left the phone unclaimed: nothing to release.
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();
      expect(done.released, 0);
    });

    testWidgets('kept, the title says only the servers were cleared', (
      WidgetTester tester,
    ) async {
      final done = await deleteOffering(tester, keep: true);

      expect(done.erased, 0);
      expect(find.text('Deleted from our servers'), findsOneWidget);
      expect(find.text('Your data is deleted'), findsNothing);
      expect(
        find.textContaining('Your sessions are still on this phone'),
        findsOneWidget,
      );
    });

    testWidgets('an erase that failed is not called an erase', (
      WidgetTester tester,
    ) async {
      await deleteOffering(tester, eraseFails: true);

      expect(find.text('Deleted from our servers'), findsOneWidget);
      expect(
        find.textContaining("This phone's copy could not be erased"),
        findsOneWidget,
      );
    });

    testWidgets('with no eraser, the phone is said to be untouched', (
      WidgetTester tester,
    ) async {
      await pumpScreen(tester, deleter: FakeAccountDeleter());

      expect(find.byType(Switch), findsNothing);
      expect(
        find.textContaining('What is on this phone is not touched'),
        findsOneWidget,
      );
    });
  });

  group('reaching it', () {
    testWidgets('the legal hub offers deletion when there is an account', (
      WidgetTester tester,
    ) async {
      final auth = FakeAuth(account: _signedIn);
      addTearDown(auth.dispose);

      await pumpTall(
        tester,
        LegalScreen(
          email: _signedIn.email,
          auth: auth,
          deleter: FakeAccountDeleter(),
        ),
      );

      expect(find.text('Delete account'), findsOneWidget);
      // The row says a choice is coming, so it does not read as the single
      // irreversible thing it could have been.
      expect(find.text('This app only, or your whole account'), findsOneWidget);

      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      expect(find.byType(DeleteAccountScreen), findsOneWidget);
    });

    testWidgets('and hides it when there is not', (WidgetTester tester) async {
      final signedOut = FakeAuth();
      addTearDown(signedOut.dispose);

      // Signed out: nothing to delete.
      await pumpTall(
        tester,
        LegalScreen(auth: signedOut, deleter: FakeAccountDeleter()),
      );
      expect(find.text('Delete account'), findsNothing);

      // No server: the row would be a button that fails at the moment somebody
      // most needs it to work.
      final signedIn = FakeAuth(account: _signedIn);
      addTearDown(signedIn.dispose);
      await pumpTall(tester, LegalScreen(auth: signedIn));
      expect(find.text('Delete account'), findsNothing);
    });
  });
}
