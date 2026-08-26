import '../../../core/brand.dart';
import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../../coaching/data/plan_repository.dart';
import '../../coaching/domain/coach_note.dart';
import '../../coaching/domain/plan_headline.dart';
import '../../coaching/domain/training_history.dart';
import '../../coaching/domain/week_progress.dart';
import '../../coaching/domain/training_plan.dart';
import '../../coaching/presentation/coach_button.dart';
import '../../coaching/presentation/session_labels.dart';
import '../../profile/domain/runner_stats.dart';
import '../../recording/domain/run_summary.dart';
import 'home_today_tile.dart';
import 'home_week_tile.dart';
import '../../coaching/domain/coach_access.dart';
import 'home_last_run.dart';
import 'training_charts.dart';

/// The app's front page, as **a grid of tiles each carrying one fact**: what is
/// on today, where the week stands, what the runner's own log says about them,
/// and what the coach has noticed.
///
/// ## Why it is a grid
///
/// It was a wordmark, one session card, and then two-thirds of a screen of
/// nothing (IMG_4702). That is a thin front page for a runner in a block and an
/// actively misleading one for a runner without a plan, who saw a card headed
/// *No plan yet* and very little else — a paid screen with the contents taken
/// out, which is the counter-signal
/// [ADR-0019](../../../../docs/decisions/0019-onboarding-is-two-moments.md)
/// names for its own reversal.
///
/// ## What decides whether a tile exists
///
/// **A tile earns its place by being true for every runner every day.** Today
/// is always a day; the week is always a week; a runner always has a log, even
/// an empty one, and a coach who has read it. Everything on the permanent part
/// of this page answers one of those, and none of them needs a plan to have an
/// answer. What a runner with a plan gets is *more in the same tiles* — the day
/// named as a session rather than as a run, the week counted in prescriptions
/// rather than in runs — not extra tiles a free runner sees the outline of.
///
/// Sections that are genuinely about something a runner may never have stay
/// conditional: the missed-session card needs a plan to have missed anything,
/// and the charts need a history to plot.
///
/// Deliberately **not** the record screen. Recording is one thing a runner does
/// here, so it gets a prominent action rather than the whole surface — the home
/// page has to be worth opening on a rest day too.
///
/// Nothing administrative appears here. An email address and a sign-out button
/// are settings, and settings belong where a runner goes looking for them, not
/// on the first thing they see.
class HomeTab extends StatelessWidget {
  const HomeTab({
    super.key,
    required this.onRecord,
    this.onStartSession,
    required this.onOpenPlan,
    this.onOpenCoach,
    this.today,
    this.thisWeek,
    this.headline,
    this.note,
    this.outcomes = const <int, DayOutcome>{},
    this.volumes = const <WeekVolume>[],
    this.consistency = const <List<RunDay>>[],
    this.lastRunAgainst,
    this.access = CoachAccess.free,
    this.onUpgrade,
    this.standing,
    this.stats = RunnerStats.empty,
    this.lastRun,
    this.hasRuns = false,
    this.missed,
    this.onAskCoach,
    this.onAdjustWeek,
    this.onCloseRace,
    this.onOpenRun,
    this.unit = UnitSystem.metric,
    this.now,
  });

  /// Starts tracking a run — the one input that cannot be a sentence, and so
  /// the only physical action left on this screen (ADR-0017).
  final VoidCallback onRecord;

  /// Switches to the Plan tab.
  final VoidCallback onOpenPlan;

  /// Opens the conversation. Null in a build with no coach behind it.
  ///
  /// Separate from [onOpenPlan]: these were one callback that switched tabs, so
  /// the coach's own note opened a plan screen.
  final VoidCallback? onOpenCoach;

  /// Today's prescribed session, when a plan exists.
  final TodayView? today;

  /// This week's sessions, drawn as a ribbon inside the week tile so the runner
  /// can see where in the week they are without leaving Home.
  final TrainingWeek? thisWeek;

  /// What the runner is working on and where they are in it, already resolved
  /// for the plan's shape. Null when there is no plan, which is the only case
  /// where a greeting is the most useful thing this space can hold.
  final PlanHeadline? headline;

  /// The coach's current observation, if there is an honest one to make. Null
  /// no longer hides the tile — see [_CoachTile].
  final CoachNote? note;

  /// What became of each prescribed day this week, derived from the run log.
  final Map<int, DayOutcome> outcomes;

  /// Weekly distance for the volume chart, oldest first.
  final List<WeekVolume> volumes;

  /// Starts today's prescribed session, with the prescription attached so the
  /// in-run screen can count down what is left of it.
  ///
  /// Null falls back to [onRecord], which is right for every caller that has no
  /// plan to start: a free run and "the session" are the same run when there is
  /// no session.
  final VoidCallback? onStartSession;

  /// What the coach asked for on the day of [lastRun], when it answered a
  /// session. Null for an unplanned run, for a runner with no plan, and for a
  /// run that matched nothing — and all three mean the same thing here: there
  /// is no comparison to draw, bought or not.
  final PlannedAgainst? lastRunAgainst;

  /// Whether the coach's reading of a run is paid for.
  ///
  /// Defaults to [CoachAccess.free] because that is the direction a mistake
  /// has to fall (ADR-0014), and because nothing sets the other value yet.
  final CoachAccess access;

  /// Opens whatever explains what a coach adds. Null hides the offer rather
  /// than showing a control that does nothing.
  final VoidCallback? onUpgrade;

  /// Did-you-run, by day, for the week strip. Its **last row is the
  /// current week**, which is what the week tile draws for a runner with no
  /// plan — the same derivation serving both, rather than a second one that
  /// could disagree with the grid a few hundred pixels below it.
  final List<List<RunDay>> consistency;

  /// Where this week stands against what was asked.
  final WeekStanding? standing;

  /// Lifetime totals and bests, for the tiles that hold them open.
  final RunnerStats stats;

  /// The newest run on record. Drives "have they run today" and the last-run
  /// tile; null for a runner who has not recorded one.
  final RunSummary? lastRun;

  /// Whether the runner has ever recorded a run. Decides whether they are new
  /// enough to want the explainer, and whether the charts have anything to
  /// plot.
  final bool hasRuns;

  /// What to raise about days that went by without a run, if anything.
  final MissedPrompt? missed;

  /// Puts a sentence to the coach on the runner's behalf. Every answer Home
  /// offers to a missed day goes through here rather than writing anything
  /// itself.
  final void Function(String opener)? onAskCoach;

  /// Opens the way to bend this week — ill, sore, behind, out of time. Null
  /// when there is no plan to bend or no coach to bend it.
  final VoidCallback? onAdjustWeek;

  /// Opens the flow that records what they ran on race day and ends the plan.
  /// Null when the plan is not aimed at a date, or the race is not in view.
  final VoidCallback? onCloseRace;

  /// Opens a recorded run. Null hides the tap on the last-run tile rather than
  /// offering a target that does nothing.
  final void Function(RunSummary run)? onOpenRun;

  final UnitSystem unit;

  /// The clock, injectable so a test can pin the hour.
  ///
  /// One reading of it for the whole page, for the reason the shell gives about
  /// its own: an eyebrow and a session name that disagree about the time of day
  /// are worse than either being absent, and this page holds three surfaces
  /// that each used to call `DateTime.now()` for themselves.
  final DateTime? now;

  /// Whether today's tile is already showing [run].
  ///
  /// True only with no plan and a run recorded today, which is exactly when
  /// [HomeTodayTile] falls back to the log to answer the day.
  bool _todayAlreadyShows(RunSummary? run, DateTime at) {
    if (today != null || run == null) return false;
    final d = run.startedAt;
    return d.year == at.year && d.month == at.month && d.day == at.day;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final at = now ?? DateTime.now();
    final thisWeeksDays = consistency.isEmpty
        ? const <RunDay>[]
        : consistency.last;

    return Scaffold(
      body: PhotoBackdrop(
        image: 'assets/images/backgrounds/in-run.jpg',
        // `balanced` rather than `grounded`: the content here starts at the top
        // and the list scrolls, so the photo needs to breathe through the middle
        // instead of being pinned behind the base.
        scrim: ScrimStrength.balanced,
        opacity: 0.34,
        alignment: Alignment.topCenter,
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xl,
              AppSpacing.xl,
              // The coach mark floats over this tab too, so the last card needs
              // the same room the Plan tab leaves it.
              kCoachMarkClearance,
            ),
            children: <Widget>[
              Entrance(
                child: _Header(theme: theme, headline: headline, at: at),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Today leads, because it is the question a runner opens the app
              // to answer — and it carries the action as well as the answer,
              // rather than describing the session and leaving a generic button
              // underneath to ignore it.
              Entrance(
                index: 1,
                child: HomeTodayTile(
                  now: at,
                  unit: unit,
                  today: today,
                  lastRun: lastRun,
                  outcomes: outcomes,
                  onFreeRun: onRecord,
                  onStartSession: onStartSession ?? onRecord,
                  onOpenPlan: onOpenPlan,
                  onOpenCoach: onOpenCoach,
                  onAdjustWeek: onAdjustWeek,
                  onCloseRace: onCloseRace,
                ),
              ),

              // Raised, never silently absorbed — and both answers are
              // sentences handed to the coach rather than buttons that write
              // training state (ADR-0017). Directly under today because it is
              // about a day that has already gone by.
              if (missed != null && onAskCoach != null) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Entrance(
                  index: 2,
                  child: _MissedCard(prompt: missed!, onAsk: onAskCoach!),
                ),
              ],

              const SizedBox(height: AppSpacing.md),
              Entrance(
                index: 3,
                child: HomeWeekTile(
                  now: at,
                  unit: unit,
                  week: thisWeek,
                  outcomes: outcomes,
                  standing: standing,
                  runDays: thisWeeksDays,
                  onOpenPlan: onOpenPlan,
                ),
              ),

              // Skipped when the tile above is already showing this run.
              //
              // A runner with no plan whose last run was today gets it named,
              // measured and paced on the Today tile — the log is what answers
              // "today" when no session does. Drawing it again immediately
              // underneath is the same run twice on one screen, which reads as
              // a bug however correct both copies are. With a plan there is no
              // clash: Today is the session and this is the run.
              if (!_todayAlreadyShows(lastRun, at)) ...<Widget>[
                const SizedBox(height: AppSpacing.xl),
                Entrance(
                  index: 4,
                  child: LastRunCard(
                    run: lastRun,
                    unit: unit,
                    against: lastRunAgainst,
                    access: access,
                    onOpenRun: onOpenRun,
                    onUpgrade: onUpgrade,
                  ),
                ),
              ],

              // A runner with nothing yet used to get one text link out of here
              // and then a photograph. That was defensible while every runner
              // was on their way to a plan; it is not now that a plan is
              // something you opt into and most of this screen's visitors will
              // never have one (ADR-0019).
              //
              // It sits directly under the grid it explains: those four tiles
              // are what "totals, records and your whole history" looks like,
              // and the card names the one promise they cannot show — the route
              // and the splits, which live inside a run.
              //
              // Not a third way in. There are exactly two ways into Runio —
              // press start, or say something to the coach (ADR-0017) — and
              // both are already above this.
              if (today == null && !hasRuns) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Entrance(index: 5, child: _FirstRun(onOpenPlan: onOpenPlan)),
              ],

              // No explainer here. "How this works" moved to the Plan tab,
              // where the runner it is written for actually is: someone with no
              // plan opens Plan to get one, and that screen had nothing on it
              // but a photograph and a button.
              // The coach's note is not a section any more. It reads the last
              // run, so it lives inside that card, under the numbers it is
              // about — see [LastRunCard]. A floating remark above a chart was
              // the coach talking near the runner rather than to them.
              //
              // And a runner with no plan has no coach at all: the subscription
              // buys one (ADR-0019), so an empty card headed FROM YOUR COACH is
              // an advert for something they have not got, on a screen that is
              // supposed to be a whole free product.

              // The long view, under the day. These answer questions the tiles
              // above do not — am I building, and have I been turning up.
              //
              // Both are absent until there is something to plot. A chart of
              // one week is a bar, and a grid of nothing is a scorecard the
              // runner has not had a chance to fill in yet. That is not the
              // empty-state rule being broken: the tiles above state the page's
              // structure, and these two are the depth behind it.
              if (hasRuns) ...<Widget>[
                if (volumes.isNotEmpty && standing != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.xl),
                  Entrance(
                    index: 7,
                    child: VolumeChart(
                      weeks: volumes,
                      standing: standing!,
                      unit: unit,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// No identity, still. An email address is an account fact and lives in
/// Settings.
///
/// The greeting is kept for the one case where it is the most useful thing this
/// space can hold — a runner with no plan, where there is genuinely nothing to
/// count down to and a blank would be colder than a hello.
class _Header extends StatelessWidget {
  const _Header({required this.theme, required this.at, this.headline});

  final ThemeData theme;
  final DateTime at;
  final PlanHeadline? headline;

  @override
  Widget build(BuildContext context) {
    final plan = headline;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          kAppName.toUpperCase(),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
          ),
        ),
        // **One quiet line, or none.**
        //
        // Three versions of this have now been wrong in three different ways.
        // It was the time of day, which is warm and is also the one thing a
        // runner knew before they opened the app. It became the goal at display
        // size — which fixed that, and introduced a worse fault: "Marathon" is a
        // static noun that does not change for sixteen weeks, so the largest
        // thing on the front page became the least alive.
        //
        // What actually earns space is the part that moves. `112 days` is
        // different tomorrow and `week 1 of 16` is different next Monday, and
        // the goal is the word that makes them mean anything — so all three sit
        // together at the weight of a caption rather than one of them being a
        // headline. The size goes back to today's card, which is what the page
        // is for.
        //
        // **The greeting survives where nothing is competing with it.** With no
        // plan there is no countdown, no position and no goal — and a blank
        // here is colder than a hello. It keeps its size there, because it is
        // then the only thing this space has to say rather than the least
        // interesting of three.
        const SizedBox(height: AppSpacing.sm),
        if (plan == null)
          Text(
            // [timeOfDayName], not a private copy of it. This header had its
            // own `_greeting()` with the same three words and the same two
            // boundaries, kept in step by hand — two answers to "what time of
            // day is it" in one app, waiting for somebody to move one boundary.
            timeOfDayName(at),
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.05,
            ),
          )
        else
          Text(
            '${plan.goal}  ·  ${plan.position}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
      ],
    );
  }
}

/// The top of Home: the wordmark, then **what the runner is working on**.
///
/// The largest, first thing on the app's front page used to be the time of day.
/// "Afternoon" is warm and it is also the one line on the screen that a runner
/// already knew before they opened it — while the fact they came for, that
/// there is a half marathon in 75 days and this is week 2 of 12, lived a tab
/// away. The headline the Plan tab is topped with belongs here at least as
/// much: this is the page opened every morning, that one is opened to plan.
///
/// No identity, still. An email address is an account fact and lives in
/// Settings.
///
class _FirstRun extends StatelessWidget {
  const _FirstRun({required this.onOpenPlan});

  final VoidCallback onOpenPlan;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionLabel('Once you run'),
          const SizedBox(height: AppSpacing.md),
          const _FirstRunLine(
            icon: Icons.route_outlined,
            text: 'Your route, pace and splits, every time',
          ),
          const SizedBox(height: AppSpacing.md),
          const _FirstRunLine(
            icon: Icons.insights_outlined,
            text: 'Totals, records and your whole history in one place',
          ),
          const SizedBox(height: AppSpacing.md),
          // The coach's own mark rather than a speech bubble, so the thing the
          // app is named for is recognisable before it has said anything.
          const _FirstRunLine(
            text: 'A coach that answers questions about any of it',
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: AppTextButton(
              label: 'Training for something? See how plans work',
              onPressed: onOpenPlan,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One line of [_FirstRun]. A [CoachLetter] where no [icon] is given, so the
/// coach's line carries the coach's mark.
class _FirstRunLine extends StatelessWidget {
  const _FirstRunLine({required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 20,
          height: 20,
          child: Center(
            child: icon == null
                ? const CoachLetter(size: 16, color: AppColors.textSecondary)
                : Icon(icon, size: 18, color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

/// A day that went by without a run, and the two things the runner can say
/// about it.
///
/// **Both answers are sentences, not writes.** The card asks what a coach asks
/// first — did you actually miss it? — and hands either answer to the
/// conversation, where the `log_run` and adaptation surfaces already live. Home
/// changes nothing itself (ADR-0017).
class _MissedCard extends StatelessWidget {
  const _MissedCard({required this.prompt, required this.onAsk});

  final MissedPrompt prompt;
  final void Function(String opener) onAsk;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(
                Icons.history_toggle_off,
                size: 20,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  prompt.headline,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => onAsk(prompt.logOpener),
                  child: const Text('I ran it'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: FilledButton(
                  onPressed: () => onAsk(prompt.adjustOpener),
                  child: const Text('Adjust'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
