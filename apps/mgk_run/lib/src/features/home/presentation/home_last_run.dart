import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../../coaching/domain/coach_access.dart';
import '../../coaching/domain/prescribed_distance.dart';
import '../../coaching/domain/training_plan.dart';
import '../../coaching/presentation/session_labels.dart';
import '../../history/presentation/run_tile.dart' show shortRunDate;
import '../../recording/domain/run_summary.dart';

/// What the coach asked for on the day of a run, so the run can be read against
/// it.
///
/// Assembled by the shell rather than here, because working out *which* session
/// a run answers needs the plan and the log together and this widget has only
/// one of them.
class PlannedAgainst {
  const PlannedAgainst({required this.session, this.targetPace});

  final PlannedSession session;

  /// The pace the session was asking for, or null when the profile has no time
  /// trial to derive one from. Null draws no pace row rather than a guessed one.
  final Pace? targetPace;
}

/// The most recent run, and — for a runner who pays for a coach — what it was
/// measured against.
///
/// **This replaced four lifetime tiles.** Home used to carry Longest run,
/// Fastest pace and Runs logged: facts about a career, on the screen a runner
/// opens to find out about a day. They live on Profile, which is the page about
/// the runner rather than the week, and Home is left with the two things it is
/// actually for — the plan, and what just happened.
///
/// **The free product is whole here.** Distance, pace and time are the runner's
/// own numbers and are never gated; a tracker that hides your own pace behind a
/// paywall is not a tracker. What is bought is the coach's reading — the
/// comparison against what was asked for — which only exists at all when there
/// is a plan to be asked by.
class LastRunCard extends StatelessWidget {
  const LastRunCard({
    super.key,
    required this.run,
    required this.unit,
    this.against,
    this.access = CoachAccess.free,
    this.onOpenRun,
    this.onUpgrade,
  });

  final RunSummary? run;
  final UnitSystem unit;

  /// The session this run answers, when it answers one. Null for an unplanned
  /// run, for a runner with no plan, and for a run that matched nothing — and
  /// in all three cases there is simply no comparison to draw, paid or not.
  final PlannedAgainst? against;

  final CoachAccess access;
  final void Function(RunSummary run)? onOpenRun;
  final VoidCallback? onUpgrade;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = run;

    return HomeTile(
      label: 'Last run',
      onTap: last == null || onOpenRun == null ? null : () => onOpenRun!(last),
      child: last == null
          ? Text(
              'Your latest run lands here, with how it went.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  // Named the way a run is named once it has happened and its
                  // hour is known — "Morning run" — which is the half of the
                  // naming rule a planned Thursday cannot have.
                  runName(last.startedAt),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  shortRunDate(last.startedAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _Figure(
                      label: 'Distance',
                      // Earned precision. A distance somebody actually covered
                      // keeps its decimal — prescriptions round, achievements
                      // do not.
                      value: Distance.meters(
                        last.distanceMeters,
                      ).format(unit, fractionDigits: 1),
                    ),
                    _Figure(
                      label: 'Pace',
                      value: last.avgPaceSecondsPerKm == null
                          ? '—'
                          : Pace.secondsPerKilometer(
                              last.avgPaceSecondsPerKm!,
                            ).format(unit),
                    ),
                    _Figure(
                      label: 'Time',
                      value: last.duration.hoursMinutesSeconds,
                    ),
                  ],
                ),
                if (against != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.lg),
                  Divider(color: AppColors.elevated, height: 1),
                  const SizedBox(height: AppSpacing.md),
                  if (access.isSubscribed)
                    _AgainstThePlan(against: against!, run: last, unit: unit)
                  else
                    _Locked(onUpgrade: onUpgrade),
                ],
              ],
            ),
    );
  }
}

/// One figure in the row: label over value, sharing the width evenly.
class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.textTertiary,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// What was asked for, beside what was done.
///
/// Two rows rather than a verdict, and the ordering is deliberate: the ask
/// first, then the run. A runner reading their own effort should meet the
/// standard before the mark, or the mark reads as a grade.
///
/// **Nothing here calls a run good or bad.** `fulfils` already knows whether a
/// session was answered — a ±12% band with a floor — and that is used to say
/// *done* or *not quite*, which is a fact about the session rather than a
/// judgement of the runner. The interpretation is the coach's job and it has a
/// conversation to do it in.
class _AgainstThePlan extends StatelessWidget {
  const _AgainstThePlan({
    required this.against,
    required this.run,
    required this.unit,
  });

  final PlannedAgainst against;
  final RunSummary run;
  final UnitSystem unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = against.session;
    final done = fulfils(session, run.distanceMeters, unit: unit);
    final pace = against.targetPace;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const SectionLabel('Against the plan'),
            const Spacer(),
            Text(
              done ? 'Session done' : 'Off the session',
              style: theme.textTheme.labelSmall?.copyWith(
                color: done ? AppColors.textSecondary : AppColors.textTertiary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _CompareRow(
          what: 'Asked',
          detail: sessionName(session),
          distance: formatPrescribed(session.distanceMeters, unit),
          pace: pace?.format(unit),
          muted: true,
        ),
        const SizedBox(height: 6),
        _CompareRow(
          what: 'Ran',
          detail: runName(run.startedAt),
          distance: Distance.meters(
            run.distanceMeters,
          ).format(unit, fractionDigits: 1),
          pace: run.avgPaceSecondsPerKm == null
              ? null
              : Pace.secondsPerKilometer(run.avgPaceSecondsPerKm!).format(unit),
          muted: false,
        ),
      ],
    );
  }
}

class _CompareRow extends StatelessWidget {
  const _CompareRow({
    required this.what,
    required this.detail,
    required this.distance,
    required this.pace,
    required this.muted,
  });

  final String what;
  final String detail;
  final String distance;
  final String? pace;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = muted ? AppColors.textSecondary : AppColors.textPrimary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 52,
          child: Text(
            what,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            detail,
            style: theme.textTheme.bodyMedium?.copyWith(color: colour),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          pace == null ? distance : '$distance  ·  $pace',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colour,
            fontWeight: muted ? FontWeight.w400 : FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// The paid comparison, not shown.
///
/// **It says what is behind it rather than only that something is.** A blurred
/// rectangle with a padlock tells a runner they are missing out without telling
/// them what of, which is a worse offer and a ruder one. The rows are drawn in
/// the shape they will take, dimmed, so the upgrade is a proposition rather
/// than a mystery.
class _Locked extends StatelessWidget {
  const _Locked({this.onUpgrade});

  final VoidCallback? onUpgrade;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionLabel('Against the plan'),
        const SizedBox(height: AppSpacing.sm),
        // The shape of the thing, at a weight that cannot be mistaken for data.
        Opacity(
          opacity: 0.28,
          child: Column(
            children: <Widget>[
              for (final what in const <String>['Asked', 'Ran'])
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 52,
                        child: Text(
                          what,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 9,
                          decoration: BoxDecoration(
                            color: AppColors.elevated,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      Container(
                        width: 64,
                        height: 9,
                        decoration: BoxDecoration(
                          color: AppColors.elevated,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Upgrade to see this stat',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Your own numbers are always yours. A coach reads them against the '
          'session you were set.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textTertiary,
          ),
        ),
        if (onUpgrade != null) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          AppTextButton(label: 'See what a coach adds', onPressed: onUpgrade),
        ],
      ],
    );
  }
}
