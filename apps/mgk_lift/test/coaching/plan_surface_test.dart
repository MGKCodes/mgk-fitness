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
  group('the tiers', () {
    testWidgets('name photos as paid, and Free as tracking only', (
      WidgetTester tester,
    ) async {
      // Photos moved behind the entitlement on 2026-09-01 and the tier copy
      // did not follow for one commit. This is what notices next time: a
      // feature that changes side has to change this block too.
      await pumpTall(tester, const PlanSurface());

      expect(find.textContaining('and progress photos'), findsOneWidget);
      expect(
        find.text('Sessions, templates, history, stats. No limits and no ads.'),
        findsOneWidget,
      );
    });

    testWidgets('say the two paid tiers differ only by how much you can talk', (
      WidgetTester tester,
    ) async {
      // £3 buys more messages and nothing else. Leaving a price difference
      // unexplained invites somebody to infer a feature list from it, which is
      // how a paywall starts lying without anybody writing a false sentence.
      await pumpTall(tester, const PlanSurface());

      expect(
        find.textContaining('Everything in Coaching, feature for feature'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Far more room to talk to the coach'),
        findsOneWidget,
      );
    });
  });

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
      expect(find.text('It answers back'), findsOneWidget);
    });

    testWidgets('states every tier, not only the one being sold', (
      WidgetTester tester,
    ) async {
      await pumpTall(tester, const PlanSurface());

      expect(find.text('Free'), findsOneWidget);
      expect(find.text('£1'), findsOneWidget);
      expect(find.text('£3'), findsOneWidget);
      expect(find.text('Start coaching — £1/mo'), findsOneWidget);
    });

    testWidgets('promises tracking stays free', (WidgetTester tester) async {
      // The load-bearing one. Tracking must never be paywalled, and a paid
      // surface that does not say so makes the free app feel like a demo — so
      // the free tier is a row on the price block rather than a footnote.
      await pumpTall(tester, const PlanSurface());

      expect(find.text('Everything you are using now'), findsOneWidget);
      expect(find.textContaining('No limits and no ads'), findsOneWidget);
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

    testWidgets('shows what asking the coach looks like', (
      WidgetTester tester,
    ) async {
      // "Build a plan" is otherwise an instruction with no picture attached.
      await tester.pumpWidget(
        wrap(PlanSurface(isEntitled: true, onBuildPlan: () {})),
      );
      await tester.pumpAndSettle();

      expect(find.text('What are you training for?'), findsOneWidget);
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
