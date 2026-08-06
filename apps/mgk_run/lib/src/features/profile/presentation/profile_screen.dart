import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import '../../../core/units/distance.dart';
import '../../../core/units/duration_format.dart';
import '../../../core/units/pace.dart';
import '../../../core/units/unit_system.dart';
import '../../coaching/domain/plan_history.dart';
import '../../coaching/domain/runner_profile.dart';
import '../../coaching/domain/stored_plan.dart';
import '../../coaching/domain/training_standing.dart';
import '../../coaching/presentation/coach_button.dart';
import '../../history/presentation/run_tile.dart';
import '../../recording/domain/run_summary.dart';
import '../domain/runner_stats.dart';

/// What the runner has done: their lifetime totals, what their coach makes of
/// them, their bests, the goal they are training for, and every run recorded.
///
/// The training log lives here rather than on a page of its own. Totals and a
/// log of the runs they are derived from are the same subject read at two
/// depths, and splitting them meant the numbers sat on a screen with nothing
/// under the fold while the log sat on a screen with no identity above it.
///
/// **This is a page about running, not an account page.** The address the
/// runner signed in with and the date they joined say nothing about their
/// training, and led the page with administration; both live in Settings now.
///
/// Everything shown is derived from data already on the device — no new storage,
/// nothing to keep in sync. A runner with no history gets an honest empty state
/// rather than a wall of zeroes.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.stats,
    this.pastPlans = const <LabelledPlan>[],
    this.profile,
    this.standing,
    this.runs = const <RunSummary>[],
    this.unit = UnitSystem.metric,
    this.onOpenRun,
    this.onAddRun,
    this.onAskCoach,
    this.onOpenSettings,
  });

  final RunnerStats stats;

  /// Plans the runner has finished with, oldest first, already labelled.
  ///
  /// **Past ones only** — the current plan is the whole Coach tab, and listing
  /// it here as history would read as two plans. Empty for a runner on their
  /// first, which hides the section rather than showing an empty one: "no
  /// previous plans" is not a fact worth a heading.
  final List<LabelledPlan> pastPlans;

  /// The profile behind the current plan, if there is one.
  final RunnerProfile? profile;

  /// Where the runner stands: their position in the plan and whether they have
  /// been turning up. Null hides the card entirely — for a caller that has not
  /// worked it out rather than for a runner who has no standing, since every
  /// runner has one.
  final TrainingStanding? standing;

  /// The training log, newest first. The caller orders it — this screen shows
  /// what it is given rather than re-sorting a list it did not build.
  final List<RunSummary> runs;

  final UnitSystem unit;

  final void Function(RunSummary run)? onOpenRun;

  /// Adds a run the phone did not record. Null hides the affordance — a build
  /// that cannot write runs should not offer to.
  final VoidCallback? onAddRun;

  /// Opens the conversation on the given question. Null when no coach is
  /// configured for this build, which hides the action rather than offering a
  /// control that cannot do anything.
  final void Function(String opener)? onAskCoach;

  /// Settings sit behind this page: it is where a runner comes to look at their
  /// own details, so it is where they look for the controls over them.
  final VoidCallback? onOpenSettings;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ScrollController _scroll = ScrollController();
  double _offset = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      // Parallax: the backdrop drifts at a third of the scroll, so it sits
      // behind the content rather than travelling with it.
      final next = _scroll.hasClients ? _scroll.offset : 0.0;
      if ((next - _offset).abs() > 0.5) setState(() => _offset = next);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// How far the backdrop is allowed to drift, in logical pixels.
  ///
  /// The log makes this page scroll for as long as the runner has been running,
  /// and an unbounded parallax would walk the photograph clean off the top of
  /// the screen a few hundred rows in, leaving bare charcoal behind the content.
  /// Clamping keeps the treatment present however deep the scroll goes.
  static const double _maxDrift = 120;

  @override
  Widget build(BuildContext context) {
    final stats = widget.stats;
    final theme = Theme.of(context);
    final runs = widget.runs;

    return Scaffold(
      body: PhotoBackdrop(
        image: 'assets/images/backgrounds/summary.jpg',
        scrim: ScrimStrength.grounded,
        alignment: Alignment.topCenter,
        offset: -(_offset / 3).clamp(0.0, _maxDrift),
        child: CustomScrollView(
          controller: _scroll,
          slivers: <Widget>[
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              // The log makes this page scroll a long way under a pinned bar,
              // and a transparent one let run rows collide with the title. Glass
              // rather than a solid fill because there is always something
              // behind it here — the photograph at rest, the cards once moving —
              // which is the one condition that makes the material worth its
              // cost (docs/design/design-system.md).
              // `SizedBox.expand`, not a bare `ColoredBox`: a ColoredBox with no
              // child takes `constraints.smallest`, and the flexible space is
              // laid out loose — so the filter covered nothing at all and the
              // bar stayed as transparent as before.
              flexibleSpace: ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: const SizedBox.expand(
                    child: ColoredBox(color: Color(0x991A1A1A)),
                  ),
                ),
              ),
              title: const Text('Profile'),
              actions: <Widget>[
                if (widget.onOpenSettings != null)
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: 'Settings',
                    onPressed: widget.onOpenSettings,
                  ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.sm,
                AppSpacing.xl,
                0,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate(<Widget>[
                  // The lifetime total leads. It is the number the page is
                  // about, and it says more about a runner than their address
                  // did.
                  if (stats.isEmpty)
                    const Entrance(child: _NoRuns())
                  else
                    Entrance(
                      child: _Lifetime(stats: stats, unit: widget.unit),
                    ),

                  if (widget.standing != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.xl),
                    Entrance(
                      index: 1,
                      child: _Standing(
                        standing: widget.standing!,
                        onAsk: widget.onAskCoach,
                      ),
                    ),
                  ],

                  if (!stats.isEmpty) ...<Widget>[
                    const SizedBox(height: AppSpacing.xl),
                    Entrance(
                      index: 2,
                      child: _Records(stats: stats, unit: widget.unit),
                    ),
                  ],

                  if (widget.profile != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.xl),
                    Entrance(
                      index: 3,
                      child: _Goal(
                        profile: widget.profile!,
                        unit: widget.unit,
                        theme: theme,
                      ),
                    ),
                  ],

                  // Only the plans behind them. The current one is already the
                  // whole Coach tab, and repeating it here as "history" would
                  // read as two plans.
                  if (widget.pastPlans.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpacing.xl),
                    Entrance(
                      index: 4,
                      child: _PastPlans(
                        plans: widget.pastPlans,
                        unit: widget.unit,
                      ),
                    ),
                  ],

                  if (runs.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpacing.xl),
                    Entrance(
                      index: 5,
                      child: _LogHeader(
                        count: runs.length,
                        onAdd: widget.onAddRun,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ]),
              ),
            ),

            // The log is its own sliver rather than more children of the list
            // above: built lazily, it costs one row per screen no matter how
            // many years of running sit below the fold.
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                // The coach mark floats over this tab too, so the last row of
                // the log needs the same room the Plan tab leaves it.
                kCoachMarkClearance,
              ),
              sliver: SliverList.separated(
                itemCount: runs.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, i) {
                  final run = runs[i];
                  return Entrance(
                    // Continues the header's sequence, so the first rows arrive
                    // after the cards above them rather than alongside.
                    index: i + 5,
                    child: RunTile(
                      run: run,
                      unit: widget.unit,
                      onTap: widget.onOpenRun == null
                          ? null
                          : () => widget.onOpenRun!(run),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The eyebrow over the training log, with the count beside it and the order
/// stated — a list of runs with no stated order invites the runner to guess.
class _LogHeader extends StatelessWidget {
  const _LogHeader({required this.count, this.onAdd});

  final int count;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        SectionLabel(count == 1 ? '1 run' : '$count runs'),
        if (onAdd == null)
          Text(
            'Newest first',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.textTertiary,
            ),
          )
        else
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add a run'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              visualDensity: VisualDensity.compact,
            ),
          ),
      ],
    );
  }
}

/// Where the runner stands, and the way into arguing with it.
///
/// This is deliberately **not** the note Home shows. Home answers "what just
/// happened"; this answers "how am I doing" — the standing question, the one an
/// athlete actually brings to a coach. It is [TrainingStanding], derived in
/// Dart, so the claim is checkable against the runs below it (CLAUDE.md rule
/// 2). The conversation behind the tap is where the model belongs.
///
/// The whole card is the target rather than a button in the corner: the card is
/// a statement about them, and the thing a runner wants to do with a statement
/// about them is take it up with someone.
class _Standing extends StatelessWidget {
  const _Standing({required this.standing, required this.onAsk});

  final TrainingStanding standing;
  final void Function(String opener)? onAsk;

  /// What the tap asks on the runner's behalf.
  ///
  /// The standing question, phrased the way a runner would ask it. The coach
  /// answers it against this runner's own history — see the chat instructions
  /// in `supabase/functions/coach/surfaces.ts`, which is where "you versus you"
  /// is enforced rather than hoped for.
  String get _opener => switch (standing.verdict) {
    StandingVerdict.nothingYet => 'What should I be working on first?',
    StandingVerdict.gettingStarted => 'I am just starting out. How am I doing?',
    StandingVerdict.returning => 'I have had time off. How do I come back?',
    StandingVerdict.easing => 'My mileage has dropped. Does that matter?',
    _ => 'How am I doing?',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tappable = onAsk != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionLabel('Your coach'),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.xl),
          onTap: tappable ? () => onAsk!(_opener) : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                standing.headline,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                standing.detail,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
              if (tappable) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: <Widget>[
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: Center(
                        child: CoachLetter(
                          size: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Ask about this',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: AppColors.textTertiary,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Lifetime totals. The distance counts up — it is the number the screen is
/// about, and watching it climb is the point of having it.
class _Lifetime extends StatelessWidget {
  const _Lifetime({required this.stats, required this.unit});

  final RunnerStats stats;
  final UnitSystem unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionLabel('Lifetime', emphasis: LabelEmphasis.stat),
          const SizedBox(height: AppSpacing.sm),
          CountUp(
            value: Distance.meters(stats.totalMeters).inDisplayUnit(unit),
            format: (v) => '${v.toStringAsFixed(1)} ${unit.distanceSuffix}',
            style: theme.textTheme.displayMedium?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: StatBlock(label: 'Runs', value: '${stats.runCount}'),
              ),
              Expanded(
                child: StatBlock(
                  label: 'Time',
                  value: stats.totalDuration.hoursMinutesSeconds,
                ),
              ),
              Expanded(
                child: StatBlock(
                  label: 'Streak',
                  value: stats.currentStreakWeeks <= 0
                      ? '—'
                      : '${stats.currentStreakWeeks} wk',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// What the runner has trained for before.
///
/// Newest first here, unlike the list it is given — labels are *numbered* from
/// the first plan so they stay put, but a runner scanning their own past reads
/// the most recent thing first. Two different orderings for two different jobs.
class _PastPlans extends StatelessWidget {
  const _PastPlans({required this.plans, required this.unit});

  final List<LabelledPlan> plans;
  final UnitSystem unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final newestFirst = plans.reversed.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionLabel('Before this'),
        const SizedBox(height: AppSpacing.md),
        for (final entry in newestFirst)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: AppCard(
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          entry.label,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _describe(entry.record),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _OutcomeMark(outcome: entry.record.outcome),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// The one line under the label: when it ran, and how far they got.
  ///
  /// A week number only when they stopped short. "Week 16 of 16" is a strange
  /// way to say they finished, and the tick beside it already says it.
  String _describe(PlanRecord record) {
    final when = _monthYear(record.startDate);
    if (record.wasSeenThrough) return '$when · ${record.weeks} weeks';
    return '$when · stopped at week ${record.weekReached} of ${record.weeks}';
  }

  static String _monthYear(DateTime d) => '${_months[d.month - 1]} ${d.year}';

  static const List<String> _months = <String>[
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
}

/// How a plan ended, as a mark rather than a word.
///
/// Deliberately quiet. A big red cross beside a block someone stopped would
/// make their own history into a scoreboard, and stopping a block is ordinary —
/// people get injured and change their minds.
class _OutcomeMark extends StatelessWidget {
  const _OutcomeMark({required this.outcome});

  final PlanOutcome outcome;

  @override
  Widget build(BuildContext context) => switch (outcome) {
    PlanOutcome.raced => const Icon(
      Icons.check,
      size: 18,
      color: AppColors.textSecondary,
    ),
    // Nothing at all for the rest. An absent mark reads as "no verdict", which
    // is the truth: the record does not know why they stopped.
    PlanOutcome.leftEarly ||
    PlanOutcome.ended ||
    PlanOutcome.current => const SizedBox.shrink(),
  };
}

/// Personal bests. Absent ones are simply not shown.
class _Records extends StatelessWidget {
  const _Records({required this.stats, required this.unit});

  final RunnerStats stats;
  final UnitSystem unit;

  @override
  Widget build(BuildContext context) {
    final longest = stats.longestRunMeters;
    final fastest = stats.fastestPaceSecondsPerKm;
    if (longest == null && fastest == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionLabel('Records'),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: <Widget>[
            if (longest != null)
              Expanded(
                child: AppCard(
                  child: StatBlock(
                    label: 'Longest run',
                    value: Distance.meters(
                      longest,
                    ).format(unit, fractionDigits: 1),
                  ),
                ),
              ),
            if (longest != null && fastest != null)
              const SizedBox(width: AppSpacing.md),
            if (fastest != null)
              Expanded(
                child: AppCard(
                  child: StatBlock(
                    label: 'Fastest pace',
                    value: Pace.secondsPerKilometer(fastest).format(unit),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// What they are training for, if a plan exists.
class _Goal extends StatelessWidget {
  const _Goal({required this.profile, required this.unit, required this.theme});

  final RunnerProfile profile;
  final UnitSystem unit;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    // Both are optional: a runner keeping a rhythm has neither a goal distance
    // nor a race day, and the card says so rather than inventing them.
    final goalMeters = profile.goalDistanceMeters;
    final goal = goalMeters == null ? null : Distance.meters(goalMeters);
    final event = profile.eventDate;
    final days = event == null ? null : daysBetweenDates(DateTime.now(), event);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionLabel('Training for'),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Row(
            children: <Widget>[
              Expanded(
                child: StatBlock(
                  size: StatSize.large,
                  label: 'Goal',
                  value: goal == null
                      ? '—'
                      : goal.format(
                          unit,
                          fractionDigits: goal.kilometers >= 10 ? 0 : 1,
                        ),
                ),
              ),
              Expanded(
                child: StatBlock(
                  size: StatSize.large,
                  label: days == null
                      ? 'Race day'
                      : (days < 0 ? 'Event was' : 'To go'),
                  value: days == null
                      ? 'none set'
                      : (days < 0 ? '${-days} d ago' : '$days days'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Nothing recorded yet — an invitation, not an error.
class _NoRuns extends StatelessWidget {
  const _NoRuns();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('No runs yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Record your first run and your totals, records and streak will '
            'build here.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
