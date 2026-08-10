import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/data/coach_service.dart';
import 'package:mgk_run/src/features/coaching/presentation/plan_reveal_screen.dart';

/// The reveal blocks the back gesture for the whole of its build, on purpose —
/// there is nothing behind it to return to. That makes its failure state the
/// only way off the screen, so the failure state has to be reachable and it has
/// to offer an exit.
///
/// The gap these close: nothing on the coach path had a request deadline, so a
/// provider that accepted the connection and then went quiet never produced a
/// throw, never reached the failure state, and left the runner on a screen with
/// `canPop: false` and no button. Force-quitting the app was the only way out.
void main() {
  Widget host(Widget child) => MaterialApp(theme: AppTheme.dark, home: child);

  testWidgets('a failed build offers a way out', (WidgetTester tester) async {
    StoredPlan? doneWith;
    var doneCalled = false;

    await tester.pumpWidget(
      host(
        PlanRevealScreen(
          build: () async => throw const CoachException('upstream is quiet'),
          onDone: (StoredPlan? plan) {
            doneCalled = true;
            doneWith = plan;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    // Null rather than a plan: they left without one, and the flow above has to
    // be able to tell those apart.
    expect(doneCalled, isTrue);
    expect(doneWith, isNull);
  });

  testWidgets('the wait state has no exit, which is why the timeout matters', (
    WidgetTester tester,
  ) async {
    // Never completes — a hung provider, before there was a deadline.
    final Completer<StoredPlan> hung = Completer<StoredPlan>();

    await tester.pumpWidget(
      host(PlanRevealScreen(build: () => hung.future, onDone: (_) {})),
    );
    await tester.pump();

    // Documents the trap rather than asserting it is fine: while building there
    // is no button, and the route refuses to pop. The only thing that ends this
    // state is the future completing, which is the service's job.
    expect(find.text('Try again'), findsNothing);
    expect(find.text('Not now'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    final PopScope<void> scope = tester.widget(find.byType(PopScope<void>));
    expect(scope.canPop, isFalse);
  });

  test('the client deadline is longer than the function\'s own', () {
    // The function aborts upstream at 75s so it can answer with a 502 the app
    // can name and account for. If the app gave up first it would show a
    // generic failure and the call would go unrecorded.
    expect(
      CoachService.requestTimeout,
      greaterThan(const Duration(seconds: 75)),
    );
  });
}
