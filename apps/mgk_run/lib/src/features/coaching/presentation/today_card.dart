import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../domain/pace_model.dart';
import '../domain/session_status.dart';
import '../domain/training_plan.dart';
import 'session_labels.dart';

/// The coach's daily heartbeat, atop the Plan tab: today's session (or a rest
/// day), with its target pace and mark-done / skip. Completion feeds back into
/// weekly generation (plan-generation.md); for now it drives the card's state.
class TodayCard extends StatelessWidget {
  const TodayCard({
    super.key,
    required this.session,
    required this.phase,
    required this.status,
    this.paces,
    this.onComplete,
    this.onSkip,
    this.onReset,
    this.unit = UnitSystem.metric,
  });

  /// Today's run, or null for a rest day.
  final PlannedSession? session;
  final Phase phase;
  final SessionStatus status;
  final TrainingPaces? paces;
  final VoidCallback? onComplete;
  final VoidCallback? onSkip;
  final VoidCallback? onReset;
  final UnitSystem unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = session;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: AppColors.elevated),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionLabel(
            'Today · ${phaseLabel(phase)}',
            emphasis: LabelEmphasis.stat,
          ),
          const SizedBox(height: 12),
          if (s == null) ..._rest(theme) else ..._session(theme, s),
        ],
      ),
    );
  }

  List<Widget> _rest(ThemeData theme) => <Widget>[
    Text(
      'Rest day',
      style: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    ),
    const SizedBox(height: 4),
    const Text(
      'Recovery is part of the plan.',
      style: TextStyle(color: AppColors.textSecondary),
    ),
  ];

  List<Widget> _session(ThemeData theme, PlannedSession s) {
    final pace = paces == null ? null : paceFor(s.kind, paces!);
    return <Widget>[
      Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Expanded(
            child: Text(
              kindLabel(s.kind),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            Distance.meters(s.distanceMeters).format(unit, fractionDigits: 1),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      if (pace != null) ...<Widget>[
        const SizedBox(height: 4),
        Text(
          'target ${pace.format(unit)}',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      ],
      const SizedBox(height: 16),
      _footer(),
    ];
  }

  Widget _footer() {
    switch (status) {
      case SessionStatus.planned:
        return Row(
          children: <Widget>[
            Expanded(
              child: FilledButton(
                onPressed: onComplete,
                child: const Text('Mark done'),
              ),
            ),
            const SizedBox(width: 12),
            TextButton(onPressed: onSkip, child: const Text('Skip')),
          ],
        );
      case SessionStatus.completed:
        return _statusRow(
          icon: Icons.check_circle,
          color: AppColors.success,
          label: 'Done',
        );
      case SessionStatus.skipped:
        return _statusRow(
          icon: Icons.remove_circle_outline,
          color: AppColors.textTertiary,
          label: 'Skipped',
        );
    }
  }

  Widget _statusRow({
    required IconData icon,
    required Color color,
    required String label,
  }) => Row(
    children: <Widget>[
      Icon(icon, color: color, size: 20),
      const SizedBox(width: 8),
      Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
      const Spacer(),
      if (onReset != null)
        TextButton(onPressed: onReset, child: const Text('Undo')),
    ],
  );
}
