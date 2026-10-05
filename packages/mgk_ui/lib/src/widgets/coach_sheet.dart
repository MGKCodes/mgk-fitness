import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import 'app_buttons.dart';
import 'coach_title.dart';
import 'glass_surface.dart';
import 'photo_backdrop.dart';
import 'sheet_handle.dart';
import 'step_progress.dart';

/// **The coach, as both apps draw it** (5 October 2026): each app's own
/// photograph behind a sheet of glass, the conversation running under a
/// frosted bar, and the composer on the floor of the sheet.
///
/// Lift's design, which the owner preferred to Run's solid panel, with what
/// Run had that Lift did not: the sheet rises above the keyboard rather than
/// under it, suggestion chips on an empty conversation, and a way to report a
/// reply (see `ConversationBubble.onReport`). What the coach *does* stays with
/// each app: these are the frame, the bar, the composer and the empty state,
/// and each app fills them from its own controller.
///
/// Opens the coach the same way in both apps: over everything, a scrim rather
/// than a blackout, the sheet painting its own photograph and glass.
Future<T?> showCoachSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool useRootNavigator = true,
}) => showModalBottomSheet<T>(
  context: context,
  // The sheet paints its own photograph and glass, so the default Material
  // underneath would sit in front of both.
  backgroundColor: Colors.transparent,
  // Above a nav bar rather than inside the body, or the bar draws over the
  // composer.
  useRootNavigator: useRootNavigator,
  isScrollControlled: true,
  // Scrim, not a blackout. Seeing the surface you came from is the difference
  // between a sheet and a screen.
  barrierColor: Colors.black.withValues(alpha: 0.45),
  builder: builder,
);

/// The glass the coach is drawn on: the app's photograph, blurred.
///
/// **The photograph is load-bearing.** Blur over a flat fill is a no-op, so
/// without one this sheet is a grey box with a rounded top. Each app passes
/// its own, and not the one the screen behind shows: the same image blurred
/// over itself reads as a smear rather than as a pane in front of something.
///
/// **It rises above the keyboard.** Lift's sheet did not pad for it, so on a
/// phone the keyboard came up over the composer it had been opened to type
/// into; Run's always had. The sheet keeps its share of whatever height the
/// keyboard leaves.
class CoachSheetFrame extends StatelessWidget {
  const CoachSheetFrame({
    super.key,
    required this.photo,
    required this.child,
    this.heightFactor = 0.88,
  });

  /// The app's own photograph, by asset path.
  final String photo;

  final Widget child;

  /// The share of the screen it opens at. Tall enough that a conversation is a
  /// conversation rather than a peephole, short enough that the surface behind
  /// stays visible, which is what makes it read as over that surface rather
  /// than as having replaced it.
  final double heightFactor;

  static const BorderRadius _radius = BorderRadius.vertical(
    top: Radius.circular(AppRadius.sheet + 8),
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: FractionallySizedBox(
      heightFactor: heightFactor,
      alignment: Alignment.bottomCenter,
      child: ClipRRect(
        borderRadius: _radius,
        child: PhotoBackdrop(
          image: photo,
          // Balanced: the conversation sits low in the sheet, and a scrim
          // weighted to the bottom buries the photograph exactly where the
          // glass needs something to refract.
          scrim: ScrimStrength.balanced,
          // High for a backdrop, because this one is seen through 34px of blur
          // and a tint.
          opacity: 0.62,
          child: GlassSurface(
            borderRadius: _radius,
            padding: EdgeInsets.zero,
            // Stronger than a card's: a whole sheet of glass at card settings
            // lets enough of the photograph through to compete with the text.
            blurSigma: 34,
            tintOpacity: 0.14,
            child: child,
          ),
        ),
      ),
    ),
  );
}

/// The sheet's parts in their places: the conversation filling it, the bar
/// floating over the top of it, and [footer] (the composer, and anything said
/// about it) on the floor.
///
/// **The bar floats over the conversation, and blurs it.** Laid out above the
/// list, it cut the topmost bubble along a straight edge, text stopping
/// mid-word against a hard line. The conversation carries
/// [CoachTopBar.height] of top padding, so nothing is permanently hidden.
class CoachSheetLayout extends StatelessWidget {
  const CoachSheetLayout({
    super.key,
    required this.bar,
    required this.conversation,
    this.footer,
  });

  final Widget bar;
  final Widget conversation;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => Material(
    // Transparent: the frame paints the photograph and the glass behind this,
    // and a fill would sit in front of both.
    color: Colors.transparent,
    child: SafeArea(
      top: false,
      child: Column(
        children: <Widget>[
          Expanded(
            child: Stack(
              children: <Widget>[
                Positioned.fill(child: conversation),
                Positioned(top: 0, left: 0, right: 0, child: bar),
              ],
            ),
          ),
          ?footer,
        ],
      ),
    ),
  );
}

/// The sheet's chrome: a handle, the app's icon and "Coach", how far through
/// an intake, and the ways out.
///
/// The fade below the blur matters as much as the blur: a blurred band with a
/// hard bottom edge is still an edge.
class CoachTopBar extends StatelessWidget {
  const CoachTopBar({
    super.key,
    required this.icon,
    required this.onClose,
    this.progress,
    this.onHistory,
    this.onDisclosure,
    this.disclosureTooltip = 'How your coach uses AI',
    this.closeTooltip = 'Close',
  });

  /// The app's icon, beside "Coach": what tells the two apps' coaches apart.
  final ImageProvider icon;

  final VoidCallback onClose;

  /// Step and total, during an intake. History is hidden while it shows: an
  /// intake is a sequence with an end, and a way into old conversations part
  /// way through it is an invitation to abandon it.
  final (int, int)? progress;

  /// Opens the previous conversations. Null hides the button: a control that
  /// opens an empty list is a promise the app cannot keep.
  final VoidCallback? onHistory;

  /// Opens what the coach sends to the AI provider, at the point of use
  /// (Guideline 5.1.2(i)). Null hides it.
  final VoidCallback? onDisclosure;

  final String disclosureTooltip;
  final String closeTooltip;

  /// Mirrored into the conversation's top padding, so the first turn opens
  /// below the bar rather than already under it.
  static const double height = 64;

  @override
  Widget build(BuildContext context) {
    final steps = progress;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                AppColors.bg.withValues(alpha: 0.55),
                AppColors.bg.withValues(alpha: 0.28),
                AppColors.bg.withValues(alpha: 0),
              ],
              stops: const <double>[0, 0.65, 1],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SheetHandle(bottomSpacing: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.lg,
                  right: AppSpacing.sm,
                ),
                child: Row(
                  children: <Widget>[
                    CoachTitle(icon: icon),
                    const Spacer(),
                    if (steps != null) ...<Widget>[
                      StepProgress(step: steps.$1, total: steps.$2),
                      const SizedBox(width: AppSpacing.md),
                    ],
                    if (onHistory != null && steps == null)
                      _BarButton(
                        icon: Icons.history,
                        tooltip: 'Previous conversations',
                        onPressed: onHistory!,
                      ),
                    if (onDisclosure != null)
                      _BarButton(
                        icon: Icons.info_outline,
                        tooltip: disclosureTooltip,
                        onPressed: onDisclosure!,
                      ),
                    _BarButton(
                      icon: Icons.close,
                      tooltip: closeTooltip,
                      onPressed: onClose,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => AppIconButton(
    onPressed: onPressed,
    icon: icon,
    size: 20,
    color: AppColors.textSecondary,
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
  );
}

/// The field and its send button, on the floor of the sheet where a thumb
/// expects them. The same in both apps, worded as Lift's: "Ask your coach".
class CoachComposer extends StatelessWidget {
  const CoachComposer({
    super.key,
    required this.controller,
    required this.enabled,
    required this.onSend,
    this.focusNode,
    this.hintText = 'Ask your coach',
  });

  final TextEditingController controller;

  /// False while the coach is answering: one question at a time.
  final bool enabled;

  final VoidCallback onSend;
  final FocusNode? focusNode;
  final String hintText;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      0,
      AppSpacing.lg,
      AppSpacing.md,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            decoration: InputDecoration(hintText: hintText),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        IconButton.filled(
          onPressed: enabled ? onSend : null,
          icon: const Icon(Icons.arrow_upward),
          tooltip: 'Send',
        ),
      ],
    ),
  );
}

/// Nothing said yet: what the coach can see, and questions to start on.
///
/// **Questions rather than instructions** (Run's): somebody should not have
/// to think of something to ask before anything has been offered, and "ask me
/// anything" is the least useful prompt in software. A chip sends its
/// question as written.
class CoachEmptyState extends StatelessWidget {
  const CoachEmptyState({
    super.key,
    required this.lead,
    this.detail,
    this.suggestions = const <String>[],
    this.onSuggestion,
    this.footnote,
    this.trailing,
  });

  /// What the coach has read: "It has read your log".
  final String lead;

  final String? detail;
  final List<String> suggestions;

  /// Null while a question cannot be sent, which leaves the chips showing and
  /// inert.
  final ValueChanged<String>? onSuggestion;

  /// What somebody should know before the first message, said small.
  final String? footnote;

  /// Anything else the empty sheet has to say, such as why the last attempt
  /// failed.
  final Widget? trailing;

  static const EdgeInsets _padding = EdgeInsets.fromLTRB(
    AppSpacing.xl,
    CoachTopBar.height,
    AppSpacing.xl,
    AppSpacing.lg,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Centred in the sheet, as Lift's always was, and still scrollable: the
    // keyboard can leave the sheet shorter than what it has to say.
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: _padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            // Clamped: a layout pass that reports no height makes this
            // negative, and a negative minimum takes the route down.
            minHeight: (box.maxHeight - _padding.vertical).clamp(
              0.0,
              double.infinity,
            ),
          ),
          child: Center(child: _content(theme)),
        ),
      ),
    );
  }

  Widget _content(ThemeData theme) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Text(
        lead,
        style: theme.textTheme.titleMedium,
        textAlign: TextAlign.center,
      ),
      if (detail case final String detail) ...<Widget>[
        const SizedBox(height: AppSpacing.sm),
        Text(
          detail,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
      ],
      if (suggestions.isNotEmpty) ...<Widget>[
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            for (final suggestion in suggestions)
              _Chip(
                text: suggestion,
                onTap: onSuggestion == null
                    ? null
                    : () => onSuggestion!(suggestion),
              ),
          ],
        ),
      ],
      if (footnote case final String footnote) ...<Widget>[
        const SizedBox(height: AppSpacing.lg),
        Text(
          footnote,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textTertiary,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
      ],
      ?trailing,
    ],
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.elevated,
    borderRadius: AppRadius.chipAll,
    child: InkWell(
      onTap: onTap,
      borderRadius: AppRadius.chipAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}

/// Why the last message got no answer, said next to it rather than stranded
/// at the foot of the sheet with the question at the top.
class CoachFailureLine extends StatelessWidget {
  const CoachFailureLine({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: Text(
      message,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
    ),
  );
}
