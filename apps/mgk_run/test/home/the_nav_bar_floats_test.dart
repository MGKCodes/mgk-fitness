import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/features/coaching/data/coach_client.dart';
import 'package:mgk_run/src/features/coaching/presentation/coach_reveal.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_access.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// **The bottom chrome floats now** (ADR-0033), and this is the assertion that
/// would have caught what happened last time.
///
/// A floating bar stops reserving its own height, so every scrolling surface
/// has to pad its own foot. The shortcut is to inject fake `MediaQuery` bottom
/// padding for the subtree and change nothing else — which was tried, and
/// shortened the viewport a `SafeArea` was measuring rather than the content
/// inside it: Plan's last card was sliced and a black band appeared above the
/// bar. Asserted at the shell rather than per screen, because the failure was
/// the *composition* and each screen looked right on its own.
void main() {
  List<RunSummary> runs() => <RunSummary>[
    for (var i = 1; i <= 12; i++)
      RunSummary(
        id: 'run-$i',
        startedAt: DateTime.now().subtract(Duration(days: i)),
        duration: const Duration(minutes: 30),
        distanceMeters: 5000 + i * 100,
        avgPaceSecondsPerKm: 360,
      ),
  ];

  Future<void> pumpShell(WidgetTester tester, {int tab = 0}) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeShell(
          auth: FakeAuthRepository(signedIn: true, email: 'sam@example.com'),
          access: CoachAccess.subscribed,
          historySource: () async => runs(),
          initialTab: tab,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('it really did leave the Scaffold slot', (tester) async {
    await pumpShell(tester);

    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).bottomNavigationBar,
      isNull,
      reason: 'still in the slot means it still reserves height',
    );
    expect(find.byType(FloatingNavBar), findsOneWidget);
  });

  testWidgets('every label is on screen and hittable', (tester) async {
    await pumpShell(tester);

    for (final label in <String>['Home', 'Plan', 'Profile']) {
      expect(find.text(label).hitTestable(), findsOneWidget, reason: label);
    }
  });

  testWidgets('and tapping one changes tab', (tester) async {
    await pumpShell(tester);

    // Asserted on the bar's own selection rather than on a widget from the
    // tab: the three tabs live in an `IndexedStack`, so all of them are in the
    // tree at all times and finding one proves nothing about which is showing.
    int selected() => tester
        .widget<FloatingNavBar>(find.byType(FloatingNavBar))
        .selectedIndex;

    expect(selected(), 0);

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(selected(), 2);

    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    expect(selected(), 1);
  });

  testWidgets('the coach mark clears the pill rather than sharing its band', (
    tester,
  ) async {
    // Both are full width in Run — the reveal expands to deliver a note as
    // prose, so it cannot be right-aligned the way Lift's mark is. Two
    // full-width things at the same `bottom` would sit on top of one another.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeShell(
          auth: FakeAuthRepository(signedIn: true, email: 'sam@example.com'),
          access: CoachAccess.subscribed,
          historySource: () async => runs(),
          chatClient: _SilentChat(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final Rect pill = tester.getRect(find.byType(FloatingNavBar));
    final Rect mark = tester.getRect(find.byType(CoachReveal));
    expect(
      mark.bottom,
      lessThanOrEqualTo(pill.top),
      reason: 'the mark sits above the pill, not over it',
    );
  });
}

class _SilentChat implements CoachChatClient {
  @override
  Future<ChatTurn> chat({
    required String brief,
    required List<ChatMessage> history,
    required String message,
  }) async => const ChatTurn(reply: '');
}
