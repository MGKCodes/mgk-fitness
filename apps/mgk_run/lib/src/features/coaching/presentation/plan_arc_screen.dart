import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../domain/pace_model.dart';
import '../domain/runner_profile.dart';
import '../domain/training_plan.dart';
import 'session_labels.dart';

/// The plan **arc**, shown in full so the runner sees what they've committed to
/// (plan-generation.md): every week's phase, volume, and long run, with the
/// deloads and taper visible at a glance. Tapping a week opens its sessions.
class PlanArcScreen extends StatelessWidget {
  const PlanArcScreen({
    super.key,
    required this.skeleton,
    required this.profile,
    this.onOpenWeek,
    this.todayCard,
    this.onReplacePlan,
    this.unit = UnitSystem.metric,
  });

  final PlanSkeleton skeleton;
  final RunnerProfile profile;
  final void Function(SkeletonWeek week)? onOpenWeek;

  /// An optional card (today's session) shown above the arc.
  final Widget? todayCard;

  /// Starts a fresh plan, superseding this one. Null hides the action — a goal
  /// or an injury can make a plan obsolete long before its event, and without
  /// this the only route to a new plan is deleting the account.
  final VoidCallback? onReplacePlan;

  final UnitSystem unit;

  double get _peak =>
      skeleton.weeks.map((w) => w.volumeMeters).reduce((a, b) => a > b ? a : b);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your plan'),
        actions: onReplacePlan == null
            ? null
            : <Widget>[
                IconButton(
                  icon: const Icon(Icons.autorenew),
                  tooltip: 'Start a new plan',
                  onPressed: onReplacePlan,
                ),
              ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _Header(skeleton: skeleton, profile: profile, unit: unit),
            ?todayCard,
            const Divider(height: 1, color: AppColors.elevated),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                itemCount: skeleton.weeks.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (context, i) => Entrance(
                  index: i,
                  child: _WeekRow(
                    week: skeleton.weeks[i],
                    peak: _peak,
                    unit: unit,
                    onTap: onOpenWeek == null
                        ? null
                        : () => onOpenWeek!(skeleton.weeks[i]),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.skeleton,
    required this.profile,
    required this.unit,
  });

  final PlanSkeleton skeleton;
  final RunnerProfile profile;
  final UnitSystem unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final goalMeters = profile.goalDistanceMeters;
    final goal = goalMeters == null ? null : Distance.meters(goalMeters);
    final ttDistance = profile.timeTrialDistanceMeters;
    final ttTime = profile.timeTrialDuration;
    final projected = (goal != null && ttDistance != null && ttTime != null)
        ? riegelPredict(Distance.meters(ttDistance), ttTime, goal)
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            goal == null
                ? 'Your plan'
                : '${goal.format(unit, fractionDigits: goal.kilometers >= 10 ? 0 : 1)} goal',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            projected == null
                ? '${skeleton.weeks.length} weeks to go'
                : '${skeleton.weeks.length} weeks · projected ${_hms(projected)}',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _WeekRow extends StatelessWidget {
  const _WeekRow({
    required this.week,
    required this.peak,
    required this.unit,
    this.onTap,
  });

  final SkeletonWeek week;
  final double peak;
  final UnitSystem unit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fillFraction = peak <= 0 ? 0.0 : (week.volumeMeters / peak);
    final fillColor = week.isDeload
        ? AppColors.textTertiary
        : AppColors.primary;
    final volume = Distance.meters(week.volumeMeters);
    final longRun = Distance.meters(week.longRunMeters);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 34,
              child: Text(
                'W${week.index}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(width: 56, child: _PhaseTag(week: week)),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Stack(
                  children: <Widget>[
                    Container(height: 10, color: AppColors.elevated),
                    FractionallySizedBox(
                      widthFactor: fillFraction.clamp(0.04, 1.0),
                      child: Container(height: 10, color: fillColor),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 96,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    volume.format(unit, fractionDigits: 0),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'long ${longRun.format(unit, fractionDigits: 0)}',
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                    ),
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

class _PhaseTag extends StatelessWidget {
  const _PhaseTag({required this.week});

  final SkeletonWeek week;

  @override
  Widget build(BuildContext context) {
    final label = week.isDeload ? 'Deload' : phaseLabel(week.phase);
    return Text(
      label,
      style: TextStyle(
        color: week.isDeload ? AppColors.textTertiary : AppColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    );
  }
}

/// `h:mm:ss` (or `m:ss` under an hour) for a projected finish time.
String _hms(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  final two = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$two';
  return '$m:$two';
}
