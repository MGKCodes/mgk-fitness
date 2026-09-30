import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/legal/presentation/medical_disclaimer_screen.dart';

/// The medical notice at the gate (screen board C9 and G1). "I understand"
/// was a narrow centred pill where every other step's main action is full
/// width, and the panel behind the buttons stopped short of the bottom edge.
void main() {
  const phone = Size(393, 852);
  const homeIndicator = 34.0;

  Future<void> pump(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = phone;
    tester.view.padding = const FakeViewPadding(top: 59, bottom: homeIndicator);
    tester.view.viewPadding = const FakeViewPadding(
      top: 59,
      bottom: homeIndicator,
    );
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: MedicalDisclaimerScreen(onAcknowledge: () {}, onDecline: () {}),
      ),
    );
    await tester.pumpAndSettle();
  }

  final panel = find.ancestor(
    of: find.text('I understand'),
    matching: find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).color == AppColors.surface,
    ),
  );

  testWidgets('"I understand" is the full-width primary', (tester) async {
    await pump(tester);

    expect(find.widgetWithText(PrimaryButton, 'I understand'), findsOneWidget);
    final button = tester.getSize(
      find.ancestor(
        of: find.text('I understand'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.width, phone.width - 40, reason: 'edge to edge of the panel');
  });

  testWidgets('the panel runs to the bottom edge, its buttons clear of it', (
    tester,
  ) async {
    await pump(tester);

    expect(tester.getBottomLeft(panel).dy, phone.height);
    final notNow = tester.getBottomLeft(find.text('Not now')).dy;
    expect(notNow, lessThan(phone.height - homeIndicator));
  });

  testWidgets('the reference view has no panel and keeps its inset', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = phone;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark, home: const MedicalDisclaimerScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('I understand'), findsNothing);
  });
}
