import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../../coaching/domain/race_day.dart' show midSentenceRaceName;
import '../../coaching/domain/race_finish.dart';
import '../domain/race_breakdown.dart';
import '../domain/run_race.dart';
import '../domain/run_summary.dart';

/// The pieces of a race screen that a training run does not have.
///
/// Kept apart from `RunSummaryScreen` so the screen reads as a list of what is
/// on it rather than as eight hundred lines of how each thing is drawn. Every
/// piece takes plain values and draws them; deciding what to say lives in
/// `race_finish.dart` and `race_breakdown.dart`.

/// The heading every section on the race screen shares: the quiet, spaced
/// label `SPLITS` and `NOTES` already use, so a race reads as the same screen
/// with more on it.
class RaceSectionLabel extends StatelessWidget {
  const RaceSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      color: AppColors.textSecondary,
      letterSpacing: 3,
    ),
  );
}

/// Which time is the headline, and what the phone made of it.
///
/// **Both figures, where they differ, and said plainly.** A chip time and a
/// phone time seventeen seconds apart is the ordinary outcome of a big race:
/// the phone starts in the pen and stops past the line. Leaving the runner to
/// notice that their own phone disagrees with the number above it would look
/// like a fault, so the line says what each one is.
///
/// Without an official time the headline *is* the phone's, and the line is the
/// way to add one — the moment that matters, because the result comes out a
/// few hours after the race, when the runner opens the run to look at it again.
class RaceTimeLine extends StatelessWidget {
  const RaceTimeLine({
    super.key,
    required this.run,
    required this.race,
    required this.unit,
    this.onEdit,
  });

  final RunSummary run;
  final RunRace race;
  final UnitSystem unit;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final official = race.officialTime;
    final phone = run.duration.hoursMinutesSeconds;
    final phoneDistance = Distance.meters(
      run.distanceMeters,
    ).format(unit, fractionDigits: 2);

    final text = official == null
        ? 'This is your phone’s time, over $phoneDistance. Add your '
              'official time when the results are out.'
        : 'Official time. Your phone had $phone over $phoneDistance, which is '
              'normal for a race: it starts before the mat and picks up the '
              'weaving.';

    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
          if (onEdit != null)
            AppTextButton(
              label: official == null ? 'Add' : 'Edit',
              onPressed: onEdit,
            ),
        ],
      ),
    );
  }
}

/// Where the race stands, and the records set inside it.
class RaceStandingCard extends StatelessWidget {
  const RaceStandingCard({super.key, required this.standing});

  final RaceStanding standing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            standing.headline,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            standing.detail,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// How the race was run: the two halves side by side, then every checkpoint.
///
/// **Paces, not checkpoint times.** The sections are placed proportionally along
/// the phone's trace (`raceBreakdownFor`), which is accurate to a few seconds a
/// kilometre and not to the second at a mat. A pace says what that accuracy
/// supports; a "15K at 1:23:16" beside the results page's 1:23:37 would invite
/// exactly the comparison it cannot win.
class RaceBreakdownCard extends StatelessWidget {
  const RaceBreakdownCard({
    super.key,
    required this.breakdown,
    required this.unit,
  });

  final RaceBreakdown breakdown;
  final UnitSystem unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = breakdown.sections;
    final slowest = sections
        .map((s) => s.paceSecondsPerKm)
        .fold<double>(1, (a, b) => a > b ? a : b);
    final quickest = sections
        .map((s) => s.paceSecondsPerKm)
        .fold<double>(slowest, (a, b) => a < b ? a : b);
    final range = slowest - quickest;

    String pace(RaceSection s) =>
        Pace.secondsPerKilometer(s.paceSecondsPerKm).format(unit);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const RaceSectionLabel('HOW YOU RAN IT'),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: <Widget>[
              Expanded(
                child: StatBlock(
                  label: 'FIRST HALF',
                  value: pace(breakdown.firstHalf),
                  shrinkToFit: true,
                ),
              ),
              Expanded(
                child: StatBlock(
                  label: 'SECOND HALF',
                  value: pace(breakdown.secondHalf),
                  shrinkToFit: true,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (var i = 0; i < sections.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 52,
                  child: Text(
                    raceSectionLabel(sections[i], unit),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      // Across this race's own range, so a fade of half a
                      // minute a kilometre reads as one rather than as four
                      // bars of nearly the same length.
                      widthFactor: range <= 0
                          ? 0.7
                          : 0.35 +
                                0.65 *
                                    (sections[i].paceSecondsPerKm - quickest) /
                                    range,
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                SizedBox(
                  width: 68,
                  child: Text(
                    pace(sections[i]),
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textPrimary,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'From your phone, measured against the course distance.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

/// The training that led to the race, when a plan was aimed at it.
///
/// **Hidden without a plan**, at the runner's request: a race run with no plan
/// behind it has no window to total, and a section that guessed one ("your last
/// twelve weeks") would be reporting a block nobody committed to.
///
/// Distances only — runs, kilometres, the longest, the weeks. The plan's own
/// arc is drawn on the Plan tab; here the bars are what was *run*, week by
/// week, so the shape is the runner's rather than the plan's.
class RaceBuildUpSection extends StatelessWidget {
  const RaceBuildUpSection({
    super.key,
    required this.buildUp,
    required this.unit,
    this.planFinished = false,
  });

  final RaceBuildUp buildUp;
  final UnitSystem unit;

  /// The plan was closed by marking this race, so the Plan tab is about to be
  /// empty — said here, because nothing else would tell them why.
  final bool planFinished;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weekly = buildUp.weeklyMeters;
    final peak = buildUp.peakWeekMeters;
    String km(double meters) =>
        Distance.meters(meters).format(unit, fractionDigits: 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const RaceSectionLabel('THE TRAINING'),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${buildUp.label} · ${buildUp.weeks} '
                '${buildUp.weeks == 1 ? 'week' : 'weeks'}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: <Widget>[
                  Expanded(
                    child: StatBlock(label: 'RUNS', value: '${buildUp.runs}'),
                  ),
                  Expanded(
                    child: StatBlock(
                      label: 'DISTANCE',
                      value: km(buildUp.meters),
                      shrinkToFit: true,
                    ),
                  ),
                  Expanded(
                    child: StatBlock(
                      label: 'LONGEST',
                      value: buildUp.longest == null
                          ? '—'
                          : Distance.meters(
                              buildUp.longest!.distanceMeters,
                            ).format(unit, fractionDigits: 1),
                      shrinkToFit: true,
                    ),
                  ),
                ],
              ),
              if (weekly.isNotEmpty && peak > 0) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                Semantics(
                  label: 'Distance run each week of the plan',
                  child: SizedBox(
                    height: 56,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        for (var i = 0; i < weekly.length; i++)
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(left: i == 0 ? 0 : 3),
                              child: Container(
                                // A week with nothing run still shows as a
                                // sliver, so a missed week is a gap in a row
                                // rather than a hole in the axis.
                                height: weekly[i] <= 0
                                    ? 2
                                    : 4 + 52 * weekly[i] / peak,
                                decoration: BoxDecoration(
                                  color: weekly[i] <= 0
                                      ? AppColors.elevated
                                      : AppColors.primary,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: <Widget>[
                    Text(
                      'Week 1',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Race week',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Biggest week ${km(peak)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (planFinished) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Your plan is finished, so the Plan tab is clear. Ask the coach '
            'whenever you want to start the next one.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textTertiary,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }
}

/// "Was this a race?", on a run that looks like one.
///
/// A quiet card rather than a banner: most runs near 5 or 10 km are training,
/// and a line that shouted on every one of them would be ignored on the day it
/// was right.
class RaceOffer extends StatelessWidget {
  const RaceOffer({super.key, required this.label, required this.onTap});

  /// The race the run looks like: "Half marathon".
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.flag_outlined,
            size: 20,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Was this a race?',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Mark it as your ${midSentenceRaceName(label)} and add your '
                  'official time.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textTertiary,
          ),
        ],
      ),
    );
  }
}
