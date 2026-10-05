import 'package:flutter/material.dart';

import '../theme/app_radius.dart';
import 'coach_orb.dart';

/// The coach's orb on its own, on the coach's side, for a scripted beat.
///
/// Distinct from `ThinkingIndicator`, and both are right for different waits.
/// `ThinkingIndicator` puts "Thinking…" beside the orb and is for a real model
/// call, where the wait is unbounded and honesty about it matters. This one is
/// for a *scripted* beat — the intro conversation, where the coach's next line
/// is already written and the pause exists purely so the exchange reads as a
/// conversation rather than a form that printed itself.
///
/// Words for the scripted case would be the app claiming to think when it is
/// not. So: the orb alone for a beat, the orb and words for a wait.
///
/// It was three dots in a bubble until 4 October 2026, when the suite's coach
/// took the orb for every wait.
class TypingIndicator extends StatelessWidget {
  const TypingIndicator({super.key});

  @override
  Widget build(BuildContext context) => const Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.sm),
      child: CoachOrb(),
    ),
  );
}
