import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../../coaching/domain/plan_history.dart';
import '../../coaching/domain/prescribed_distance.dart';
import '../../coaching/domain/runner_profile.dart';
import '../../coaching/domain/stored_plan.dart';
import '../../coaching/domain/training_history.dart';
import '../../coaching/domain/training_standing.dart';
import '../../coaching/presentation/coach_button.dart';
import 'year_grid.dart';
import '../../history/presentation/route_thumbnail.dart';
import '../../history/presentation/run_tile.dart';
import '../../recording/domain/best_effort.dart';
import '../../recording/domain/run_point.dart';
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
/// nothing to keep in sync.
///
/// **A runner with no history sees this same page, held open.** The sections do
/// not vanish when there is nothing in them yet: the lifetime card, the coach's
/// read, the records and the log all render with their figures as dashes, so
/// somebody who has not run yet can see what the page will tell them once they
/// have. The page used to collapse to a single "No runs yet" card over bare
/// background, which reads as broken rather than as new — the counter-signal
/// [ADR-0019](../../../../docs/decisions/0019-onboarding-is-two-moments.md)
/// names for a free surface, arrived at from the run side instead of the plan
/// side.
///
/// The rule the empty tiles follow: **a dash is an absence, a zero is a claim.**
/// `0.0 km` and `0:00 /km` are numbers this app has not earned, and a runner
/// cannot tell an unearned number from a wrong one. The unit is stated once, on
/// the lifetime figure, where a distance with no unit promises nothing; the
/// tiles below it are labelled and can stay quiet.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.stats,
    this.pastPlans = const <LabelledPlan>[],
    this.profile,
    this.standing,
    this.runs = const <RunSummary>[],
    this.now,
    this.unit = UnitSystem.metric,
    this.onOpenRun,
    this.onAddRun,
    this.onAskCoach,
    this.onOpenSettings,
  });

  final RunnerStats stats;

  /// The clock the year view is drawn against. Injected rather than read here
  /// so a plate and a test can stand on a fixed day — a grid whose last column
  /// moves with the calendar is a grid no assertion can pin.
  final DateTime? now;

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

  /// Read once per build rather than per use, so the year grid's last column
  /// and its "today" square cannot disagree inside one frame.
  DateTime get _now => widget.now ?? DateTime.now();

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
              // cost (docs/history/design-system.md).
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
                  AppIconButton(
                    icon: Icons.settings_outlined,
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
                  // did. It leads on an empty log too, holding that figure open
                  // at a dash, with the invitation to record a first run sitting
                  // under the totals it is describing.
                  Entrance(
                    child: _Lifetime(stats: stats, unit: widget.unit),
                  ),

                  // Shown on an empty log as well, which reverses the decision
                  // this comment used to record. The old reasoning was that the
                  // standing's empty copy — "record a run… there is nothing to
                  // compare you against" — only repeated the card above it, and
                  // on the old screen that was true: those two sentences *were*
                  // the whole page, one of them an empty state explaining why it
                  // had nothing to say.
                  //
                  // What changed is what sits between them. The runner now
                  // arrives at this card having read their lifetime figures held
                  // open above it, so it is no longer a second apology; it is
                  // the coach claiming a place on the page from day one. Hiding
                  // it meant a new runner could not tell that anybody was going
                  // to look at their training at all — the profile of a runner
                  // with no runs said nothing about them and promised nothing
                  // either, and a screen that only announces its own emptiness
                  // is the thing ADR-0019 is trying to keep off a free surface.
                  //
                  // Null still hides it, for the reason the field documents: a
                  // caller that has not worked out a standing, rather than a
                  // runner without one.
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

                  const SizedBox(height: AppSpacing.xl),
                  Entrance(
                    index: 2,
                    child: _Records(stats: stats, unit: widget.unit),
                  ),

                  // The long view, and the reason it is here rather than on
                  // Home: a year is a fact about the runner, and Home is about
                  // this week. It is drawn on an empty log too — the shape of
                  // the year is the promise, and a runner who has recorded
                  // nothing is exactly the person deciding whether the promise
                  // is worth anything.
                  const SizedBox(height: AppSpacing.xl),
                  Entrance(
                    index: 3,
                    child: YearGrid(
                      weeks: runYear(runs: widget.runs, now: _now),
                      unit: widget.unit,
                    ),
                  ),

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

                  // The log heads itself even when it is empty. A runner who
                  // has not run has still come to a page about their runs, and
                  // an unheaded gap at the bottom of it is the thing that made
                  // the old screen trail off into background.
                  const SizedBox(height: AppSpacing.xl),
                  Entrance(
                    index: 5,
                    child: _LogHeader(
                      count: runs.length,
                      onAdd: widget.onAddRun,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Two rows in the shape a run takes, so the promise reaches
                  // the level a runner actually reads their training at: not
                  // "totals will appear" but "each run lands here, with its
                  // route, its date, how long it took and how fast it was".
                  if (runs.isEmpty)
                    const Entrance(index: 6, child: _LogPlaceholder()),
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
///
/// With nothing in the log it names the section instead of counting it. "0 runs"
/// is the zero this screen refuses everywhere else, and "newest first" is a
/// claim about an order that has nothing in it to order; the heading's job on an
/// empty log is simply to say what the rows below it are going to be.
///
/// *Add a run* survives the empty case, and is the one control that matters
/// most there: somebody who ran this morning without the app has a run to put
/// in, and until now the only affordance for it was hidden behind having
/// already recorded one.
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
        SectionLabel(switch (count) {
          0 => 'Your runs',
          1 => '1 run',
          _ => '$count runs',
        }),
        if (onAdd != null)
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add a run'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              visualDensity: VisualDensity.compact,
            ),
          )
        else if (count > 0)
          Text(
            'Newest first',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.textTertiary,
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
///
/// **Before there is a first run this card is the empty state**, rather than
/// being swapped out for one. Four figures the runner is going to watch — the
/// lifetime distance, how many runs it took, how long they spent and how many
/// weeks in a row — held open as dashes, with the sentence that used to be the
/// whole screen sitting underneath them. That sentence names totals, records
/// and streak, which is now a caption for placeholders the runner can see
/// rather than a description of a page they cannot.
///
/// The figure does not count up to nothing. [CountUp] animating 0.0 → 0.0 is a
/// flourish over an absence, and the unit is carried on the dash instead: a
/// blank where a distance goes promises nothing, `— km` promises kilometres.
class _Lifetime extends StatelessWidget {
  const _Lifetime({required this.stats, required this.unit});

  final RunnerStats stats;
  final UnitSystem unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final empty = stats.isEmpty;

    // Placeholders sit a step back from real figures. A dash rendered at full
    // strength beside a live number would read as a value that had gone wrong;
    // dimmed, the whole card reads as waiting, which is what it is doing.
    final waiting = empty ? AppColors.textTertiary : null;

    final heroStyle = theme.textTheme.displayMedium?.copyWith(
      fontWeight: FontWeight.w700,
      height: 1,
      color: waiting,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );

    // Tightened from `xl` padding and `lg` gaps. Three figures and a headline
    // were taking a third of the fold on the page that has the most to say, and
    // the air was not doing any work — the card already reads as one block
    // because it is a card.
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionLabel('Lifetime', emphasis: LabelEmphasis.stat),
          const SizedBox(height: AppSpacing.xs),
          if (empty)
            Text('— ${unit.distanceSuffix}', style: heroStyle)
          else
            CountUp(
              value: Distance.meters(stats.totalMeters).inDisplayUnit(unit),
              // A tenth of a kilometre is a real distinction on a single run
              // and none at all on a career: `3119.8 km` spends two of its six
              // glyphs on a hundred metres run some time in March. Below ten
              // the decimal is most of the number, so it stays.
              format: (v) => v >= 10
                  ? '${v.round()} ${unit.distanceSuffix}'
                  : '${v.toStringAsFixed(1)} ${unit.distanceSuffix}',
              style: heroStyle,
            ),
          const SizedBox(height: AppSpacing.md),
          Row(
            // Labels on one line. The default centres the three columns against
            // each other, so the moment one of them shrinks to fit — see the
            // note on TIME below — its eyebrow drops a few pixels and the row
            // stops reading as a row.
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: StatBlock(
                  label: 'Runs',
                  value: empty ? '—' : '${stats.runCount}',
                  valueColor: waiting,
                ),
              ),
              Expanded(
                child: StatBlock(
                  label: 'Time',
                  value: empty ? '—' : stats.totalDuration.totalHours,
                  valueColor: waiting,
                  // `305 h`, not `305:32:23`. This column has no upper bound
                  // and a `Text` in a tight `Expanded` clips **silently** — no
                  // overflow stripe inside a bounded box — so the full reading
                  // drew straight through the streak beside it and rendered
                  // `305:32:2353 wk`. `shrinkToFit` was the first fix and it
                  // only made an unreadable figure smaller; the seconds were
                  // never worth a glyph on a career. See
                  // [DurationFormat.totalHours].
                  shrinkToFit: true,
                ),
              ),
              Expanded(
                child: StatBlock(
                  label: 'Streak',
                  // A dash here on a log that *does* have runs is a lapsed
                  // streak rather than a placeholder, and keeps its full
                  // strength: it is a fact about this runner, not a slot.
                  value: stats.currentStreakWeeks <= 0
                      ? '—'
                      : '${stats.currentStreakWeeks} wk',
                  valueColor: waiting,
                ),
              ),
            ],
          ),
          if (empty) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Record your first run and your totals, records and streak will '
              'build here.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
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
  ///
  /// **The time takes the line where there is one**, because it is the answer
  /// to what the plan was for. "Aug 2026 · 16 weeks" describes the process; a
  /// runner reading their own history wants the result, and the process is the
  /// thing they already remember.
  String _describe(PlanRecord record) {
    final when = _monthYear(record.startDate);
    final time = record.raceTime;
    if (time != null) return '$when · ${time.hoursMinutesSeconds}';
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
    // Nothing at all for the rest, **including a race they did not start.**
    // An absent mark reads as "no verdict", which is the truth even now that
    // the record knows: a runner who did not race got injured, or the event
    // was cancelled, or they changed their mind, and none of those is a thing
    // to put a symbol beside on someone's own history.
    PlanOutcome.didNotRace ||
    PlanOutcome.leftEarly ||
    PlanOutcome.ended ||
    PlanOutcome.current => const SizedBox.shrink(),
  };
}

/// Personal bests.
///
/// Two kinds of record, kept visibly apart because they are read off different
/// things. The two cards are facts about **whole runs** — the longest one, and
/// the best average pace over one. The table under them is the fastest
/// continuous 5 km, 10 km, half or full found **inside** a run, cut from the
/// trace when the run finished (ADR-0026). Putting a 10K time in a card beside
/// "longest run" would invite the reading the whole design exists to refuse:
/// that a 10.18 km run's 58:28 is a 10K record. It is not; the 10K inside it
/// was about a minute quicker.
///
/// A record a runner has runs but no figure for — every run under a kilometre,
/// so no pace qualifies — is still simply not shown among the cards. That is a
/// gap in a real record, and inventing a slot for it would be reporting on a
/// thing that has not happened yet in the middle of things that have.
///
/// **The four race rows are different: they are always all there.** Somebody
/// who has never run 10 km sees the 10K row with a dash in it, and that is the
/// point — the row is naming a distance, not claiming a time. It is what makes
/// the section legible to a runner with nothing in it yet, which is the rule
/// this whole page lives by: a screen with no data states its structure, and a
/// dash is an absence where a zero would be a claim.
///
/// **Both cards absent is a different case**, and it is only ever the empty
/// log: anybody with one run has a longest one. So the section holds both bests
/// open instead of disappearing, because "what does this app consider a record"
/// is exactly what a runner with nothing recorded wants to know, and the answer
/// is worth more before the first run than after it.
class _Records extends StatelessWidget {
  const _Records({required this.stats, required this.unit});

  final RunnerStats stats;
  final UnitSystem unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final longest = stats.longestRunMeters;
    final fastest = stats.fastestPaceSecondsPerKm;
    final empty = longest == null && fastest == null;
    final waiting = empty ? AppColors.textTertiary : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionLabel('Records'),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: <Widget>[
            if (longest != null || empty)
              Expanded(
                child: AppCard(
                  child: StatBlock(
                    label: 'Longest run',
                    value: longest == null
                        ? '—'
                        : Distance.meters(
                            longest,
                          ).format(unit, fractionDigits: 1),
                    valueColor: waiting,
                  ),
                ),
              ),
            if (fastest != null || empty) ...<Widget>[
              if (longest != null || empty)
                const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppCard(
                  child: StatBlock(
                    label: 'Fastest pace',
                    value: fastest == null
                        ? '—'
                        : Pace.secondsPerKilometer(fastest).format(unit),
                    valueColor: waiting,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        // **Labelled, because it stopped being a PB table.** These four rows
        // used to sit unlabelled under "Records", which made them read as
        // bests — and a best is the wrong answer to "what is my 5K": it is one
        // day, by construction the untypical one, and for most runners a number
        // they set once and cannot repeat. What moves with the training, and so
        // what this page is for, is the average.
        const SectionLabel('Typical', emphasis: LabelEmphasis.stat),
        const SizedBox(height: AppSpacing.sm),
        // One card holding four rows rather than four more cards. A table is
        // how runners already read these — a column of distances against a
        // column of times — and four extra cards would push the year grid off
        // the fold to say the same thing at three times the height.
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (var i = 0; i < kRecordDistancesMeters.length; i++)
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : AppSpacing.md),
                  child: _RaceRecord(
                    meters: kRecordDistancesMeters[i],
                    typical: stats.averageEffortAt(kRecordDistancesMeters[i]),
                  ),
                ),
              // Only for the runner it could bite. A record is read off a
              // trace, so a race typed in by hand sets none — and the runner
              // who does that is looking at a marathon in their log and a dash
              // beside "Marathon", with no way to work out why.
              if (stats.hasRecordlessRuns) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Averaged from your routes, over every unbroken stretch of '
                  'each distance inside a run — not the runs’ own times. A '
                  'run without a route counts towards none of them.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One row of the table: the distance as runners say it, and what it usually
/// takes.
///
/// The name comes from `raceName`, which exists for exactly this — "Half
/// marathon" is both shorter and more accurate than "21 km", which is a
/// rounding of 21.0975, or than "13 mi", which is a rounding of 13.1.
///
/// The name is rendered as a label rather than as a value, and that is not only
/// styling: it is what makes "5K" on an empty profile a heading rather than a
/// number the app has not earned.
class _RaceRecord extends StatelessWidget {
  const _RaceRecord({required this.meters, required this.typical});

  final double meters;
  final Duration? typical;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = typical;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Expanded(
          child: SectionLabel(
            // Never null for these four — they are the distances `raceName`
            // was written for — but the fallback is a distance rather than a
            // crash if a fifth is ever added to one list and not the other.
            raceName(meters) ?? formatPrescribed(meters, UnitSystem.metric),
            emphasis: LabelEmphasis.stat,
          ),
        ),
        Text(
          time == null ? '—' : time.hoursMinutesSeconds,
          style: theme.textTheme.titleMedium?.copyWith(
            // A dash sits a step back, the way the held-open figures above it
            // do: at full strength beside a real time it reads as a value that
            // has gone wrong rather than as one not set yet.
            color: time == null ? AppColors.textTertiary : null,
            fontFeatures: const <ui.FontFeature>[
              ui.FontFeature.tabularFigures(),
            ],
          ),
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

/// The shape a run takes in the log, before there is one to put in it.
///
/// Two rows rather than one, because one row is an item and two are a list —
/// and the list is the promise. They carry the same furniture a real
/// [RunTile] does: the route sketch on the left, the distance as the headline,
/// and the three things underneath it named rather than blanked, so the row
/// reads as a legend for what a run is going to say about itself.
///
/// **No chevron, and nothing to tap.** A real row opens the run behind it; a
/// placeholder with an arrow on it is a control that does nothing, which is a
/// worse first impression than an empty page. The card that used to be the
/// whole empty state — "No runs yet" over its invitation — is gone from here on
/// purpose: its one useful sentence moved up into the lifetime card, where it
/// captions the figures it was always talking about, and the headline over it
/// was the sentence that made the screen read as broken.
class _LogPlaceholder extends StatelessWidget {
  const _LogPlaceholder();

  /// The second row is quieter than the first, so the log reads as a list that
  /// carries on rather than as exactly two empty slots waiting to be filled.
  static const List<double> _fade = <double>[1, 0.55];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: <Widget>[
        for (final (i, opacity) in _fade.indexed)
          Padding(
            padding: EdgeInsets.only(
              bottom: i == _fade.length - 1 ? 0 : AppSpacing.sm,
            ),
            child: Opacity(
              opacity: opacity,
              child: AppCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: <Widget>[
                    // The real thumbnail, given the route it does not have. It
                    // draws its own "no route" state — the same one a treadmill
                    // run gets — so the placeholder is the component rather than
                    // a drawing of the component.
                    const RouteThumbnail(points: <RunPoint>[], size: 52),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '—',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textTertiary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Date  ·  time  ·  pace',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
