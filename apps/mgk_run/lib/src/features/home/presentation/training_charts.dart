import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../../coaching/domain/training_history.dart';

/// Weekly distance over the last two months, with the week in progress picked
/// out.
///
/// **One tone, one emphasis.** Every bar is the same weight and the current week
/// is the only one lit — colouring bars darker-where-bigger would spend the one
/// free channel restating the height the bar already shows. The story is "am I
/// building, holding, or drifting", and that is carried by the silhouette.
///
/// Only the current week is labelled. A number over every bar is the fastest way
/// to make a chart go unread, and the axis line carries the rest.
class VolumeChart extends StatelessWidget {
  const VolumeChart({
    super.key,
    required this.weeks,
    required this.standing,
    this.unit = UnitSystem.metric,
  });

  final List<WeekVolume> weeks;
  final WeekStanding standing;
  final UnitSystem unit;

  /// Capped rather than filling the slot, so the bars stay marks instead of
  /// blocks and the leftover band is air.
  static const double _maxBarWidth = 20;
  static const double _plotHeight = 96;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final peak = weeks.fold<double>(0, (m, w) => w.meters > m ? w.meters : m);
    final ran = Distance.meters(
      standing.ranMeters,
    ).format(unit, fractionDigits: 0);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionLabel('Weekly volume'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            standing.hasPlan
                ? '$ran of '
                      '${Distance.meters(standing.plannedMeters).format(unit, fractionDigits: 0)} '
                      'this week · ${standing.done} of ${standing.sessions} runs'
                : '$ran this week',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: _plotHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (final week in weeks)
                  Expanded(
                    child: Padding(
                      // The 2px surface gap that separates touching marks —
                      // never a stroke around them.
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: _Bar(
                        fraction: peak <= 0 ? 0 : week.meters / peak,
                        lit: week.isCurrent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // A hairline, solid, one step off the surface. The baseline the bars
          // grow from is the only chrome the chart needs at this size.
          Container(height: 1, color: AppColors.elevated),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              Text(
                '${weeks.length} weeks ago',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
              const Spacer(),
              Text(
                'this week',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.lit});

  final double fraction;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: VolumeChart._maxBarWidth),
        child: FractionallySizedBox(
          heightFactor: fraction.clamp(0.0, 1.0),
          widthFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: lit
                  ? AppColors.primary
                  : AppColors.primary.withValues(alpha: 0.3),
              // Rounded at the data end, square at the baseline.
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Did you run, each day, over the last two months.
///
/// **The one measure that reads the same on every plan shape.** A rhythm's
/// weekly volume is flat by design, so the chart above says almost nothing about
/// whether a parkrun habit is being kept; this says it plainly. It needs no plan
/// at all, which is also why it survives for a runner who has never built one.
///
/// State is carried by **shape, not shade** — filled, hollow, faint — the same
/// way the week ribbon carries it, so the two never have to be learned twice.
class ConsistencyGrid extends StatelessWidget {
  const ConsistencyGrid({super.key, required this.grid});

  /// Rows of seven, oldest week first, Monday to Sunday.
  final List<List<RunDay>> grid;

  static const List<String> _initials = <String>[
    'M',
    'T',
    'W',
    'T',
    'F',
    'S',
    'S',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = grid
        .expand((row) => row)
        .where((d) => d == RunDay.ran)
        .length;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionLabel('Turning up'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '$total runs over ${grid.length} weeks',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              for (final letter in _initials)
                Expanded(
                  child: Center(
                    child: Text(
                      letter,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final week in grid)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: <Widget>[
                  for (final day in week)
                    Expanded(
                      child: Center(child: _DayCell(day: day)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day});

  final RunDay day;

  @override
  Widget build(BuildContext context) {
    // A day that has not happened yet is not an absence, so it is barely drawn
    // at all — the grid should read as a record, not as a scorecard with most of
    // the marks still missing.
    final (Color fill, bool hollow) = switch (day) {
      RunDay.ran => (AppColors.primary, false),
      RunDay.today => (AppColors.primary, true),
      RunDay.none => (AppColors.elevated, false),
      RunDay.future => (AppColors.elevated.withValues(alpha: 0.45), false),
    };

    return Container(
      width: 11,
      height: 11,
      decoration: BoxDecoration(
        color: hollow ? Colors.transparent : fill,
        borderRadius: BorderRadius.circular(3),
        border: hollow ? Border.all(color: fill, width: 1.6) : null,
      ),
    );
  }
}
