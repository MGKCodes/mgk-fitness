import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/coaching/presentation/plan_surface.dart';
import 'package:mgk_ui/mgk_ui.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

/// Pumps on a viewport tall enough to hold the whole surface.
///
/// The default 800×600 is shorter than a phone, and a lazy ListView does not
/// build what it cannot show — so on the default the price block and the button
/// simply do not exist, and every assertion about them fails for a reason that
/// has nothing to do with the screen.
Future<void> pumpTall(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1080, 4200);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(wrap(child));
  await tester.pumpAndSettle();
}

void main() {
  group('the offer', () {
    // The first version was a headline, a paragraph and a disabled button with
    // nine hundred pixels of nothing between them — a third of the app's
    // navigation, selling nothing.

    testWidgets('says what the coach does, not just that it exists', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(wrap(const PlanSurface()));
      await tester.pumpAndSettle();

      expect(find.text('Train with a coach'), findsOneWidget);
      expect(find.text('A block, not a list'), findsOneWidget);
      expect(find.text('Numbers from your numbers'), findsOneWidget);
    });

    testWidgets('promises nothing the app does not do', (
      WidgetTester tester,
    ) async {
      // Nothing can move a planned session (a plan's days are derived, not
      // stored), and the coach reads Lift's log and nothing of Run's. The
      // offer said both.
      await pumpTall(tester, const PlanSurface());

      expect(find.textContaining('move Thursday'), findsNothing);
      expect(find.textContaining('running'), findsNothing);
    });

    testWidgets('names no tier and no price: the sales screen does', (
      WidgetTester tester,
    ) async {
      // One place sells (R6). A second price table here was a second chance
      // to disagree with the store.
      await pumpTall(tester, const PlanSurface());

      expect(find.textContaining('£'), findsNothing);
      expect(find.text('Premium Coach'), findsNothing);
      expect(find.text('Start coaching'), findsOneWidget);
    });

    testWidgets('promises tracking stays free', (WidgetTester tester) async {
      // The load-bearing one. Tracking must never be paywalled, and a paid
      // surface that does not say so makes the free app feel like a demo — so
      // the free tier is a row on the price block rather than a footnote.
      await pumpTall(tester, const PlanSurface());

      expect(find.textContaining('Tracking stays free'), findsOneWidget);
    });

    testWidgets('carries its content even with no billing wired up', (
      WidgetTester tester,
    ) async {
      // The screen is not allowed to become empty just because the button
      // cannot do anything yet — that is exactly what it was.
      await pumpTall(tester, const PlanSurface());

      final button = tester.widget<FilledButton>(
        find.descendant(
          of: find.byType(PrimaryButton),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
      expect(find.text('A block, not a list'), findsOneWidget);
    });
  });

  group('paid, but no plan yet', () {
    testWidgets('offers to build one instead of selling again', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(PlanSurface(isEntitled: true, onBuildPlan: () {})),
      );
      await tester.pumpAndSettle();

      expect(find.text('No plan yet'), findsOneWidget);
      expect(find.text('Build a plan'), findsOneWidget);
      expect(find.text('£1'), findsNothing);
    });

    testWidgets('says what happens next, in three steps (16)', (
      WidgetTester tester,
    ) async {
      // "Build a plan" is otherwise an instruction with no picture attached.
      await pumpTall(tester, PlanSurface(isEntitled: true, onBuildPlan: () {}));

      expect(
        find.text('Tell the coach your goal and your days'),
        findsOneWidget,
      );
      expect(find.text('It builds the block'), findsOneWidget);
      expect(find.text("Today's session appears on Track"), findsOneWidget);
    });

    testWidgets('says why the button is dead when the coach is unreachable', (
      WidgetTester tester,
    ) async {
      // This surface is the one place the app is honestly online-only, and it
      // has to distinguish that from tracking, which is not.
      await tester.pumpWidget(wrap(const PlanSurface(isEntitled: true)));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Your coach needs a connection'),
        findsOneWidget,
      );
      expect(find.textContaining('Tracking carries on'), findsOneWidget);
    });
  });
}
