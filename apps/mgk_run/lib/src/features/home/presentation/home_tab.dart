import '../../../core/brand.dart';
import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../../coaching/data/plan_repository.dart';
import '../../coaching/domain/coach_note.dart';
import '../../coaching/domain/plan_headline.dart';
import '../../coaching/domain/training_history.dart';
import '../../coaching/domain/session_effort.dart';
import '../../coaching/domain/week_progress.dart';
import '../../coaching/domain/training_plan.dart';
import '../../coaching/presentation/coach_button.dart';
import '../../coaching/presentation/session_labels.dart';
import '../../coaching/presentation/week_ribbon.dart';
import 'training_charts.dart';

/// The app's front page: what's on today, what the coach has noticed, the last
/// few runs, and the way into a new one.
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
    required this.onOpenPlan,
    this.onOpenCoach,
    this.today,
    this.thisWeek,
    this.headline,
    this.note,
    this.outcomes = const <int, DayOutcome>{},
    this.volumes = const <WeekVolume>[],
    this.consistency = const <List<RunDay>>[],
    this.standing,
    this.hasRuns = false,
    this.missed,
    this.onAskCoach,
    this.onAdjustWeek,
    this.unit = UnitSystem.metric,
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

  /// This week's sessions, drawn as a ribbon above today so the runner can see
  /// where in the week they are without leaving Home.
  final TrainingWeek? thisWeek;

  /// What the runner is working on and where they are in it, already resolved
  /// for the plan's shape. Null when there is no plan, which is the only case
  /// where a greeting is the most useful thing this space can hold.
  final PlanHeadline? headline;

  /// The coach's current observation, if there is an honest one to make.
  final CoachNote? note;

  /// What became of each prescribed day this week, derived from the run log.
  final Map<int, DayOutcome> outcomes;

  /// Weekly distance for the volume chart, oldest first.
  final List<WeekVolume> volumes;

  /// Did-you-run, by day, for the consistency grid.
  final List<List<RunDay>> consistency;

  /// Where this week stands against what was asked.
  final WeekStanding? standing;

  /// Whether the runner has ever recorded a run. Only used to decide whether
  /// they are new enough to want the explainer — it went on "no recent runs on
  /// screen" until the recent-runs list was removed, which showed a runner with
  /// ten runs and no plan a page telling them what the app is for.
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

  final UnitSystem unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                child: _Header(theme: theme, headline: headline),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Today leads, because it is the question a runner opens the app
              // to answer — and it now carries the action as well as the
              // answer, rather than describing the session and leaving a
              // generic button underneath to ignore it.
              Entrance(
                index: 1,
                child: _Today(
                  today: today,
                  thisWeek: thisWeek,
                  outcomes: outcomes,
                  unit: unit,
                  onOpenPlan: onOpenPlan,
                  onOpenCoach: onOpenCoach,
                  onRecord: onRecord,
                  onAdjustWeek: onAdjustWeek,
                ),
              ),

              // Raised, never silently absorbed — and both answers are
              // sentences handed to the coach rather than buttons that write
              // training state (ADR-0017).
              if (missed != null && onAskCoach != null) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Entrance(
                  index: 2,
                  child: _MissedCard(prompt: missed!, onAsk: onAskCoach!),
                ),
              ],

              // A runner with nothing yet used to get one text link out of
              // here and then a photograph. That was defensible while every
              // runner was on their way to a plan; it is not now that a plan is
              // something you opt into and most of this screen's visitors will
              // never have one (ADR-0019). This is the screen somebody decides
              // on, and it was showing them an empty version of a product they
              // had not been offered.
              //
              // So: what Runio does with a run, before there is one to show.
              // Not a third way in — recording and talking are the only two
              // (ADR-0017), and both are already on the card above.
              if (today == null && !hasRuns) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                Entrance(index: 3, child: _FirstRun(onOpenPlan: onOpenPlan)),
              ],

              // No explainer here. "How this works" moved to the Plan tab,
              // where the runner it is written for actually is: someone with no
              // plan opens Plan to get one, and that screen had nothing on it
              // but a photograph and a button.
              if (note != null) ...<Widget>[
                const SizedBox(height: AppSpacing.xl),
                Entrance(
                  index: 4,
                  child: _CoachNoteCard(
                    note: note!,
                    // The coach's own observation opens the coach. It used to
                    // open the Plan tab, which is a different thing wearing the
                    // same callback.
                    onTap: onOpenCoach ?? onOpenPlan,
                  ),
                ),
              ],

              // The long view, under the day. Recents was three rows of the
              // four facts Profile already owns; these answer questions Profile
              // does not — am I building, and have I been turning up.
              //
              // Both are absent until there is something to plot. A chart of
              // one week is a bar, and a grid of nothing is a scorecard the
              // runner has not had a chance to fill in yet.
              if (hasRuns) ...<Widget>[
                if (volumes.isNotEmpty && standing != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.xl),
                  Entrance(
                    index: 5,
                    child: VolumeChart(
                      weeks: volumes,
                      standing: standing!,
                      unit: unit,
                    ),
                  ),
                ],
                if (consistency.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  Entrance(index: 6, child: ConsistencyGrid(grid: consistency)),
                ],
              ],
            ],
          ),
        ),
      ),
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
/// The greeting is kept for the one case where it is the most useful thing this
/// space can hold — a runner with no plan, where there is genuinely nothing to
/// count down to and a blank would be colder than a hello.
class _Header extends StatelessWidget {
  const _Header({required this.theme, this.headline});

  final ThemeData theme;
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
        const SizedBox(height: AppSpacing.sm),
        Text(
          plan?.goal ?? _greeting(),
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.05,
          ),
        ),
        if (plan != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            plan.position,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Morning';
    return hour < 18 ? 'Afternoon' : 'Evening';
  }
}

/// What's on today — a prescribed session, a rest day, or an invitation to get
/// a plan. Glass, because it sits over the photograph.
class _Today extends StatelessWidget {
  const _Today({
    required this.today,
    required this.thisWeek,
    required this.outcomes,
    required this.unit,
    required this.onOpenPlan,
    required this.onRecord,
    this.onOpenCoach,
    this.onAdjustWeek,
  });

  final TodayView? today;
  final TrainingWeek? thisWeek;
  final Map<int, DayOutcome> outcomes;
  final UnitSystem unit;
  final VoidCallback onOpenPlan;
  final VoidCallback onRecord;
  final VoidCallback? onOpenCoach;
  final VoidCallback? onAdjustWeek;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = today;

    return GlassSurface(
      padding: const EdgeInsets.all(AppSpacing.xl),
      tintOpacity: 0.12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Resolved by the repository, not branched on here: a phase is block
          // vocabulary, and this card must not know which shapes have one
          // (ADR-0011).
          SectionLabel(
            session == null ? 'Today' : session.heading,
            emphasis: LabelEmphasis.stat,
          ),
          const SizedBox(height: AppSpacing.md),
          if (thisWeek != null) ...<Widget>[
            // Outcomes for the whole week, derived from the log. It used to get
            // a status for today and nothing else, so six of the seven cells
            // could only say "there is a session here".
            WeekRibbon(
              week: thisWeek!,
              today: DateTime.now(),
              outcomes: outcomes,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (session == null || session.session == null) ...<Widget>[
            Text(
              session == null
                  ? 'No plan yet'
                  : session.support == null
                  ? 'Rest day'
                  : kindLabel(session.support!.kind),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              session == null
                  ? 'Run whenever you like — or let the coach build a plan '
                        'around a goal.'
                  // A day carrying strength is not a rest day, and saying
                  // "nothing scheduled" over one contradicted the Plan tab
                  // reading the same week. What is *in* the session is Liftio's
                  // to say, not Runio's (ADR-0010) — so this says when, and
                  // stops.
                  : session.support == null
                  ? 'Nothing scheduled. Rest is part of the plan.'
                  // Dashed rather than a second sentence: the cues are written
                  // lowercase for the week list, where they trail a session
                  // name, so a full stop in front of one reads as a typo.
                  : 'No run today — ${effortFor(session.support!.kind).cue}.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            // What is coming, so a rest day is a position in a week rather
            // than a blank. Only when the rest of the week actually holds
            // something — on a Sunday it says nothing rather than reaching into
            // next week, which is not generated yet.
            if (session != null && thisWeek != null) ...<Widget>[
              Builder(
                builder: (context) {
                  final next = nextRunAfter(thisWeek!, DateTime.now().weekday);
                  if (next == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      'Next · ${sessionName(next).toLowerCase()} '
                      '${Distance.meters(next.distanceMeters).format(unit, fractionDigits: 1)}'
                      ' on ${weekdayLongName(next.weekday)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            // **The same button in every state.** Recording is what this app is
            // for, so it keeps one shape and one place — the label is the only
            // thing that changes with the day. A previous pass made the
            // contextual version prominent and demoted the generic one to a
            // text link, which meant the core action of a running app vanished
            // on every day the plan did not ask for a run.
            _StartButton(label: 'Record a run', onTap: onRecord),
            const SizedBox(height: AppSpacing.sm),
            // Two different destinations that shared one callback until now:
            // a runner with no plan wants the coach, a runner on a rest day
            // wants the plan.
            Align(
              alignment: Alignment.centerLeft,
              child: AppTextButton(
                label: session == null ? 'Talk to your coach' : 'See the week',
                onPressed: session == null
                    ? (onOpenCoach ?? onOpenPlan)
                    : onOpenPlan,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ] else ...<Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(
                  child: Text(
                    sessionName(session.session!),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  Distance.meters(
                    session.session!.distanceMeters,
                  ).format(unit, fractionDigits: 1),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            // How to run it, not just how far. "Easy 9 km" is the half of a
            // prescription a runner can act on without opening anything; the
            // other half — that easy means conversational the whole way — was
            // two taps into the Plan tab. The effort rather than a pace, for
            // the reason the week list gives: a target pace tells a runner what
            // their watch should say, an effort tells them how the run should
            // feel (ADR-0011's sibling in session_effort.dart).
            const SizedBox(height: 2),
            Text(
              effortFor(session.session!.kind).cue,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // The action *is* today's session. There is no "Mark done" beside
            // it: a session is complete when a run exists on the day, which the
            // app can see for itself, and a button asserting otherwise wrote a
            // status no run backed (ADR-0017).
            //
            // Already run today? Then the ribbon says so and this reads as an
            // offer of a second run rather than an instruction.
            if (outcomes[session.session!.weekday] == DayOutcome.done)
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.check_circle,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Run recorded today.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  AppTextButton(label: 'Record another', onPressed: onRecord),
                ],
              )
            else
              _StartButton(
                label:
                    'Start · '
                    // One decimal, matching the figure directly above it. They
                    // disagreed — "Easy 6.2 km" over "Start · 6 km easy" — and
                    // two numbers for one session eight pixels apart reads as a
                    // bug whichever is right.
                    '${Distance.meters(session.session!.distanceMeters).format(unit, fractionDigits: 1)} '
                    '${sessionName(session.session!).toLowerCase()}',
                onTap: onRecord,
              ),
          ],

          // Under everything and quiet, but on Home rather than three taps into
          // the Plan tab. A plan that will not bend is this category's loudest
          // complaint, and the runner who needs to bend it is ill, sore or
          // already behind — not in the mood to compose a paragraph at a chat
          // box, which was the only way in.
          //
          // On a rest day too: "I'm ill" is not a thing that waits for a
          // session to be scheduled before it is true.
          if (onAdjustWeek != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: AppTextButton(
                label: 'Not feeling it? Adjust this week',
                onPressed: onAdjustWeek,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The one physical action on Home: start tracking.
///
/// It used to be a full-width slab beneath the Today card reading "Record a
/// run" — generic, in the one place the app knows exactly what the runner is
/// meant to be doing, and the loudest thing on screen on a rest day. It carries
/// the session now and lives inside the card, so the prescription and the button
/// that starts it are one object rather than two strangers.
class _StartButton extends StatelessWidget {
  const _StartButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.primary,
      borderRadius: AppRadius.cardAll,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(
                Icons.play_arrow_rounded,
                color: AppColors.onPrimary,
                size: 24,
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.onPrimary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
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
/// What Runio does with a run, shown to somebody who has not done one yet.
///
/// ## Why this exists
///
/// Home for a runner with no plan and no runs was a card, a text link and a
/// photograph. That was fine while a plan was the assumed destination — the
/// screen was a waiting room. Onboarding is two moments now (ADR-0019) and
/// plenty of runners will stay on the free side indefinitely, so this stopped
/// being a waiting room and became the product's front page while nobody was
/// looking at it.
///
/// ## Why it is not a list of buttons
///
/// There are exactly two ways into Runio — press start, or say something to the
/// coach — and both are already on the card above this one. Adding a third here
/// would be the counter-signal ADR-0017 names for its own reversal. So every
/// line below describes what *happens*, and none of them is tappable.
///
/// Everything named here is free. A runner reading it has not been offered a
/// plan and must not be shown one as though it were included; the only mention
/// of a plan is the way out at the bottom, which goes to the tab that sells it.
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

/// The coach's current observation, as a way into the conversation.
class _CoachNoteCard extends StatelessWidget {
  const _CoachNoteCard({required this.note, required this.onTap});

  final CoachNote note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // The coach's own mark, boxed at the size the icon used to occupy so
          // the row's rhythm is unchanged.
          const SizedBox(
            width: 20,
            height: 20,
            child: Center(
              child: CoachLetter(size: 16, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  note.headline,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  note.detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            size: 20,
            color: AppColors.textTertiary,
          ),
        ],
      ),
    );
  }
}
