import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.dark,
  home: Scaffold(
    body: Center(child: SizedBox(width: 320, child: child)),
  ),
);

void main() {
  testWidgets('says what it does, and is a button', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(ProviderSignInButton.apple(onPressed: () => taps++)),
    );

    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.byType(AppleLogo), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(ProviderSignInButton)),
      matchesSemantics(
        label: 'Continue with Apple',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(find.byType(ProviderSignInButton));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('Google carries its own mark', (tester) async {
    await tester.pumpWidget(
      _host(ProviderSignInButton.google(onPressed: () {})),
    );
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.byType(GoogleLogo), findsOneWidget);
  });

  testWidgets('is the height of the buttons it stacks with', (tester) async {
    await tester.pumpWidget(
      _host(ProviderSignInButton.google(onPressed: () {})),
    );
    expect(
      tester.getSize(find.byType(ProviderSignInButton)).height,
      ProviderSignInButton.height,
    );
  });

  testWidgets('busy, it waits and cannot be pressed again', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(ProviderSignInButton.apple(onPressed: () => taps++, busy: true)),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(AppleLogo), findsNothing);

    await tester.tap(find.byType(ProviderSignInButton));
    await tester.pump();
    expect(taps, 0);
  });

  testWidgets('without an action it is disabled', (tester) async {
    await tester.pumpWidget(
      _host(const ProviderSignInButton.apple(onPressed: null)),
    );
    expect(
      tester.getSemantics(find.byType(ProviderSignInButton)),
      matchesSemantics(
        label: 'Continue with Apple',
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
      ),
    );
  });
}
