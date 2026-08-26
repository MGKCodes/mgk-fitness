import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../../coaching/data/plan_repository.dart';
import '../../coaching/domain/prescribed_distance.dart';
import '../../coaching/domain/session_effort.dart';
import '../../coaching/domain/training_plan.dart';
import '../../coaching/domain/week_progress.dart';
import '../../coaching/presentation/session_labels.dart';
import '../../recording/domain/run_summary.dart';

/// What today is, in one sentence, over the button that starts it.
///
/// ## The sentence
///
/// This card used to read `TODAY` in an eyebrow with `Threshold` underneath it
/// — two headings and no sentence, naming a physiological zone rather than a
/// thing a person does (IMG_4702). It reads `TODAY · MONDAY 25 AUG` over
/// `Afternoon threshold run` now: the eyebrow is a date, which is information
/// and cannot be mistaken for a title, and the headline is the activity.
///
/// The time of day comes from [sessionNameAt], which is honest here and
/// nowhere else on the plan surfaces: today is one of exactly two occasions the
/// app really knows the hour of. A Wednesday four days out gets [sessionName]
/// with no hour attached, because nothing has told us when its owner intends to
/// run it.
///
/// ## The runner with no plan
///
/// **Today is answered by the log rather than by the plan.** A free runner is
/// not shown a plan-shaped hole where a session would be — no "no plan yet"
/// placeholder, no empty prescription — because the counter-signal
/// [ADR-0019](../../../../docs/decisions/0019-onboarding-is-two-moments.md)
/// watches for is exactly that: a paid screen with its contents removed. What
/// they get instead is a true fact about their own running today, which is
/// either the run they have already done or the fact that they have not done
/// one yet. Both are information; neither mentions a plan.
class HomeTodayTile extends StatelessWidget {
  const HomeTodayTile({
    super.key,
    required this.now,
    required this.unit,
    required this.onFreeRun,
    required this.onStartSession,
    required this.onOpenPlan,
    this.today,
    this.lastRun,
    this.outcomes = const <int, DayOutcome>{},
    this.onOpenCoach,
    this.onAdjustWeek,
  });

  /// One reading of the clock for the whole card, handed down rather than taken
  /// here — the same reason the shell reads it once. A card whose eyebrow and
  /// whose session name disagreed about the hour would be a bug that only ever
  /// fired at noon and at six.
  final DateTime now;

  final UnitSystem unit;

  /// Starts a run with **no session attached**, so nothing counts down and
  /// nothing is judged against a prescription the runner did not choose.
  final VoidCallback onFreeRun;

  /// Starts today's prescribed session, handing the recorder what was asked
  /// for so the in-run screen can say what is left of it.
  ///
  /// Falls back to a free run where there is no session, which is what makes
  /// the no-plan card work without a second code path.
  final VoidCallback onStartSession;
  final VoidCallback onOpenPlan;

  /// Today's prescribed session, when a plan exists.
  final TodayView? today;

  /// The newest run on record, whenever it was. Read only to answer "have they
  /// run today" and, for a runner with no plan, to say what that run was.
  final RunSummary? lastRun;

  final Map<int, DayOutcome> outcomes;
  final VoidCallback? onOpenCoach;
  final VoidCallback? onAdjustWeek;

  /// Whether a run is already on record for today.
  ///
  /// Two sources because there are two kinds of runner. The outcome map is
  /// derived against the plan's week and is what the ribbon draws, so a plan
  /// runner and their own ribbon can never disagree; the log answers for
  /// everybody else, who has no week for an outcome to hang on.
  bool get _ranToday {
    final last = lastRun;
    if (last != null && _sameDay(last.startedAt, now)) return true;
    return outcomes[now.weekday] == DayOutcome.done;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final session = today;

    return GlassSurface(
      padding: const EdgeInsets.all(AppSpacing.xl),
      tintOpacity: 0.12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // A date, not a second title. The heading itself is resolved by the
          // repository rather than branched on here: a phase is block
          // vocabulary and this card must not know which shapes have one
          // (ADR-0011).
          SectionLabel(
            '${session?.heading ?? 'Today'} · '
            '${weekdayLongName(now.weekday)} ${now.day} '
            '${monthShortName(now.month)}',
            emphasis: LabelEmphasis.stat,
          ),
          const SizedBox(height: AppSpacing.md),

          if (session?.session != null)
            _PrescribedDay(
              session: session!.session!,
              now: now,
              unit: unit,
              ranToday: _ranToday,
              onFreeRun: onFreeRun,
              onStartSession: onStartSession,
            )
          else if (session != null)
            // A rest day has no session to start, so both paths are the same
            // run: whatever they go and do is unplanned by definition.
            _RestDay(session: session, onRecord: onFreeRun)
          else
            _NoPlanDay(
              lastRun: _ranToday ? lastRun : null,
              unit: unit,
              onRecord: onFreeRun,
            ),

          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            // Two different destinations that shared one callback until they
            // were split: a runner with no plan wants the coach, a runner on a
            // rest day wants the plan.
            child: _QuietLink(
              label: session == null ? 'Talk to your coach' : 'See the week',
              onPressed: session == null
                  ? (onOpenCoach ?? onOpenPlan)
                  : onOpenPlan,
            ),
          ),

          // Under everything and quiet, but on Home rather than three taps into
          // the Plan tab. A plan that will not bend is this category's loudest
          // complaint, and the runner who needs to bend it is ill, sore or
          // already behind — not in the mood to compose a paragraph at a chat
          // box, which was the only way in.
          //
          // On a rest day too: "I'm ill" is not a thing that waits for a
          // session to be scheduled before it is true.
          if (onAdjustWeek != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: _QuietLink(
                label: 'Not feeling it? Adjust this week',
                onPressed: onAdjustWeek,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A day the plan has asked for a run on.
class _PrescribedDay extends StatelessWidget {
  const _PrescribedDay({
    required this.session,
    required this.now,
    required this.unit,
    required this.ranToday,
    required this.onFreeRun,
    required this.onStartSession,
  });

  final PlannedSession session;
  final DateTime now;
  final UnitSystem unit;
  final bool ranToday;
  final VoidCallback onFreeRun;
  final VoidCallback onStartSession;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // **The distance is the instruction, so it gets the size.**
        //
        // This used to lead with "Afternoon threshold run" and hang the figure
        // off the end of it. Two things were wrong with that. The hour is not
        // information — a runner opening this at seven in the morning does not
        // need telling it is morning — and "threshold" is a physiological zone
        // rather than an instruction: it names the adaptation being chased, not
        // the thing to go and do. What a runner can act on without opening
        // anything is *how far*.
        //
        // The effort has not gone, it has moved behind a tap. It is the answer
        // to the second question rather than the first, and a card that answers
        // both at once answers neither loudly.
        Text(
          formatPrescribed(session.distanceMeters, unit),
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.05,
          ),
        ),
        const SizedBox(height: 4),
        _EffortLine(kind: session.kind, session: session, unit: unit),
        const SizedBox(height: AppSpacing.lg),
        // The action *is* today's session. There is no "Mark done" beside it: a
        // session is complete when a run exists on the day, which the app can
        // see for itself, and a button asserting otherwise wrote a status no
        // run backed (ADR-0017).
        //
        // Already run today? Then this reads as an offer of a second run rather
        // than an instruction.
        if (ranToday)
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
              AppTextButton(label: 'Record another', onPressed: onFreeRun),
            ],
          )
        else ...<Widget>[
          // **Two starts, and they are not the same run.**
          //
          // Starting the session hands the recorder today's prescription, so
          // the in-run screen can count down what is left of it. Starting a
          // free run deliberately does not — a runner who is going out for
          // something other than what the plan asked should not spend the next
          // half hour being measured against a session they chose not to do.
          //
          // The plain word on the button. It used to read "Start · 9 km
          // threshold run", which restated the two lines directly above it and
          // was the longest thing on the card.
          StartRunButton(label: 'Start', onTap: onStartSession),
          const SizedBox(height: 2),
          // Quieter, and second, because the session is what today is. Present
          // even with a plan on purpose: the alternative is a runner who wants
          // an easy half hour either not recording it or recording it against
          // a threshold session and reading a verdict that means nothing.
          Align(
            alignment: Alignment.centerLeft,
            child: AppTextButton(
              label: 'Just go for a run',
              onPressed: onFreeRun,
            ),
          ),
        ],
      ],
    );
  }
}

/// The effort cue, with the rest of it behind a tap.
///
/// A cue — "comfortably hard" — is what a runner needs at the door. The rest
/// (what the session is for, the RPE it should sit at, how it should feel) is
/// what they want when they are deciding whether they can face it, which is a
/// different moment and does not belong on the same line.
///
/// Expanded in place rather than pushed as a sheet: the question is "what does
/// that mean", and an answer that replaces the screen it was asked on makes the
/// runner navigate back to where they already were.
class _EffortLine extends StatefulWidget {
  const _EffortLine({
    required this.kind,
    required this.session,
    required this.unit,
  });

  final SessionKind kind;
  final PlannedSession session;
  final UnitSystem unit;

  @override
  State<_EffortLine> createState() => _EffortLineState();
}

class _EffortLineState extends State<_EffortLine> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effort = effortFor(widget.kind);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(
          button: true,
          expanded: _open,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: Row(
              children: <Widget>[
                Flexible(
                  child: Text(
                    effort.cue,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  _open ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
        if (_open) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          Text(
            effort.feel,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            // What it is for. A session a runner understands the point of is a
            // session they are more likely to run as asked.
            effort.purpose,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            // The number the runner asked for. Stated as the range it is, not
            // a single figure: an effort is a band and pretending otherwise is
            // the same mistake as prescribing a pace to the second.
            'Effort ${effort.rpeLow}–${effort.rpeHigh} out of 10',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

/// A day the plan has not asked for a run on — rest, or work this app does not
/// prescribe.
class _RestDay extends StatelessWidget {
  const _RestDay({required this.session, required this.onRecord});

  final TodayView session;
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final support = session.support;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          support == null ? 'Rest day' : kindLabel(support.kind),
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          // A day carrying strength is not a rest day, and saying "nothing
          // scheduled" over one contradicted the Plan tab reading the same
          // week. What is *in* the session is Liftio's to say, not Runio's
          // (ADR-0010) — so this says when, and stops.
          support == null
              ? 'Nothing scheduled. Rest is part of the plan.'
              // Dashed rather than a second sentence: the cues are written
              // lowercase for the week list, where they trail a session name,
              // so a full stop in front of one reads as a typo.
              : 'No run today — ${effortFor(support.kind).cue}.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        // **The same button in every state.** Recording is what this app is
        // for, so it keeps one shape and one place — the label is the only
        // thing that changes with the day. A previous pass made the contextual
        // version prominent and demoted the generic one to a text link, which
        // meant the core action of a running app vanished on every day the plan
        // did not ask for a run.
        StartRunButton(label: 'Record a run', onTap: onRecord),
      ],
    );
  }
}

/// Today for a runner with no plan: the run they have done, or the one they
/// have not.
///
/// Nothing here is a placeholder for a session. "No run yet today" is a
/// complete statement about their running, in the way "No plan yet" — which is
/// what this card used to say — is a statement about their billing.
class _NoPlanDay extends StatelessWidget {
  const _NoPlanDay({
    required this.lastRun,
    required this.unit,
    required this.onRecord,
  });

  /// Today's run, when there is one. Non-null only for a run recorded today —
  /// the caller has already decided that.
  final RunSummary? lastRun;

  final UnitSystem unit;
  final VoidCallback onRecord;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final run = lastRun;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: Text(
                // "Afternoon run" — the same vocabulary a planned session gets,
                // off the run's own start time rather than off the clock.
                run == null ? 'No run yet today' : runName(run.startedAt),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (run != null) ...<Widget>[
              const SizedBox(width: AppSpacing.sm),
              Text(
                // **A decimal, deliberately.** This is a distance the runner
                // covered, not one the app asked for, and prescriptions round
                // where achievements do not.
                Distance.meters(
                  run.distanceMeters,
                ).format(unit, fractionDigits: 1),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          run == null
              // "the app", not the product name and not a bare "Run" — see
              // docs/naming.md. Runio was retired as a user-facing name on
              // 2026-08-21, and a bare "Run" is worse than either, because
              // "your Run data" and "your run data" are the same sentence.
              ? 'Press start and the app tracks the route, the splits and the '
                    'pace.'
              : _describe(run, unit),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        StartRunButton(
          label: run == null ? 'Record a run' : 'Record another run',
          onTap: onRecord,
        ),
      ],
    );
  }

  /// "58:28 · 5:44 /km". The stored average pace where there is one, derived
  /// from the totals otherwise, and omitted entirely for a run with no distance
  /// — `0:00 /km` would be a lie rather than a blank.
  static String _describe(RunSummary run, UnitSystem unit) {
    final stored = run.avgPaceSecondsPerKm;
    final pace = stored != null
        ? Pace.secondsPerKilometer(stored)
        : run.distanceMeters > 0
        ? Pace.from(Distance.meters(run.distanceMeters), run.duration)
        : null;
    return <String>[
      run.duration.hoursMinutesSeconds,
      ?pace?.format(unit),
    ].join('  ·  ');
  }
}

/// The one physical action on Home: start tracking.
///
/// It used to be a full-width slab beneath the Today card reading "Record a
/// run" — generic, in the one place the app knows exactly what the runner is
/// meant to be doing, and the loudest thing on screen on a rest day. It carries
/// the session now and lives inside the card, so the prescription and the
/// button that starts it are one object rather than two strangers.
class StartRunButton extends StatelessWidget {
  const StartRunButton({super.key, required this.label, required this.onTap});

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

/// A text link that sits under a card's action without competing with it.
class _QuietLink extends StatelessWidget {
  const _QuietLink({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AppTextButton(
      label: label,
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
