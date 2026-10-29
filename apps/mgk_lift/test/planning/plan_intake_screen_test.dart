import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_lift/src/features/planning/domain/coach_planner.dart';
import 'package:mgk_lift/src/features/planning/domain/intake_flow.dart';
import 'package:mgk_lift/src/features/planning/domain/plan_intake.dart';
import 'package:mgk_lift/src/features/planning/domain/plan_builder.dart';
import 'package:mgk_lift/src/features/planning/domain/plan_proposal.dart';
import 'package:mgk_lift/src/features/planning/presentation/plan_intake_screen.dart';
import 'package:mgk_lift/src/features/tracking/domain/session.dart';

/// A planner that extracts whatever it is told to, so a test can drive the
/// flow one field at a time instead of asserting against a fixed transcript.
class _Planner implements CoachPlanner {
  _Planner({this.extract = const PlanIntake(), this.reply = 'Noted.'});

  final PlanIntake extract;
  final String reply;

  @override
  Future<IntakeTurn> intake({
    required IntakeProgress progress,
    required List<PlannerTurn> history,
  }) async => IntakeTurn(reply: reply, extracted: extract);

  @override
  Future<PlanProposal> plan({
    required PlanIntake intake,
    required List<int> weekdays,
    required List<String> catalogue,
    List<String> violations = const <String>[],
  }) => throw UnimplementedError();

  @override
  Future<SwapProposal> swap({
    required String message,
    required Session session,
  }) => throw UnimplementedError();
}

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('the options under the newest question', () {
    testWidgets('offer the field the flow is still missing', (tester) async {
      await tester.pumpWidget(
        wrap(
          PlanIntakeScreen(
            planner: _Planner(),
            opener: IntakeField.days.question,
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final o in IntakeField.days.options) {
        expect(find.text(o), findsOneWidget);
      }
    });

    testWidgets('follow what is answered, not what comes next in a list', (
      tester,
    ) async {
      // Somebody who says "4 days, home gym" in one sentence is asked about
      // injuries next, not equipment - the whole reason the flow returns the
      // first MISSING field rather than the next in a script.
      await tester.pumpWidget(
        wrap(
          PlanIntakeScreen(
            planner: _Planner(
              extract: const PlanIntake(
                daysPerWeek: 4,
                equipment: 'Home, with weights',
              ),
            ),
            opener: IntakeField.days.question,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('4 days'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing to work around'), findsOneWidget);
      expect(find.text('A full gym'), findsNothing);
    });

    testWidgets('are gone while the lifter has spoken last', (tester) async {
      // Options hanging under somebody's own message offer to answer a
      // question that has not been asked yet.
      await tester.pumpWidget(
        wrap(
          PlanIntakeScreen(
            planner: _Planner(reply: ''),
            opener: IntakeField.days.question,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('4 days'));
      await tester.pumpAndSettle();

      expect(find.byType(OptionStack), findsNothing);
    });

    testWidgets('a tapped option is sent verbatim', (tester) async {
      // The transcript is what the coach reads back, so it has to say what was
      // offered rather than a paraphrase of it. The planner extracts the
      // answer here so the options move on to the next field — left
      // unlearned, the same row would still be offered and the text would be
      // on screen twice for a reason that is not this one.
      await tester.pumpWidget(
        wrap(
          PlanIntakeScreen(
            planner: _Planner(extract: const PlanIntake(daysPerWeek: 5)),
            opener: IntakeField.days.question,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('5 or more'));
      await tester.pumpAndSettle();

      expect(find.text('5 or more'), findsOneWidget);
    });
  });

  group('skipping', () {
    testWidgets('a declined field is not asked again', (tester) async {
      // The coach extracts nothing from "prefer not to say", so without the
      // local decline the same question would come straight back.
      await tester.pumpWidget(
        wrap(
          PlanIntakeScreen(
            planner: _Planner(),
            initialKnown: const IntakeProgress(
              plan: PlanIntake(daysPerWeek: 4, injuryNotes: 'none'),
            ),
            opener: IntakeField.equipment.question,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Prefer not to say'));
      await tester.pumpAndSettle();

      // The question stays in the scrollback, because it was asked. What must
      // not happen is being asked it a second time: the options move on to the
      // goal, which is what is genuinely still missing.
      expect(find.text(IntakeField.equipment.question), findsOneWidget);
      for (final o in IntakeField.goal.options) {
        expect(find.text(o), findsOneWidget);
      }
    });

    testWidgets('days offers no way out, because a plan needs it', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          PlanIntakeScreen(
            planner: _Planner(),
            opener: IntakeField.days.question,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Prefer not to say'), findsNothing);
    });
  });

  group('the button', () {
    testWidgets('is absent while anything is still unknown', (tester) async {
      await tester.pumpWidget(
        wrap(
          PlanIntakeScreen(
            planner: _Planner(),
            opener: IntakeField.days.question,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Build my plan'), findsNothing);
    });

    testWidgets('appears the moment nothing is left to ask', (tester) async {
      // Not when the coach decides the conversation is over: somebody who has
      // answered enough should not have to keep chatting to get out.
      await tester.pumpWidget(
        wrap(
          PlanIntakeScreen(
            planner: _Planner(),
            initialKnown: const IntakeProgress(
              plan: PlanIntake(
                daysPerWeek: 4,
                equipment: 'A full gym',
                injuryNotes: 'none',
                goal: 'Get stronger',
              ),
            ),
            opener: 'That is everything I need.',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Build my plan'), findsOneWidget);
      expect(find.byType(OptionStack), findsNothing);
    });

    testWidgets('does not wait on weekdays the shell already defaults', (
      tester,
    ) async {
      // PlanIntake.missing still names "which weekdays" for the coach to
      // extract from prose, and LiftShell._buildPlan defaults it when it is
      // absent. Gating the button on it as well, as PlanIntake.isComplete did,
      // left a lifter with a full progress bar and no way forward.
      await tester.pumpWidget(
        wrap(
          PlanIntakeScreen(
            planner: _Planner(),
            initialKnown: const IntakeProgress(
              plan: PlanIntake(
                daysPerWeek: 3,
                equipment: 'Bodyweight only',
                injuryNotes: 'none',
                goal: 'Build muscle',
              ),
            ),
            opener: 'Ready.',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Build my plan'), findsOneWidget);
    });
  });

  group('the bar', () {
    testWidgets('counts answers rather than position', (tester) async {
      await tester.pumpWidget(
        wrap(
          PlanIntakeScreen(
            planner: _Planner(),
            initialKnown: const IntakeProgress(
              plan: PlanIntake(daysPerWeek: 4, equipment: 'A full gym'),
            ),
            opener: IntakeField.injuries.question,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bar = tester.widget<StepProgress>(find.byType(StepProgress));
      expect(bar.step, 2);
      expect(bar.total, IntakeField.values.length);
    });
  });
}
