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

/// Settings is where everything that is not itself training lives. The account
/// facts moved here off Profile, and the controls a runner goes looking for —
/// units, what the app promises, how to leave, what version this is — have to
/// be findable in one place rather than scattered behind other screens.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    DateTime? memberSince,
    String? email = 'dev@runio.app',
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

    expect(find.text('ACCOUNT'), findsOneWidget);
    expect(find.text('dev@runio.app'), findsOneWidget);
    expect(find.textContaining('since July 2026'), findsOneWidget);
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
  group('what the coach calls you can be changed', () {
    Future<FakeAuthRepository> pumpWithName(
      WidgetTester tester,
      String? name,
    ) async {
      final auth = FakeAuthRepository(
        signedIn: true,
        email: 'dev@runio.app',
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

      expect(find.text('Coach calls you'), findsOneWidget);
      expect(find.text('Sam'), findsOneWidget);
    });

    testWidgets('and a typo can be corrected', (tester) async {
      final auth = await pumpWithName(tester, 'Smaa');

      await tester.tap(find.text('Coach calls you'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Sam');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(auth.currentName, 'Sam');
      expect(find.text('Sam'), findsOneWidget);
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

    // Band 1, in the first viewport: who this is, and the reversible half of
    // the account actions.
    expect(find.text('Sign out'), findsOneWidget);

    // Which build this is. Settings is a ListView and the version sits at its
    // foot, below the debug-only developer tools, so it has to be scrolled to
    // rather than found in the first viewport — a widget test runs in debug,
    // where those tools are present.
    //
    // Scrolled to in the order they appear, and asserted as each arrives: a
    // lazy ListView disposes what it has scrolled past, so checking for an
    // earlier row after reaching the foot finds nothing. That order is now
    // load-bearing rather than incidental, and `the page reads as four bands`
    // below is what pins it.
    Future<void> scrollTo(Finder target) => tester.scrollUntilVisible(
      target,
      300,
      scrollable: find.byType(Scrollable).first,
    );

    // Band 3 — units, and what the app says about itself.
    final units = find.text('Kilometres');
    await scrollTo(units);
    expect(units, findsOneWidget);
    expect(find.text('Miles'), findsOneWidget);

    final legal = find.text('Privacy & legal');
    await scrollTo(legal);
    expect(legal, findsOneWidget);

    // Band 4 — the one irreversible row, at the foot of everything a runner
    // uses rather than beside the things they use daily.
    final delete = find.text('Delete account');
    await scrollTo(delete);
    expect(delete, findsOneWidget);

    final version = find.textContaining('$kProductName $kAppVersion');
    await scrollTo(version);
    expect(version, findsOneWidget);
  });

  /// **The screen is four bands, and the order of them is the argument.**
  ///
  /// Build 12's field test called Settings disorganised: one undifferentiated
  /// list, with consent, the permissions, the account and the deletion all
  /// below the fold and nothing to mark any of them out. The answer was not to
  /// shuffle rows but to give them an order that can be stated — sections
  /// descend by how much of the runner's record they decide, and the single
  /// irreversible control is placed by the cost of an accidental tap instead,
  /// which puts it last.
  ///
  /// A layout with a stated principle and no test is a layout that drifts back
  /// the first time a row is added, so the principle is asserted here as
  /// positions rather than described in a comment nobody runs.
  group('the page reads as four bands', () {
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
              email: signedIn ? 'dev@runio.app' : null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the headings run in the one stated order', (tester) async {
      await pumpWhole(tester);

      double topOf(String label) => tester.getTopLeft(find.text(label)).dy;

      // Band 1 · where you stand — band 2 · what the app may do with your
      // running — band 3 · what neither of those touches — band 4 · leaving.
      final order = <String>[
        'YOU',
        'ACCOUNT',
        'YOUR DATA',
        'PERMISSIONS',
        'DISTANCE',
        'ABOUT',
        'LEAVING',
      ];
      // `topOf` throws on a heading that is not there, so this list existing
      // at all is the assertion that all seven bands drew.
      final tops = <double>[for (final label in order) topOf(label)];

      for (var i = 1; i < order.length; i++) {
        expect(
          tops[i],
          greaterThan(tops[i - 1]),
          reason: '${order[i]} must sit below ${order[i - 1]}',
        );
      }
    });

    testWidgets('the row that cannot be undone is the last one on the page', (
      tester,
    ) async {
      await pumpWhole(tester);

      final delete = tester.getTopLeft(find.text('Delete account')).dy;

      // Below everything a runner touches on an ordinary visit — including
      // the documents, which is as far down as anything else goes.
      for (final earlier in <String>[
        'Sign out',
        'Back up my data',
        'Location',
        'Kilometres',
        'Privacy & legal',
      ]) {
        expect(
          tester.getTopLeft(find.text(earlier)).dy,
          lessThan(delete),
          reason: '"$earlier" must sit above the deletion, not below it',
        );
      }
    });

    testWidgets('and it keeps the danger tint that says so', (tester) async {
      await pumpWhole(tester);

      // The only sanctioned use of colour on this screen (ADR-0009). A
      // deletion demoted to the foot and then greyed to match its neighbours
      // would have traded one signal for another rather than added one.
      final tile = tester.widget<SettingsTile>(
        find.widgetWithText(SettingsTile, 'Delete account'),
      );
      expect(tile.tint, AppColors.danger);
    });

    testWidgets('nothing is left pointing at an empty band with no account', (
      tester,
    ) async {
      await pumpWhole(tester, signedIn: false);

      // The whole band is signed-in only, heading and rule included. A rule
      // with nothing under it is the last thing on the page promising a
      // section that does not exist.
      expect(find.text('LEAVING'), findsNothing);
      expect(find.text('Delete account'), findsNothing);
      expect(find.text('ABOUT'), findsOneWidget);
    });
  });

  /// **ADR-0012's cost function turns on consent not being something you go
  /// looking for.** The switch is also the place it is withdrawn, and consent
  /// must be at least as easy to take back as it was to give. It used to sit
  /// below the unit picker, below a rule, and below the fold — reachable only
  /// by somebody already scrolling for it.
  testWidgets('backup consent is in the first screenful of a phone', (
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
          auth: FakeAuthRepository(signedIn: true, email: 'dev@runio.app'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Whole tile, not just its top edge: a switch half off the bottom of the
    // screen is a switch somebody has to go looking for.
    final tile = find.byType(SwitchListTile);
    expect(tester.getBottomLeft(tile).dy, lessThan(fold));
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
            auth: FakeAuthRepository(signedIn: true, email: 'dev@runio.app'),
            consentStore: InMemoryBackupConsent(consent),
            backupHealthStore: InMemoryBackupHealth(health),
          ),
        ),
      );
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

    // At the foot of the page now, which is the point of it — so it has to be
    // scrolled to, exactly as a runner would have to.
    final delete = find.text('Delete account');
    await tester.scrollUntilVisible(
      delete,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(delete);
    await tester.pumpAndSettle();

    // The same confirmation the legal screen reaches — promoting the row must
    // not have promoted it past the gate.
    expect(find.text('This cannot be undone.'), findsOneWidget);
    expect(find.textContaining('Type DELETE to confirm'), findsOneWidget);
  });
}
