import 'package:flutter/material.dart';
import 'package:mgk_units/mgk_units.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../domain/standing_plan.dart';

/// The plan: the week at a glance, and one day open at a time.
///
/// ## Overview first, details on demand
///
/// The first version of this listed every movement of every day — twelve rows,
/// twelve role labels and twelve swap icons on a four-day plan — so the one
/// question it exists to answer, *what does my week look like*, could only be
/// answered by scrolling and remembering. It also printed today's session twice,
/// once in the Today card and again in the day card underneath it.
///
/// This follows the ordinary information-design answer instead: an overview you
/// can take in at once, then detail for the thing you pointed at. The week strip
/// is seven days including rest, because rest is part of the shape of a week and
/// leaving it out was why Wednesday did not exist. Tapping a day opens it; only
/// one is ever open, so the screen has a fixed size no matter how many movements
/// a day holds.
///
/// ## What is deliberately absent
///
/// No week number, no "week 3 of 12", no countdown. Those are marathon ideas
/// and they only mean something when there is a race to count toward. What is
/// here instead is what a lifter opens this screen for on the way to the gym:
/// what am I doing today, what did I lift last time, and is anything going
/// stale.
class StandingPlanSurface extends StatefulWidget {
  const StandingPlanSurface({
    super.key,
    required this.plan,
    required this.today,
    this.massUnit = MassUnit.kilograms,
    this.onStartToday,
    this.onSwap,
    this.onChangeSplit,
  });

  final StandingPlan plan;
  final DateTime today;
  final MassUnit massUnit;

  /// Null on a rest day. Null rather than disabled, because there is genuinely
  /// nothing to start rather than something withheld.
  final VoidCallback? onStartToday;

  /// "I have no cable machine." The same mechanism SwapSheet already runs for a
  /// live session, reached from the plan instead.
  final void Function(MovementSlot)? onSwap;

  /// **A plan can be replaced whenever somebody wants.** It never expires on
  /// them; it changes when they ask. Those are different things, and the second
  /// one needs a door.
  final VoidCallback? onChangeSplit;

  @override
  State<StandingPlanSurface> createState() => _StandingPlanSurfaceState();
}

class _StandingPlanSurfaceState extends State<StandingPlanSurface> {
  /// Opens on today, which is the day somebody came here about.
  late int _open = widget.today.weekday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = widget.plan;
    final todayName = plan.dayFor(widget.today);
    final openDay = plan.week.firstWhere((d) => d.weekday == _open).day;
    final openSlots = openDay == null
        ? const <MovementSlot>[]
        : plan.slots[openDay] ?? const <MovementSlot>[];

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
              // long it has been going.
              plan.startedAt == null
                  ? '${plan.weekdays.length} days a week'
                  : '${plan.weekdays.length} days a week · running since '
                        '${_month(plan.startedAt!)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),

            // ---- Today, and the one action ------------------------------
            const SizedBox(height: AppSpacing.xl),
            _TodayCard(
              day: todayName,
              // **Not the movement list.** It used to repeat what the day card
              // below already said. A count says the same useful thing in one
              // line and does not go stale when a slot is swapped.
              count: plan.movementsFor(widget.today).length,
              onStart: widget.onStartToday,
            ),

            // ---- Overview -----------------------------------------------
            const SizedBox(height: AppSpacing.xl),
            const SectionLabel('The week'),
            const SizedBox(height: AppSpacing.sm),
            _WeekStrip(
              week: plan.week,
              today: widget.today.weekday,
              open: _open,
              onTap: (d) => setState(() => _open = d),
            ),

            // ---- Detail, for the day pointed at --------------------------
            const SizedBox(height: AppSpacing.lg),
            _DayDetail(
              weekday: _open,
              day: openDay,
              slots: openSlots,
              massUnit: widget.massUnit,
              onSwap: widget.onSwap,
            ),

            // ---- Things to read about the plan ---------------------------
            const SizedBox(height: AppSpacing.xl),
            const SectionLabel('How it is going'),
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: StatBlock(
                      label: 'a week',
                      value: '${plan.weekdays.length}',
                    ),
                  ),
                  Expanded(
                    child: StatBlock(
                      label: 'movements',
                      value: '${plan.slots.values.expand((s) => s).length}',
                    ),
                  ),
                  Expanded(
                    child: StatBlock(
                      label: 'gone stale',
                      value: '${plan.stalled.length}',
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),
            const SectionLabel('Why this split'),
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              child: Text(
                plan.split.why,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
            ),

            if (widget.onChangeSplit != null) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton(
                onPressed: widget.onChangeSplit,
                child: const Text('Change the split'),
              ),
            ],
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

/// What you came here to do.
class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.day,
    required this.count,
    required this.onStart,
  });

  final String? day;
  final int count;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionLabel('Today'),
          const SizedBox(height: 4),
          Text(day ?? 'Rest', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            day == null
                // A rest day is an answer. Nothing is owed and nothing is
                // behind, which is the point of deriving the week rather than
                // scheduling it.
                ? 'Nothing scheduled, and nothing owed. Log something anyway if '
                      'you feel like it.'
                : '$count movements',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (day != null) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(label: "Start today's workout", onPressed: onStart),
          ],
        ],
      ),
    );
  }
}

/// Seven days, rest included, in one row.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.week,
    required this.today,
    required this.open,
    required this.onTap,
  });

  final List<({int weekday, String? day})> week;
  final int today;
  final int open;
  final ValueChanged<int> onTap;

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
    return Row(
      children: <Widget>[
        for (final d in week)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: InkWell(
                onTap: () => onTap(d.weekday),
                borderRadius: BorderRadius.circular(AppRadius.control),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    color: d.weekday == open
                        ? AppColors.elevated
                        : Colors.transparent,
                    // Today is outlined even when another day is open, so
                    // pointing at Friday never loses where you actually are.
                    border: Border.all(
                      color: d.weekday == today
                          ? AppColors.textSecondary
                          : Colors.transparent,
                    ),
                  ),
                  child: Column(
                    children: <Widget>[
                      Text(
                        _initials[d.weekday - 1],
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      // A dot for rest, an initial for a training day. The
                      // shape of the week is readable without reading a word.
                      Text(
                        d.day == null ? '·' : d.day![0],
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: d.day == null
                              ? AppColors.textTertiary
                              : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One day, opened.
class _DayDetail extends StatelessWidget {
  const _DayDetail({
    required this.weekday,
    required this.day,
    required this.slots,
    required this.massUnit,
    required this.onSwap,
  });

  final int weekday;
  final String? day;
  final List<MovementSlot> slots;
  final MassUnit massUnit;
  final void Function(MovementSlot)? onSwap;

  static const List<String> _names = <String>[
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(_names[weekday - 1], style: theme.textTheme.titleMedium),
              const Spacer(),
              Text(
                day ?? 'Rest',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          if (day == null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                'No session on this day.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          for (final s in slots)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(s.movement, style: theme.textTheme.bodyLarge),
                        const SizedBox(height: 2),
                        Text(
                          _under(s),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: s.hasStalled
                                ? AppColors.textSecondary
                                : AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Only where it is worth offering. Twelve swap icons made a
                  // rare corrective action the loudest thing on the screen; one
                  // on the slot that has actually gone stale is a
                  // recommendation.
                  if (onSwap != null && s.hasStalled)
                    TextButton(
                      onPressed: () => onSwap!(s),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Swap'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Last time's top set, or why there is not one. The role is only named when
  /// the slot is in trouble, where it explains what the replacement has to do;
  /// under every movement it was twelve lines of jargon nobody reads.
  String _under(MovementSlot s) {
    if (s.hasStalled) {
      return '${s.role} · not moved in ${s.sessionsAtSameTop} sessions';
    }
    if (!s.hasHistory) return 'first time';
    final top = Mass.kilograms(s.lastTopKg!).label(massUnit);
    return 'last time $top × ${s.lastTopReps}';
  }
}
