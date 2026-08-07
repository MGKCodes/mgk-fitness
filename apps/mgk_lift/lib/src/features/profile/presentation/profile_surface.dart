import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../../stats/domain/training_stats.dart';
import '../../tracking/data/exercise_lookup.dart';
import '../../tracking/domain/exercise.dart';
import '../../tracking/domain/session.dart';

/// **Profile** — the long view, and where settings live.
///
/// Three things share this surface, which is a consolidation rather than a
/// shortcut: the training log, the numbers, and settings. In Liftio these were
/// separate tabs, which spent a whole navigation slot on a screen people open
/// twice a year.
///
/// Everything here is a fold over the log rather than a stored counter. Nothing
/// to migrate, nothing to get out of step, and deleting a session corrects every
/// figure at once.
class ProfileSurface extends StatelessWidget {
  const ProfileSurface({
    super.key,
    this.log = const <Session>[],
    this.massUnit = MassUnit.kilograms,
    this.now,
    this.lookup,
    this.onOpenSettings,
    this.onOpenTrack,
  });

  /// Finished sessions, newest first.
  final List<Session> log;

  /// What the lifter works in. Every figure on this surface honours it, so
  /// Profile and the session screen cannot report the same training in two
  /// different units.
  final MassUnit massUnit;

  /// Injected so a test can pin the clock — a streak that reads `DateTime.now()`
  /// internally cannot be tested.
  final DateTime? now;

  final ExerciseLookup? lookup;
  final VoidCallback? onOpenSettings;

  /// Sends someone with an empty log back to the thing that fills it.
  final VoidCallback? onOpenTrack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clock = now ?? DateTime.now();
    final stats = TrainingStats.from(log, now: clock);
    final frequent = TrainingStats.byFrequency(log).take(5).toList();
    final catalogue = lookup ?? ExerciseLookup();

    return PhotoBackdrop(
      image: 'assets/images/backgrounds/hero_profile.webp',
      scrim: ScrimStrength.quiet,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xxl * 2,
          ),
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(child: SectionLabel('Profile')),
                IconButton(
                  onPressed: onOpenSettings,
                  icon: const Icon(Icons.settings_outlined),
                  color: AppColors.textSecondary,
                  tooltip: 'Settings',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            if (log.isEmpty)
              _Empty(onOpenTrack: onOpenTrack)
            else ...<Widget>[
              _HeadlineStats(stats: stats, massUnit: massUnit),
              const SizedBox(height: AppSpacing.xl),
              _Consistency(stats: stats),
              if (frequent.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.xl),
                Row(
                  children: <Widget>[
                    const Expanded(child: SectionLabel('Most trained')),
                    // The count needs a unit. A bare "3" beside a movement name
                    // could be sessions, sets or kilos; the same column-header
                    // fix the set rows needed.
                    const SectionLabel(
                      'Sessions',
                      emphasis: LabelEmphasis.stat,
                      color: AppColors.textTertiary,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                for (final row in frequent)
                  _FrequencyRow(
                    row: row,
                    catalogue: catalogue.find(row.name),
                    max: frequent.first.sessions,
                    // A bar is a comparison. When everything shown has the same
                    // count — which is the normal case for a short log, where
                    // every movement has been done once — every bar is full,
                    // and five identical full-width rules read as dividers
                    // rather than as data. Nothing to compare, so no bars.
                    showBars: frequent.first.sessions != frequent.last.sessions,
                  ),
              ],
              const SizedBox(height: AppSpacing.xl),
              const SectionLabel('Recent sessions'),
              const SizedBox(height: AppSpacing.md),
              for (final session in log.take(5))
                _SessionRow(
                  session: session,
                  stats: stats,
                  massUnit: massUnit,
                ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                // Says where the numbers come from. Cross-app awareness is the
                // point of the suite, and this is where a lifter meets it.
                'Runs you log in Run appear here too.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeadlineStats extends StatelessWidget {
  const _HeadlineStats({required this.stats, required this.massUnit});

  final TrainingStats stats;
  final MassUnit massUnit;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: StatBlock(
                  label: 'Sessions',
                  value: '${stats.sessions}',
                ),
              ),
              Expanded(
                child: StatBlock(
                  label: 'Volume',
                  value: compactVolume(stats.totalVolume, massUnit),
                ),
              ),
              Expanded(
                child: StatBlock(label: 'Sets', value: '${stats.totalSets}'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: StatBlock(
                  label: 'Time',
                  value: _compactDuration(stats.totalTime),
                ),
              ),
              Expanded(
                child: StatBlock(
                  label: 'Per week',
                  value: stats.sessionsPerWeek.toStringAsFixed(1),
                ),
              ),
              Expanded(
                child: StatBlock(
                  label: 'Streak',
                  value: '${stats.currentWeekStreak}w',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Tonnes past four figures. `47,500 kg` is a number you read; `47.5 t` is one
  /// you take in.
  ///
  /// Follows the lifter's chosen unit, because Profile reporting kilograms
  /// while the session screen reports pounds is the same "two screens, two
  /// answers" fault the warm-up bug was.
  static String compactVolume(Mass m, MassUnit unit) {
    final value = m.inDisplayUnit(unit);
    // A short tonne is 2,000 lb, and nobody means that. Pounds get thousands
    // separators instead of a unit nobody uses for barbell volume.
    if (unit == MassUnit.pounds) {
      return value >= 10000
          ? '${_thousands(value.round())} ${unit.suffix}'
          : '${value.round()} ${unit.suffix}';
    }
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)} t';
    return '${value.round()} ${unit.suffix}';
  }

  static String _thousands(int n) {
    final digits = n.toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }

  static String _compactDuration(Duration d) {
    if (d.inHours >= 1) return '${d.inHours}h';
    return '${d.inMinutes}m';
  }
}

class _Consistency extends StatelessWidget {
  const _Consistency({required this.stats});

  final TrainingStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = stats.currentWeekStreak;
    final best = stats.longestWeekStreak;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionLabel('Consistency', emphasis: LabelEmphasis.stat),
          const SizedBox(height: AppSpacing.sm),
          Text(
            current == 0
                ? 'No streak running'
                : '$current week${current == 1 ? '' : 's'} in a row',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            current == 0
                ? 'Train this week to start one. A week counts from Monday.'
                : current >= best
                ? 'Your best run yet.'
                : 'Your best is $best.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _FrequencyRow extends StatelessWidget {
  const _FrequencyRow({
    required this.row,
    required this.catalogue,
    required this.max,
    required this.showBars,
  });

  final ExerciseCount row;
  final Exercise? catalogue;
  final int max;

  /// Whether there is anything to compare. See the call site.
  final bool showBars;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = max == 0 ? 0.0 : row.sessions / max;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  row.name,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${row.sessions}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          if (showBars) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            // A bar rather than a chart library: one number relative to the top
            // one is all this says, and a dependency for that would be silly.
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 3,
                backgroundColor: AppColors.elevated,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.session,
    required this.stats,
    required this.massUnit,
  });

  final Session session;
  final TrainingStats stats;
  final MassUnit massUnit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final volume = Mass.kilograms(session.volumeKg);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(session.name, style: theme.textTheme.bodyMedium),
                Text(
                  '${_date(session.startedAt)} · ${session.exercises.length} '
                  'movement${session.exercises.length == 1 ? '' : 's'} · '
                  '${session.completedSets} '
                  'set${session.completedSets == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            volume.kilograms == 0 ? '—' : volume.label(massUnit),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  static String _date(DateTime d) {
    const months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }
}

class _Empty extends StatelessWidget {
  const _Empty({this.onOpenTrack});

  final VoidCallback? onOpenTrack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Nothing logged yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Your totals, streaks and personal bests build up here as you '
            'train — and so do your runs, if you use Run.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (onOpenTrack != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            TextButton(
              onPressed: onOpenTrack,
              child: const Text('Log a session'),
            ),
          ],
        ],
      ),
    );
  }
}
