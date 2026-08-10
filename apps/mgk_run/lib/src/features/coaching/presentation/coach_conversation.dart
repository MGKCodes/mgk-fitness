import 'dart:async';

import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import 'chat_controller.dart';
import 'chat_widgets.dart';

/// The conversation with the coach, as a sheet.
///
/// **A sheet, not a dock.** The dock this replaces was a bar bolted to the foot
/// of one tab: it spent 76px permanently, sat on the block card's caption, read
/// as a second storey of navigation, and could only ever exist on the Coach
/// tab. A sheet costs nothing until it is opened and can be opened from
/// anywhere, which is what lets the coach be present across the app rather than
/// on one screen of it.
///
/// The controller is unchanged — it never knew it was in a dock.
class CoachConversationSheet extends StatefulWidget {
  const CoachConversationSheet({
    super.key,
    required this.controller,
    this.suggestions = const <String>[],
    this.unit = UnitSystem.metric,
  });

  final ChatController? controller;
  final List<String> suggestions;
  final UnitSystem unit;

  /// Opens the conversation.
  ///
  /// [opener] is the coach's own observation, seeded as its first turn so the
  /// conversation starts on something rather than on nothing — see
  /// [ChatController.openWithNote].
  static Future<void> show(
    BuildContext context, {
    required ChatController? controller,
    List<String> suggestions = const <String>[],
    UnitSystem unit = UnitSystem.metric,
    String? opener,
  }) {
    if (opener != null && controller != null) {
      unawaited(controller.openWithNote(opener));
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // The keyboard has to push the composer, not cover it.
      useSafeArea: true,
      builder: (_) => CoachConversationSheet(
        controller: controller,
        suggestions: suggestions,
        unit: unit,
      ),
      // Dismissing the sheet is what ends a conversation, and ending one is
      // what writes the rolling summary. The dock did this from its collapse
      // handler; a sheet has several ways out — the button, the scrim, a
      // back gesture — so it hangs off the route completing instead.
    ).whenComplete(
      () => unawaited(controller?.endConversation() ?? Future<void>.value()),
    );
  }

  @override
  State<CoachConversationSheet> createState() => _CoachConversationSheetState();
}

class _CoachConversationSheetState extends State<CoachConversationSheet> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  ChatController? get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c?.addListener(_onChange);
  }

  @override
  void dispose() {
    _c?.removeListener(_onChange);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: AppMotion.base,
        curve: AppMotion.entrance,
      );
    });
  }

  void _send([String? text]) {
    final controller = _c;
    if (controller == null) return;
    final message = (text ?? _input.text).trim();
    if (message.isEmpty || !controller.canSend) return;
    _input.clear();
    unawaited(controller.send(message));
  }

  @override
  Widget build(BuildContext context) {
    final controller = _c;
    final media = MediaQuery.of(context);
    final insets = media.viewInsets.bottom;

    // **A settled height, not one that tracks the content.** Growing with what
    // was said was right for the dock — it was already on the page, and taking
    // the screen to hold one line would have been absurd. A sheet is somewhere
    // you have arrived, and three attempts at content-driven sizing each failed
    // a different way: hugging opened a 200px strip that read as a snackbar,
    // `Expanded` pinned it to its ceiling whatever was said, and `Flexible`
    // honoured the floor but left the composer stranded mid-panel with dead
    // space beneath it.
    final available = media.size.height - media.padding.top;
    final height = (available * 0.62).clamp(0.0, available - insets - 8);

    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            // Solid. Glass exists where there is something behind it to distort,
            // and behind a sheet is a scrim.
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.sheet),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.md),
                  child: SheetHandle(bottomSpacing: 0),
                ),
                _header(context),
                if (controller == null)
                  const _Offline()
                else
                  // Expanded, so the transcript takes the room and the
                  // composer stays on the floor of the sheet where a thumb
                  // expects it.
                  Expanded(
                    child: controller.isEmpty && !controller.isBusy
                        ? _empty()
                        : _transcript(controller),
                  ),
                if (controller?.error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.sm,
                    ),
                    child: Text(
                      controller!.error!,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                if (controller != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.md,
                    ),
                    child: ChatComposer(
                      controller: _input,
                      enabled: controller.canSend,
                      onSend: _send,
                      hintText: 'Tell your coach',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.xs,
      AppSpacing.sm,
      AppSpacing.sm,
    ),
    child: Row(
      children: <Widget>[
        const Expanded(child: SectionLabel('Your coach')),
        IconButton(
          icon: const Icon(Icons.close, size: 22),
          color: AppColors.textSecondary,
          tooltip: 'Close the conversation',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    ),
  );

  Widget _transcript(ChatController controller) {
    final entries = controller.entries;
    final now = DateTime.now();
    final thinking = controller.isBusy || controller.isProposing;

    // Bottom-anchored, like every other conversation in the suite. A
    // ListView top-anchors, which pinned a single message — the common case
    // for a sheet somebody has just opened, and for the rate-limited state —
    // to the ceiling with the rest of the sheet empty beneath it.
    //
    // Built eagerly rather than lazily: a transcript is bounded by what has
    // been said in one conversation, and each row needs the row before it to
    // know whether it starts a run or crosses a day.
    return ConversationView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      children: <Widget>[
        for (int i = 0; i < entries.length; i++)
          Builder(
            builder: (BuildContext context) {
              final entry = entries[i];
              final previous = i == 0 ? null : entries[i - 1];
              final startsRun =
                  previous == null || previous.isUser != entry.isUser;
              final at = entry.at;
              final crossesDay =
                  at != null &&
                  previous != null &&
                  (previous.at == null || !_sameDay(previous.at!, at));

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (crossesDay) DayDivider(label: dayLabel(at, now)),
                  ChatBubble(
                    text: entry.text,
                    isUser: entry.isUser,
                    showAvatar: startsRun,
                    proposal: entry.proposal,
                    unit: widget.unit,
                    onApply: () => unawaited(controller.applyProposal(entry)),
                    onDecline: () => controller.declineProposal(entry),
                  ),
                ],
              );
            },
          ),
        if (thinking) const TypingBubble(),
      ],
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Nothing said yet. Openers rather than instructions — a runner should not
  /// have to think of a question before anything has been offered.
  Widget _empty() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      0,
      AppSpacing.lg,
      AppSpacing.md,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text(
          'Your coach can see your plan and your recent runs.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.45),
        ),
        if (widget.suggestions.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              for (final suggestion in widget.suggestions)
                _SuggestionChip(
                  text: suggestion,
                  onTap: () => _send(suggestion),
                ),
            ],
          ),
        ],
      ],
    ),
  );
}

/// No coach configured for this build. Said plainly rather than offering a
/// field that cannot send.
class _Offline extends StatelessWidget {
  const _Offline();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(
      AppSpacing.lg,
      0,
      AppSpacing.lg,
      AppSpacing.xl,
    ),
    child: Row(
      children: <Widget>[
        Icon(Icons.cloud_off, size: 18, color: AppColors.textTertiary),
        SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            'The coach is unavailable in this build.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ],
    ),
  );
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

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
