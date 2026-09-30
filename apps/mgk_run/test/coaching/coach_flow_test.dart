import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/data/coach_client.dart';
import 'package:mgk_run/src/features/coaching/data/plan_store.dart';
import 'package:mgk_run/src/features/coaching/domain/intake_conversation.dart';
import 'package:mgk_run/src/features/coaching/domain/intake_slots.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_validator.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:mgk_run/src/features/coaching/presentation/coach_flow.dart';
import 'package:mgk_run/src/features/legal/domain/disclaimer_store.dart';

/// Greets instantly, then completes on the first answer — enough to reach the
/// confirmation step without timers.
class _InstantCoach implements CoachClient {
  int _n = 0;

  @override
  Future<IntakeTurn> intake({
    required IntakeSlots slots,
    required List<IntakeMessage> history,
  }) async {
    _n++;
    if (_n == 1) {
      return const IntakeTurn(
        reply: 'Hi, what are you training for?',
        extracted: IntakeSlots(),
      );
    }
    return IntakeTurn(
      reply: "That's everything.",
      extracted: IntakeSlots(
        goalDistanceMeters: 42000,
        eventDate: DateTime(2026, 11, 1),
        currentWeeklyMeters: 40000,
        longestRecentMeters: 18000,
        daysPerWeek: 5,
        availableWeekdays: const <int>{1, 2, 4, 6, 7},
        timeTrialDistanceMeters: 5000,
        timeTrialDuration: const Duration(minutes: 22),
      ),
    );
  }
}

void main() {
  final now = DateTime(2026, 7, 25);

  /// What the flow builds at the end. The flow owns plan creation now, so a
  /// test has to supply something for it to create (ADR-0019).
  Future<StoredPlan> aPlan(RunnerProfile profile) async => StoredPlan(
    id: 'plan-1',
    profile: profile,
    skeleton: buildSkeleton(profile, now: now),
    startDate: mondayOf(now),
  );

  Future<void> openFlow(
    WidgetTester tester, {
    required void Function() onPop,
    Future<StoredPlan> Function(RunnerProfile)? buildPlan,
  }) async {
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
                        coach: _InstantCoach(),
                        buildPlan: buildPlan ?? aPlan,
                        now: () => now,
                        // These tests are about navigation between the
                        // conversation and the confirmation. The medical
                        // disclaimer gate that precedes both has its own suite
                        // (test/legal/disclaimer_gate_test.dart), so start past
                        // it.
                        disclaimer: InMemoryDisclaimerStore(acknowledged: true),
                      ),
                    ),
                  );
                  onPop();
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(); // push route
    await tester.pump(); // the disclaimer store read resolves

    // The shape question is the first step of the flow now (ADR-0019), and it
    // is what builds the controller the conversation runs on. A block, to match
    // what `_InstantCoach` extracts. These tests are about everything behind
    // this screen, so walk straight through it.
    await tester.tap(find.text('I have a race coming up'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50)); // greeting resolves
  }

  testWidgets('starts on the conversation with a working close', (
    tester,
  ) async {
    var popped = false;
    await openFlow(tester, onPop: () => popped = true);

    expect(find.text('Your coach'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(popped, isTrue); // closing exits the whole flow
  });

  testWidgets('review moves to confirmation; back returns to the chat', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openFlow(tester, onPop: () {});

    // One answer completes the (instant) conversation.
    await tester.enterText(find.byType(TextField).first, '5k in 22');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Review details'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm your details'), findsOneWidget);

    // Back returns to the conversation, not out of the flow.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Your coach'), findsOneWidget);
    expect(find.text('Review details'), findsOneWidget); // chat still complete
  });

  /// The flow used to pop the profile the moment the runner confirmed, and the
  /// tab underneath built the plan behind its own spinner. Four questions about
  /// yourself ended with a screen vanishing, and the plan turned up afterwards
  /// somewhere else, unannounced (ADR-0019).
  group('the flow does not end before the plan does', () {
    /// Walks to the confirmation and confirms.
    Future<void> toReveal(WidgetTester tester) async {
      await tester.enterText(find.byType(TextField).first, '5k in 22');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Review details'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Build my plan'));
      await tester.pump();
    }

    testWidgets('confirming reveals the plan rather than popping', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var popped = false;
      await openFlow(tester, onPop: () => popped = true);

      await toReveal(tester);
      // The wait is owned by the flow and says what it is doing.
      expect(find.textContaining('put your weeks together'), findsOneWidget);
      expect(popped, isFalse, reason: 'the flow has not finished yet');

      await tester.pumpAndSettle();
      expect(find.text('Here it is.'), findsOneWidget);
      expect(find.text('See my week'), findsOneWidget);
      expect(popped, isFalse, reason: 'it ends when the runner says so');

      await tester.tap(find.text('See my week'));
      await tester.pumpAndSettle();
      expect(popped, isTrue);
    });

    testWidgets('a block is shown the shape it just earned', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await openFlow(tester, onPop: () {});

      await toReveal(tester);
      await tester.pumpAndSettle();

      // Computed off the skeleton, never generated prose: this is the moment a
      // runner decides whether to trust the thing (ADR-0003).
      expect(find.text('THE SHAPE OF IT'), findsOneWidget);
      expect(find.text('Length'), findsOneWidget);
      expect(find.text('Biggest week'), findsOneWidget);
      expect(find.text('Longest run'), findsOneWidget);
    });

    testWidgets('and a build that fails is not a dead end', (tester) async {
      // The conversation is spent by this point. Dropping the runner back to
      // the tab with nothing would mean answering it all again.
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var attempts = 0;
      await openFlow(
        tester,
        onPop: () {},
        buildPlan: (profile) async {
          attempts++;
          if (attempts == 1) throw Exception('the coach could not be reached');
          return aPlan(profile);
        },
      );

      await toReveal(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('did not work'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(attempts, 2, reason: 'retry rebuilds from the profile it kept');
      expect(find.text('Here it is.'), findsOneWidget);
    });

    testWidgets('a build the validator refuses goes back to the details', (
      tester,
    ) async {
      // Screen board G7. Retrying the same details can only be refused the
      // same way, so the way on is the details, with what was confirmed still
      // in them.
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await openFlow(
        tester,
        onPop: () {},
        buildPlan: (profile) async =>
            throw PlanRejectedException(const <Violation>[
              Violation(
                'race_day_outside_final_week',
                'race day falls in week 3',
              ),
            ]),
      );

      await toReveal(tester);
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsNothing);

      await tester.tap(find.text('Change the race'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm your details'), findsOneWidget);
      expect(find.text('1 Nov 2026'), findsOneWidget);
      expect(find.text('40.0'), findsOneWidget);
    });
  });
}
