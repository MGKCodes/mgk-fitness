import 'package:mgk_run/src/core/brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/features/legal/domain/account_deleter.dart';
import 'package:mgk_run/src/features/legal/presentation/delete_account_screen.dart';

/// Records whether deletion was actually requested — the assertion that matters
/// most here is that it *isn't*, until the runner has typed the phrase.
class _FakeDeleter implements AccountDeleter {
  _FakeDeleter({this.result, this.failure});

  final AccountDeletionResult? result;
  final AccountDeletionException? failure;

  int calls = 0;

  @override
  Future<AccountDeletionResult> deleteAccount() async {
    calls++;
    final failure = this.failure;
    if (failure != null) throw failure;
    return result ?? const AccountDeletionResult(accountDeleted: true);
  }
}

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    required AccountDeleter deleter,
    FakeAuthRepository? auth,
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: DeleteAccountScreen(
          auth:
              auth ?? FakeAuthRepository(signedIn: true, email: 'a@runio.app'),
          deleter: deleter,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> typeConfirmation(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
  }

  group('the confirmation is genuine', () {
    testWidgets('says plainly what goes, and that it cannot be undone', (
      tester,
    ) async {
      await pumpScreen(tester, deleter: _FakeDeleter());

      expect(find.text('This cannot be undone.'), findsOneWidget);
      expect(
        find.textContaining('Every run, with its route points and splits'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Your runner profile and generated plans'),
        findsOneWidget,
      );
      // The shared-login consequence is disclosed before the runner commits.
      expect(find.textContaining('$kPlatformName profile'), findsOneWidget);
    });

    testWidgets('the delete button is inert until the phrase is typed', (
      tester,
    ) async {
      final deleter = _FakeDeleter();
      await pumpScreen(tester, deleter: deleter);

      final button = find.widgetWithText(OutlinedButton, 'Delete my data');
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);

      // Tapping a disabled button must not delete anything.
      await tester.tap(button);
      await tester.pump();
      expect(deleter.calls, 0);
    });

    testWidgets('a near miss does not arm the button', (tester) async {
      final deleter = _FakeDeleter();
      await pumpScreen(tester, deleter: deleter);

      await typeConfirmation(tester, 'DELET');
      final button = find.widgetWithText(OutlinedButton, 'Delete my data');
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);

      await tester.tap(button);
      await tester.pump();
      expect(deleter.calls, 0);
    });

    testWidgets('typing the phrase arms it, and one tap deletes once', (
      tester,
    ) async {
      final deleter = _FakeDeleter();
      await pumpScreen(tester, deleter: deleter);

      await typeConfirmation(tester, 'DELETE');
      final button = find.widgetWithText(OutlinedButton, 'Delete my data');
      expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(deleter.calls, 1);
      expect(find.text('Your data is deleted'), findsOneWidget);
    });

    testWidgets('lower case counts, since the field is a confirmation not a '
        'password', (tester) async {
      final deleter = _FakeDeleter();
      await pumpScreen(tester, deleter: deleter);

      await typeConfirmation(tester, ' delete ');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete my data'));
      await tester.pumpAndSettle();

      expect(deleter.calls, 1);
    });

    testWidgets('keeping the account leaves without deleting', (tester) async {
      final deleter = _FakeDeleter();
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DeleteAccountScreen(
                      auth: FakeAuthRepository(signedIn: true),
                      deleter: deleter,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Keep my account'));
      await tester.pumpAndSettle();

      expect(find.text('open'), findsOneWidget); // back on the host screen
      expect(deleter.calls, 0);
    });
  });

  group('after deletion', () {
    testWidgets('signs out as soon as the server confirms, and Done leaves', (
      tester,
    ) async {
      // It used to wait for Done. This screen is a route over the app, so the
      // outcome is still read first either way -- what the wait cost was an
      // app closed here keeping a session to an account that no longer
      // existed, and an erased phone claiming itself for that session.
      final auth = FakeAuthRepository(signedIn: true, email: 'a@runio.app');
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DeleteAccountScreen(
                      auth: auth,
                      deleter: _FakeDeleter(),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await typeConfirmation(tester, 'DELETE');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete my data'));
      await tester.pumpAndSettle();

      expect(auth.isSignedIn, isFalse);
      expect(find.text('Your data is deleted'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();

      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('explains when the shared profile was kept for Lift', (
      tester,
    ) async {
      // `other_app_data` is what the deployed function sends. The screen only
      // ever recognised `sibling_app_data`, so every runner whose login was
      // kept for Lift was told it had gone "along with your login".
      await pumpScreen(
        tester,
        deleter: _FakeDeleter(
          result: const AccountDeletionResult(
            accountDeleted: false,
            retainedReason: 'other_app_data',
            deletedRows: <String, int>{'run.runs': 10},
          ),
        ),
      );

      await typeConfirmation(tester, 'DELETE');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete my data'));
      await tester.pumpAndSettle();

      expect(find.text('Your data is deleted'), findsOneWidget);
      expect(find.textContaining('Your login is still active'), findsOneWidget);
      expect(find.textContaining('hello@mgkcodes.com'), findsOneWidget);
      expect(find.textContaining('along with your login'), findsNothing);
    });

    testWidgets('the older name for the same answer still counts', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        deleter: _FakeDeleter(
          result: const AccountDeletionResult(
            accountDeleted: false,
            retainedReason: 'sibling_app_data',
          ),
        ),
      );

      await typeConfirmation(tester, 'DELETE');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete my data'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Your login is still active'), findsOneWidget);
    });

    testWidgets('a login that could not be removed is not called removed', (
      tester,
    ) async {
      // `auth_delete_failed`: the data went and the login did not. It fell
      // through to the sentence for a login that had been removed.
      await pumpScreen(
        tester,
        deleter: _FakeDeleter(
          result: const AccountDeletionResult(
            accountDeleted: false,
            retainedReason: 'auth_delete_failed',
          ),
        ),
      );

      await typeConfirmation(tester, 'DELETE');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete my data'));
      await tester.pumpAndSettle();

      expect(find.textContaining('along with your login'), findsNothing);
      expect(find.textContaining('Lift is using it'), findsNothing);
      expect(
        find.textContaining('Your login could not be removed'),
        findsOneWidget,
      );
      expect(find.textContaining('hello@mgkcodes.com'), findsOneWidget);
    });

    testWidgets('says the profile went too when it held nothing else', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        deleter: _FakeDeleter(
          result: const AccountDeletionResult(accountDeleted: true),
        ),
      );

      await typeConfirmation(tester, 'DELETE');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete my data'));
      await tester.pumpAndSettle();

      expect(find.textContaining('along with your login'), findsOneWidget);
      expect(find.textContaining('Your login is still active'), findsNothing);
    });
  });

  group('when deletion fails', () {
    testWidgets('shows the reason and keeps the runner signed in', (
      tester,
    ) async {
      final auth = FakeAuthRepository(signedIn: true, email: 'a@runio.app');
      await pumpScreen(
        tester,
        auth: auth,
        deleter: _FakeDeleter(
          failure: const AccountDeletionException(
            'The server could not complete the deletion.',
          ),
        ),
      );

      await typeConfirmation(tester, 'DELETE');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete my data'));
      await tester.pumpAndSettle();

      expect(
        find.text('The server could not complete the deletion.'),
        findsOneWidget,
      );
      // No false success, and no sign-out on a failed deletion.
      expect(find.text('Your data is deleted'), findsNothing);
      expect(auth.isSignedIn, isTrue);
    });

    testWidgets('the runner can retry', (tester) async {
      final deleter = _FakeDeleter(
        failure: const AccountDeletionException('Try again.'),
      );
      await pumpScreen(tester, deleter: deleter);

      await typeConfirmation(tester, 'DELETE');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete my data'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete my data'));
      await tester.pumpAndSettle();

      expect(deleter.calls, 2);
    });
  });
}
