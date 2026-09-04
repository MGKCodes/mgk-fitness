import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/recording/presentation/run_start_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// **The tap that opens the screen used to start the clock.**
///
/// The recorder was built in the same `push` that opened the in-run screen, so
/// the first seconds of every run were spent getting a phone into a pocket and
/// were recorded as running — at whatever pace a pocket happens to be. The
/// build 12 field test asked for the separation directly.
///
/// What these assert is the *seam*: that nothing starts until the count-in
/// ends, and that the count can be abandoned. The pace consequences are a
/// device question and belong on the test sheet, not here.
void main() {
  Widget host({
    required VoidCallback onStart,
    VoidCallback? onCancel,
    PlannedSession? session,
    Duration countIn = const Duration(seconds: 3),
  }) => MaterialApp(
    theme: AppTheme.dark,
    home: RunStartScreen(
      onStart: onStart,
      onCancel: onCancel,
      plannedSession: session,
      countIn: countIn,
    ),
  );

  testWidgets('nothing starts until the count-in has finished', (tester) async {
    var started = 0;
    await tester.pumpWidget(host(onStart: () => started++));
    await tester.pump();

    expect(find.text('Start'), findsOneWidget);
    expect(started, 0, reason: 'opening the screen must not start a run');

    await tester.tap(find.text('Start'));
    await tester.pump();

    // The count is on screen and the run has still not begun.
    expect(find.text('3'), findsOneWidget);
    expect(started, 0);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('2'), findsOneWidget);
    expect(started, 0);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1'), findsOneWidget);
    expect(started, 0, reason: 'one second left is still not running');

    await tester.pump(const Duration(seconds: 1));
    expect(started, 1, reason: 'the run begins when the count reaches zero');
  });

  testWidgets('the count can be stopped, and stopping starts nothing', (
    tester,
  ) async {
    var started = 0;
    await tester.pumpWidget(host(onStart: () => started++));
    await tester.pump();

    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(find.text('3'), findsOneWidget);

    // Three seconds is long enough to change your mind, and a count nobody can
    // stop is a countdown to something being done *to* them.
    await tester.tap(find.text('Stop'));
    await tester.pump();

    expect(find.text('Start'), findsOneWidget);

    // Well past where the count would have fired.
    await tester.pump(const Duration(seconds: 5));
    expect(started, 0);
  });

  testWidgets('backing out is offered before the count and not during it', (
    tester,
  ) async {
    var cancelled = 0;
    await tester.pumpWidget(host(onStart: () {}, onCancel: () => cancelled++));
    await tester.pump();

    // The one button on the screen before the count starts. `byTooltip` would
    // match the Tooltip, which `IconButton` builds *inside* itself — so it is
    // the ancestor, not the descendant, and reaching for it that way finds
    // nothing.
    final close = find.byType(IconButton);
    expect(
      tester.widget<IconButton>(close).onPressed,
      isNotNull,
      reason: 'a runner who opened this by mistake must be able to leave',
    );

    await tester.tap(find.text('Start'));
    await tester.pump();

    // Disabled mid-count, because Stop is the control that means "not yet" and
    // two ways out of a three-second state is one too many.
    expect(tester.widget<IconButton>(close).onPressed, isNull);
    expect(cancelled, 0);
  });

  testWidgets(
    "today's session is named before setting off, when there is one",
    (tester) async {
      await tester.pumpWidget(
        host(
          onStart: () {},
          session: const PlannedSession(
            weekday: DateTime.monday,
            kind: SessionKind.easy,
            distanceMeters: 5000,
          ),
        ),
      );
      await tester.pump();

      // Read here rather than discovered on the in-run panel at 400 metres.
      expect(find.textContaining('5'), findsWidgets);
    },
  );

  testWidgets('a zero-length count starts immediately rather than hanging', (
    tester,
  ) async {
    // A legitimate configuration, and it must not leave the screen showing a
    // number that never counts down.
    var started = 0;
    await tester.pumpWidget(
      host(onStart: () => started++, countIn: Duration.zero),
    );
    await tester.pump();

    await tester.tap(find.text('Start'));
    await tester.pump();

    expect(started, 1);
  });
}
