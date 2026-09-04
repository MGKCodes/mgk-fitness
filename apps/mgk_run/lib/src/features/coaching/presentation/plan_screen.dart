import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../domain/session_status.dart';
import '../domain/stored_plan.dart';
import '../domain/training_plan.dart';
import 'coach_button.dart';
import 'session_brief_sheet.dart';
import 'session_labels.dart';
import '../../recording/domain/run_summary.dart';
import '../domain/pace_model.dart';
import '../domain/plan_headline.dart';
import '../domain/readiness.dart';
import 'week_list.dart';

/// How far ahead the plan is shown as actual sessions.
///
/// Weeks are generated one ahead (docs/architecture/plan-generation.md) and each
/// one is shaped by how the previous went — an adaptation, a missed long run, a
/// niggle. Printing a fixed session for three weeks' time would present a guess
/// as a commitment. Beyond the horizon there is only the *shape* of the block,
/// which is the part that really is decided — drawn on `PlanBlockScreen`, a tap
/// away on the goal, rather than on this tab under a heading of its own.
const int kPlannedWeekHorizon = 2;

/// The coach: a conversation, and the plan when there is one.
///
/// The conversation is **docked at the foot of the tab**, not behind a row that
/// pushes a screen. A runner without a goal is still a runner with questions,
/// and the old arrangement made the coach look like a feature of having a plan
/// rather than the other way round — worse, the only conversation it offered was
/// the intake, which builds a plan and then ends.
class PlanScreen extends StatelessWidget {
  const PlanScreen({
    super.key,
    this.plan,
    this.weeks = const <int, TrainingWeek>{},
    this.now,
    this.statusFor,
    this.onOpenWeek,
    this.onBuildPlan,
    this.onReplacePlan,
    this.onOpenBlock,
    this.onOpenCalendar,
    this.paces,
    this.onAskAboutSession,
    this.runs = const <RunSummary>[],
    this.unit = UnitSystem.metric,
  });

  final StoredPlan? plan;

  /// The loaded sessions for each week index inside the horizon. Passed in
  /// rather than derived here: the store owns weeks, and a screen that built
  /// its own would show something different from what was saved.
  final Map<int, TrainingWeek> weeks;

  /// Injected so "this week" is testable.
  final DateTime? now;

  /// A recorded status for a weekday of the current week.
  final SessionStatus? Function(int weekday)? statusFor;

  /// Opens a week at the day that was tapped (1=Mon..7=Sun).
  ///
  /// The weekday is part of the callback because the calendar's seven cells are
  /// seven different targets. Dropping it — which this screen used to do — made
  /// every cell in the row do the same thing, so the calendar looked like a
  /// control and behaved like a single button.
  final void Function(SkeletonWeek slot, int weekday)? onOpenWeek;
  final VoidCallback? onBuildPlan;
  final VoidCallback? onReplacePlan;

  /// Opens the week-by-week view of the whole block.
  ///
  /// **It hangs off the goal, not off a section of its own.** A card headed
  /// "The whole block" sitting under the week read as a second, competing plan
  /// — two things on one screen both claiming to be what the runner is doing.
  /// The week *is* the plan; the block is background to it, and the line that
  /// already says "week 3 of 9" is the one place a runner is asking about the
  /// block when they read it.
  final VoidCallback? onOpenBlock;

  /// Opens the scrollable calendar of every week.
  final VoidCallback? onOpenCalendar;

  /// Target paces, shown under each session. Null when the profile has no time
  /// trial to derive them from.
  final TrainingPaces? paces;

  /// The run log, for the measures a plan cannot supply on its own. A rhythm
  /// has no ramp and no date, so how often the runner has actually turned up is
  /// its only state — and that lives in the runs, not in the plan.
  final List<RunSummary> runs;

  /// Opens the conversation with an opener already written — the hand-off from
  /// a session brief to the coach, which is where anything needing judgement
  /// goes.
  final void Function(String opener)? onAskAboutSession;
  final UnitSystem unit;

  @override
  Widget build(BuildContext context) {
    final today = now ?? DateTime.now();
    final current = plan;

    return Scaffold(
      // Transparent so the backdrop runs to the top of the screen rather than
      // starting below a charcoal bar.
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text('Plan'),
        actions: <Widget>[
          if (current != null && onReplacePlan != null)
            AppIconButton(
              icon: Icons.autorenew,
              tooltip: 'Start a new plan',
              onPressed: onReplacePlan,
            ),
        ],
      ),
      // The photograph is what makes the glass above it mean anything: over a
      // flat fill a BackdropFilter blurs nothing (docs/history/design-system.md).
      // `quiet`, because this screen is dense — the picture is texture here
      // rather than subject.
      body: PhotoBackdrop(
        image: 'assets/images/backgrounds/in-run.jpg',
        // `grounded`, not `quiet`: quiet is 88% opaque at the top, which left
        // the photograph invisible and the glass above it refracting nothing.
        // Grounded lets the picture breathe where the week panes sit and goes
        // solid toward the foot, under the chat dock.
        scrim: ScrimStrength.grounded,
        opacity: 0.34,
        alignment: Alignment.topCenter,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              // Room for the floating mark, so the last card is never tucked
              // under it.
              kCoachMarkClearance,
            ),
            children: <Widget>[
              if (current != null) ...<Widget>[
                Entrance(
                  child: _GoalStrip(
                    plan: current,
                    today: today,
                    unit: unit,
                    runs: runs,
                    onOpenBlock: onOpenBlock,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],

              if (current == null) ...<Widget>[
                Entrance(child: _NoPlan(onBuildPlan: onBuildPlan)),
                const SizedBox(height: AppSpacing.xl),
                const Entrance(index: 1, child: _NewHere()),
              ] else
                ..._planSections(context, current, today),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _planSections(
    BuildContext context,
    StoredPlan plan,
    DateTime today,
  ) {
    final currentIndex = plan.weekIndexOn(today);
    final planWeeks = plan.skeleton.weeks;

    return <Widget>[
      // Only the week the runner is in. Next week used to sit beneath it at
      // identical weight, which doubled the height of the screen to show
      // something nobody can act on for six days. It is one tap away in the
      // calendar.
      Entrance(
        index: 1,
        child: _WeekBlock(
          plan: plan,
          slot: planWeeks[currentIndex - 1],
          week: weeks[currentIndex],
          today: today,
          statusFor: statusFor,
          unit: unit,
          paces: paces,
          onOpenCalendar: onOpenCalendar,
          // A tapped day opens the coach on that session, not the week screen.
          // The runner tapped one row; answering with seven is answering a
          // question they did not ask.
          onOpenDay: (weekday) => SessionBriefSheet.show(
            context,
            session: weeks[currentIndex]?.sessionOn(weekday),
            date: plan.dateFor(
              weekIndex: currentIndex,
              weekday: weekday,
              on: today,
            ),
            paces: paces,
            unit: unit,
            onAskCoach: onAskAboutSession,
            now: today,
          ),
        ),
      ),
    ];
  }
}

/// The current week: one glass pane carrying its own heading.
class _WeekBlock extends StatelessWidget {
  const _WeekBlock({
    required this.plan,
    required this.slot,
    required this.today,
    required this.unit,
    required this.week,
    this.paces,
    this.statusFor,
    this.onOpenCalendar,
    this.onOpenDay,
  });

  final StoredPlan plan;
  final SkeletonWeek slot;
  final DateTime? today;
  final UnitSystem unit;
  final SessionStatus? Function(int weekday)? statusFor;
  final VoidCallback? onOpenCalendar;
  final TrainingPaces? paces;
  final void Function(int weekday)? onOpenDay;

  /// Null while the week is still loading from the store.
  final TrainingWeek? week;

  @override
  Widget build(BuildContext context) {
    if (week == null) return const _WeekLoading();

    // A list, not the grid. The grid belongs in the calendar where weeks are
    // stacked and the job is comparison; here there is one week to read, and a
    // row can hold the session's name and its target pace without abbreviating
    // either into a bar.
    return GlassSurface(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.md,
      ),
      blurSigma: 28,
      tintOpacity: 0.12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SectionLabel(
                        'This week · '
                        '${weekRangeLabel(plan.dateFor(weekIndex: slot.index, weekday: 1, on: today))}',
                      ),
                      const SizedBox(height: 3),
                      Text(
                        weekSubtitle(
                          plan,
                          slot,
                          unit: unit,
                          week: week,
                          // The header above already says "week 1 of 16".
                          showWeekNumber: false,
                        ),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onOpenCalendar != null)
                  GestureDetector(
                    onTap: onOpenCalendar,
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.all(AppSpacing.xs),
                      child: Row(
                        children: <Widget>[
                          Text(
                            'Calendar',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: AppColors.textTertiary,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          WeekList(
            week: week!,
            weekStart: plan.dateFor(
              weekIndex: slot.index,
              weekday: 1,
              on: today,
            ),
            paces: paces,
            today: today,
            statusFor: statusFor,
            unit: unit,
            onTapDay: onOpenDay,
          ),
        ],
      ),
    );
  }
}

class _NoPlan extends StatelessWidget {
  const _NoPlan({this.onBuildPlan});

  final VoidCallback? onBuildPlan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'No plan — that’s fine',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Log runs and ask the coach about them whenever you like. If you '
            'get a race in mind, it can build a block around it.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          if (onBuildPlan != null) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            // The action this screen exists for, so it carries the weight —
            // principle 10 in docs/design.md. As an OutlinedButton it was the
            // quietest styled thing on a page whose entire message is "you have
            // no plan, here is how to get one". Lift's identical control is a
            // PrimaryButton; two apps in one suite had two answers.
            PrimaryButton(label: 'Build a plan', onPressed: onBuildPlan),
          ],
        ],
      ),
    );
  }
}

/// A week whose sessions have not arrived from the store yet.
class _WeekLoading extends StatelessWidget {
  const _WeekLoading();

  @override
  Widget build(BuildContext context) => Container(
    height: 96,
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: AppRadius.chipAll,
    ),
  );
}

/// What the block is for, and how long is left of it. The coach screen without
/// this answers "what am I doing" but never "why".
///
/// **It is also the way into the block**, since the block stopped having a card
/// of its own. Both lines here are about the whole thing rather than this week
/// — a race, and how far through the weeks toward it the runner is — so a
/// runner reading "week 3 of 9" and wanting to see the other six taps the words
/// that raised the question.
class _GoalStrip extends StatelessWidget {
  const _GoalStrip({
    required this.plan,
    required this.today,
    required this.unit,
    this.runs = const <RunSummary>[],
    this.onOpenBlock,
  });

  final StoredPlan plan;
  final DateTime today;
  final UnitSystem unit;
  final List<RunSummary> runs;
  final VoidCallback? onOpenBlock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Two strings, computed where the shapes live. A block counts down to a
    // date, a horizon counts up toward a distance and a rhythm counts turning
    // up — three sentences this widget deliberately knows nothing about
    // (ADR-0011).
    final headline = planHeadline(
      plan,
      today,
      unit: unit,
      completedThisPlan: turnedUpCount(plan, runs, now: today),
      readiness: assessReadiness(plan.profile, runs, now: today),
    );

    final strip = Row(
      children: <Widget>[
        Expanded(
          child: Text(
            headline.goal,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          headline.position,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        if (onOpenBlock != null)
          const Padding(
            padding: EdgeInsets.only(left: 2),
            child: Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.textTertiary,
            ),
          ),
      ],
    );

    if (onOpenBlock == null) return strip;
    return GestureDetector(
      onTap: onOpenBlock,
      // Opaque, so the gap between the goal and the position is part of the
      // target rather than a hole in it.
      behavior: HitTestBehavior.opaque,
      child: strip,
    );
  }
}

/// How the app works, for the runner who has not used it yet.
///
/// **Mechanics, not promises.** Each row says what actually happens — the coach
/// asks and then builds, a week bends when you say you are not up to it, the
/// run is written to the phone before anywhere else. A new runner's real
/// question is "what is this going to do", and three concrete answers beat an
/// empty half-screen and a slogan.
///
/// It sits under the empty state on **this** tab rather than on Home, which is
/// where it started. A runner with no plan comes here to get one, so this is
/// where the question "what is this going to do for me" is actually being
/// asked — and this screen was a card and three quarters of a screenful of
/// photograph. It disappears the moment there is a plan.
///
/// **It carries no button of its own.** Explaining is its whole job, and
/// "Build a plan" is already in the card above it.
class _NewHere extends StatelessWidget {
  const _NewHere();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionLabel('How this works'),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: const <Widget>[
              _HowRow(
                icon: Icons.route_outlined,
                title: 'A plan built round your week',
                detail:
                    'Tell the coach what you are training for and which days '
                    'you can actually run. It proposes the block; you approve '
                    'it before it becomes yours.',
              ),
              SizedBox(height: AppSpacing.lg),
              _HowRow(
                icon: Icons.forum_outlined,
                title: 'A week that bends',
                detail:
                    'Ill, sore, or short on time? Say so and the coach '
                    'rewrites what is left — you see every change before it '
                    'lands.',
              ),
              SizedBox(height: AppSpacing.lg),
              _HowRow(
                icon: Icons.phone_iphone,
                title: 'Recorded on this phone first',
                detail:
                    'Runs are written to the device as they happen, so a lost '
                    'signal costs nothing. None of it leaves the phone unless '
                    'you turn backup on.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One line of [_NewHere].
class _HowRow extends StatelessWidget {
  const _HowRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 20, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The one action this screen exists to make easy.
