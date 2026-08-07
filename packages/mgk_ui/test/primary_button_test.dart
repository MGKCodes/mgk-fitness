import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// The distinction these pin is emphasis, and emphasis is invisible to the
/// analyzer: swapping one of these buttons for the other compiles, passes every
/// screen test that looks for a label, and quietly makes "Forget everything"
/// the loudest thing on the page — which is how it shipped.
void main() {
  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(body: child),
  );

  testWidgets('the primary action is filled, the destructive one is not', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(
        Column(
          children: <Widget>[
            PrimaryButton(label: 'Start a session', onPressed: () {}),
            DestructiveButton(label: 'Forget everything', onPressed: () {}),
          ],
        ),
      ),
    );

    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byType(OutlinedButton), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DestructiveButton),
        matching: find.byType(FilledButton),
      ),
      findsNothing,
      reason: 'a destructive action must never carry the primary fill',
    );
  });

  testWidgets('destructive text is the danger token', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(DestructiveButton(label: 'Delete my data', onPressed: () {})),
    );

    final OutlinedButton button = tester.widget(find.byType(OutlinedButton));
    final Set<WidgetState> pressable = <WidgetState>{};
    expect(button.style?.foregroundColor?.resolve(pressable), AppColors.danger);
  });

  testWidgets('the border stays neutral — the red is on the label only', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(DestructiveButton(label: 'Delete my data', onPressed: () {})),
    );

    final OutlinedButton button = tester.widget(find.byType(OutlinedButton));
    // A red ring was tried and pulled the eye harder than the primary fill it
    // was meant to be quieter than. Nothing but the word should be red.
    expect(
      button.style?.side?.resolve(<WidgetState>{})?.color,
      isNot(AppColors.danger),
    );
  });

  testWidgets('both fill the width, so either can hold the same slot', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(
        Column(
          children: <Widget>[
            PrimaryButton(label: 'Keep', onPressed: () {}),
            DestructiveButton(label: 'Erase', onPressed: () {}),
          ],
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(PrimaryButton)).width,
      tester.getSize(find.byType(DestructiveButton)).width,
    );
    // Same height too: swapping one for the other must not move the layout.
    expect(
      tester.getSize(find.byType(PrimaryButton)).height,
      tester.getSize(find.byType(DestructiveButton)).height,
    );
  });
}
