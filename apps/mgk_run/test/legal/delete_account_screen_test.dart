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
      expect(
        find.textContaining('shared MGKCodes fitness account'),
        findsOneWidget,
      );
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
      expect(find.text('Your Runio data is deleted'), findsOneWidget);
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
    testWidgets('signs out only once the runner has read the outcome', (
      tester,
    ) async {
      final auth = FakeAuthRepository(signedIn: true, email: 'a@runio.app');
      await pumpScreen(tester, deleter: _FakeDeleter(), auth: auth);

      await typeConfirmation(tester, 'DELETE');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete my data'));
      await tester.pumpAndSettle();

      // Still signed in while the confirmation is on screen.
      expect(auth.isSignedIn, isTrue);

      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();

      expect(auth.isSignedIn, isFalse);
    });

    testWidgets('explains when the shared login was kept for Liftio', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        deleter: _FakeDeleter(
          result: const AccountDeletionResult(
            accountDeleted: false,
            retainedReason: 'sibling_app_data',
            deletedRows: <String, int>{'runio.runs': 10},
          ),
        ),
      );

      await typeConfirmation(tester, 'DELETE');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete my data'));
      await tester.pumpAndSettle();

      expect(find.text('Your Runio data is deleted'), findsOneWidget);
      expect(find.textContaining('Your login is still active'), findsOneWidget);
      expect(find.textContaining('hello@mgkcodes.com'), findsOneWidget);
    });

    testWidgets('says the login went too when the account was Runio-only', (
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
      expect(find.text('Your Runio data is deleted'), findsNothing);
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
