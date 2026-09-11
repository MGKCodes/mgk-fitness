import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/features/auth/data/auth_repository.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_store.dart';
import 'package:mgk_run/src/features/settings/data/backup_eraser.dart';
import 'package:mgk_run/src/features/settings/domain/backup_consent.dart';
import 'package:mgk_run/src/features/settings/domain/unit_settings.dart';
import 'package:mgk_run/src/features/settings/presentation/settings_screen.dart';
import 'package:mgk_run/src/features/settings/presentation/settings_row.dart';
import 'package:mgk_run/src/features/settings/presentation/avatar.dart';
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
  /// Opens the account screen, where the name is edited. It was a row on the
  /// settings index until the header became a profile, which put the name on
  /// that screen twice -- as the card's headline and as the row's value.
  ///
  /// Signed out there is no account screen, so the card raises sign-up
  /// instead; those tests pass `signedOut: true` and edit from where they can.
  Future<void> openAccount(WidgetTester tester) async {
    await tester.tap(find.byType(Avatar).first);
    await tester.pumpAndSettle();
  }

  /// Opens Settings' backup screen, where the switch now lives.
  ///
  /// It was a `SwitchListTile` on the index until 2026-09-11. The switch moved
  /// with the paragraph that made its consent informed — see `BackupScreen` —
  /// so every test that flips it now walks the tap a runner walks.
  Future<Finder> openBackup(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(SettingsRow, 'Back up my data'));
    await tester.pumpAndSettle();
    return find.byType(Switch);
  }

  Future<IntroStore> pumpSignedOut(
    WidgetTester tester, {
    String? name,
    BackupConsentStore? consent,
    Future<bool> Function()? ensureAccount,
    AuthRepository? auth,
    ValueChanged<String?>? onNameChanged,
    BackupErasure? eraser,
    Future<void> Function()? onBackupGranted,
  }) async {
    final intro = InMemoryIntroStore(done: true, name: name);
    // Tall enough for the whole page. Settings is a `ListView`, so it builds
    // only what is near the viewport — and half of what this file asserts is
    // that a row is *absent*, which a fold turns into a claim about scrolling
    // rather than about the tree.
    await tester.binding.setSurfaceSize(const Size(420, 2600));
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
          eraser: eraser,
          onBackupGranted: onBackupGranted,
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

      // On the card now rather than in a row: the header states identity, and
      // it does so with no account, which is the point of this group.
      expect(find.text('Sam'), findsOneWidget);
      expect(find.text('Nothing in particular'), findsNothing);

      await openAccount(tester);
      expect(find.text('Coach calls you'), findsOneWidget);
      // Twice over: the heading under the avatar, and the row's value.
      expect(find.text('Sam'), findsNWidgets(2));
    });

    testWidgets('correcting it writes where the coach will read it', (
      tester,
    ) async {
      final intro = await pumpSignedOut(tester, name: 'Smaa');

      await openAccount(tester);
      await tester.tap(find.text('Coach calls you'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Sam');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // Asserted on the store rather than on the row. A row that updates its
      // own state and persists nothing looks identical on screen, and that is
      // precisely the failure being replaced.
      expect(await intro.readName(), 'Sam');
      // The heading under the avatar, and the row's value.
      expect(find.text('Sam'), findsNWidgets(2));
    });

    testWidgets('clearing it stays reachable with no account either', (
      tester,
    ) async {
      final intro = await pumpSignedOut(tester, name: 'Sam');

      await openAccount(tester);
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

      await openAccount(tester);
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

      await openAccount(tester);
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
      // And the two acts stay absent one level in, where the invitation takes
      // their place rather than sitting beside them.
      await openAccount(tester);
      expect(find.text('Sign out'), findsNothing);
      expect(find.text('Delete account'), findsNothing);
      expect(find.text('Create an account'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        find.textContaining('on this phone only'),
        findsOneWidget,
      );
    });

    testWidgets('and all three change back once there is one', (tester) async {
      await pumpSignedOut(
        tester,
        auth: FakeAuthRepository(signedIn: true, email: 'sam@example.com'),
      );

      expect(find.text('Create an account'), findsNothing);
      expect(find.text('sam@example.com'), findsOneWidget);

      // The two ways out came back with the account — one tap in, on the
      // account screen, rather than on the index beside the units.
      await tester.tap(find.text('sam@example.com'));
      await tester.pumpAndSettle();
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text('Delete account'), findsOneWidget);
    });

    testWidgets('the rows that work without one still do, in one band', (
      tester,
    ) async {
      // The reorganisation moved every band on this page, and three of these
      // rows answer for a runner with no session at all: the name comes from
      // the install store, the units from a local file, the documents from the
      // bundle. A regrouping that quietly made any of them account-only would
      // be the exact failure this file was opened for, one layout later.
      await pumpSignedOut(tester, name: 'Sam');

      expect(find.text('Distance'), findsOneWidget);
      expect(find.text('Kilometres'), findsOneWidget);
      expect(find.text('Support'), findsOneWidget);
      expect(find.text('Privacy & legal'), findsOneWidget);

      // And still in the stated order, with nothing left pointing at a group
      // that has no rows in it.
      double topOf(String label) => tester.getTopLeft(find.text(label)).dy;
      expect(topOf('PREFERENCES'), lessThan(topOf('YOUR DATA')));
      expect(topOf('YOUR DATA'), lessThan(topOf('ABOUT')));
      expect(find.text('Sign out'), findsNothing);
      expect(find.text('Delete account'), findsNothing);
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

      // The card leads to the profile; the invitation lives there, where it
      // can be explained rather than asserted in a row.
      await openAccount(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Create an account'));
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
    testWidgets('but the question is asked of them anyway, above the fold', (
      tester,
    ) async {
      // ADR-0012's cost function: consent that has to be discovered is not
      // really offered, and the runner with no account is exactly the one the
      // amended ADR expects to reach their second week without ever being
      // asked in a dialog. So the *row* has to be in the first screenful of an
      // ordinary phone here too — not only for somebody signed in. The switch
      // itself moved to `BackupScreen` on 2026-09-11, one tap beyond it.
      const fold = 844.0;
      await tester.binding.setSurfaceSize(const Size(390, fold));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: SettingsScreen(
            unit: UnitSystem.metric,
            settings: InMemoryUnitSettings(),
            auth: FakeAuthRepository(),
            introStore: InMemoryIntroStore(done: true),
            consentStore: InMemoryBackupConsent(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .getBottomLeft(find.widgetWithText(SettingsRow, 'Back up my data'))
            .dy,
        lessThan(fold),
      );
    });

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

      await tester.tap(await openBackup(tester));
      await tester.pumpAndSettle();

      expect(raised, 1);
      // Refused, so nothing was written and the switch is where it was. The
      // gate is asked *before* the optimistic flip for this reason: a switch
      // that slides on and then back reads as the app changing its mind.
      expect(await store.read(), BackupConsent.unknown);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
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

      await tester.tap(await openBackup(tester));
      await tester.pumpAndSettle();

      expect(await store.read(), BackupConsent.granted);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
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

      await tester.tap(await openBackup(tester));
      await tester.pumpAndSettle();

      expect(raised, 0);
      expect(await store.read(), BackupConsent.declined);
    });
  });

  /// **Withdrawal has to actually erase, and until 2026-09-04 it did not.**
  ///
  /// `BackupEraser` was written, documented, and never constructed anywhere in
  /// `lib/`: `HomeShell` built `SettingsScreen` without an `eraser`, so
  /// `_setConsent` fell to its `?? true` default, reported success, and deleted
  /// nothing. Meanwhile the published privacy policy said in as many words that
  /// turning the switch off "deletes what is already there" -- about
  /// special-category health data, under a UK GDPR right.
  ///
  /// `legal_copy_test.dart` pins that sentence in four places. None of them is
  /// a behaviour, which is exactly why the gap survived: the promise was tested
  /// and the act was not. These tests assert the act.
  group('withdrawing consent erases what is stored', () {
    testWidgets('the eraser is asked, and only on withdrawal', (tester) async {
      final eraser = _RecordingEraser();
      final store = InMemoryBackupConsent(BackupConsent.granted);
      await pumpSignedOut(tester, consent: store, eraser: eraser);

      await tester.tap(await openBackup(tester));
      await tester.pumpAndSettle();

      expect(await store.read(), BackupConsent.declined);
      expect(eraser.calls, 1);

      // And turning it back on does not erase: granting is not a withdrawal,
      // and an erase here would delete the data the runner just asked us to
      // keep.
      await tester.tap(await openBackup(tester));
      await tester.pumpAndSettle();

      expect(await store.read(), BackupConsent.granted);
      expect(eraser.calls, 1);
    });

    testWidgets('a failed erase is said out loud, not swallowed', (
      tester,
    ) async {
      // The switch is already off locally by this point, so uploads have
      // stopped either way. What must not happen is silence: the runner has
      // withdrawn consent and their data is still on a server, and they can
      // only try again if they are told.
      final eraser = _RecordingEraser(succeeds: false);
      await pumpSignedOut(
        tester,
        consent: InMemoryBackupConsent(BackupConsent.granted),
        eraser: eraser,
      );

      await tester.tap(await openBackup(tester));
      await tester.pumpAndSettle();

      expect(eraser.calls, 1);
      expect(
        find.textContaining('could not be removed'),
        findsOneWidget,
        reason: 'a silent failure leaves data on a server nobody knows about',
      );
    });
  });

  /// **Granting consent has to upload what is already here.**
  ///
  /// `backfill()` had two callers, both at launch inside `HomeShell`. A runner
  /// who created an account in Settings and turned backup on therefore wrote a
  /// `granted` and uploaded nothing -- not then, and not until the next cold
  /// start. They had said yes and watched nothing happen, which from the
  /// outside is indistinguishable from a backup that does not work. Reported as
  /// E5 by the build 12 field test: "existing runs did not upload after backup
  /// was enabled".
  group('granting consent uploads what the phone already holds', () {
    testWidgets('the backfill runs, and only on the grant', (tester) async {
      var backfills = 0;
      final store = InMemoryBackupConsent();
      await pumpSignedOut(
        tester,
        auth: FakeAuthRepository(signedIn: true, email: 'sam@example.com'),
        consent: store,
        onBackupGranted: () async => backfills++,
      );

      await tester.tap(await openBackup(tester));
      await tester.pumpAndSettle();

      expect(await store.read(), BackupConsent.granted);
      expect(backfills, 1);

      // And withdrawing does not upload. Obvious, and worth pinning: the two
      // branches sit one line apart and both end in a network call.
      await tester.tap(await openBackup(tester));
      await tester.pumpAndSettle();

      expect(await store.read(), BackupConsent.declined);
      expect(backfills, 1);
    });
  });
}

/// Counts the asking. The real one needs a Supabase project, which is how the
/// unwired switch went unnoticed for as long as it did.
class _RecordingEraser implements BackupErasure {
  _RecordingEraser({this.succeeds = true});

  final bool succeeds;
  int calls = 0;

  @override
  Future<bool> eraseAll() async {
    calls++;
    return succeeds;
  }
}
