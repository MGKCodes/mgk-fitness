/// The conversation's parts, shared by the two places Runio holds one: the
/// onboarding intake (`onboarding_screen.dart`) and the open coach chat
/// (`coach_chat.dart`).
///
/// They were built for intake first and copied nowhere — this file exists so
/// that stays true. A bubble that reads differently on two screens would make
/// the coach feel like two coaches.
library;

import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../domain/goal_draft.dart';
import '../domain/plan_shape.dart';
import '../domain/prescribed_distance.dart';
import '../domain/training_plan.dart';
import '../domain/week_adaptation.dart';
import '../../history/domain/run_draft.dart';
import 'chat_entry.dart';
import 'coach_button.dart' show CoachLetter;
import 'session_labels.dart';

/// One line of the conversation.
///
/// **Only the runner gets a bubble.** Their messages are short, right-aligned
/// and filled — the shape of something you just typed. The coach speaks as text
/// on the page beside a small mark, the way a coach talks rather than the way
/// two peers text.
///
/// Two reasons, and the second is load-bearing. A grey blob around every reply
/// made a considered answer look like a chat message, and the coach's replies
/// run longer than the runner's questions — a column of grey rounded rectangles
/// is harder to read, not friendlier. And a reply that carries a *proposal*
/// needs room for it: a card inside a bubble inside a docked panel is three
/// containers deep before any content, which is not what an offer to change
/// someone's week should look like.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.text,
    required this.isUser,
    this.showAvatar = true,
    this.proposal,
    this.unit = UnitSystem.metric,
    this.onApply,
    this.onDecline,
  });

  final String text;
  final bool isUser;

  /// Whether to draw the coach's mark. False for a reply that follows another,
  /// so a run of coach messages reads as one voice continuing rather than as
  /// several separate arrivals.
  final bool showAvatar;

  /// A change offered with this message, if any.
  final CoachProposal? proposal;
  final UnitSystem unit;
  final VoidCallback? onApply;
  final VoidCallback? onDecline;

  @override
  Widget build(BuildContext context) {
    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            child: AppCard(
              color: AppColors.primary,
              // The one sanctioned asymmetric radius: three corners take the
              // control step and the corner nearest the speaker is tucked in.
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppRadius.control),
                topRight: Radius.circular(AppRadius.control),
                bottomLeft: Radius.circular(AppRadius.control),
                bottomRight: Radius.circular(AppSpacing.xs),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md + 2,
                vertical: AppSpacing.sm + 2,
              ),
              child: Text(
                text,
                style: const TextStyle(color: AppColors.onPrimary, height: 1.4),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 30, child: showAvatar ? const CoachMark() : null),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  text,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    height: 1.45,
                    fontSize: 15,
                  ),
                ),
                if (proposal != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  ProposalCard(
                    proposal: proposal!,
                    unit: unit,
                    onApply: onApply,
                    onDecline: onDecline,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The coach's mark. Small, and only on the first of a run of replies — a
/// stack of identical avatars down the left edge is noise, not identity.
///
/// The **C**, the same letter the floating mark uses. It was
/// `Icons.auto_awesome` until the two were reconciled: the coach is called
/// Coach, and wearing the badge every AI feature of the last three years wears
/// undid the work of reading as a coach rather than a chatbot. See
/// [CoachButton] for the full argument.
class CoachMark extends StatelessWidget {
  const CoachMark({super.key});

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

/// A change to the runner's week, offered **inside the conversation**.
///
/// This was a modal sheet. A runner who asked for a change in a sentence had to
/// leave the conversation to agree to it, in a different visual language, and
/// the transcript kept no record of what they agreed — so next week, when they
/// wondered why Sunday moved, there was nothing to look at.
///
/// **What is inside it is already valid.** The model produced a sentence and an
/// intent; the adaptation service turned that into a revision and the validator
/// accepted it. The runner is approving a change, not approving model output.
class ProposalCard extends StatelessWidget {
  const ProposalCard({
    super.key,
    required this.proposal,
    this.unit = UnitSystem.metric,
    this.onApply,
    this.onDecline,
  });

  final CoachProposal proposal;
  final UnitSystem unit;
  final VoidCallback? onApply;
  final VoidCallback? onDecline;

  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: AppMotion.base,
    curve: AppMotion.entrance,
    alignment: Alignment.topLeft,
    child: Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardAll,
        border: Border.all(
          color: AppColors.textPrimary.withValues(alpha: 0.10),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Exhaustive: adding a kind of proposal will not compile until it has
          // a way to be shown, which is the point of sealing the type.
          ...switch (proposal) {
            ChatProposal(:final changes) => <Widget>[
              for (final change in changes)
                _ChangeLine(change: change, unit: unit),
            ],
            RunProposal(:final draft, :final isEdit) => <Widget>[
              if (isEdit)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Change it to',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              _RunLine(draft: draft, unit: unit),
            ],
            GoalProposal(:final draft, :final shape, :final supersedes) =>
              <Widget>[
                _GoalLine(draft: draft, shape: shape, unit: unit),
                // The cost, said before they tap rather than discovered after.
                // Every other card here adds or amends a row; this one throws a
                // block away, and a card that showed only the new race would be
                // hiding the half of the decision they cannot reconstruct.
                if (supersedes != null && supersedes > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'This replaces your current plan, including '
                      '$supersedes ${supersedes == 1 ? 'week' : 'weeks'} '
                      'already worked through.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
              ],
          },
          const SizedBox(height: AppSpacing.xs),
          switch (proposal.state) {
            ProposalState.pending => _Actions(
              onApply: onApply,
              onDecline: onDecline,
            ),
            ProposalState.applied => _Outcome(
              icon: Icons.check,
              text: switch (proposal) {
                ChatProposal() => 'Applied — your week is updated',
                RunProposal(:final isEdit) =>
                  isEdit ? 'Run updated' : 'Added to your runs',
                GoalProposal(:final shape) =>
                  shape == PlanShape.rhythm
                      ? 'Plan cleared — no goal set'
                      : 'Plan rebuilt around your new goal',
              },
            ),
            ProposalState.declined => _Outcome(
              icon: Icons.close,
              text: switch (proposal) {
                ChatProposal() => 'Left as it was',
                RunProposal(:final isEdit) =>
                  isEdit ? 'Left as it was' : 'Not added',
                GoalProposal() => 'Left as it was',
              },
            ),
            ProposalState.failed => _Actions(
              onApply: onApply,
              onDecline: onDecline,
              note: "That didn't save.",
            ),
          },
        ],
      ),
    ),
  );
}

class _ChangeLine extends StatelessWidget {
  const _ChangeLine({required this.change, required this.unit});

  final SessionChange change;
  final UnitSystem unit;

  String _label(PlannedSession? s) => s == null
      ? 'Rest'
      : '${kindLabel(s.kind)} ${formatPrescribed(s.distanceMeters, unit)}';

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(
      children: <Widget>[
        SizedBox(
          width: 36,
          child: Text(
            weekdayName(change.weekday),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            _label(change.before),
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 13,
              decoration: TextDecoration.lineThrough,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const Icon(
          Icons.arrow_forward,
          size: 13,
          color: AppColors.textTertiary,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            _label(change.after),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

class _Actions extends StatelessWidget {
  const _Actions({this.onApply, this.onDecline, this.note});

  final VoidCallback? onApply;
  final VoidCallback? onDecline;
  final String? note;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      if (note != null) ...<Widget>[
        Text(
          note!,
          style: const TextStyle(color: AppColors.danger, fontSize: 12),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      Row(
        children: <Widget>[
          Expanded(
            child: FilledButton(
              onPressed: onApply,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(40),
              ),
              child: const Text('Apply'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppTextButton(label: 'Not this time', onPressed: onDecline),
        ],
      ),
    ],
  );
}

/// What was decided, in the place the buttons were. The transcript is a record
/// of decisions, not only of sentences.
class _Outcome extends StatelessWidget {
  const _Outcome({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Icon(icon, size: 15, color: AppColors.textSecondary),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}

/// A day boundary in the transcript.
///
/// Only worth drawing because conversations now survive a relaunch. Without it,
/// a question asked last Tuesday sits directly above one asked this morning and
/// the transcript reads as one long conversation nobody had.
class DayDivider extends StatelessWidget {
  const DayDivider({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
    child: Row(
      children: <Widget>[
        const Expanded(child: Divider(color: AppColors.elevated, height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ),
        const Expanded(child: Divider(color: AppColors.elevated, height: 1)),
      ],
    ),
  );
}

/// "Today", "Yesterday", the weekday inside a week, or the date beyond it.
String dayLabel(DateTime at, DateTime now) {
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(at.year, at.month, at.day)).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return weekdayLongName(at.weekday);
  return '${at.day} ${monthShortName(at.month)}';
}

/// The three-dot "coach is typing" bubble shown while a turn is in flight.
class TypingBubble extends StatefulWidget {
  const TypingBubble({super.key});

  @override
  State<TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          const SizedBox(width: 30, child: CoachMark()),
          AnimatedBuilder(
            animation: _anim,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: EdgeInsets.only(right: i == 2 ? 0 : 6),
                    child: Opacity(
                      opacity: 0.3 + 0.7 * _dotPhase(i),
                      child: const CircleAvatar(
                        radius: 3,
                        backgroundColor: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double _dotPhase(int i) {
    final t = (_anim.value - i * 0.2) % 1.0;
    return t < 0.5 ? t * 2 : (1 - t) * 2;
  }
}

/// The message input row — a rounded field and a silver send button.
class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.enabled,
    required this.onSend,
    this.hintText = 'Type your answer',
    this.focusNode,
    this.leading,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;
  final String hintText;
  final FocusNode? focusNode;

  /// An optional control before the field — the chat's way back into a
  /// conversation it has collapsed.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        ?leading,
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            decoration: InputDecoration(
              hintText: hintText,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          height: 44,
          width: 44,
          child: FilledButton(
            onPressed: enabled ? onSend : null,
            style: FilledButton.styleFrom(
              padding: EdgeInsets.zero,
              // The theme floors every filled button at 52 high, which is right
              // for a full-width CTA but leaves this inline button taller than
              // the field beside it, bulging above and below the row.
              minimumSize: const Size.square(44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.control - 2),
              ),
            ),
            child: const Icon(Icons.arrow_upward, size: 20),
          ),
        ),
      ],
    );
  }
}

/// One line describing the run the coach heard, for the runner to check before
/// it becomes a row in their log.
///
/// Reads as a sentence rather than a form. The runner is being asked "is this
/// the run you did?", and a labelled grid invites proof-reading fields instead
/// of recognising a run — which is the thing they can actually judge.
/// The new target, in one line the runner can check against what they said.
///
/// Names the shape rather than only the numbers, because "42.2 km" alone does
/// not tell them whether they are getting a countdown or an open-ended build,
/// and those are different plans (ADR-0011).
class _GoalLine extends StatelessWidget {
  const _GoalLine({
    required this.draft,
    required this.shape,
    required this.unit,
  });

  final GoalDraft draft;
  final PlanShape shape;
  final UnitSystem unit;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Text(
      _describe(),
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: AppColors.textPrimary,
        height: 1.4,
      ),
    ),
  );

  String _describe() {
    final distance = draft.goalDistanceMeters;
    // Stepping off a goal is a decision worth stating plainly rather than
    // rendering as an absence.
    if (distance == null) return 'No goal — just keeping the running going';

    // The runner's own word for it where there is one. A goal is stored exactly
    // — 42,195 m, because every pace projection hangs off it — but "42.2 km" is
    // nobody's name for a marathon, and "42 km" is a worse one. See
    // [describeGoal].
    final label = describeGoal(distance, unit);
    final date = draft.eventDate;
    if (date == null) return '$label · no race date yet';
    return '$label on ${_dayMonth(date)}';
  }

  static String _dayMonth(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  static const List<String> _months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
}

class _RunLine extends StatelessWidget {
  const _RunLine({required this.draft, required this.unit});

  final RunDraft draft;
  final UnitSystem unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        _describe(),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: AppColors.textPrimary,
          height: 1.4,
        ),
      ),
    );
  }

  String _describe() {
    final parts = <String>[];
    final d = draft.distanceMeters;
    if (d != null) {
      // A decimal on purpose, and the one place in this file that keeps one.
      // This is a run the runner *did* — typed to the coach, or read back off a
      // recording they are editing — not a distance the plan asked for.
      // Prescriptions round; achievements do not, and telling someone who ran
      // 10.18 km that they ran "10 km" is the app shaving their work down to
      // fit its own grid. See `prescribed_distance.dart`.
      parts.add(Distance.meters(d).format(unit, fractionDigits: 1));
    }
    final t = draft.duration;
    if (t != null) parts.add('in ${_hms(t)}');
    final when = draft.startedAt;
    if (when != null) parts.add(_when(when));
    if (draft.type == kTypeTreadmill) parts.add('on the treadmill');
    final line = parts.join(' ');
    final rpe = draft.rpe;
    return rpe == null ? line : '$line · effort $rpe/10';
  }

  static String _hms(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    return s == 0 ? '${m}m' : '${m}m ${s}s';
  }

  /// Relative, like the rest of the coach's language: a runner confirming a run
  /// they just did should read "this morning", not a date they have to decode.
  static String _when(DateTime at) {
    final now = DateTime.now();
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(at.year, at.month, at.day)).inDays;
    if (days == 0) return at.hour < 12 ? 'this morning' : 'today';
    if (days == 1) return 'yesterday';
    if (days < 7) return '$days days ago';
    return 'on ${at.day}/${at.month}';
  }
}
