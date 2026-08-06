import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/main.dart';
import 'package:mgk_ui/mgk_ui.dart';

void main() {
  testWidgets('the shell renders and takes its theme from mgk_ui', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MgkLiftApp());

    // SectionLabel uppercases its text — the eyebrow is a design decision made
    // once in mgk_ui, not something each screen restates.
    expect(find.text('LIFT'), findsOneWidget);
    expect(find.text('Nothing here yet'), findsOneWidget);

    // The font is the trap worth guarding: mgk_ui ships Inter as a package
    // font, so the family is `packages/mgk_ui/Inter`. Writing the bare string
    // 'Inter' resolves to nothing and falls back to the platform default —
    // wrong in a way only visible by eye, never by a crash.
    final BuildContext context = tester.element(find.text('Nothing here yet'));
    expect(Theme.of(context).textTheme.bodyMedium?.fontFamily, AppTheme.fontFamily);
    expect(AppTheme.fontFamily, 'packages/mgk_ui/Inter');
  });
}
