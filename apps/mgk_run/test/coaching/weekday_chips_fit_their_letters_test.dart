import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/coaching/domain/intake_slots.dart';
import 'package:mgk_run/src/features/coaching/presentation/profile_confirmation_screen.dart';

import '../plates/plate.dart' show kPhone, loadInter;

/// "Which days" on the confirmation screen (screen board G4, G6): at 393pt
/// the M and W chips were drawn with their right edge faded out, because each
/// of seven chips spent 16pt of its width on label padding and Inter's widest
/// capitals no longer fitted what was left.
///
/// In real Inter, since the test font draws every glyph the same width and
/// would fit either way.
void main() {
  testWidgets('every weekday letter is drawn whole at 393pt', (tester) async {
    await loadInter();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(kPhone.width, 1600);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: ProfileConfirmationScreen(
          slots: const IntakeSlots(
            daysPerWeek: 5,
            availableWeekdays: <int>{1, 2, 4, 6, 7},
          ),
          onConfirm: (_) {},
          now: () => DateTime(2026, 9, 30),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final letter in <String>['M', 'T', 'W', 'F', 'S']) {
      for (final element in find.text(letter).evaluate()) {
        final paragraph = element.renderObject! as RenderParagraph;
        final natural = paragraph.getMaxIntrinsicWidth(double.infinity);
        expect(
          paragraph.size.width,
          greaterThanOrEqualTo(natural - 0.01),
          reason:
              '$letter is ${natural.toStringAsFixed(1)}pt wide and was '
              'given ${paragraph.size.width.toStringAsFixed(1)}pt',
        );
      }
    }
  });
}
