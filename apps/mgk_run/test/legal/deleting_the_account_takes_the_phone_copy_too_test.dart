import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/features/legal/domain/account_deleter.dart';
import 'package:mgk_run/src/features/legal/presentation/delete_account_screen.dart';
import 'package:mgk_run/src/features/settings/domain/backup_consent.dart';
import 'package:mgk_run/src/features/settings/domain/local_data.dart';
import 'package:mgk_run/src/features/settings/presentation/phone_scope.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_store.dart';
import 'package:mgk_run/src/features/settings/domain/backup_health.dart';

/// **Deleting the account left the phone ready to put it all back.**
///
/// A successful deletion signed out and said "Your data is deleted". The
/// backup answer on the phone still said yes, so signing back in -- the login
/// is kept whenever Lift holds data -- or creating a new account on the same
/// phone backfilled every deleted run straight back to the server. The screen
/// said nothing about the copy still on the phone, and the login it said was
/// gone was, for every runner who also used Lift, still there.
void main() {
  late FakeAuthRepository auth;
  late InMemoryBackupConsent consent;
  late InMemoryLocalDataOwner owner;
  late _Training training;
  late LocalDataGuard guard;

  setUp(() {
    auth = FakeAuthRepository(signedIn: true, email: 'alex@example.com');
    consent = InMemoryBackupConsent(BackupConsent.granted);
    owner = InMemoryLocalDataOwner('alex');
    training = _Training();
    guard = LocalDataGuard(owner: owner, data: training);
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    AccountDeletionResult result = const AccountDeletionResult(
      accountDeleted: false,
      retainedReason: 'other_app_data',
    ),
    AccountDeletionException? failure,
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: DeleteAccountScreen(
          auth: auth,
          deleter: _Deleter(result: result, failure: failure),
          consentStore: consent,
          localData: guard,
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

  testWidgets('the backup answer goes back to unasked', (tester) async {
    // The yes stayed on the phone, and the next sign-in backfilled every
    // deleted run to the server.
    await pumpScreen(tester);
    await deleteIt(tester);

    expect(await consent.read(), BackupConsent.unknown);
  });

  testWidgets("the phone's copy goes too unless the runner keeps it", (
    tester,
  ) async {
    await pumpScreen(tester);

    final toggle = tester.widget<Switch>(find.byType(Switch));
    expect(toggle.value, isTrue, reason: 'on by default when deleting');
    expect(find.text("Also erase this phone's copy"), findsOneWidget);

    await deleteIt(tester);

    expect(training.erased, 1);
    expect(await owner.read(), isNull);
    expect(find.text('Your data is deleted'), findsOneWidget);
    expect(find.text("This phone's copy has been erased too."), findsOneWidget);
  });

  testWidgets('kept, the screen says so, and the phone is nobody\'s', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your runs stay on this phone'), findsOneWidget);

    await deleteIt(tester);

    expect(training.erased, 0);
    expect(
      await owner.read(),
      isNull,
      reason:
          'the account it belonged to is gone; the runner making a new one '
          'must not be told their own runs are somebody else\'s',
    );
    expect(find.text('Your data is deleted'), findsNothing);
    expect(find.text('Deleted from our servers'), findsOneWidget);
    expect(
      find.textContaining('Your runs are still on this phone'),
      findsOneWidget,
    );
    expect(await consent.read(), BackupConsent.unknown);
  });

  testWidgets('an erase that fails is not reported as done', (tester) async {
    training.failErase = true;
    await pumpScreen(tester);
    await deleteIt(tester);

    expect(find.text('Deleted from our servers'), findsOneWidget);
    expect(
      find.textContaining("This phone's copy could not be erased"),
      findsOneWidget,
    );
  });

  testWidgets("this app's keys leave a login that stays, while it is there", (
    tester,
  ) async {
    await pumpScreen(tester);
    await deleteIt(tester);

    expect(
      auth.runMetadataClears,
      <bool>[true],
      reason: 'once, and before signing out -- it needs the session',
    );
    expect(auth.isSignedIn, isFalse);
  });

  testWidgets('and are left alone when the login went with everything', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      result: const AccountDeletionResult(accountDeleted: true),
    );
    await deleteIt(tester);

    expect(auth.runMetadataClears, isEmpty);
    expect(auth.isSignedIn, isFalse);
  });

  testWidgets('a deletion that failed touches nothing on the phone', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      failure: const AccountDeletionException('Try again.'),
    );
    await deleteIt(tester);

    expect(auth.isSignedIn, isTrue);
    expect(await consent.read(), BackupConsent.granted);
    expect(training.erased, 0);
    expect(await owner.read(), 'alex');
    expect(auth.runMetadataClears, isEmpty);
  });

  testWidgets('reached from Privacy & legal, it finds the phone by itself', (
    tester,
  ) async {
    // The legal screen builds this with an auth and a deleter and nothing
    // else. The phone's stores are above the navigator for exactly this.
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => PhoneScope(
          phone: PhoneServices(
            consent: consent,
            backupHealth: InMemoryBackupHealth(),
            intro: InMemoryIntroStore(done: true),
            localData: guard,
          ),
          child: child!,
        ),
        home: DeleteAccountScreen(
          auth: auth,
          deleter: _Deleter(
            result: const AccountDeletionResult(accountDeleted: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await deleteIt(tester);

    expect(await consent.read(), BackupConsent.unknown);
    expect(training.erased, 1);
  });
}

class _Deleter implements AccountDeleter {
  _Deleter({required this.result, this.failure});

  final AccountDeletionResult result;
  final AccountDeletionException? failure;

  @override
  Future<AccountDeletionResult> deleteAccount() async {
    final failure = this.failure;
    if (failure != null) throw failure;
    return result;
  }
}

class _Training implements LocalRunnerData {
  bool hasTraining = true;
  bool failErase = false;
  int erased = 0;

  @override
  Future<bool> isEmpty() async => !hasTraining;

  @override
  Future<void> eraseAll() async {
    if (failErase) throw StateError('disk');
    erased++;
    hasTraining = false;
  }
}
