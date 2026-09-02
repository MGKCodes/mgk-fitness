import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../domain/race_day.dart';

/// What the runner answers when their race has been and gone: the time they
/// ran, or that they did not run it.
///
/// **The log answers first, and the runner corrects it.** A run recorded on the
/// day arrives here already filled in — its time on the drums, its distance
/// beside it — because completion is observed rather than asserted
/// ([ADR-0017](../../../../../docs/decisions/0017-the-coach-is-the-entry-point.md))
/// and a runner who tracked their own marathon should not have to type it in
/// again. What they can do is change the number, and that is the whole point of
/// the screen: in a chip-timed race the watch starts in the pen and stops at
/// the barrier, so the phone's time and the certificate's time are routinely a
/// minute apart. **Neither is wrong.** The sheet says so in as many words,
/// because a runner shown two different times for the same race will otherwise
/// assume the app has a bug.
///
/// The confirmed figure is what gets stored (ADR-0027). Storing what was
/// *confirmed* rather than re-deriving it later is deliberate: it is the same
/// argument `RunEditor` makes about refusing to repair a draft — a silent fix
/// would make the button the runner pressed a description of something other
/// than what got written — and it is what lets a GPS run be corrected or
/// deleted afterwards without rewriting a marathon time they will quote for
/// years.
///
/// A runner who did not race gets an answer of their own, and it is not tucked
/// away. Injury, a cancelled event, an entry never made: all ordinary, all
/// common, and every one of them leaves a plan active forever if there is no
/// way to say so.
class RaceResultSheet extends StatefulWidget {
  const RaceResultSheet({
    super.key,
    required this.race,
    this.observed,
    this.unit = UnitSystem.metric,
  });

  /// The race being closed out, already resolved for the plan's shape.
  final RaceOutlook race;

  /// What the log says they ran, or null when the phone recorded nothing.
  ///
  /// Null is ordinary rather than a problem: plenty of runners race on a watch,
  /// or leave the phone in a bag. It changes the sheet from "is this right?" to
  /// "what did you run?" and nothing else.
  final RaceResult? observed;

  final UnitSystem unit;

  /// Opens the sheet and completes with the runner's answer, or null if they
  /// backed out without saying.
  static Future<RaceAnswer?> show(
    BuildContext context, {
    required RaceOutlook race,
    RaceResult? observed,
    UnitSystem unit = UnitSystem.metric,
  }) => showModalBottomSheet<RaceAnswer>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => RaceResultSheet(race: race, observed: observed, unit: unit),
  );

  @override
  State<RaceResultSheet> createState() => _RaceResultSheetState();
}

/// What the runner said, on the way back out of the sheet.
class RaceAnswer {
  const RaceAnswer({required this.closure, this.time});

  final PlanClosure closure;

  /// The finish time, when they gave one. Always null for
  /// [PlanClosure.didNotRace].
  final Duration? time;
}

class _RaceResultSheetState extends State<RaceResultSheet> {
  /// Seeded from the log where there is one, and zeroed otherwise.
  ///
  /// Zero is where a drum has to start when there is nothing to start it at —
  /// there is no "empty" position on a wheel. What zero must never be is an
  /// answer, which is what [_hasTime] is for.
  late int _hours = widget.observed?.time.inHours ?? 0;
  late int _minutes = widget.observed?.time.inMinutes.remainder(60) ?? 0;
  late int _seconds = widget.observed?.time.inSeconds.remainder(60) ?? 0;

  Duration get _time =>
      Duration(hours: _hours, minutes: _minutes, seconds: _seconds);

  /// A time of zero is not a result. It is the state a runner with no recorded
  /// run starts in, so the confirm is disabled rather than the sheet refusing
  /// them afterwards.
  bool get _hasTime => _time > Duration.zero;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final observed = widget.observed;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Your ${midSentenceRaceName(widget.race.name)}',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                observed == null
                    ? 'Nothing was recorded on the day, so tell me what you '
                          'ran and I will close the plan out.'
                    // Said before they look at the number, not after they
                    // notice it is wrong. The disagreement is the expected
                    // case in any chip-timed race and it is not a fault.
                    : 'This is what your phone recorded. If your chip time is '
                          'different, that is normal — put the official one in '
                          'and it is the one I will keep.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              if (observed != null) ...<Widget>[
                _Observed(observed: observed, unit: widget.unit),
                const SizedBox(height: AppSpacing.lg),
              ],

              const SectionLabel('Finish time'),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: <Widget>[
                  Expanded(
                    child: WheelPicker(
                      label: 'Hours',
                      min: 0,
                      max: 12,
                      initial: _hours,
                      onChanged: (v) => setState(() => _hours = v),
                    ),
                  ),
                  Expanded(
                    child: WheelPicker(
                      label: 'Minutes',
                      min: 0,
                      max: 59,
                      initial: _minutes,
                      format: _twoDigits,
                      onChanged: (v) => setState(() => _minutes = v),
                    ),
                  ),
                  Expanded(
                    child: WheelPicker(
                      label: 'Seconds',
                      min: 0,
                      max: 59,
                      initial: _seconds,
                      format: _twoDigits,
                      onChanged: (v) => setState(() => _seconds = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                // The number in the label, so the thing being agreed to is on
                // the control that agrees to it rather than three wheels above.
                label: _hasTime
                    ? 'That was my time · ${_time.hoursMinutesSeconds}'
                    : 'Enter your time',
                onPressed: _hasTime
                    ? () => Navigator.of(
                        context,
                      ).pop(RaceAnswer(closure: PlanClosure.raced, time: _time))
                    : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: AppTextButton(
                  // **Not "abandon".** The stored value is `abandoned` because
                  // that is what the column has said since it was written, and
                  // nothing the runner reads will ever use the word. Getting
                  // injured is not a failure of character.
                  label: 'I did not race in the end',
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(const RaceAnswer(closure: PlanClosure.didNotRace)),
                ),
              ),
              Center(
                child: AppTextButton(
                  // Leaves the plan exactly as it is, and the card asking.
                  label: 'Not now',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _twoDigits(int v) => v.toString().padLeft(2, '0');
}

/// What the phone made of the day.
///
/// Shown as evidence rather than as the answer: it is what the runner is being
/// asked to confirm or correct, and labelling it "your phone" is what keeps a
/// GPS distance of 42.61 km from reading as a claim that they ran a longer
/// marathon than everyone else.
class _Observed extends StatelessWidget {
  const _Observed({required this.observed, required this.unit});

  final RaceResult observed;
  final UnitSystem unit;

  @override
  Widget build(BuildContext context) {
    final watched = observed.watchDistanceMeters;
    return AppCard(
      child: Row(
        children: <Widget>[
          Expanded(
            child: StatBlock(
              label: 'TIME',
              value: observed.time.hoursMinutesSeconds,
              size: StatSize.standard,
            ),
          ),
          if (watched != null)
            Expanded(
              child: StatBlock(
                label: 'DISTANCE',
                // A decimal, because this is a distance the runner covered
                // rather than one the plan asked for — prescriptions round
                // where achievements do not.
                value: Distance.meters(watched).format(unit, fractionDigits: 2),
                size: StatSize.standard,
              ),
            ),
        ],
      ),
    );
  }
}
