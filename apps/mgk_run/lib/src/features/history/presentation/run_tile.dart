import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../../recording/domain/run_summary.dart';
import 'route_thumbnail.dart';

/// One run in the training log: its route sketched, its distance as the
/// headline, and the date, time and pace beneath.
///
/// A card rather than a bare row. With no accent colour to lean on, surface is
/// how this palette separates things (ADR-0009), and the log sits under the
/// stat cards on the profile page — a run that did not read as a card there
/// would look like a list that had escaped the design.
class RunTile extends StatelessWidget {
  const RunTile({
    super.key,
    required this.run,
    this.unit = UnitSystem.metric,
    this.onTap,
  });

  final RunSummary run;
  final UnitSystem unit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: <Widget>[
          // Smaller than the standalone log's thumbnail: on the profile page the
          // row sits inside a card that already has padding, and the old 64 left
          // the text crowded against the chevron.
          RouteThumbnail(points: run.points, type: run.type, size: 52),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  Distance.meters(run.distanceMeters).format(unit),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _subtitle(run),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            size: 20,
            color: AppColors.textTertiary,
          ),
        ],
      ),
    );
  }

  String _subtitle(RunSummary run) {
    final date = _shortDate(run.startedAt);
    final time = run.duration.hoursMinutesSeconds;
    final pace = _pace(run)?.format(unit);
    return <String>[date, time, ?pace].join('  ·  ');
  }

  /// The stored average when there is one, else derived from the totals. A run
  /// with no distance has no pace — showing `0:00 /km` would be a lie.
  Pace? _pace(RunSummary run) {
    if (run.avgPaceSecondsPerKm != null) {
      return Pace.secondsPerKilometer(run.avgPaceSecondsPerKm!);
    }
    if (run.distanceMeters > 0) {
      return Pace.from(Distance.meters(run.distanceMeters), run.duration);
    }
    return null;
  }
}

const List<String> _months = <String>[
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

String _shortDate(DateTime at) => '${at.day} ${_months[at.month - 1]}';
