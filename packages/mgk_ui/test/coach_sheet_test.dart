import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// The coach sheet both apps draw since 5 October 2026.
void main() {
  Widget host(Widget child, {double keyboard = 0}) => MaterialApp(
    theme: AppTheme.dark,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(viewInsets: EdgeInsets.only(bottom: keyboard)),
        child: Scaffold(
          body: Align(alignment: Alignment.bottomCenter, child: child),
        ),
      ),
    ),
  );

  Future<void> sized(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('the sheet rises above the keyboard, composer and all', (
    tester,
  ) async {
    // Lift's sheet did not pad for it, so on a phone the keyboard came up
    // over the field it had been opened to type into.
    await sized(tester);
    final field = TextEditingController();
    addTearDown(field.dispose);
    await tester.pumpWidget(
      host(
        CoachSheetFrame(
          photo: 'missing.webp',
          child: CoachSheetLayout(
            bar: CoachTopBar(
              icon: const AssetImage('missing.png'),
              onClose: () {},
            ),
            conversation: const SizedBox.expand(),
            footer: CoachComposer(
              controller: field,
              enabled: true,
              onSend: () {},
            ),
          ),
        ),
        keyboard: 300,
      ),
    );
    await tester.pump();

    final screen = tester.view.physicalSize.height / 3;
    final fieldBottom = tester.getBottomLeft(find.byType(TextField)).dy;
    expect(fieldBottom, lessThanOrEqualTo(screen - 300));
  });

  testWidgets('the bar: history hides mid-intake, the disclosure does not', (
    tester,
  ) async {
    await sized(tester);
    Widget bar((int, int)? progress) => host(
      CoachTopBar(
        icon: const AssetImage('missing.png'),
        progress: progress,
        onHistory: () {},
        onDisclosure: () {},
        onClose: () {},
      ),
    );

    await tester.pumpWidget(bar(null));
    expect(find.byTooltip('Previous conversations'), findsOneWidget);
    expect(find.byTooltip('How your coach uses AI'), findsOneWidget);
    expect(find.text('Coach'), findsOneWidget);

    await tester.pumpWidget(bar((2, 5)));
    expect(find.byTooltip('Previous conversations'), findsNothing);
    expect(find.byTooltip('How your coach uses AI'), findsOneWidget);
  });

  testWidgets('the composer sends, and not while the coach is answering', (
    tester,
  ) async {
    await sized(tester);
    final field = TextEditingController();
    addTearDown(field.dispose);
    var sent = 0;
    Widget composer({required bool enabled}) => host(
      CoachComposer(controller: field, enabled: enabled, onSend: () => sent++),
    );

    await tester.pumpWidget(composer(enabled: true));
    expect(find.text('Ask your coach'), findsOneWidget);
    await tester.tap(find.byTooltip('Send'));
    expect(sent, 1);

    await tester.pumpWidget(composer(enabled: false));
    await tester.tap(find.byTooltip('Send'), warnIfMissed: false);
    expect(sent, 1);
  });

  testWidgets('an empty coach offers questions, and a tap sends one', (
    tester,
  ) async {
    await sized(tester);
    final asked = <String>[];
    await tester.pumpWidget(
      host(
        SizedBox(
          height: 600,
          child: CoachEmptyState(
            lead: 'It has read your log',
            suggestions: const <String>['Was this week enough?'],
            onSuggestion: asked.add,
            footnote: 'It also remembers you.',
          ),
        ),
      ),
    );

    expect(find.text('It has read your log'), findsOneWidget);
    expect(find.text('It also remembers you.'), findsOneWidget);
    await tester.tap(find.text('Was this week enough?'));
    expect(asked, <String>['Was this week enough?']);
  });

  group('the bubble', () {
    testWidgets("a long press reports a coach's reply, and says so", (
      tester,
    ) async {
      await sized(tester);
      var reports = 0;
      await tester.pumpWidget(
        host(
          ConversationBubble(
            text: 'Off your recent 5k, 5:10 a km.',
            fromCoach: true,
            onReport: () => reports++,
            note: "Reported. Thanks, we'll take a look.",
          ),
        ),
      );

      // Not selectable where it reports: selection takes the long press.
      expect(find.byType(SelectableText), findsNothing);
      await tester.longPress(find.text('Off your recent 5k, 5:10 a km.'));
      expect(reports, 1);
      expect(find.text("Reported. Thanks, we'll take a look."), findsOneWidget);
    });

    testWidgets('your own words are not reportable, and stay selectable', (
      tester,
    ) async {
      await sized(tester);
      var reports = 0;
      await tester.pumpWidget(
        host(
          ConversationBubble(
            text: 'How was my week?',
            fromCoach: false,
            onReport: () => reports++,
          ),
        ),
      );

      expect(find.byType(SelectableText), findsOneWidget);
      await tester.longPress(find.text('How was my week?'));
      expect(reports, 0);
    });
  });
}
