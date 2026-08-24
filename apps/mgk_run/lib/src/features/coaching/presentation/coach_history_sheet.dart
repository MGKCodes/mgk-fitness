import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import '../domain/coach_memory.dart';
import 'chat_controller.dart';
import 'chat_widgets.dart';

/// Previous conversations with the coach, and one of them read back.
///
/// **This is where the old behaviour went.** The dock used to reopen on
/// whatever was last said, however long ago, which is what let the coach read a
/// week-old exchange as current (ADR-0025). Sessions stop that, and the cost is
/// that a runner no longer finds last week's conversation waiting for them. So
/// it is kept, and it is here — the same words, in a place that says plainly
/// they are over.
///
/// **Read-only by construction.** There is no composer, and nothing here loads
/// a past conversation back into [ChatController]: reopening an old transcript
/// to write into it is exactly the endless chat this feature ends. Saying
/// something new starts a new conversation, and the sheet says so.
///
/// Special-category data (CLAUDE.md rule 6): these are the runner's own words
/// about their body, drawn on their own screen. Nothing here logs.
class PastConversationsSheet extends StatefulWidget {
  const PastConversationsSheet({super.key, required this.controller});

  final ChatController controller;

  /// Opens the list over whatever is on screen.
  static Future<void> show(
    BuildContext context, {
    required ChatController controller,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (_) => PastConversationsSheet(controller: controller),
  );

  @override
  State<PastConversationsSheet> createState() => _PastConversationsSheetState();
}

class _PastConversationsSheetState extends State<PastConversationsSheet> {
  /// Null while loading, empty when there is nothing to show. The two are
  /// different states and a list that draws its empty message during the load
  /// tells a runner with ten conversations that they have none.
  List<CoachConversationSummary>? _conversations;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final found = await widget.controller.pastConversations();
    if (!mounted) return;
    setState(() => _conversations = found);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // The same clamped ceiling as the conversation sheet, and for the same
    // reason: a layout pass that reports no height must not take the sheet down
    // with an ArgumentError from `clamp`.
    final available = media.size.height - media.padding.top;
    final ceiling = (available - 8).clamp(0.0, double.infinity);
    final height = (available * 0.62).clamp(0.0, ceiling);

    return SizedBox(
      height: height,
      child: DecoratedBox(
        decoration: const BoxDecoration(
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
              Expanded(child: _body()),
            ],
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
        const Expanded(child: SectionLabel('Previous conversations')),
        AppIconButton(
          icon: Icons.close,
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).maybePop(),
          size: 22,
          color: AppColors.textSecondary,
        ),
      ],
    ),
  );

  Widget _body() {
    final conversations = _conversations;
    if (conversations == null) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (conversations.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        child: Text(
          'Nothing here yet. Conversations you have with your coach are kept '
          'once they end, so you can read them back.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.45),
        ),
      );
    }

    final now = DateTime.now();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      itemCount: conversations.length,
      itemBuilder: (BuildContext context, int i) => _ConversationRow(
        conversation: conversations[i],
        now: now,
        onTap: () => _open(context, conversations[i]),
      ),
    );
  }

  /// Opens one conversation, read back.
  void _open(BuildContext context, CoachConversationSummary conversation) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PastConversationScreen(
          controller: widget.controller,
          summary: conversation,
        ),
      ),
    );
  }
}

/// One row of the list: when it was, how long it ran, and what opened it.
///
/// The opening line is what makes this a list a person recognises themselves
/// in. A column of dates is a filing cabinet.
class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    required this.conversation,
    required this.now,
    required this.onTap,
  });

  final CoachConversationSummary conversation;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final opening = conversation.opening?.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: AppColors.elevated,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        dayLabel(conversation.lastTurnAt, now),
                        style: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    Text(
                      conversation.turns == 1
                          ? '1 message'
                          : '${conversation.turns} messages',
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                if (opening != null && opening.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    opening,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One past conversation, read back in the order it was spoken.
///
/// A page rather than a sheet over a sheet: this is somewhere a runner reads
/// rather than glances, and it can be long.
class PastConversationScreen extends StatefulWidget {
  const PastConversationScreen({
    super.key,
    required this.controller,
    required this.summary,
  });

  final ChatController controller;
  final CoachConversationSummary summary;

  @override
  State<PastConversationScreen> createState() => _PastConversationScreenState();
}

class _PastConversationScreenState extends State<PastConversationScreen> {
  List<CoachTurn>? _turns;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final turns = await widget.controller.readBack(widget.summary.id);
    if (!mounted) return;
    setState(() => _turns = turns);
  }

  @override
  Widget build(BuildContext context) {
    final turns = _turns;
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text(dayLabel(widget.summary.lastTurnAt, now)),
      ),
      body: turns == null
          ? const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : SafeArea(
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.md,
                        AppSpacing.lg,
                        AppSpacing.md,
                      ),
                      children: <Widget>[
                        for (int i = 0; i < turns.length; i++)
                          _bubble(turns, i, now),
                      ],
                    ),
                  ),
                  // Said out loud rather than left to be inferred from a
                  // missing composer. A runner who cannot see why they are not
                  // able to type will assume it is broken.
                  const Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    child: Text(
                      'This conversation has ended. Anything you say to your '
                      'coach now starts a new one.',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _bubble(List<CoachTurn> turns, int i, DateTime now) {
    final turn = turns[i];
    final previous = i == 0 ? null : turns[i - 1];
    final startsRun = previous == null || previous.isUser != turn.isUser;
    final crossesDay = previous != null && !_sameDay(previous.at, turn.at);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (crossesDay) DayDivider(label: dayLabel(turn.at, now)),
        ChatBubble(text: turn.text, isUser: turn.isUser, showAvatar: startsRun),
      ],
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
