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
}
