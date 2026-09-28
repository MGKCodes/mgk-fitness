import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_access.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';
import 'package:mgk_run/src/features/profile/presentation/profile_screen.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// **IMG_4700, asserted.**
///
/// A floating bar does not reserve its own height, so the last row of a
/// scrolling tab is under it unless the surface pads for it. The first attempt
/// at this padded by injecting a fake `MediaQuery` bottom inset for the whole
/// subtree, which shortened the viewport a `SafeArea` was measuring rather than
/// the content inside it: Plan's last card was sliced and a black band appeared
/// above the bar.
///
/// The fix is a clearance constant applied at each scrolling surface. The thing
/// that makes it stay fixed is this test, at the shell — every screen looked
/// right on its own last time, because the fault was in the composition.
void main() {
  testWidgets('the oldest run in the log clears the floating chrome', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeShell(
          auth: FakeAuthRepository(signedIn: true, email: 'sam@example.com'),
          access: CoachAccess.subscribed,
          initialTab: 2,
          historySource: () async => <RunSummary>[
            for (var i = 1; i <= 12; i++)
              RunSummary(
                id: 'run-$i',
                startedAt: DateTime.now().subtract(Duration(days: i)),
                duration: const Duration(minutes: 30),
                // Distinct per run, so the last one can be found by its figure.
                distanceMeters: 5000 + i * 100,
                avgPaceSecondsPerKm: 360,
              ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The oldest run is the last row, and the one the bar would eat.
    final Finder oldest = find.text('6.20 km');
    // Scoped to Profile's own scrollable: all three tabs are in the
    // `IndexedStack`, so `find.byType(Scrollable).first` is Home's.
    await tester.scrollUntilVisible(
      oldest,
      300,
      scrollable: find
          .descendant(
            of: find.byType(ProfileScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    final Rect row = tester.getRect(oldest);
    final Rect pill = tester.getRect(find.byType(FloatingNavBar));

    expect(
      row.bottom,
      lessThanOrEqualTo(pill.top),
      reason: 'scrolled fully, the last row still sits above the pill',
    );
  });
}
