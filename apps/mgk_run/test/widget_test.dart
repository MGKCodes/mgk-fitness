import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/main.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/auth/presentation/sign_in_screen.dart';
import 'package:mgk_run/src/features/onboarding/presentation/welcome_screen.dart';

void main() {
  testWidgets('shows the config-missing screen when unconfigured', (
    tester,
  ) async {
    await tester.pumpWidget(const RunioApp(isConfigured: false));

    expect(find.text('Configuration missing'), findsOneWidget);
  });

  testWidgets('sign-in screen renders email, password, and submit', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SignInScreen()));

    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });

  testWidgets('welcome screen renders wordmark and CTA', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: WelcomeScreen(onGetStarted: () {}, onHaveAccount: () {}),
      ),
    );

    expect(find.text('RUNIO'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('I already have an account'), findsOneWidget);
  });
}
