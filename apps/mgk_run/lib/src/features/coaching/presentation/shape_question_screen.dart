import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import '../domain/plan_shape.dart';
import '../domain/shape_question.dart';
import 'scripted_conversation.dart';

/// "What are you after?" — the first step of the plan flow.
///
/// Scripted, not a model turn, for the same reason the intro is: five chips
/// cannot be answered wrong, so there is nothing here for a model to
/// understand. What it buys is that the LLM intake on the next screen opens
/// already knowing the shape, and spends its turns on the questions that
/// genuinely need language (ADR-0011, ADR-0018).
///
/// It used to be the second question of the pre-account intro. It sits here now
/// because the answer only matters to a runner who is getting a plan
/// (ADR-0019), and asking it one screen before the intake that consumes it
/// means nothing has to survive a widget swap to get there.
class ShapeQuestionScreen extends StatelessWidget {
  const ShapeQuestionScreen({
    super.key,
    required this.onChosen,
    this.name,
    this.onBack,
  });

  /// Called with the chosen shape. **Null is a real answer** — "I'm not sure
  /// yet" — and is passed through rather than defaulted, so the coach resolves
  /// it on its first turn instead of the screen guessing.
  final void Function(PlanShape? shape) onChosen;

  /// What the coach calls them, from the intro. Null is fine; the question just
  /// loses the name.
  final String? name;

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your coach'),
        leading: onBack == null ? null : BackButton(onPressed: onBack),
      ),
      // Bottom-aligned for the same reason the intro is: a question and five
      // chips do not fill a phone, and top-anchoring them left the answers
      // stranded mid-screen with a void underneath. Here the chips are also the
      // only affordance — there is no button below them — so sitting them at
      // the foot puts the thing being tapped where the thumb already is.
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight:
                    constraints.maxHeight - AppSpacing.lg - AppSpacing.xl,
              ),
              // Arrives, rather than being painted in one frame — but does
              // not make anybody wait.
              //
              // SequencedReveal was tried here first, to match how the coach
              // speaks on the intro screen, and it is the wrong instrument. The
              // intro is a monologue somebody reads; this is a question they
              // have to answer, and holding its four answers back behind a
              // timed beat is friction dressed as pacing. Entrance staggers the
              // arrival and gates nothing.
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Entrance(child: Said(shapeQuestion(name: name))),
                  const SizedBox(height: AppSpacing.md),
                  for (final (i, option) in shapeOptions.indexed)
                    Entrance(
                      index: i + 1,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: ChoiceCard(
                          label: option.label,
                          detail: option.detail,
                          onTap: () => onChosen(option.shape),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
