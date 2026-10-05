import 'dart:async';

import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../data/supabase_coach_reports.dart';
import '../domain/coach_report.dart';
import 'chat_controller.dart';
import 'chat_entry.dart';
import 'chat_widgets.dart';
import 'coach_history_sheet.dart';
import 'coach_report_sheet.dart';

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
    this.beforeSend,
    this.reporter = const SupabaseCoachReports(),
  });

  final ChatController? controller;
  final List<String> suggestions;
  final UnitSystem unit;

  /// Asked before anything typed or tapped here is sent, and nothing is sent
  /// unless it answers true.
  ///
  /// The sheet only opens once the runner has agreed to the coach sending
  /// their training, so this is normally a quick yes. It is here so the rule
  /// belongs to the place things are sent from, rather than to however the
  /// sheet happened to be opened: a suggestion chip sends on one tap, and a
  /// tap should not be able to outrun a withdrawn permission. Null asks
  /// nothing, which is what a test of the sheet on its own wants.
  final Future<bool> Function()? beforeSend;

  /// Where a reply the runner reports goes. A long press on any of the
  /// coach's replies opens the report sheet.
  final CoachReporter reporter;

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
    Future<bool> Function()? beforeSend,
  }) {
    if (opener != null && controller != null) {
      unawaited(controller.openWithNote(opener));
    }
    // The suite's way of opening the coach, shared with Lift's. The frame
    // pushes the composer above the keyboard rather than under it.
    return showCoachSheet<void>(
      context,
      builder: (_) => CoachConversationSheet(
        controller: controller,
        suggestions: suggestions,
        unit: unit,
        beforeSend: beforeSend,
      ),
      // Dismissing the sheet folds what was said into the rolling summary. The
      // dock did this from its collapse handler; a sheet has several ways out —
      // the button, the scrim, a back gesture — so it hangs off the route
      // completing instead.
      //
      // It does not *end* the conversation. It used to, which meant a runner
      // who shut the sheet and reopened it two minutes later saw the same
      // transcript being written into a different stored conversation. What
      // ends one is the session window lapsing (ADR-0025).
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

  /// Replies reported from this sheet, so each says so under it.
  final Set<ChatEntry> _reported = <ChatEntry>{};

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

  Future<void> _send([String? text]) async {
    final controller = _c;
    if (controller == null) return;
    final message = (text ?? _input.text).trim();
    if (message.isEmpty || !controller.canSend) return;
    // Cleared only once it is going, so a runner who says "Not now" keeps what
    // they typed.
    if (!await _mayAsk() || !mounted) return;
    _input.clear();
    unawaited(controller.send(message));
  }

  /// A question the runner picked rather than typed. See the chip below for why
  /// this is not [_send].
  Future<void> _ask(String text) async {
    final controller = _c;
    if (controller == null || !controller.canSend) return;
    if (!await _mayAsk() || !mounted) return;
    unawaited(controller.ask(text));
  }

  Future<bool> _mayAsk() async {
    final gate = widget.beforeSend;
    return gate == null || await gate();
  }

  Future<void> _report(ChatEntry entry) async {
    final sent = await reportCoachReply(
      context,
      reply: entry.text,
      reporter: widget.reporter,
    );
    if (sent && mounted) setState(() => _reported.add(entry));
  }

  /// The suite's coach sheet (5 October 2026): Lift's glass over a photograph,
  /// in place of the solid panel this was, and drawn by the same pieces
  /// (`CoachSheetFrame`, `CoachSheetLayout`, `CoachTopBar`, `CoachComposer`,
  /// `CoachEmptyState`), so the two apps' coaches look like one product's.
  ///
  /// The night road, not the photograph Home shows: the sheet rises over Home,
  /// and the same image blurred over itself reads as a smear rather than as a
  /// pane in front of something.
  @override
  Widget build(BuildContext context) {
    final controller = _c;
    return CoachSheetFrame(
      photo: 'assets/images/backgrounds/summary.jpg',
      child: CoachSheetLayout(
        bar: CoachTopBar(
          // "[icon] Coach", as Lift's says it: the icon is what tells the two
          // apps' coaches apart.
          icon: const AssetImage('assets/images/brand/app_icon.png'),
          // The way back to what was said before. A conversation ends when
          // the session window lapses, so opening the app no longer puts last
          // week's transcript in front of the runner. This is where it went.
          onHistory: controller == null
              ? null
              : () => unawaited(
                  PastConversationsSheet.show(context, controller: controller),
                ),
          onClose: () => Navigator.of(context).maybePop(),
        ),
        conversation: controller == null
            ? const _Offline()
            : controller.isEmpty && !controller.isBusy
            ? _empty(controller)
            : _transcript(controller),
        footer: controller == null
            ? null
            : CoachComposer(
                controller: _input,
                enabled: controller.canSend,
                onSend: () => unawaited(_send()),
              ),
      ),
    );
  }

  Widget _transcript(ChatController controller) {
    final entries = controller.entries;
    final now = DateTime.now();
    final thinking = controller.isBusy || controller.isProposing;

    // Built eagerly rather than lazily: a transcript is bounded by what has
    // been said in one conversation, and each row needs the row before it to
    // know whether it crosses a day.
    return ConversationView(
      controller: _scroll,
      // Room for the bar floating over this, so the first turn opens below it.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        CoachTopBar.height,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      children: <Widget>[
        for (int i = 0; i < entries.length; i++)
          Builder(
            builder: (BuildContext context) {
              final entry = entries[i];
              final previous = i == 0 ? null : entries[i - 1];
              final at = entry.at;
              final crossesDay =
                  at != null &&
                  previous != null &&
                  (previous.at == null || !_sameDay(previous.at!, at));
              final proposal = entry.proposal;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (crossesDay) DayDivider(label: dayLabel(at, now)),
                  ConversationBubble(
                    text: entry.text,
                    fromCoach: !entry.isUser,
                    // Only the coach's replies take a report: they are what
                    // a model wrote, and Play's policy on AI-generated content
                    // wants them reportable where they are read.
                    onReport: entry.isUser
                        ? null
                        : () => unawaited(_report(entry)),
                    note: _reported.contains(entry)
                        ? "Reported. Thanks, we'll take a look."
                        : null,
                  ),
                  // Under the reply, full width, not inside its bubble: an
                  // offer to change somebody's week should not be a card in
                  // a bubble in a sheet.
                  if (proposal != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: ProposalCard(
                        proposal: proposal,
                        unit: widget.unit,
                        onApply: () =>
                            unawaited(controller.applyProposal(entry)),
                        onDecline: () => controller.declineProposal(entry),
                      ),
                    ),
                ],
              );
            },
          ),
        if (thinking) const ThinkingIndicator(),
        // Next to the message it refers to, as Lift's says it, rather than
        // stranded above the composer.
        if (controller.error case final String error)
          CoachFailureLine(message: error),
      ],
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Nothing said yet. Openers rather than instructions — a runner should not
  /// have to think of a question before anything has been offered.
  Widget _empty(ChatController controller) => CoachEmptyState(
    lead: 'It has read your runs',
    detail:
        'Your coach can see your plan and your recent runs. Ask about any of '
        'it, or start with one of these.',
    suggestions: widget.suggestions,
    // `ask`, not `send`: a suggested question starts its own conversation. A
    // chip is a subject a surface raised rather than the next line of one the
    // runner was already having, and continuing into it is how a half-finished
    // exchange about a sore calf becomes the context for "how has my training
    // been going".
    onSuggestion: (String suggestion) => unawaited(_ask(suggestion)),
    trailing: switch (controller.error) {
      final String error => CoachFailureLine(message: error),
      null => null,
    },
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
      CoachTopBar.height + AppSpacing.lg,
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
