import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/core/config/app_config.dart';
import 'package:mgk_run/src/features/auth/presentation/sign_in_screen.dart';

void main() {
  const devAccounts = <DevAccount>[
    DevAccount(
      label: 'Runner A',
      email: 'a@mgkfitness.mgkcodes.com',
      password: 'password',
    ),
    DevAccount(
      label: 'Runner B',
      email: 'b@mgkfitness.mgkcodes.com',
      password: 'secret6',
    ),
  ];

  testWidgets('shows developer quick sign-in buttons when accounts are given', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SignInScreen(
          auth: FakeAuthRepository(),
          devAccounts: devAccounts,
        ),
      ),
    );

    expect(find.text('Developer sign-in'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Runner A'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Runner B'), findsOneWidget);
  });

  testWidgets('hides developer quick sign-in when no accounts are given', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SignInScreen()));

    expect(find.text('Developer sign-in'), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets("tapping a dev button signs in with that account's credentials", (
    tester,
  ) async {
    final auth = FakeAuthRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: SignInScreen(auth: auth, devAccounts: devAccounts),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Runner B'));
    await tester.pump();

    expect(auth.lastEmail, 'b@mgkfitness.mgkcodes.com');
    expect(auth.lastPassword, 'secret6');
  });
}
