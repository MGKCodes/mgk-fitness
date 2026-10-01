import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// The three tab roots, shared by both apps for the first time.
///
/// Until this existed each app hand-wrote the same `NavigationBar` — Run's and
/// Lift's were separate copies of one construct, and `mgk_ui` carried no
/// navigation widget and no `navigationBarTheme` at all, so both inherited
/// Material's defaults and neither knew the other had drifted.
///
/// What is asserted here is the part a shared component must not get wrong:
/// that it takes its destinations as **data**. The two apps disagree about
/// their first tab — Run's is Home, a summary of the day; Lift's is Track, the
/// thing you are doing in the gym — so a baked-in label would make one of them
/// wrong on the day it landed.
void main() {
  const List<NavPillDestination> runTabs = <NavPillDestination>[
    NavPillDestination(
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      label: 'Home',
    ),
    NavPillDestination(
      icon: Icons.calendar_month_outlined,
      selectedIcon: Icons.calendar_month,
      label: 'Plan',
    ),
  ];

  const List<NavPillDestination> liftTabs = <NavPillDestination>[
    NavPillDestination(
      icon: Icons.fitness_center_outlined,
      selectedIcon: Icons.fitness_center,
      label: 'Track',
    ),
    NavPillDestination(
      icon: Icons.calendar_month_outlined,
      selectedIcon: Icons.calendar_month,
      label: 'Plan',
    ),
  ];

  Future<void> pump(
    WidgetTester tester, {
    required List<NavPillDestination> destinations,
    int selected = 0,
    ValueChanged<int>? onSelected,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: FloatingNavBar(
          selectedIndex: selected,
          onSelected: onSelected ?? (_) {},
          destinations: destinations,
        ),
      ),
    ),
  );

  testWidgets('it draws whichever destinations it is given', (tester) async {
    await pump(tester, destinations: runTabs);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Track'), findsNothing);

    await pump(tester, destinations: liftTabs);
    expect(find.text('Track'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });

  testWidgets('the labels are real text, not tooltips', (tester) async {
    // Both apps change tab in tests by tapping a label, and a bar whose icons
    // alone must be recognised is a bar people learn by trial.
    await pump(tester, destinations: runTabs);
    expect(find.text('Home').hitTestable(), findsOneWidget);
    expect(find.text('Plan').hitTestable(), findsOneWidget);
  });

  testWidgets('the selected one is filled and the rest are not', (
    tester,
  ) async {
    await pump(tester, destinations: runTabs, selected: 1);
    expect(find.byIcon(Icons.calendar_month), findsOneWidget); // selected
    expect(find.byIcon(Icons.home_outlined), findsOneWidget); // not
    expect(find.byIcon(Icons.home), findsNothing);
  });

  testWidgets('tapping reports the index it was given', (tester) async {
    int? tapped;
    await pump(
      tester,
      destinations: runTabs,
      onSelected: (int i) => tapped = i,
    );

    await tester.tap(find.text('Plan'));
    expect(tapped, 1);
  });

  // The selection used to be a property of each tab, so a change was one tab
  // going bright and another going dim in the same frame. It is a plate now,
  // and it travels.
  group('the selection moves', () {
    // The plate is the only AnimatedAlign in the bar.
    double plateCentre(WidgetTester tester) => tester
        .getCenter(
          find.descendant(
            of: find.byType(AnimatedAlign),
            matching: find.byType(DecoratedBox),
          ),
        )
        .dx;

    testWidgets('it sits behind the selected tab', (tester) async {
      await pump(tester, destinations: runTabs, selected: 1);
      expect(
        plateCentre(tester),
        closeTo(tester.getCenter(find.text('Plan')).dx, 0.5),
      );
    });

    testWidgets('and travels to the next one rather than jumping', (
      tester,
    ) async {
      await pump(tester, destinations: runTabs);
      final double home = tester.getCenter(find.text('Home')).dx;
      final double plan = tester.getCenter(find.text('Plan')).dx;
      expect(plateCentre(tester), closeTo(home, 0.5));

      await pump(tester, destinations: runTabs, selected: 1);
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        plateCentre(tester),
        allOf(greaterThan(home), lessThan(plan)),
        reason: 'part way between the two, part way through',
      );

      await tester.pumpAndSettle();
      expect(plateCentre(tester), closeTo(plan, 0.5));
    });

    testWidgets('at once, with Reduce Motion on', (tester) async {
      Widget bar(int selected) => MaterialApp(
        theme: AppTheme.dark,
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: FloatingNavBar(
              selectedIndex: selected,
              onSelected: (_) {},
              destinations: runTabs,
            ),
          ),
        ),
      );
      await tester.pumpWidget(bar(0));
      await tester.pumpWidget(bar(1));
      await tester.pump();

      expect(
        plateCentre(tester),
        closeTo(tester.getCenter(find.text('Plan')).dx, 0.5),
      );
    });
  });
}
