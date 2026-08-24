import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../domain/plan_headline.dart';
import '../domain/readiness.dart';
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
///
/// **This is now the only place the shape of the plan is drawn.** It used to
/// have a card of its own on the Plan tab, an arc and a sentence under the
/// heading "The whole block" — which sat beneath the week reading as a second,
/// competing plan. The week is the plan; this is the background to it, and it
/// is reached by tapping the goal at the top of the Plan tab, which is the line
/// that raises the question ("week 3 of 9") in the first place. The arc and the
/// sentence came with it, so nothing the card said was lost — only the claim
/// that it was a plan in its own right.
class PlanBlockScreen extends StatelessWidget {
  const PlanBlockScreen({
    super.key,
    required this.plan,
    this.now,
    this.unit = UnitSystem.metric,
    this.readiness,
  });

  final StoredPlan plan;
  final DateTime? now;
  final UnitSystem unit;

  /// How ready the runner already is for what they are training towards, read
  /// from the run log rather than from the profile they typed months ago.
  ///
  /// Optional because this screen is perfectly coherent without it, and null is
  /// what a caller with no log to read should pass rather than a guess. When it
  /// is here, [planOutlook] can ask the question the old card asked — a horizon
  /// runner who could already run the distance is told so, and asked whether it
  /// is worth entering something.
  final Readiness? readiness;

  @override
  Widget build(BuildContext context) {
    final today = now ?? DateTime.now();
    final current = plan.weekIndexOn(today);
    final weeks = plan.skeleton.weeks;
    final peak = weeks
        .map((w) => w.volumeMeters)
        .reduce((a, b) => a > b ? a : b);
    final groups = _group(weeks);
    // Written in the domain, because a rhythm has no peak and nothing to taper
    // into. This screen used to be headed "The whole block" whatever it was
    // showing, which is block vocabulary over a parkrunner's flat arc — the
    // same leak [planOutlook] was written to stop on the card it used to head.
    //
    // Readiness is handed in rather than derived, because it is read from the
    // run log and this screen is given a plan. That is the right way round: a
    // profile ages and the log does not, so the caller that holds the log is
    // the one that can answer it. It briefly was not passed at all, and the
    // cost was a horizon runner's "you could run a marathon now — worth
    // finding one to enter?" going missing entirely; the shorter form on the
    // goal strip on the Plan tab still says "ready for it now" in the line
    // above the tap that gets here, but the invitation only exists on this
    // screen and a short form is not a substitute for it.
    final outlook = planOutlook(plan, unit: unit, readiness: readiness);

    return Scaffold(
      appBar: AppBar(title: Text(outlook.title)),
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
            const SizedBox(height: AppSpacing.sm),
            // What the arc is doing, in a sentence — "peaks at 76 km in week
            // 12, then tapers". It travelled here with the arc when the Plan
            // tab's card was dropped, because an arc without it is a shape
            // nobody has to read the same way twice.
            Entrance(
              index: 1,
              child: Text(
                outlook.caption,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiary,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Entrance(
              index: 2,
              child: _Summary(plan: plan, today: today, unit: unit),
            ),
            const SizedBox(height: AppSpacing.xl),

            for (var g = 0; g < groups.length; g++) ...<Widget>[
              Entrance(
                index: 3 + g,
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
    // Null when there is no race to count down to. A horizon block has an arc
    // worth reading and simply no deadline attached to it.
    final event = plan.profile.eventDate;
    final days = event == null ? null : daysBetweenDates(today, event);

    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            '${plan.skeleton.weeks.length} weeks · '
            '${_totalOfShown(plan.skeleton.weeks.map((w) => w.volumeMeters), unit)} in total',
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
              _totalOfShown(group.weeks.map((w) => w.volumeMeters), unit),
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

/// The sum of the numbers on screen, not the sum of what they were rounded
/// from.
///
/// Every week row rounds to whole kilometres or miles independently, so adding
/// the exact metres and rounding once gives a different answer: this block's
/// Build phase listed weeks summing to 373 km under a heading that said 372.
///
/// Same rule, and the same reasoning, as [formatPrescribedTotal] on the week
/// screen — "a runner who adds up the rows and gets a different number has
/// found a bug, whatever the tolerance says". It applies wherever a total sits
/// above the figures it totals.
String _totalOfShown(Iterable<double> meters, UnitSystem unit) {
  final total = meters.fold<double>(
    0,
    (sum, m) => sum + Distance.meters(m).inDisplayUnit(unit).roundToDouble(),
  );
  return '${total.toStringAsFixed(0)} ${unit.distanceSuffix}';
}
