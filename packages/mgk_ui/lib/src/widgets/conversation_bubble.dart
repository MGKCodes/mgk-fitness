import 'package:flutter/material.dart';

import '../motion/coach_orb.dart';
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
///
/// **One bubble for both apps' coaches** since 5 October 2026: Lift's, which
/// the owner preferred, with the corner nearest the speaker tucked in, and
/// with what Run's replies had that Lift's did not — a long press to report a
/// reply ([onReport]) and the line that says it was ([note]). Anything a reply
/// carries, such as a proposed change to the week, goes under the bubble, not
/// inside it: a card inside a bubble is two containers deep before any
/// content.
class ConversationBubble extends StatelessWidget {
  const ConversationBubble({
    super.key,
    required this.text,
    required this.fromCoach,
    this.selectable = true,
    this.onReport,
    this.note,
  });

  final String text;

  /// Which side said it. Drives alignment, fill and contrast together — they
  /// are one decision, not three.
  final bool fromCoach;

  /// Whether the text can be selected. On by default: a coach's answer is
  /// something people copy out. Off wherever [onReport] is given, because
  /// selection takes the long press the report needs.
  final bool selectable;

  /// Opens the report sheet for a coach's reply, on a long press. A model
  /// wrote it, and Play's policy on AI-generated content wants it reportable
  /// where it is read. Null offers nothing.
  final VoidCallback? onReport;

  /// A small line under the bubble: "Reported. Thanks, we'll take a look."
  final String? note;

  /// The share of the width a bubble may occupy.
  static const double _maxWidthFraction = 0.8;

  static const Radius _round = Radius.circular(AppRadius.card);
  static const Radius _tucked = Radius.circular(AppSpacing.xs + 2);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: fromCoach ? AppColors.textPrimary : AppColors.textSecondary,
      height: 1.4,
    );
    final report = fromCoach ? onReport : null;
    final words = selectable && report == null
        ? SelectableText(text, style: style)
        : Text(text, style: style);

    Widget bubble = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * _maxWidthFraction,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fromCoach ? AppColors.elevated : AppColors.surface,
          // The corner nearest the speaker tucked in: which side said it,
          // readable at a glance down a long conversation.
          borderRadius: BorderRadius.only(
            topLeft: _round,
            topRight: _round,
            bottomLeft: fromCoach ? _tucked : _round,
            bottomRight: fromCoach ? _round : _tucked,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: words,
        ),
      ),
    );
    if (report != null) {
      bubble = Semantics(
        onLongPressHint: 'Report this reply',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: report,
          child: bubble,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Align(
        alignment: fromCoach ? Alignment.centerLeft : Alignment.centerRight,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: fromCoach
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.end,
          children: <Widget>[
            bubble,
            if (note case final String note)
              Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.xs,
                  left: AppSpacing.xs,
                  right: AppSpacing.xs,
                ),
                child: Text(
                  note,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The coach composing a reply: its orb, with the word beside it.
///
/// On the coach's side of the conversation, so the wait reads as somebody
/// thinking rather than as the app working. A spinner here would be the only
/// indeterminate progress in the product. The orb is the same one every wait
/// for the coach shows, in both apps ([CoachOrb]); the word is what says this
/// wait is a real one.
class ThinkingIndicator extends StatelessWidget {
  const ThinkingIndicator({super.key, this.label = 'Thinking…'});

  final String label;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CoachOrb(),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
          ),
        ],
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
    this.anchor = ConversationAnchor.top,
  });

  /// The turns, oldest first, plus anything trailing them — a thinking
  /// indicator, a failure note.
  final List<Widget> children;

  final ScrollController? controller;
  final EdgeInsets padding;

  /// Which end a conversation shorter than the screen settles against.
  final ConversationAnchor anchor;

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
              mainAxisAlignment: anchor == ConversationAnchor.top
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
  );
}

/// Which end a short conversation settles against.
///
/// **This has been both ways, and the second answer is not a reversal of the
/// first — the screen changed underneath it.**
///
/// Bottom was right while the coach was a full-height page. A lone opener at
/// the top of 844pt left the rest of the screen empty beneath it, and the reply
/// was as far from the composer as the layout could put it.
///
/// The coach is a sheet now, and two things flipped with it. The sheet is
/// shorter, so the gap a top anchor leaves is smaller than the gap a bottom
/// anchor left. And the composer is above a keyboard that opens and closes:
/// bottom-anchored, every turn on screen jumps the height of the keyboard each
/// time somebody taps the field, which is motion nobody asked for applied to
/// text they were reading.
///
/// Top also means an onboarding question stays where it was read while its
/// answer is being chosen underneath it — a wheel and a stack of options are
/// tall, and bottom-anchored they push the question they belong to off screen.
enum ConversationAnchor {
  /// Turns settle at the top. The default, and what a sheet wants.
  top,

  /// Turns settle against the composer. For a full-height surface, where the
  /// distance from the last word to the field is otherwise the whole screen.
  bottom,
}
