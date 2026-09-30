import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// A snackbar used to be the one light thing in a dark suite: the scheme never
/// names `inverseSurface`, and Material paints snackbars in it, so every
/// confirmation in both apps was a white bar with dark text (Run's screen
/// board, T15).
void main() {
  testWidgets('a snackbar sits on the surface, in primary text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Withdrawn.'))),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    final bar = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(SnackBar),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(bar.color, AppColors.surface);

    final text = tester.renderObject<RenderParagraph>(find.text('Withdrawn.'));
    expect(text.text.style?.color, AppColors.textPrimary);
    expect(text.text.style?.fontFamily, AppTheme.fontFamily);
  });
}
