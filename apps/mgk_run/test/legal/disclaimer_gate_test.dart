import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/presentation/coach_button.dart';
import 'package:mgk_run/src/features/coaching/data/coach_client.dart';
import 'package:mgk_run/src/features/coaching/domain/intake_conversation.dart';
import 'package:mgk_run/src/features/coaching/domain/intake_slots.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:mgk_run/src/features/coaching/presentation/coach_flow.dart';
import 'package:mgk_run/src/features/legal/domain/disclaimer_store.dart';

/// The flow builds its own plan now, so a test has to give it something to
/// build (ADR-0019). These suites never reach the reveal; this exists to
/// satisfy the constructor.
Future<StoredPlan> _aPlan(RunnerProfile profile) async => StoredPlan(
  id: 'plan-1',
  profile: profile,
  skeleton: buildSkeleton(profile, now: DateTime(2026, 7, 25)),
  startDate: mondayOf(DateTime(2026, 7, 25)),
);

/// Greets instantly so the conversation is reachable without timers.
class _InstantCoach implements CoachClient {
  int calls = 0;

  @override
  Future<IntakeTurn> intake({
    required IntakeSlots slots,
    required List<IntakeMessage> history,
  }) async {
    calls++;
    return const IntakeTurn(
      reply: 'Hi, what are you training for?',
      extracted: IntakeSlots(),
    );
  }
}

/// A store whose reads fail, standing in for a broken or unavailable backing
/// store. The contract says such a store reports "not acknowledged".
class _BrokenStore implements DisclaimerStore {
  @override
  Future<bool> isAcknowledged() async => false;

  @override
  Future<void> acknowledge() async {}
}

void main() {
  /// Pushes [CoachFlow] over a host route, so popping the flow is observable.
  Future<_InstantCoach> openFlow(
    WidgetTester tester, {
    required DisclaimerStore store,
    void Function()? onPop,
  }) async {
    final coach = _InstantCoach();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CoachFlow(
                        buildPlan: _aPlan,
                        coach: coach,
                        now: () => DateTime(2026, 7, 26),
                        disclaimer: store,
                      ),
                    ),
                  );
                  onPop?.call();
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(); // push the route
    await tester.pump(); // the store read resolves
    await tester.pump(const Duration(milliseconds: 50)); // greeting, if reached
    return coach;
  }

  group('the disclaimer gates the coach flow', () {
    testWidgets('a first-time runner sees the disclaimer, not the coach', (
      tester,
    ) async {
      final coach = await openFlow(tester, store: InMemoryDisclaimerStore());

      expect(find.text('Before we start'), findsOneWidget);
      expect(find.text('I understand'), findsOneWidget);
      // The load-bearing sentences are on screen.
      expect(find.textContaining('is not medical advice'), findsOneWidget);
      expect(find.textContaining('Consult a physician'), findsOneWidget);
      expect(
        find.textContaining('Stop and seek medical attention'),
        findsOneWidget,
      );

      // Nothing downstream has started: no conversation, and the coach has not
      // even been asked to greet.
      expect(find.byType(CoachButton), findsNothing);
      expect(coach.calls, 0);
    });

    testWidgets('accepting records it and lets the conversation start', (
      tester,
    ) async {
      final store = InMemoryDisclaimerStore();
      final coach = await openFlow(tester, store: store);

      await tester.tap(find.text('I understand'));
      await tester.pumpAndSettle();

      expect(await store.isAcknowledged(), isTrue);
      expect(store.acknowledgeCount, 1);
      expect(find.text('Your coach'), findsOneWidget);

      // The shape question comes between the gate and the conversation now
      // (ADR-0019), and it is scripted — so accepting the disclaimer still
      // spends nothing. The model is not asked to say a word until the runner
      // has told it what they are after.
      expect(coach.calls, 0);

      await tester.tap(find.text('I have a race coming up'));
      await tester.pumpAndSettle();
      expect(coach.calls, 1);
    });

    testWidgets('declining exits the flow without generating anything', (
      tester,
    ) async {
      final store = InMemoryDisclaimerStore();
      var popped = false;
      final coach = await openFlow(
        tester,
        store: store,
        onPop: () => popped = true,
      );

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(popped, isTrue);
      expect(coach.calls, 0);
      // Backing out is not consent.
      expect(await store.isAcknowledged(), isFalse);
    });

    testWidgets('a system back at the gate also exits the flow', (
      tester,
    ) async {
      var popped = false;
      await openFlow(
        tester,
        store: InMemoryDisclaimerStore(),
        onPop: () => popped = true,
      );

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      await navigator.maybePop();
      await tester.pumpAndSettle();

      expect(popped, isTrue);
    });
  });

  group('acknowledgement persists', () {
    testWidgets('an acknowledged runner goes straight to the coach', (
      tester,
    ) async {
      final coach = await openFlow(
        tester,
        store: InMemoryDisclaimerStore(acknowledged: true),
      );

      expect(find.text('Your coach'), findsOneWidget);
      expect(find.text('Before we start'), findsNothing);
      expect(find.text('I understand'), findsNothing);

      // Straight past the gate to the flow's first step, which is the shape
      // question. Still nothing spent until they answer it.
      expect(coach.calls, 0);
      await tester.tap(find.text('I have a race coming up'));
      await tester.pumpAndSettle();
      expect(coach.calls, 1);
    });

    testWidgets('the gate does not reappear on a later visit to the flow', (
      tester,
    ) async {
      // One store across two mounts — the same store a real install keeps.
      final store = InMemoryDisclaimerStore();

      await openFlow(tester, store: store);
      expect(find.text('Before we start'), findsOneWidget);
      await tester.tap(find.text('I understand'));
      await tester.pumpAndSettle();
      expect(find.text('Your coach'), findsOneWidget);

      // Leave the flow and come back, as returning to the Plan tab would.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Before we start'), findsNothing);
      expect(find.text('Your coach'), findsOneWidget);
      // Accepted once, recorded once.
      expect(store.acknowledgeCount, 1);
    });
  });

  testWidgets('a store that cannot be read shows the gate again', (
    tester,
  ) async {
    // Fail-safe: an unreadable store must never be taken as consent.
    final coach = await openFlow(tester, store: _BrokenStore());

    expect(find.text('Before we start'), findsOneWidget);
    expect(coach.calls, 0);
  });
}
