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

/// A conversation that grows upward from the composer.
///
/// **Bottom-anchored, and that is the whole reason this exists.** A plain
/// `ListView` top-anchors, which leaves a two-line opener floating above a
/// screen of nothing — and `Spacer` cannot help inside one, because a
/// scrollable has no bounded main axis to distribute. The fix is a
/// `SingleChildScrollView` whose child is forced to at least viewport height
/// with its content pushed to the end.
///
/// It is a component rather than a paragraph of advice because the app that had
/// worked this out still shipped a second conversation without it: the coach
/// screen anchored correctly and the plan intake, written later, did not. A
/// behaviour that lives in one screen is a behaviour the next screen will miss.
class ConversationView extends StatelessWidget {
  const ConversationView({
    super.key,
    required this.children,
    this.controller,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  /// The turns, oldest first, plus anything trailing them — a thinking
  /// indicator, a failure note.
  final List<Widget> children;

  final ScrollController? controller;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) =>
        SingleChildScrollView(
          controller: controller,
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              // Clamped. A layout pass that reports no height makes this
              // negative, and a BoxConstraints with a negative minimum fails
              // an assertion that takes the whole route down — which is what
              // it did, at -12, the first time this was given a padding taller
              // than the height it was offered.
              //
              // Third instance of one mistake in this codebase: a measurement
              // of the screen used as a size before asking whether the screen
              // had been measured. The other two were a negative width in the
              // coach reveal and a clamp with an inverted range in the coach
              // sheet.
              minHeight: (constraints.maxHeight - padding.vertical).clamp(
                0.0,
                double.infinity,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
  );
}
