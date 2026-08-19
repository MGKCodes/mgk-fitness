import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// A button label must be set in Inter like everything around it.
///
/// This is not a hypothetical. A `ButtonStyle`'s `textStyle` is handed to
/// [Material] as the label's *whole* style rather than merged over the text
/// theme, so the family has to be spelled out there — and it was not. Every
/// filled and outlined button in the suite rendered in SF Pro or Roboto beside
/// Inter numerals, and it took rendering the in-run screen to a PNG (where the
/// fallback is the test framework's placeholder font, and therefore visible) to
/// notice.
void main() {
  for (final (String name, ButtonStyle? style) in <(String, ButtonStyle?)>[
    ('filled', AppTheme.dark.filledButtonTheme.style),
    ('outlined', AppTheme.dark.outlinedButtonTheme.style),
  ]) {
    test('the $name button theme names the font family', () {
      final TextStyle? text = style?.textStyle?.resolve(<WidgetState>{});
      expect(text, isNotNull, reason: 'the $name button sets a text style');
      expect(
        text!.fontFamily,
        AppTheme.fontFamily,
        reason:
            'omitting it resolves to the platform default, not the theme font',
      );
    });
  }

  testWidgets('a rendered button label carries the family', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: PrimaryButton(label: 'Finish', onPressed: () {}),
        ),
      ),
    );

    final TextStyle style = DefaultTextStyle.of(
      tester.element(find.text('Finish')),
    ).style;
    expect(style.fontFamily, AppTheme.fontFamily);
  });
}
