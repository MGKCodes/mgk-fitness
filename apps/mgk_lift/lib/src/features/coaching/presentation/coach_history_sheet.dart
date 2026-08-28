import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../domain/coach.dart';
import 'day_label.dart';

/// Previous conversations with the coach, and one of them read back.
///
/// **This is where the old behaviour went.** The coach used to reopen on
/// whatever was last said, however long ago, which is what let it read a
/// month-old exchange as current (ADR-0002). Sessions stop that, and the cost
/// is that a lifter no longer finds last week's conversation waiting for them.
/// So it is kept, and it is here — the same words, in a place that says plainly
/// they are over.
///
/// **Read-only by construction.** There is no composer, and nothing here loads
/// a past conversation back into [CoachScreen]: reopening an old transcript to
/// write into it is exactly the endless chat this feature ends. Saying
/// something new starts a new conversation, and the sheet says so.
class PastConversationsSheet extends StatefulWidget {
  const PastConversationsSheet({
    super.key,
    required this.transcript,
    this.liveConversationId,
    this.now,
  });

  final CoachTranscript transcript;

  /// The conversation on screen behind this, left out of the list.
  ///
  /// "Previous" means previous. Listing the live one offers to open a
  /// read-only copy of what the lifter is already looking at.
  final String? liveConversationId;

  /// Passed rather than read, so a preview of this screen shows the same
  /// labels on a Saturday as it did on a Thursday.
  final DateTime? now;

  static Future<void> show(
    BuildContext context, {
    required CoachTranscript transcript,
    String? liveConversationId,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (_) => PastConversationsSheet(
      transcript: transcript,
      liveConversationId: liveConversationId,
    ),
  );

  @override
  State<PastConversationsSheet> createState() => _PastConversationsSheetState();
}

class _PastConversationsSheetState extends State<PastConversationsSheet> {
  /// Null while loading, empty when there is nothing to show.
  ///
  /// **The two are different states.** A list that draws its empty message
  /// during the load tells a lifter with ten conversations that they have none.
  List<CoachConversationSummary>? _conversations;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final found = await widget.transcript.conversations(limit: 20);
    if (!mounted) return;
    setState(() {
      _conversations = <CoachConversationSummary>[
        for (final c in found)
          if (c.id != widget.liveConversationId) c,
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // A clamped ceiling: a layout pass that reports no height must not take the
    // sheet down with an ArgumentError from `clamp`.
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
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xs,
                  AppSpacing.sm,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: <Widget>[
                    const Expanded(
                      child: SectionLabel('Previous conversations'),
                    ),
                    AppIconButton(
                      icon: Icons.close,
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).maybePop(),
                      size: 22,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

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

    final now = widget.now ?? DateTime.now();
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
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PastConversationScreen(
              transcript: widget.transcript,
              summary: conversations[i],
              // The same clock the row was labelled with. Reading
              // DateTime.now() here made the title say "5 Aug" under a row
              // that said "Yesterday" -- the two disagreeing about the same
              // conversation, which is worse than either being wrong alone.
              now: now,
            ),
          ),
        ),
      ),
    );
  }
}

/// One row: when it was, how much was said, and what opened it.
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
    final theme = Theme.of(context);
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
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textPrimary,
                      height: 1.35,
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
/// **A screen rather than a sheet, and with no composer.** A sheet with a text
/// field at the bottom is an invitation to carry on, and carrying on is the one
/// thing this cannot do — the turns are over, and the coach is not holding
/// them in mind any more. The footer says that rather than leaving somebody to
/// discover it by looking for a box that is not there.
class PastConversationScreen extends StatefulWidget {
  const PastConversationScreen({
    super.key,
    required this.transcript,
    required this.summary,
    this.now,
  });

  final CoachTranscript transcript;
  final CoachConversationSummary summary;

  /// The clock the title is dated against, passed rather than read.
  ///
  /// It has to be the one the row that opened this was labelled with, or the
  /// two disagree about the same conversation.
  final DateTime? now;

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
    final turns = await widget.transcript.fullTranscript(widget.summary.id);
    if (!mounted) return;
    setState(() => _turns = turns);
  }

  @override
  Widget build(BuildContext context) {
    final turns = _turns;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(
          dayLabel(widget.summary.lastTurnAt, widget.now ?? DateTime.now()),
        ),
      ),
      body: SafeArea(
        child: turns == null
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : Column(
                children: <Widget>[
                  Expanded(
                    child: ConversationView(
                      children: <Widget>[
                        for (final turn in turns)
                          ConversationBubble(
                            text: turn.body,
                            fromCoach: turn.fromCoach,
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      AppSpacing.md,
                    ),
                    child: Text(
                      'This conversation has ended. Anything you say now starts '
                      'a new one.',
                      textAlign: TextAlign.center,
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
}
