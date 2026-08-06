import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import '../../../core/units/distance.dart';
import '../../../core/units/unit_system.dart';
import '../domain/stored_plan.dart';
import '../domain/training_plan.dart';
import 'block_arc.dart';
import 'session_labels.dart';

/// The whole block, week by week.
///
/// **Grouped by phase, not listed flat.** Sixteen undifferentiated rows is a
/// wall; four groups of about four weeks is a story — build, back off, build
/// higher, taper. The grouping is the design: it is what lets a runner see the
/// plan rather than read it.
///
/// Every week here is a *shape*, never a session list. Sessions firm up about a
/// week ahead (see `kPlannedWeekHorizon`), so putting a Tuesday threshold on
/// week nine would present a guess as a commitment.
class PlanBlockScreen extends StatelessWidget {
  const PlanBlockScreen({
    super.key,
    required this.plan,
    this.now,
    this.unit = UnitSystem.metric,
  });

  final StoredPlan plan;
  final DateTime? now;
  final UnitSystem unit;

  @override
  Widget build(BuildContext context) {
    final today = now ?? DateTime.now();
    final current = plan.weekIndexOn(today);
    final weeks = plan.skeleton.weeks;
    final peak = weeks
        .map((w) => w.volumeMeters)
        .reduce((a, b) => a > b ? a : b);
    final groups = _group(weeks);

    return Scaffold(
      appBar: AppBar(title: const Text('The whole block')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            AppSpacing.xxl,
          ),
          children: <Widget>[
            Entrance(
              child: BlockArc(weeks: weeks, currentIndex: current, height: 72),
            ),
            const SizedBox(height: AppSpacing.lg),
            Entrance(
              index: 1,
              child: _Summary(plan: plan, today: today, unit: unit),
            ),
            const SizedBox(height: AppSpacing.xl),

            for (var g = 0; g < groups.length; g++) ...<Widget>[
              Entrance(
                index: 2 + g,
                child: _PhaseGroup(
                  group: groups[g],
                  peak: peak,
                  currentIndex: current,
                  unit: unit,
                ),
              ),
              if (g < groups.length - 1) const SizedBox(height: AppSpacing.xl),
            ],
          ],
        ),
      ),
    );
  }

  /// Consecutive weeks sharing a phase. Deloads stay inside their phase rather
  /// than forming groups of their own — a deload is part of a build, not an
  /// interruption to it.
  static List<_Group> _group(List<SkeletonWeek> weeks) {
    final groups = <_Group>[];
    for (final week in weeks) {
      if (groups.isEmpty || groups.last.phase != week.phase) {
        groups.add(_Group(week.phase, <SkeletonWeek>[week]));
      } else {
        groups.last.weeks.add(week);
      }
    }
    return groups;
  }
}

class _Group {
  _Group(this.phase, this.weeks);

  final Phase phase;
  final List<SkeletonWeek> weeks;

  double get totalMeters =>
      weeks.fold<double>(0, (sum, w) => sum + w.volumeMeters);
}

/// Where the runner is, in one line.
class _Summary extends StatelessWidget {
  const _Summary({required this.plan, required this.today, required this.unit});

  final StoredPlan plan;
  final DateTime today;
  final UnitSystem unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = plan.skeleton.weeks.fold<double>(
      0,
      (sum, w) => sum + w.volumeMeters,
    );
    // Null when there is no race to count down to. A horizon block has an arc
    // worth reading and simply no deadline attached to it.
    final event = plan.profile.eventDate;
    final days = event == null ? null : daysBetweenDates(today, event);

    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            '${plan.skeleton.weeks.length} weeks · '
            '${Distance.meters(total).format(unit, fractionDigits: 0)} in total',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Text(
          days == null
              ? 'no date set'
              : (days < 0 ? 'Event passed' : '$days days to go'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

/// One phase, headed and totalled, with its weeks beneath.
class _PhaseGroup extends StatelessWidget {
  const _PhaseGroup({
    required this.group,
    required this.peak,
    required this.currentIndex,
    required this.unit,
  });

  final _Group group;
  final double peak;
  final int currentIndex;
  final UnitSystem unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = group.weeks.first.index;
    final last = group.weeks.last.index;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            SectionLabel(phaseLabel(group.phase)),
            const SizedBox(width: AppSpacing.sm),
            Text(
              first == last ? 'week $first' : 'weeks $first to $last',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
            const Spacer(),
            Text(
              Distance.meters(
                group.totalMeters,
              ).format(unit, fractionDigits: 0),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final week in group.weeks)
          _WeekRow(
            week: week,
            peak: peak,
            isCurrent: week.index == currentIndex,
            isPast: week.index < currentIndex,
            unit: unit,
          ),
      ],
    );
  }
}

/// One week: its number, its volume as a bar, its long run.
class _WeekRow extends StatelessWidget {
  const _WeekRow({
    required this.week,
    required this.peak,
    required this.isCurrent,
    required this.isPast,
    required this.unit,
  });

  final SkeletonWeek week;
  final double peak;
  final bool isCurrent;
  final bool isPast;
  final UnitSystem unit;

  @override
  Widget build(BuildContext context) {
    final fill = peak <= 0 ? 0.0 : week.volumeMeters / peak;

    // Weeks already run recede; the current one is the only thing lit. Past
    // weeks are still legible, just not competing — this is a plan you read
    // forwards.
    final ink = isCurrent
        ? AppColors.textPrimary
        : (isPast ? AppColors.textTertiary : AppColors.textSecondary);
    final barColour = isCurrent
        ? AppColors.primary
        : (isPast
              ? AppColors.elevated
              : AppColors.primary.withValues(alpha: 0.55));

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: isCurrent ? AppColors.surface : Colors.transparent,
        borderRadius: AppRadius.chipAll,
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 30,
            child: Text(
              '${week.index}',
              style: TextStyle(
                color: ink,
                fontSize: 14,
                fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            width: 54,
            child: week.isDeload
                ? Text(
                    'Deload',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Stack(
                children: <Widget>[
                  Container(height: 6, color: AppColors.elevated),
                  FractionallySizedBox(
                    widthFactor: fill.clamp(0.04, 1),
                    child: Container(height: 6, color: barColour),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          SizedBox(
            width: 52,
            child: Text(
              Distance.meters(
                week.volumeMeters,
              ).format(unit, fractionDigits: 0),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: ink,
                fontSize: 13,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
          // Its own gutter: at three digits the volume filled its 52px box and
          // ran straight into "long", so "76 km" and "long 26 km" read as one
          // string.
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 62,
            child: Text(
              'long ${Distance.meters(week.longRunMeters).format(unit, fractionDigits: 0)}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
