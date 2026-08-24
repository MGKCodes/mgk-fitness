import 'package:mgk_run/src/core/brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
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

    // Units.
    expect(find.text('Kilometres'), findsOneWidget);
    expect(find.text('Miles'), findsOneWidget);
    // The account actions, now grouped under Account rather than floating
    // below the divider.
    expect(find.text('Delete account'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    // Which build this is. Settings is a ListView and the version sits at its
    // foot, below the debug-only developer tools, so it has to be scrolled to
    // rather than found in the first viewport — a widget test runs in debug,
    // where those tools are present.
    // Scrolled to in the order they appear, and asserted as each arrives: a
    // lazy ListView disposes what it has scrolled past, so checking for an
    // earlier row after reaching the foot finds nothing.
    final legal = find.text('Privacy & legal');
    await tester.scrollUntilVisible(
      legal,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(legal, findsOneWidget);

    final version = find.textContaining('$kProductName $kAppVersion');
    await tester.scrollUntilVisible(
      version,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(version, findsOneWidget);
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

    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();

    // The same confirmation the legal screen reaches — promoting the row must
    // not have promoted it past the gate.
    expect(find.text('This cannot be undone.'), findsOneWidget);
    expect(find.textContaining('Type DELETE to confirm'), findsOneWidget);
  });
}
