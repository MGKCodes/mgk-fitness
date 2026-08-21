import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../domain/pace_model.dart';
import '../domain/prescribed_distance.dart';
import '../domain/session_effort.dart';
import '../domain/training_plan.dart';
import 'session_labels.dart';

/// The coach on one session: what it is, what it should feel like, what pace
/// that works out to for this runner, and why it is in the week at all.
///
/// **Deterministic, and that is the point.** Every number here is derived in
/// Dart from the runner's own time trial, so the brief cannot quote a pace they
/// cannot run or invent a session that is not in the plan. The model's job
/// starts at the button on the bottom: anything that needs judgement — "my
/// calf is sore", "why this and not intervals" — is a conversation, and
/// conversations are what the coach is for.
class SessionBriefSheet extends StatelessWidget {
  const SessionBriefSheet({
    super.key,
    required this.session,
    required this.date,
    this.paces,
    this.unit = UnitSystem.metric,
    this.onAskCoach,
  });

  /// The session, or null for a rest day — which gets a brief of its own,
  /// because "why am I not running today" is a real question and answering it
  /// is how a rest day stops feeling like a gap.
  final PlannedSession? session;
  final DateTime date;
  final TrainingPaces? paces;
  final UnitSystem unit;

  /// Opens the conversation with this session in hand.
  final void Function(String opener)? onAskCoach;

  /// Shows the brief as a bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required PlannedSession? session,
    required DateTime date,
    TrainingPaces? paces,
    UnitSystem unit = UnitSystem.metric,
    void Function(String opener)? onAskCoach,
  }) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => SessionBriefSheet(
      session: session,
      date: date,
      paces: paces,
      unit: unit,
      onAskCoach: onAskCoach,
    ),
  );

  SessionKind get _kind => session?.kind ?? SessionKind.rest;

  @override
  Widget build(BuildContext context) {
    final effort = effortFor(_kind);
    final band = paces == null ? null : bandFor(_kind, paces!);
    final run = session;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scroll) => DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            AppSpacing.xxl,
          ),
          children: <Widget>[
            const SheetHandle(bottomSpacing: AppSpacing.lg),

            SectionLabel(_dateLine()),
            const SizedBox(height: AppSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Expanded(
                  child: Text(
                    session == null ? kindLabel(_kind) : sessionLabel(session!),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                ),
                if (run != null && run.distanceMeters > 0)
                  Text(
                    formatPrescribed(run.distanceMeters, unit),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // Effort first, pace second — deliberately. The effort is the
            // instruction; the pace is what it happens to look like today.
            //
            // Skipped where the card would hold nothing: rest and strength have
            // no pace band and no RPE, so all it could show is the word already
            // set in 26pt directly above it.
            if (band != null || effort.rpeHigh > 0) ...<Widget>[
              Entrance(
                child: _EffortCard(effort: effort, band: band, unit: unit),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            Entrance(
              index: 1,
              child: _Note(title: 'How it should feel', body: effort.feel),
            ),
            const SizedBox(height: AppSpacing.md),
            Entrance(
              index: 2,
              child: _Note(title: 'Why it is here', body: effort.purpose),
            ),

            if (band != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Entrance(
                index: 3,
                child: _PaceNote(band: band, unit: unit),
              ),
            ],

            if (onAskCoach != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xl),
              Entrance(
                index: 4,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    onAskCoach!(_opener());
                  },
                  icon: const SizedBox(
                    width: 18,
                    height: 18,
                    child: Center(child: CoachLetter(size: 15)),
                  ),
                  label: const Text('Ask your coach about this'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _dateLine() {
    const months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${weekdayName(date.weekday)} ${date.day} ${months[date.month - 1]}';
  }

  /// The question a runner would actually ask, pre-written so the conversation
  /// starts somewhere rather than at an empty box.
  String _opener() => switch (_kind) {
    SessionKind.rest => 'Could I run today instead of resting?',
    SessionKind.strength => 'What should I do for this strength session?',
    _ => 'Tell me more about this ${kindLabel(_kind).toLowerCase()}.',
  };
}

/// The effort, its RPE, and the pace band it comes out at.
class _EffortCard extends StatelessWidget {
  const _EffortCard({
    required this.effort,
    required this.band,
    required this.unit,
  });

  final SessionEffort effort;
  final PaceBand? band;
  final UnitSystem unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.elevated.withValues(alpha: 0.5),
        borderRadius: AppRadius.cardAll,
        border: Border.all(
          color: AppColors.textPrimary.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // The session's name is the sheet's headline, two lines above this
          // card. Repeating it here as the card's title said "Easy" twice
          // within a hundred and thirty pixels, and the only new thing on the
          // row was the number beside it — so the number is what the row is
          // now. Principle 3: the more specific one wins.
          if (effort.rpeHigh > 0)
            Text(
              'Effort ${effort.rpe}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (band != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Text(
              band!.format(unit),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'for you, today',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionLabel(title),
        const SizedBox(height: AppSpacing.xs),
        Text(
          body,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

/// Says out loud that the band is a band. A runner given a range will still
/// treat it as a target unless told not to.
class _PaceNote extends StatelessWidget {
  const _PaceNote({required this.band, required this.unit});

  final PaceBand band;
  final UnitSystem unit;

  @override
  Widget build(BuildContext context) => _Note(
    title: 'About that pace',
    body:
        'Anywhere in ${band.format(unit)} is this session run correctly — it '
        'is a range, not a target to hit. It comes from your time trial, so it '
        'moves as you do. Hills, heat and a bad night\'s sleep all cost you '
        'time without costing you effort, and on those days the effort is the '
        'one to trust.',
  );
}
