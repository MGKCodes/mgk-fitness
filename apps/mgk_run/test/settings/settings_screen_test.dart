import 'package:mgk_run/src/core/brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import 'package:mgk_run/src/features/settings/domain/backup_consent.dart';
import 'package:mgk_run/src/features/settings/domain/backup_health.dart';
import 'package:mgk_run/src/features/settings/domain/unit_settings.dart';
import 'package:mgk_run/src/features/settings/presentation/settings_screen.dart';
import 'package:mgk_run/src/features/settings/presentation/avatar.dart';

/// Settings is where everything that is not itself training lives. The account
/// facts moved here off Profile, and the controls a runner goes looking for —
/// units, what the app promises, how to leave, what version this is — have to
/// be findable in one place rather than scattered behind other screens.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    DateTime? memberSince,
    String? email = 'dev@mgkfitness.mgkcodes.com',
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: SettingsScreen(
          unit: UnitSystem.metric,
          settings: InMemoryUnitSettings(),
          auth: FakeAuthRepository(signedIn: email != null, email: email),
          memberSince: memberSince,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('carries the account facts that used to head Profile', (
    tester,
  ) async {
    await pump(tester, memberSince: DateTime(2026, 7, 4));

    // The header states identity; the rest is a tap in. "Running since" and
    // the editable name moved to Account when the card became a profile --
    // the name was otherwise on this screen twice, as the card's headline and
    // as a row's value.
    expect(find.text('dev@mgkfitness.mgkcodes.com'), findsOneWidget);
    expect(find.textContaining('since July 2026'), findsNothing);

    await tester.tap(find.text('dev@mgkfitness.mgkcodes.com'));
    await tester.pumpAndSettle();
    expect(find.textContaining('July 2026'), findsOneWidget);
    expect(find.text('Coach calls you'), findsOneWidget);
  });

  testWidgets('a runner with no runs gets no invented joining date', (
    tester,
  ) async {
    await pump(tester);

    expect(find.textContaining('since'), findsNothing);
  });

  /// The intro accepts **any** name, on the grounds that a name is not a format
  /// and every rule that rejects one rejects somebody real. That is only a fair
  /// trade if a typo can be put right, and for a long time it could not be: the
  /// name was written once at sign-up and read back forever. The comment
  /// claiming it was fixable "on the confirmation screen at the end of intake"
  /// pointed at a screen that edits `IntakeSlots`, a type with no name in it.
  /// Opens the account screen, where the name lives. It was a row on the
  /// index until the header became a profile and put the name on the screen
  /// twice.
  Future<void> openAccount(WidgetTester tester) async {
    await tester.tap(find.byType(Avatar).first);
    await tester.pumpAndSettle();
  }

  group('what the coach calls you can be changed', () {
    Future<FakeAuthRepository> pumpWithName(
      WidgetTester tester,
      String? name,
    ) async {
      final auth = FakeAuthRepository(
        signedIn: true,
        email: 'dev@mgkfitness.mgkcodes.com',
        name: name,
      );
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: SettingsScreen(
            unit: UnitSystem.metric,
            settings: InMemoryUnitSettings(),
            auth: auth,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return auth;
    }

    testWidgets('the current one is shown', (tester) async {
      await pumpWithName(tester, 'Sam');

      // On the index the name is the card's headline, and only there -- it was
      // also a row's value until the header became a profile, which put it on
      // one screen twice.
      expect(find.text('Sam'), findsOneWidget);
      expect(find.text('Coach calls you'), findsNothing);

      await openAccount(tester);
      expect(find.text('Coach calls you'), findsOneWidget);
      // The heading under the avatar, and the row's value.
      expect(find.text('Sam'), findsNWidgets(2));
    });

    testWidgets('and a typo can be corrected', (tester) async {
      final auth = await pumpWithName(tester, 'Smaa');

      await openAccount(tester);
      await tester.tap(find.text('Coach calls you'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Sam');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(auth.currentName, 'Sam');
      expect(find.text('Sam'), findsNWidgets(2));
    });

    testWidgets('leaving it empty clears it rather than storing blank', (
      tester,
    ) async {
      // "I would rather you did not use a name" has to be reachable. Every
      // reader already treats null as "say nothing" — `currentName` returns
      // null for blank and `CoachBrief.write` omits the mention entirely — so
      // storing an empty string instead would be a third state nothing knows
      // how to read.
      final auth = await pumpWithName(tester, 'Sam');

      await openAccount(tester);
      await tester.tap(find.text('Coach calls you'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(auth.currentName, isNull);
      expect(find.text('Nothing in particular'), findsOneWidget);
    });

    testWidgets('and cancelling changes nothing', (tester) async {
      // A dismissed dialog and an emptied field are different answers, and the
      // difference is destructive in one direction.
      final auth = await pumpWithName(tester, 'Sam');

      await openAccount(tester);
      await tester.tap(find.text('Coach calls you'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Something else');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(auth.currentName, 'Sam');
    });
  });

  testWidgets('holds every app-level control in one place', (tester) async {
    await pump(tester, memberSince: DateTime(2026, 7, 4));

    // Every control, and — the part that changed on 2026-09-11 — every one of
    // them without scrolling. The screen this replaced ran to about two and a
    // half viewports, so each of these was reached with `scrollUntilVisible`
    // and the test could not tell "present" from "present eventually".
    for (final control in <String>[
      'Distance',
      'Back up my data',
      'Permissions',
      'Support',
      'Privacy & legal',
    ]) {
      expect(find.text(control), findsOneWidget, reason: control);
    }

    // Support is the row that was missing entirely: the page has been live and
    // CI-pinned the whole time, both store listings name it, and nothing in
    // the app pointed at it.

    // Sign out and Delete account are one tap away, on the account screen,
    // rather than in permanent view of somebody changing their units.
    expect(find.text('Sign out'), findsNothing);
    expect(find.text('Delete account'), findsNothing);
    await openAccount(tester);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Delete account'), findsOneWidget);
    expect(find.text('Coach calls you'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Each setting states what it is set to, which is what makes the index
    // readable without opening anything.
    expect(find.text('Kilometres'), findsOneWidget);

    // The version is the one thing still below the fold, and only in a test:
    // widget tests run in debug, where the developer tools sit between the
    // buttons and the footer. A release bundle has neither, and the footer
    // lands on the first screen with the rest.
    final version = find.textContaining('$kProductName $kAppVersion');
    await tester.scrollUntilVisible(
      version,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(version, findsOneWidget);
  });

  testWidgets('About says the app is open source, and offers a problem report', (
    tester,
  ) async {
    // Two ways in, for two kinds of people: the code for whoever will read it,
    // and an email for everybody who will not. What each opens is held by
    // mgk_ui's open_source_test; this holds that both are here, in order.
    await pump(tester);

    final about = find.text('Report a problem');
    await tester.scrollUntilVisible(
      about,
      300,
      scrollable: find.byType(Scrollable).first,
    );

    double top(String label) => tester.getTopLeft(find.text(label)).dy;
    expect(top('Support'), lessThan(top('Report a problem')));
    expect(top('Report a problem'), lessThan(top('Source code')));
    expect(top('Source code'), lessThan(top('Privacy & legal')));
    expect(find.text('AGPL-3.0'), findsOneWidget);
  });

  /// **The screen is an index, and its order is the argument.**
  ///
  /// It was four bands of rows with a sentence under each, plus three
  /// explanatory paragraphs — two and a half screens to reach a version
  /// number. The rewrite on 2026-09-11 pushed the prose onto the screens where
  /// the settings are actually changed and left the index carrying values.
  ///
  /// The order now follows how often something is changed rather than how much
  /// it decides: the two preferences, then the two data decisions, then the
  /// ways out. Distance in particular was last, on the reasoning that it is set
  /// once and read forever — which argues for it being cheap to pass, not for
  /// it being hard to find.
  ///
  /// A layout with a stated principle and no test drifts back the first time a
  /// row is added, so the principle is asserted as positions rather than
  /// described in a comment nobody runs.
  group('the page reads as an index', () {
    /// Tall enough to lay the whole page out at once. A `ListView` builds only
    /// what is near the viewport, so relative positions cannot be compared
    /// across a fold that is still there.
    Future<void> pumpWhole(WidgetTester tester, {bool signedIn = true}) async {
      await tester.binding.setSurfaceSize(const Size(420, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: SettingsScreen(
            unit: UnitSystem.metric,
            settings: InMemoryUnitSettings(),
            auth: FakeAuthRepository(
              signedIn: signedIn,
              email: signedIn ? 'dev@mgkfitness.mgkcodes.com' : null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the rows run in the one stated order', (tester) async {
      await pumpWhole(tester);

      double topOf(String label) => tester.getTopLeft(find.text(label)).dy;

      // The address, then what you can change, then what leaves the phone,
      // then the ways out. `topOf` throws on anything missing, so this list
      // existing at all asserts that every row drew.
      final order = <String>[
        'dev@mgkfitness.mgkcodes.com',
        'PREFERENCES',
        'Distance',
        'YOUR DATA',
        'Back up my data',
        'Permissions',
        'ABOUT',
        'Support',
        'Privacy & legal',
      ];
      final tops = <double>[for (final label in order) topOf(label)];

      for (var i = 1; i < order.length; i++) {
        expect(
          tops[i],
          greaterThan(tops[i - 1]),
          reason: '${order[i]} must sit below ${order[i - 1]}',
        );
      }
    });

    testWidgets('the act that cannot be undone is last, and on its own '
        'screen', (tester) async {
      await pumpWhole(tester);

      // Not on the index at all: it was a button here and a row inside
      // Privacy & legal, which is two Delete accounts in one app.
      expect(find.text('Delete account'), findsNothing);

      await openAccount(tester);

      final delete = tester.getTopLeft(find.text('Delete account')).dy;
      expect(
        tester.getTopLeft(find.text('Sign out')).dy,
        lessThan(delete),
        reason: 'the reversible way out comes before the irreversible one',
      );
    });

    testWidgets('and it is the only thing wearing the danger colour', (
      tester,
    ) async {
      await pumpWhole(tester);
      await openAccount(tester);

      // The only sanctioned use of colour here (ADR-0009). A deletion moved
      // behind a tap and then greyed to match its neighbour would trade one
      // signal for another rather than add one.
      expect(
        find.widgetWithText(DestructiveButton, 'Delete account'),
        findsOneWidget,
      );
      expect(find.widgetWithText(OutlinedButton, 'Sign out'), findsOneWidget);
    });

    testWidgets('the card still opens without an account, because the '
        'profile exists first', (tester) async {
      await pumpWhole(tester, signedIn: false);

      expect(find.text('Create an account'), findsOneWidget);
      // Not on the index: two controls that could only fail.
      expect(find.text('Delete account'), findsNothing);
      expect(find.text('Sign out'), findsNothing);
      // The documents belong to everybody.
      expect(find.text('Privacy & legal'), findsOneWidget);

      // **This assertion was once the opposite.** It read "the card does not
      // open an account that does not exist", on the reasoning that the screen
      // would be a page of blanks. That was wrong: the name and the photo are
      // profile, they exist before an account does, and gating the screen on a
      // session took away the only place to correct a name the intro gathered.
      await tester.tap(find.byType(Avatar).first);
      await tester.pumpAndSettle();
      expect(find.text('Coach calls you'), findsOneWidget);
      expect(find.text('Sign out'), findsNothing);
    });
  });

  /// **ADR-0012's cost function turns on consent not being something you go
  /// looking for.** The switch is also where consent is *withdrawn*, and taking
  /// it back must be at least as easy as giving it was.
  ///
  /// The switch moved to [BackupScreen] on 2026-09-11, so what has to be in the
  /// first screenful is now the row that opens it — and the withdrawal is one
  /// tap further away than it was. That is the cost of the move and it is worth
  /// pinning: one tap, from a row visible without scrolling, is still inside
  /// what ADR-0012 asks for. Two would not be.
  testWidgets('backup consent is one tap from the first screenful', (
    tester,
  ) async {
    // A 6.1" phone in logical pixels. Nothing here depends on the exact
    // handset: the claim is that the switch arrives before the first scroll on
    // an ordinary one, not that it lands at a particular pixel.
    const fold = 844.0;
    await tester.binding.setSurfaceSize(const Size(390, fold));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: SettingsScreen(
          unit: UnitSystem.metric,
          settings: InMemoryUnitSettings(),
          auth: FakeAuthRepository(
            signedIn: true,
            email: 'dev@mgkfitness.mgkcodes.com',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Whole row, not just its top edge: a row half off the bottom of the
    // screen is a row somebody has to go looking for.
    final row = find.widgetWithText(SettingsRow, 'Back up my data');
    expect(row, findsOneWidget);
    expect(tester.getBottomLeft(row).dy, lessThan(fold));

    // And the tap reaches the switch itself, not another index.
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsOneWidget);
  });

  /// **A switch that says "On" and means "on, and silently failing since the
  /// 3rd" is a promise the app is not keeping.** Every push is best-effort by
  /// contract, which for a long time was implemented as `catch (_) {}` and
  /// nothing else — so a backup that had been broken for a month was
  /// indistinguishable from one that was working. It is answered here, beside
  /// the switch that offered the backup, rather than shouted about mid-run:
  /// nothing was lost, and there is nothing for the runner to do but be online
  /// at some point (ADR-0023).
  group('the backup says what it last did', () {
    /// Opens Settings and then the backup screen, because that is where the
    /// readout lives now — beside the switch that offered the backup rather
    /// than on an index that only reports whether it is on.
    Future<void> pumpWithBackup(
      WidgetTester tester, {
      required BackupConsent consent,
      required BackupHealth health,
    }) async {
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: SettingsScreen(
            unit: UnitSystem.metric,
            settings: InMemoryUnitSettings(),
            auth: FakeAuthRepository(
              signedIn: true,
              email: 'dev@mgkfitness.mgkcodes.com',
            ),
            consentStore: InMemoryBackupConsent(consent),
            backupHealthStore: InMemoryBackupHealth(health),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SettingsRow, 'Back up my data'));
      await tester.pumpAndSettle();
    }

    testWidgets('a failed push is discoverable', (tester) async {
      await pumpWithBackup(
        tester,
        consent: BackupConsent.granted,
        health: const BackupHealth().failedAt(DateTime(2026, 8, 23)),
      );

      expect(
        find.textContaining('The last backup did not go through'),
        findsOneWidget,
      );
      // Calm, and explicit that nothing was lost: the log is read from the
      // phone, so the run is already there.
      expect(find.textContaining('safe on this phone'), findsOneWidget);
    });

    testWidgets('a working one says so with a date', (tester) async {
      await pumpWithBackup(
        tester,
        consent: BackupConsent.granted,
        health: const BackupHealth().succeededAt(DateTime(2026, 8, 23)),
      );

      expect(find.text('Last backed up 23 Aug.'), findsOneWidget);
    });

    testWidgets('a runner who declined is told nothing about a backup they '
        'do not have', (tester) async {
      // There is no promise to report on. A warning here would be the app
      // apologising for doing exactly what it was asked.
      await pumpWithBackup(
        tester,
        consent: BackupConsent.declined,
        health: const BackupHealth().failedAt(DateTime(2026, 8, 23)),
      );

      expect(find.textContaining('The last backup'), findsNothing);
      expect(find.textContaining('Last backed up'), findsNothing);
    });

    testWidgets('and a phone that has never pushed anything stays quiet', (
      tester,
    ) async {
      await pumpWithBackup(
        tester,
        consent: BackupConsent.granted,
        health: const BackupHealth(),
      );

      expect(find.textContaining('Last backed up'), findsNothing);
    });
  });

  testWidgets('no longer offers a way through to Profile, which is a tab', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('Profile'), findsNothing);
  });

  testWidgets('delete account opens the confirmation, not a deletion', (
    tester,
  ) async {
    await pump(tester);

    // Two taps in: the card, then the button at the foot of the account
    // screen. It was one, beside the units.
    await tester.tap(find.text('dev@mgkfitness.mgkcodes.com'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();

    // The same confirmation the legal screen reaches — promoting the row must
    // not have promoted it past the gate.
    expect(find.text('This cannot be undone.'), findsOneWidget);
    expect(find.textContaining('Type DELETE to confirm'), findsOneWidget);
  });
}
