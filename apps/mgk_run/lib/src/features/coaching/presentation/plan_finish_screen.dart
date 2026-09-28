import 'dart:async';

import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../../recording/domain/run_summary.dart';
import '../domain/prescribed_distance.dart';
import '../domain/race_day.dart';
import '../domain/stored_plan.dart';
import 'block_arc.dart';

/// The end of a block: what they ran, what it took, and what the coach makes
/// of it.
///
/// **Sixteen weeks deserve more than a status change**, and until this existed
/// that was all there was — the plan quietly stopped being active the next time
/// somebody built another one (ADR-0027). This is the one screen in the app
/// that is about a period of time rather than about a day.
///
/// **Assembled out of what already existed, deliberately.** The result takes
/// `RunSummaryScreen`'s headline shape — a quiet label over one large figure —
/// because a runner has been reading that screen for sixteen weeks and knows
/// where to look. What changes is which figure: a run's headline is its
/// distance, and here the distance was decided in January and the *time* is the
/// news. The arc is the same [BlockArc] `PlanBlockScreen` draws, at the
/// end of its own progression rather than partway along it. The coach's line is
/// derived in Dart like every other thing the coach says about a number
/// (`RunNote`, `CoachNote`), and the way past it is the conversation, which is
/// where anything needing judgement has always gone. Nothing here is a new
/// visual language and nothing here is a new coach mechanism.
///
/// **It is shown for a runner who did not race, too.** They trained for eleven
/// weeks and then could not start, and a screen that went quiet on them would
/// be the app agreeing that only the race counted.
class PlanFinishScreen extends StatelessWidget {
  const PlanFinishScreen({
    super.key,
    required this.plan,
    required this.runs,
    this.result,
    this.unit = UnitSystem.metric,
    this.onAskCoach,
    this.onDone,
  });

  /// The block that just ended. Still the full stored plan — the arc is the
  /// point of the screen, so this is one of the few places that wants it.
  final StoredPlan plan;

  /// The runner's log. Filtered to the plan's own window here, because a third
  /// marathon sits on top of years of running and totalling the lot would be
  /// reporting their life rather than the thing that just ended.
  final List<RunSummary> runs;

  /// What they ran, or null for a runner who did not race.
  final RaceResult? result;

  final UnitSystem unit;

  /// Opens the conversation with an opener already written. Null in a build
  /// with no coach behind it, and then the offer is simply absent rather than
  /// inert — the same rule `RunSummaryScreen.onAskCoach` follows.
  final void Function(String opener)? onAskCoach;

  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ran = runsDuring(plan, runs);
    final verdict = raceVerdict(
      plan: plan,
      result: result,
      runs: runs,
      unit: unit,
    );
    final meters = ran.fold<double>(0, (sum, r) => sum + r.distanceMeters);

    return Scaffold(
      appBar: AppBar(
        // No back arrow. The plan is closed on disk by the time this is
        // pushed, so there is nothing behind it to return to — going "back"
        // would land on a Home that has already moved on, which reads as the
        // app having lost the thing it just showed them.
        automaticallyImplyLeading: false,
        // Flat and factual, so it does not compete with the verdict below it —
        // and so it reads the same to a runner who did not start. "Complete"
        // would be a judgement about them; "finished" is a statement about the
        // plan, which is the only thing this screen is entitled to close.
        title: const Text('Plan finished'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            AppSpacing.xxl,
          ),
          children: <Widget>[
            // The result leads, and it is the largest thing on the screen. It
            // is the number they will still know in five years.
            Entrance(
              child: _Result(result: result, unit: unit, plan: plan),
            ),
            const SizedBox(height: AppSpacing.xl),

            // What it took. The arc at the end of itself rather than partway
            // along — the marker sits on the last week, which is the one time
            // this shape has ever been drawn complete.
            Entrance(
              index: 1,
              child: BlockArc(
                weeks: plan.skeleton.weeks,
                currentIndex: plan.skeleton.weeks.length,
                height: 72,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Entrance(
              index: 2,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: StatBlock(
                      label: 'WEEKS',
                      value: '${plan.skeleton.weeks.length}',
                    ),
                  ),
                  Expanded(
                    child: StatBlock(label: 'RUNS', value: '${ran.length}'),
                  ),
                  Expanded(
                    child: StatBlock(
                      label: 'DISTANCE',
                      // Rounded to the kilometre: this is a season's total and
                      // the last decimal of it is noise, not precision.
                      value: Distance.meters(
                        meters,
                      ).format(unit, fractionDigits: 0),
                      shrinkToFit: true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            Entrance(
              index: 3,
              child: _Verdict(
                verdict: verdict,
                onAsk: onAskCoach == null
                    ? null
                    : () => onAskCoach!(
                        raceChatOpener(
                          profile: plan.profile,
                          result: result,
                          unit: unit,
                        ),
                      ),
              ),
            ),

            if (onDone != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xxl),
              Entrance(
                index: 4,
                child: PrimaryButton(
                  label: 'Done',
                  onPressed: () {
                    unawaited(AppHaptics.commit());
                    onDone!();
                  },
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Text(
              // Said plainly rather than left to be discovered. The Plan tab is
              // about to be empty, and a runner who does not know why would
              // reasonably think something had gone wrong.
              'Your plan is finished, so the Plan tab is clear. Ask the coach '
              'whenever you want to start the next one.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textTertiary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The finish time, or its absence.
class _Result extends StatelessWidget {
  const _Result({required this.result, required this.unit, required this.plan});

  final RaceResult? result;
  final UnitSystem unit;
  final StoredPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = result;

    if (r == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionLabel('THE BLOCK', emphasis: LabelEmphasis.stat),
          const SizedBox(height: AppSpacing.sm),
          Text(
            // Not "You did not race". That is true and it is also the least
            // useful sentence available, because it names the one part of the
            // block that did not happen and none of the parts that did. The
            // number is the plan's own arc rather than a figure of speech —
            // a screen that said "sixteen weeks" over a nine-week block would
            // be the app being warm and wrong at the same time.
            '${plan.skeleton.weeks.length} weeks of running do not stop '
            'counting because a race did not happen.',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionLabel(
          describeGoal(r.distanceMeters, unit).toUpperCase(),
          emphasis: LabelEmphasis.stat,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          r.time.hoursMinutesSeconds,
          style: theme.textTheme.displayLarge?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${Pace.secondsPerKilometer(r.paceSecondsPerKm).format(unit)} '
          'for the ${describeGoal(r.distanceMeters, unit).toLowerCase()}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        // **Both figures, where they differ.** A chip time and a watch time a
        // minute apart is the ordinary outcome of a big race, and hiding the
        // one the runner did not confirm would leave them looking at a number
        // their own phone disagrees with and nothing to explain it.
        if (r.disagrees) ...<Widget>[
          const SizedBox(height: AppSpacing.md),
          Text(
            'Your phone had ${r.watchTime!.hoursMinutesSeconds}'
            '${r.watchDistanceMeters == null ? '' : ' over ${Distance.meters(r.watchDistanceMeters!).format(unit, fractionDigits: 2)}'}'
            '. The time above is the one you gave me.',
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

/// The coach's word, and the way past it.
///
/// The line itself is one sentence and its evidence, which is the shape every
/// derived coach remark in this app takes. What it is *not* is the last word:
/// "what should I do next" is a judgement call, and judgement calls go to the
/// conversation.
class _Verdict extends StatelessWidget {
  const _Verdict({required this.verdict, this.onAsk});

  final RaceVerdict verdict;
  final VoidCallback? onAsk;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            verdict.headline,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            verdict.detail,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
          if (onAsk != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: AppTextButton(label: 'Talk it through', onPressed: onAsk),
            ),
          ],
        ],
      ),
    );
  }
}
