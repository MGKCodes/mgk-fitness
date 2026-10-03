import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/auth/data/fake_auth.dart';
import 'package:mgk_lift/src/features/auth/presentation/sign_in_screen.dart';
import 'package:mgk_lift/src/features/legal/domain/legal_copy.dart';
import 'package:mgk_lift/src/features/legal/presentation/legal_document_screen.dart';
import 'package:mgk_lift/src/features/legal/presentation/legal_screen.dart';
import 'package:mgk_lift/src/features/settings/domain/unit_preferences.dart';
import 'package:mgk_lift/src/features/settings/presentation/settings_screen.dart';

Future<void> pumpTall(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1080, 4200);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

void main() {
  group('the legal screen', () {
    testWidgets('offers all three documents', (WidgetTester tester) async {
      await pumpTall(tester, const LegalScreen());

      expect(find.text(termsOfUse.title), findsOneWidget);
      expect(find.text(privacyPolicy.title), findsOneWidget);
      expect(find.text(aiDisclosure.title), findsOneWidget);
    });

    testWidgets('names the AI provider in the list itself', (
      WidgetTester tester,
    ) async {
      // The disclosure has to survive somebody who never taps through. If this
      // subtitle is ever softened to "learn more", 5.1.2(i) stops being met by
      // the list and starts depending on a tap.
      await pumpTall(tester, const LegalScreen());

      expect(find.textContaining('OpenRouter'), findsOneWidget);
    });

    testWidgets('shows the account the rights apply to, when there is one', (
      WidgetTester tester,
    ) async {
      await pumpTall(tester, const LegalScreen(email: 'lifter@example.com'));
      expect(find.text('lifter@example.com'), findsOneWidget);

      await pumpTall(tester, const LegalScreen());
      expect(find.text('lifter@example.com'), findsNothing);
    });

    testWidgets('each row opens its document', (WidgetTester tester) async {
      await pumpTall(tester, const LegalScreen());

      await tester.tap(find.text(privacyPolicy.title));
      await tester.pumpAndSettle();

      expect(find.byType(LegalDocumentScreen), findsOneWidget);
      // The lead is the sentence that says what the app does with your data.
      // Finding it proves the document rendered, not just that a route pushed.
      expect(find.textContaining('We do not sell your data'), findsOneWidget);
    });
  });

  group('reaching the documents', () {
    testWidgets('Settings has a Privacy & legal row that opens the hub', (
      WidgetTester tester,
    ) async {
      await pumpTall(
        tester,
        SettingsScreen(
          initial: const UnitPreferences(),
          store: InMemoryUnitPreferences(),
          isSignedIn: true,
          email: 'lifter@example.com',
        ),
      );

      await tester.tap(find.text('Privacy & legal'));
      await tester.pumpAndSettle();

      expect(find.byType(LegalScreen), findsOneWidget);
      // The hub was given the signed-in address rather than defaulting to null.
      expect(find.text('lifter@example.com'), findsOneWidget);
    });

    testWidgets('the sign-in screen links both documents', (
      WidgetTester tester,
    ) async {
      // Required wherever an account can be created. This screen is the only
      // place it can be, so this test is the one standing between the app and a
      // rejection nobody would see coming.
      final auth = FakeAuth();
      addTearDown(auth.dispose);
      await pumpTall(tester, SignInScreen(auth: auth));

      expect(find.textContaining('By continuing you agree'), findsOneWidget);

      // Tapped by substring, so this asserts the link half is tappable rather
      // than that the sentence exists. A styled span with no recognizer would
      // pass a find and fail a person.
      await tester.tapOnText(find.textRange.ofSubstring('privacy policy'));
      await tester.pumpAndSettle();
      expect(find.byType(LegalDocumentScreen), findsOneWidget);
      expect(find.textContaining('We do not sell your data'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tapOnText(find.textRange.ofSubstring('terms of use'));
      await tester.pumpAndSettle();
      expect(find.byType(LegalDocumentScreen), findsOneWidget);
      expect(
        find.textContaining('Using the app means you accept'),
        findsOneWidget,
      );
    });

    testWidgets('the links are there when creating an account too', (
      WidgetTester tester,
    ) async {
      final auth = FakeAuth();
      addTearDown(auth.dispose);
      await pumpTall(tester, SignInScreen(auth: auth));

      await tester.tap(find.text('Continue with email'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New here? Create an account'));
      await tester.pumpAndSettle();

      expect(find.text('Sign up'), findsWidgets);
      expect(find.textContaining('By continuing you agree'), findsOneWidget);
    });
  });

  group('the version shown in Settings', () {
    test('matches the version in pubspec.yaml', () {
      // The constant carries its own instruction to stay in step with the
      // pubspec and was a whole major version behind it, because nothing
      // checked. Now something does.
      final pubspec = _readPubspecVersion();
      expect(
        pubspec,
        isNotNull,
        reason: 'could not read version: from pubspec.yaml',
      );
      expect(kAppVersion, pubspec);
    });
  });
}

/// The `version:` line of the package's own pubspec, without its build number.
String? _readPubspecVersion() {
  final file = File('pubspec.yaml');
  if (!file.existsSync()) return null;
  for (final line in file.readAsLinesSync()) {
    final match = RegExp(
      r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)',
    ).firstMatch(line);
    if (match != null) return match.group(1);
  }
  return null;
}
