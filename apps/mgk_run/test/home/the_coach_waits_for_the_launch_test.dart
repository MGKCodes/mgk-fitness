import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/preview/fake_coach_service.dart';
import 'package:mgk_run/src/core/launch/launch_curtain.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// **The coach said its line behind the launch animation.**
///
/// Home's coach speaks when the shell loads, and since build 28 the shell
/// loads under a curtain that is up for two seconds. The line took 3.4 in all,
/// so what a runner saw was its last second: open already, typed already, and
/// closing. Reported as "the coach animation on open happens too fast to read
/// anything ... it kind of just happens and you can't really tell what it is".
///
/// It waits for the launch to finish, opens out of the mark, and is held for
/// about five seconds before it closes back.
void main() {
  Future<void> pumpApp(WidgetTester tester, {bool launch = true}) async {
    await tester.binding.setSurfaceSize(const Size(420, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        builder: (context, child) =>
            LaunchCurtain(enabled: launch, child: child!),
        home: HomeShell(
          auth: FakeAuthRepository(signedIn: true, email: 'runner@example.com'),
          historySource: () async => const [],
          // A coach to have a mark for. Not subscribed, so the line is the
          // locked one, which needs no run log to have something to say.
          chatClient: FakeCoachService(),
        ),
      ),
    );
  }

  double bar(WidgetTester tester) =>
      tester.getSize(find.byType(CoachMarkSurface)).width;
  final line = find.text(CoachReveal.lockedNote.headline);

  testWidgets('it says nothing while the launch is over the screen', (
    tester,
  ) async {
    await pumpApp(tester);

    // Well past where the shell has loaded, and the curtain still up.
    await tester.pump(const Duration(milliseconds: 1500));
    expect(bar(tester), kCoachMarkSize, reason: 'the mark, at rest');

    // The curtain is gone but the app is still settling.
    await tester.pump(const Duration(milliseconds: 500));
    expect(bar(tester), kCoachMarkSize);
    await tester.pumpAndSettle();
  });

  testWidgets('then opens, is held long enough to read, and closes', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.pump(kLaunchDuration + const Duration(milliseconds: 50));
    await tester.pump();

    // Opening out of the mark.
    await tester.pump(const Duration(milliseconds: 230));
    expect(bar(tester), greaterThan(kCoachMarkSize));

    // Open, with the line on it.
    await tester.pump(CoachReveal.openFor);
    final double open = bar(tester);
    expect(open, greaterThan(300));
    expect(line, findsOneWidget);

    // Four seconds on it is still there to be read. At the old length it had
    // closed two seconds ago.
    await tester.pump(const Duration(seconds: 4));
    expect(bar(tester), open);
    expect(line, findsOneWidget);

    // And it goes back to being the mark.
    await tester.pumpAndSettle();
    expect(bar(tester), kCoachMarkSize);
  });

  testWidgets('with no launch to wait for it speaks at once', (tester) async {
    await pumpApp(tester, launch: false);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(CoachReveal.openFor);
    await tester.pump(const Duration(milliseconds: 300));

    expect(bar(tester), greaterThan(300));
    await tester.pumpAndSettle();
  });
}
