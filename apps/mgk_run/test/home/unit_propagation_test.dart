import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_units/mgk_units.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';
import 'package:mgk_run/src/features/settings/domain/unit_settings.dart';

/// Regression: every screen accepted a `unit` parameter and nothing ever passed
/// one, so the stored choice was inert and the whole app rendered in kilometres.
/// Asserting through [HomeShell] rather than per screen is the point — the bug
/// was in the wiring, not in any screen.
void main() {
  List<RunSummary> runs() => <RunSummary>[
    RunSummary(
      startedAt: DateTime(2026, 7, 21, 7, 32),
      duration: const Duration(minutes: 27, seconds: 45),
      distanceMeters: 5230,
      avgPaceSecondsPerKm: 318,
    ),
  ];

  Future<void> pumpProfile(WidgetTester tester, UnitSystem stored) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          auth: FakeAuthRepository(
            signedIn: true,
            email: 'dev@mgkfitness.mgkcodes.com',
          ),
          historySource: () async => runs(),
          unitSettings: InMemoryUnitSettings(unit: stored),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
  }

  testWidgets('a stored imperial choice reaches the screens', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpProfile(tester, UnitSystem.imperial);

    expect(find.textContaining('mi'), findsWidgets);
    // 5230 m is 5.23 km — the metric figure must not be on screen at all.
    expect(find.textContaining('5.23 km'), findsNothing);
  });

  testWidgets('a stored metric choice still shows kilometres', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpProfile(tester, UnitSystem.metric);

    expect(find.textContaining('km'), findsWidgets);
  });

  testWidgets('settings are reachable from the Profile tab', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          auth: FakeAuthRepository(
            signedIn: true,
            email: 'dev@mgkfitness.mgkcodes.com',
          ),
          unitSettings: InMemoryUnitSettings(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Deliberately not on Home — that page is for running, not administration.
    expect(find.byTooltip('Settings'), findsNothing);
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    // Profile is about running: the signed-in address is not on it.
    expect(find.text('dev@mgkfitness.mgkcodes.com'), findsNothing);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsWidgets);
    // The account facts moved here off Profile. Still above the fold: Account
    // is the first band on the page.
    expect(find.text('dev@mgkfitness.mgkcodes.com'), findsOneWidget);
    // The unit is on the index as a value now — `Distance · Kilometres` —
    // with the choice itself in a sheet. So this asserts the row is present
    // and set, which is what "the unit is in Settings" actually means after
    // the 2026-09-11 rewrite.
    expect(find.text('Distance'), findsOneWidget);
    expect(find.text('Kilometres'), findsOneWidget);
    // The compliance surfaces moved under Settings rather than a second icon.
    // Scrolled to, because Settings grew a Permissions section above it and
    // the list builds lazily — asserting from a fixed viewport was asserting
    // the screen's length as much as its contents.
    await tester.scrollUntilVisible(
      find.text('Privacy & legal'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Privacy & legal'), findsOneWidget);
  });

  // Changing it in Settings must reflow the whole app, not only the screen you
  // are looking at — the unit lives above all three tabs for exactly this.
  testWidgets('switching to miles in Settings changes the log too', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = InMemoryUnitSettings(unit: UnitSystem.metric);
    await tester.pumpWidget(
      MaterialApp(
        home: HomeShell(
          auth: FakeAuthRepository(
            signedIn: true,
            email: 'dev@mgkfitness.mgkcodes.com',
          ),
          historySource: () async => runs(),
          unitSettings: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.textContaining('km'), findsWidgets);

    // Into Settings, flip to miles, and back out.
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Distance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Miles'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.textContaining('mi'), findsWidgets);
    expect(
      find.textContaining('km'),
      findsNothing,
      reason: 'a screen left in kilometres is the bug this suite exists for',
    );
    expect(await store.load(), UnitSystem.imperial);
  });
}
