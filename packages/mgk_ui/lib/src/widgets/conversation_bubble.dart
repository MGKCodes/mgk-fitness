import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';

/// One thing said, by either side of a conversation with the coach.
///
/// Lives here rather than in an app because **both apps have a coach and Lift
/// alone had two conversations** — the coach screen and the plan intake — which
/// had already produced two copies of this widget, identical but for the type
/// of the turn they took and a comment one of them had lost.
///
/// Two rules are carried in the layout and are the reason this is a component
/// rather than a `Container` at each call site:
///
///  * **Never full width.** A bubble that reaches both margins stops reading as
///    one side of a conversation and starts reading as a paragraph.
///  * **The two sides differ in weight, not in colour.** There is no accent to
///    reach for (ADR-0009), so the coach speaks in `elevated` at full
///    contrast and the person in `surface` at secondary — which also puts the
///    emphasis on the reply rather than on your own words, since you already
///    know what you said.
class ConversationBubble extends StatelessWidget {
  const ConversationBubble({
    super.key,
    required this.text,
    required this.fromCoach,
    this.selectable = true,
  });

  final String text;

  /// Which side said it. Drives alignment, fill and contrast together — they
  /// are one decision, not three.
  final bool fromCoach;

  /// Whether the text can be selected. On by default: a coach's answer is
  /// something people copy out.
  final bool selectable;

  /// The share of the width a bubble may occupy.
  static const double _maxWidthFraction = 0.8;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: fromCoach ? AppColors.textPrimary : AppColors.textSecondary,
      height: 1.4,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Align(
        alignment: fromCoach ? Alignment.centerLeft : Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * _maxWidthFraction,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fromCoach ? AppColors.elevated : AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: selectable
                  ? SelectableText(text, style: style)
                  : Text(text, style: style),
            ),
          ),
        ),
      ),
    );
  }
}

/// The coach composing a reply.
///
/// Text rather than a spinner, on the coach's side of the conversation, so the
/// wait reads as somebody thinking rather than as the app working. A spinner
/// here would be the only indeterminate progress in the product.
class ThinkingIndicator extends StatelessWidget {
  const ThinkingIndicator({super.key, this.label = 'Thinking…'});

  final String label;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
      ),
    ),
  );
}
