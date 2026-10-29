/// The coach speaking in a **scripted** exchange, the first time an app opens.
///
/// Lives here because both apps open on one now. Run's intro has drawn its
/// lines this way since August, as `Said` in `mgk_run`'s
/// `scripted_conversation.dart`, and Lift's first open (29 October 2026,
/// Lift's ADR-0005) is Run's pattern in Lift's words: the two apps are meant to
/// arrive the same way, so the look was lifted here rather than copied into a
/// second app, where it would drift.
///
/// **Added, not moved.** Run still draws its own `Said` and `CoachMark`, which
/// these match line for line. Pointing Run at these is a change to Run, and is
/// left for a commit that redraws Run's arrival plates to prove nothing moved.
///
/// Distinct from [ConversationBubble], which is a conversation the model is
/// holding: a filled bubble with a corner tucked in. These read as the coach
/// speaking directly, before there is anything to reply to: no fill, the mark
/// to the left.
library;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import 'coach_mark.dart';

/// One thing the coach said, in a script.
class ScriptedLine extends StatelessWidget {
  const ScriptedLine(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(width: 30, child: CoachAvatar()),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textPrimary,
              height: 1.45,
              fontSize: 15,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The coach's small round C, beside a line it said.
///
/// The same letter as the floating mark ([CoachButton]) and set the same way
/// ([CoachLetter]), so the coach has one mark at every size: the coach is
/// called Coach, and the C is its name rather than a picture of a chatbot.
class CoachAvatar extends StatelessWidget {
  const CoachAvatar({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.primary.withValues(alpha: 0.16),
      shape: BoxShape.circle,
    ),
    child: const CoachLetter(size: 12),
  );
}
