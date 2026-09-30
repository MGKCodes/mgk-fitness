import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/features/settings/domain/unit_settings.dart';
import 'package:mgk_run/src/features/settings/presentation/avatar.dart';
import 'package:mgk_run/src/features/settings/presentation/settings_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

/// **Signing out only ever called `auth.signOut()`.**
///
/// The runs, the plan, the coach's transcripts, the photo and the name all
/// stayed on the phone, and the next account to sign in got them. That half is
/// fixed where accounts change hands (`AuthGate`). This is the other half: a
/// runner handing the phone on can take their data off it on the way out.
///
/// Off by default, because the phone is where the training lives and an
/// account is its backup -- signing out of the backup is not a reason to lose
/// the original.
void main() {
  late FakeAuthRepository auth;
  late List<bool> erasedWhileSignedIn;

  Future<void> pumpSettings(WidgetTester tester, {bool canErase = true}) async {
    auth = FakeAuthRepository(signedIn: true, email: 'alex@example.com');
    erasedWhileSignedIn = <bool>[];
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: SettingsScreen(
          unit: UnitSystem.metric,
          settings: InMemoryUnitSettings(),
          auth: auth,
          eraseThisPhone: canErase
              ? () async => erasedWhileSignedIn.add(auth.isSignedIn)
              : null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Settings, then the account screen behind the profile card.
    await tester.tap(find.byType(Avatar).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();
  }

  testWidgets('the phone keeps its training unless asked', (tester) async {
    await pumpSettings(tester);

    expect(find.text('Also remove my data from this phone'), findsOneWidget);
    final toggle = tester.widget<Switch>(find.byType(Switch));
    expect(toggle.value, isFalse, reason: 'off unless the runner turns it on');
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('Your runs stay on this device'),
      ),
      findsOneWidget,
    );

    await confirm(tester);

    expect(auth.isSignedIn, isFalse);
    expect(erasedWhileSignedIn, isEmpty);
  });

  testWidgets('turned on, it says what goes and then removes it', (
    tester,
  ) async {
    await pumpSettings(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.textContaining('are removed from this phone'), findsOneWidget);
    expect(find.textContaining('gone for good'), findsOneWidget);

    await confirm(tester);

    expect(auth.isSignedIn, isFalse);
    expect(
      erasedWhileSignedIn,
      <bool>[false],
      reason:
          'erased once, after the account left -- erased first, the shell '
          'rebuilt for the empty phone would claim it for the account that '
          'was leaving',
    );
  });

  testWidgets('changing your mind leaves everything where it was', (
    tester,
  ) async {
    await pumpSettings(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stay signed in'));
    await tester.pumpAndSettle();

    expect(auth.isSignedIn, isTrue);
    expect(erasedWhileSignedIn, isEmpty);
  });

  testWidgets('with nothing to erase with, the option is not offered', (
    tester,
  ) async {
    await pumpSettings(tester, canErase: false);

    expect(find.text('Also remove my data from this phone'), findsNothing);
    expect(find.byType(Switch), findsNothing);
  });
}
