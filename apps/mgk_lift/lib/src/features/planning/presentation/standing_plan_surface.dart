import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../domain/standing_plan.dart';

/// The plan, as a thing that is simply on rather than a block being worked
/// through.
///
/// ## What is deliberately absent
///
/// No week number, no "week 3 of 12", no progress bar across the block, no end
/// date and no completion. Every one of those was in the surface this replaces,
/// and every one of them is a marathon idea: they only mean something when
/// there is a race to count down to. "Get stronger" has no week 12, and a
/// screen that implies otherwise is counting down to nothing.
///
/// What replaces them is the only question a lifter actually opens this screen
/// to answer: **what am I doing today, and is it ready.** The answer is at the
/// top, it is always yes, and it takes one tap.
///
/// ## The week is shown, not scheduled
///
/// The days below today are what the plan WILL do on those weekdays, derived
/// on the spot. Nothing is pre-written, so nothing is ever owed: miss a
/// fortnight and Thursday is still Upper, where a schedule would have you
/// three sessions behind on a plan that had moved on without you.
class StandingPlanSurface extends StatelessWidget {
  const StandingPlanSurface({
    super.key,
    required this.plan,
    required this.today,
    this.onStartToday,
    this.onSwap,
  });

  final StandingPlan plan;
  final DateTime today;

  /// Null on a rest day, and null is the honest state rather than a disabled
  /// button — there is nothing to start.
  final VoidCallback? onStartToday;

  /// "I have no cable machine." Same mechanism as SwapSheet, reached from the
  /// plan rather than from a session already underway.
  final void Function(MovementSlot)? onSwap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final todayName = plan.dayFor(today);
    final week = plan.split.weekFor(plan.weekdays.length);

    return PhotoBackdrop(
      image: 'assets/images/backgrounds/hero_home.webp',
      scrim: ScrimStrength.grounded,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xxl * 2,
          ),
          children: <Widget>[
            const SectionLabel('Your plan'),
            const SizedBox(height: 4),
            Text(plan.split.name, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 2),
            Text(
              // No end date, so the only honest thing to say about time is how
              // long it has been running.
              plan.startedAt == null
                  ? '${plan.weekdays.length} days a week'
                  : '${plan.weekdays.length} days a week · running since '
                        '${_month(plan.startedAt!)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),

            const SizedBox(height: AppSpacing.xl),
            _Today(
              day: todayName,
              movements: plan.movementsFor(today),
              onStart: onStartToday,
            ),

            const SizedBox(height: AppSpacing.xl),
            const SectionLabel('The week'),
            const SizedBox(height: AppSpacing.sm),
            for (var i = 0; i < week.length; i++)
              _DayCard(
                weekday: plan.weekdays[i],
                name: week[i],
                movements: plan.slots[week[i]] ?? const <MovementSlot>[],
                isToday: week[i] == todayName,
                onSwap: onSwap,
              ),
          ],
        ),
      ),
    );
  }

  static String _month(DateTime d) => const <String>[
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
  ][d.month - 1];
}

/// The one thing this screen is for.
class _Today extends StatelessWidget {
  const _Today({
    required this.day,
    required this.movements,
    required this.onStart,
  });

  final String? day;
  final List<MovementSlot> movements;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (day == null) {
      // A rest day is an answer, not an empty state. Nothing is owed and
      // nothing is behind.
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SectionLabel('Today'),
            const SizedBox(height: 4),
            Text('Rest', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Nothing scheduled, and nothing owed. Log something anyway if you '
              'feel like it.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionLabel('Today'),
          const SizedBox(height: 4),
          Text(day!, style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          Text(
            movements.map((m) => m.movement).join('  ·  '),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(label: "Start today's workout", onPressed: onStart),
        ],
      ),
    );
  }
}

/// One day of the split, and what fills it.
class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.weekday,
    required this.name,
    required this.movements,
    required this.isToday,
    required this.onSwap,
  });

  final int weekday;
  final String name;
  final List<MovementSlot> movements;
  final bool isToday;
  final void Function(MovementSlot)? onSwap;

  static const List<String> _short = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                SizedBox(
                  width: 44,
                  child: Text(
                    _short[weekday - 1],
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isToday
                          ? AppColors.textPrimary
                          : AppColors.textTertiary,
                    ),
                  ),
                ),
                Text(
                  name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: isToday
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final m in movements)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: <Widget>[
                    const SizedBox(width: 44),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(m.movement, style: theme.textTheme.bodyLarge),
                          Text(
                            // The ROLE, under the movement. The slot is the
                            // plan and the movement is this month's answer to
                            // it — showing both is what makes a swap read as
                            // filling the same job rather than as the plan
                            // changing.
                            m.hasStalled
                                ? '${m.role} · not moved in 6 sessions'
                                : m.role,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: m.hasStalled
                                  ? AppColors.textSecondary
                                  : AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onSwap != null)
                      IconButton(
                        onPressed: () => onSwap!(m),
                        icon: const Icon(Icons.swap_horiz),
                        iconSize: 20,
                        color: m.hasStalled
                            ? AppColors.textPrimary
                            : AppColors.textTertiary,
                        tooltip: 'Swap ${m.movement}',
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
