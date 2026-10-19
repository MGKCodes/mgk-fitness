import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/auth/data/fake_auth.dart';
import 'package:mgk_lift/src/features/auth/domain/account.dart';
import 'package:mgk_lift/src/features/home/presentation/lift_shell.dart';
import 'package:mgk_lift/src/features/settings/domain/unit_preferences.dart';
import 'package:mgk_lift/src/features/settings/presentation/account_name_sheet.dart';
import 'package:mgk_lift/src/features/settings/presentation/account_screen.dart';
import 'package:mgk_lift/src/features/settings/presentation/settings_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// The account's name where Lift shows the account (Run's ADR-0047, "The
/// name belongs to the account"): the card at the top of Settings and the
/// account screen behind it, where it is also given, changed and cleared.
Future<void> pumpTall(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1080, 4200);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: child));
  await tester.pumpAndSettle();
}

const Account _named = Account(
  id: 'u1',
  email: 'lifter@example.com',
  name: 'Sam Lee',
);

SettingsScreen _settings(FakeAuth auth) => SettingsScreen(
  initial: const UnitPreferences(),
  store: InMemoryUnitPreferences(),
  isSignedIn: true,
  email: auth.current?.email,
  name: auth.current?.name,
  auth: auth,
);

void main() {
  testWidgets('the Settings card leads with the name, the address under it', (
    tester,
  ) async {
    final auth = FakeAuth(account: _named);
    addTearDown(auth.dispose);
    await pumpTall(tester, _settings(auth));

    final card = find.byType(ProfileCard);
    expect(
      find.descendant(of: card, matching: find.text('Sam Lee')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('lifter@example.com')),
      findsOneWidget,
    );
    // The name's initials, not the address's first letter.
    expect(
      find.descendant(of: card, matching: find.text('SL')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.text('Sam Lee')).dy,
      lessThan(tester.getTopLeft(find.text('lifter@example.com')).dy),
    );
  });

  testWidgets('the account screen shows it, and changes it for both apps', (
    tester,
  ) async {
    final auth = FakeAuth(account: _named);
    addTearDown(auth.dispose);
    await pumpTall(tester, _settings(auth));
    await tester.tap(find.text('Sam Lee'));
    await tester.pumpAndSettle();

    // Headed by the name, with the address under it, and a row to change it.
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Sam Lee'), findsNWidgets(2));
    expect(find.text('lifter@example.com'), findsOneWidget);
    expect(find.widgetWithText(SettingsRow, 'Name'), findsOneWidget);

    await tester.tap(find.widgetWithText(SettingsRow, 'Name'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(AccountNameSheet.fieldKey),
    );
    expect(field.controller?.text, 'Sam Lee');

    await tester.enterText(find.byKey(AccountNameSheet.fieldKey), ' Sam ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(auth.namesWritten, <String?>['Sam']);
    expect(find.byType(AccountNameSheet), findsNothing);
    expect(find.text('Sam'), findsNWidgets(2));
    expect(find.text('Sam Lee'), findsNothing);

    // And the card behind it has it too, once the account screen closes.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(ProfileCard), matching: find.text('Sam')),
      findsOneWidget,
    );
  });

  testWidgets('a blank name clears it, and the address takes its place', (
    tester,
  ) async {
    final auth = FakeAuth(account: _named);
    addTearDown(auth.dispose);
    await pumpTall(
      tester,
      AccountScreen(email: 'lifter@example.com', name: 'Sam Lee', auth: auth),
    );

    await tester.tap(find.widgetWithText(SettingsRow, 'Name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(AccountNameSheet.fieldKey), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(auth.namesWritten, <String?>[null]);
    expect(auth.current?.name, isNull);
    expect(find.text('Sam Lee'), findsNothing);
    expect(find.text('Not set'), findsOneWidget);
    expect(find.text('lifter@example.com'), findsOneWidget);
    expect(find.text('L'), findsOneWidget);
  });

  testWidgets('an account with no name says so, and nothing prompts for one', (
    tester,
  ) async {
    // How an Apple account, which is never asked, gives a name: a row that
    // waits, not a question.
    final auth = FakeAuth(
      account: const Account(id: 'u1', email: 'lifter@example.com'),
    );
    addTearDown(auth.dispose);
    await pumpTall(
      tester,
      AccountScreen(email: 'lifter@example.com', auth: auth),
    );

    expect(find.text('lifter@example.com'), findsOneWidget);
    expect(find.text('Not set'), findsOneWidget);
    expect(find.byType(AccountNameStep), findsNothing);
    expect(find.textContaining('What should we call you'), findsNothing);
  });

  testWidgets('a name that does not save says so, and keeps what was typed', (
    tester,
  ) async {
    final auth = FakeAuth(
      account: _named,
      nameFailure: AuthFailure.unavailable,
    );
    addTearDown(auth.dispose);
    await pumpTall(
      tester,
      AccountScreen(email: 'lifter@example.com', name: 'Sam Lee', auth: auth),
    );

    await tester.tap(find.widgetWithText(SettingsRow, 'Name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(AccountNameSheet.fieldKey), 'Sam');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Your name did not save. Try again.'), findsOneWidget);
    expect(find.byType(AccountNameSheet), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(AccountNameSheet.fieldKey))
          .controller
          ?.text,
      'Sam',
    );
    expect(auth.current?.name, 'Sam Lee');
  });

  testWidgets('a build with no server shows no row it cannot fill', (
    tester,
  ) async {
    await pumpTall(tester, const AccountScreen(email: 'lifter@example.com'));
    expect(find.widgetWithText(SettingsRow, 'Name'), findsNothing);
  });

  testWidgets('the shell passes the signed-in account\'s name to Settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final auth = FakeAuth(account: _named);
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: LiftShell(auth: auth),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(ProfileCard),
        matching: find.text('Sam Lee'),
      ),
      findsOneWidget,
    );
  });
}
