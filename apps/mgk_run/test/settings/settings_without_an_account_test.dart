import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/features/auth/data/auth_repository.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_store.dart';
import 'package:mgk_run/src/features/settings/domain/backup_consent.dart';
import 'package:mgk_run/src/features/settings/domain/unit_settings.dart';
import 'package:mgk_run/src/features/settings/presentation/settings_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

/// **Settings for a runner with no account, which is now the ordinary one.**
///
/// This screen was written while every runner was signed in, and when the
/// sign-in wall came down it went on assuming one. Three things were wrong at
/// once, and all three were invisible to a suite whose every fixture was signed
/// in:
///
///   * the name row read and wrote auth metadata and nothing else, so it showed
///     nothing and saved nothing for exactly the people who had just been asked
///     for a name;
///   * the whole block was hidden unless there was an email *or* a run on
///     record, so an introduced runner who had not been out yet opened Settings
///     and found nothing about themselves at all;
///   * Sign out and Delete account were offered unconditionally — two rows that
///     could only fail, in the place somebody looks to find out where they
///     stand.
void main() {
  Future<IntroStore> pumpSignedOut(
    WidgetTester tester, {
    String? name,
    BackupConsentStore? consent,
    Future<bool> Function()? ensureAccount,
    AuthRepository? auth,
    ValueChanged<String?>? onNameChanged,
  }) async {
    final intro = InMemoryIntroStore(done: true, name: name);
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: SettingsScreen(
          unit: UnitSystem.metric,
          settings: InMemoryUnitSettings(),
          auth: auth ?? FakeAuthRepository(),
          introStore: intro,
          consentStore: consent ?? InMemoryBackupConsent(),
          ensureAccount: ensureAccount,
          onNameChanged: onNameChanged,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return intro;
  }

  group('the name the intro gathered is the name this row edits', () {
    testWidgets('it is shown with nothing signed in', (tester) async {
      // `currentName` reads auth user metadata and answers null for everybody
      // signed out, so before the install store was consulted this row said
      // "Nothing in particular" to a runner who had just introduced themselves.
      await pumpSignedOut(tester, name: 'Sam');

      expect(find.text('Coach calls you'), findsOneWidget);
      expect(find.text('Sam'), findsOneWidget);
      expect(find.text('Nothing in particular'), findsNothing);
    });

    testWidgets('correcting it writes where the coach will read it', (
      tester,
    ) async {
      final intro = await pumpSignedOut(tester, name: 'Smaa');

      await tester.tap(find.text('Coach calls you'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Sam');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // Asserted on the store rather than on the row. A row that updates its
      // own state and persists nothing looks identical on screen, and that is
      // precisely the failure being replaced.
      expect(await intro.readName(), 'Sam');
      expect(find.text('Sam'), findsOneWidget);
    });

    testWidgets('clearing it stays reachable with no account either', (
      tester,
    ) async {
      final intro = await pumpSignedOut(tester, name: 'Sam');

      await tester.tap(find.text('Coach calls you'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(await intro.readName(), isNull);
      expect(find.text('Nothing in particular'), findsOneWidget);
    });

    testWidgets('and the shell is told, because no auth event will tell it', (
      tester,
    ) async {
      // Signed in, a rename fires `onAuthStateChange` and the gate re-reads it.
      // Signed out there is no session to emit anything, so without this the
      // shell goes on handing the coach the name it read at launch.
      String? reported;
      var called = false;
      await pumpSignedOut(
        tester,
        name: 'Smaa',
        onNameChanged: (name) {
          reported = name;
          called = true;
        },
      );

      await tester.tap(find.text('Coach calls you'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Sam');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(called, isTrue);
      expect(reported, 'Sam');
    });

    testWidgets('a signed-in runner still writes to the account', (
      tester,
    ) async {
      // Both homes, every time: the install store is what answers with no
      // account, and the account is what travels to a second phone. Writing
      // only one of them is a name that goes missing on exactly one device.
      final auth = FakeAuthRepository(
        signedIn: true,
        email: 'sam@example.com',
        name: 'Smaa',
      );
      final intro = await pumpSignedOut(tester, auth: auth);

      await tester.tap(find.text('Coach calls you'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Sam');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(auth.currentName, 'Sam');
      expect(await intro.readName(), 'Sam');
    });
  });

  group('the account section says what is actually true', () {
    testWidgets('nothing offers to sign out of, or delete, an account that '
        'does not exist', (tester) async {
      await pumpSignedOut(tester);

      expect(find.text('Sign out'), findsNothing);
      expect(find.text('Delete account'), findsNothing);
      // What is offered instead, and what an account is actually for — the two
      // gates the app raises one at, named rather than sold.
      expect(find.text('Create an account'), findsOneWidget);
      expect(
        find.textContaining('on this phone, and only on this phone'),
        findsOneWidget,
      );
    });

    testWidgets('and all three change back once there is one', (tester) async {
      await pumpSignedOut(
        tester,
        auth: FakeAuthRepository(signedIn: true, email: 'sam@example.com'),
      );

      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text('Delete account'), findsOneWidget);
      expect(find.text('Create an account'), findsNothing);
      expect(find.text('sam@example.com'), findsOneWidget);
    });

    testWidgets('creating one from the row raises the same gate', (
      tester,
    ) async {
      var raised = 0;
      await pumpSignedOut(
        tester,
        ensureAccount: () async {
          raised++;
          return false;
        },
      );

      await tester.tap(find.text('Create an account'));
      await tester.pumpAndSettle();

      expect(raised, 1);
    });
  });

  /// **Backup is the second gate an account stands at.** The mirror writes rows
  /// attributed to a user, and with nobody signed in there is nowhere to put
  /// them — so the switch would have read "On" while every push failed on a
  /// row-level policy. That is a promise the app cannot keep, made by the one
  /// section whose entire job is not making those.
  group('turning backup on needs an account', () {
    testWidgets('the switch raises sign-up rather than storing a yes', (
      tester,
    ) async {
      final store = InMemoryBackupConsent();
      var raised = 0;
      await pumpSignedOut(
        tester,
        consent: store,
        ensureAccount: () async {
          raised++;
          return false;
        },
      );

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(raised, 1);
      // Refused, so nothing was written and the switch is where it was. The
      // gate is asked *before* the optimistic flip for this reason: a switch
      // that slides on and then back reads as the app changing its mind.
      expect(await store.read(), BackupConsent.unknown);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
    });

    testWidgets('and grants it once the account arrives', (tester) async {
      final store = InMemoryBackupConsent();
      final auth = FakeAuthRepository();
      await pumpSignedOut(
        tester,
        auth: auth,
        consent: store,
        ensureAccount: () async {
          await auth.signUp(email: 'sam@example.com', password: 'hunter2222');
          return true;
        },
      );

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(await store.read(), BackupConsent.granted);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
    });

    testWidgets('withdrawing is never gated, whatever the session', (
      tester,
    ) async {
      // Consent has to be at least as easy to take back as it was to give. A
      // sign-up raised on the way *out* would be the app demanding an account
      // in order to let somebody leave.
      final store = InMemoryBackupConsent(BackupConsent.granted);
      var raised = 0;
      await pumpSignedOut(
        tester,
        consent: store,
        ensureAccount: () async {
          raised++;
          return false;
        },
      );

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(raised, 0);
      expect(await store.read(), BackupConsent.declined);
    });
  });
}
