import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../../coaching/domain/prescribed_distance.dart' show raceName;
import '../../coaching/domain/race_finish.dart';
import '../domain/best_effort.dart';
import '../domain/run_race.dart';
import '../domain/run_summary.dart';

/// What the runner said in the race sheet, on the way back out.
///
/// [race] null means "this was not a race" — a real answer, distinct from
/// backing out of the sheet, which completes the sheet with no answer at all.
class RaceSheetAnswer {
  const RaceSheetAnswer(this.race);

  final RunRace? race;
}

/// Marks a run as a race, or corrects one: the distance, a name, and the time
/// on the certificate.
///
/// **The phone's time is already in the wheels.** A runner who looks their
/// result up and finds the phone was right taps Save and is done; one whose
/// chip time differs — the ordinary case, because the phone starts in the pen
/// and stops past the line — turns the wheels to it. The sheet says which is
/// which before they look at the number, for `RaceResultSheet`'s reason: two
/// times for one race reads as a bug unless somebody has said it is not one.
///
/// Only a time that differs from the phone's is stored as official. Saving the
/// phone's own figure untouched is the runner agreeing with it, not giving a
/// second source, and the race screen should not claim a chip time it never
/// had.
class RaceSheet extends StatefulWidget {
  const RaceSheet({
    super.key,
    required this.run,
    this.unit = UnitSystem.metric,
  });

  final RunSummary run;
  final UnitSystem unit;

  static Future<RaceSheetAnswer?> show(
    BuildContext context, {
    required RunSummary run,
    UnitSystem unit = UnitSystem.metric,
  }) => showModalBottomSheet<RaceSheetAnswer>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => RaceSheet(run: run, unit: unit),
  );

  @override
  State<RaceSheet> createState() => _RaceSheetState();
}

class _RaceSheetState extends State<RaceSheet> {
  RunRace? get _existing => widget.run.race;

  /// The named distance chosen, or null when the runner picked Other.
  late double? _named = _initialNamed();

  late final TextEditingController _other = TextEditingController(
    text: _named == null ? _otherText(_existing!.distanceMeters) : '',
  );

  late final TextEditingController _name = TextEditingController(
    text: _existing?.name ?? '',
  );

  late final Duration _start =
      _existing?.timeFor(widget.run.duration) ?? widget.run.duration;
  late int _hours = _start.inHours;
  late int _minutes = _start.inMinutes.remainder(60);
  late int _seconds = _start.inSeconds.remainder(60);

  double? _initialNamed() {
    final existing = _existing;
    if (existing != null) {
      for (final meters in kRecordDistancesMeters) {
        if (sameRaceDistance(existing.distanceMeters, meters)) return meters;
      }
      return null;
    }
    return suggestedRaceDistance(widget.run) ??
        nearestRaceDistance(widget.run.distanceMeters);
  }

  String _otherText(double meters) {
    final d = Distance.meters(meters);
    final shown = widget.unit.isMetric ? d.kilometers : d.miles;
    return shown.toStringAsFixed(shown == shown.roundToDouble() ? 0 : 2);
  }

  /// The distance as typed under Other, in metres, or null when it is not a
  /// distance anybody races.
  double? get _otherMeters {
    final value = double.tryParse(_other.text.trim().replaceAll(',', '.'));
    if (value == null || value <= 0) return null;
    final meters = widget.unit.isMetric
        ? value * metersPerKilometer
        : value * metersPerMile;
    return meters > 250000 ? null : meters;
  }

  double? get _distance => _named ?? _otherMeters;

  Duration get _time =>
      Duration(hours: _hours, minutes: _minutes, seconds: _seconds);

  bool get _canSave => _distance != null && _time > Duration.zero;

  @override
  void dispose() {
    _other.dispose();
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final distance = _distance;
    if (distance == null) return;
    final name = _name.text.trim();
    Navigator.of(context).pop(
      RaceSheetAnswer(
        RunRace(
          distanceMeters: distance,
          officialTime: _time == widget.run.duration ? null : _time,
          name: name.isEmpty ? null : name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editing = _existing != null;
    final phone = widget.run.duration.hoursMinutesSeconds;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                editing ? 'Your race' : 'Was this a race?',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Pick the distance you entered. Your pace and sections are '
                'measured against it, not against the extra the phone picked '
                'up weaving round people.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              const SectionLabel('Distance'),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final meters in kRecordDistancesMeters)
                    ChoiceChip(
                      label: Text(raceName(meters) ?? ''),
                      showCheckmark: false,
                      selected: _named == meters,
                      onSelected: (_) => setState(() => _named = meters),
                    ),
                  ChoiceChip(
                    label: const Text('Other'),
                    showCheckmark: false,
                    selected: _named == null,
                    onSelected: (_) => setState(() => _named = null),
                  ),
                ],
              ),
              if (_named == null) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                TextField(
                  key: const ValueKey<String>('race-other-distance'),
                  controller: _other,
                  autofocus: !editing,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Distance',
                    suffixText: widget.unit.distanceSuffix,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),

              const SectionLabel('Name, if you like'),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const ValueKey<String>('race-name'),
                controller: _name,
                maxLength: 80,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'What the race is called',
                  counterText: '',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              const SectionLabel('Official time'),
              const SizedBox(height: AppSpacing.xs),
              Text(
                // Said before they look at the wheels, not after they notice
                // the number differs from the one on their certificate.
                'Your phone had $phone. If your chip time is different, that '
                'is normal: put it in here and it is the one I will keep.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: <Widget>[
                  Expanded(
                    child: WheelPicker(
                      label: 'Hours',
                      min: 0,
                      max: 23,
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
                label: 'Save race · ${_time.hoursMinutesSeconds}',
                onPressed: _canSave ? _save : null,
              ),
              if (editing) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                Center(
                  child: AppTextButton(
                    // A real answer, kept apart from Cancel: it clears the
                    // race and leaves the run exactly as it was recorded.
                    label: 'It was not a race',
                    onPressed: () =>
                        Navigator.of(context).pop(const RaceSheetAnswer(null)),
                  ),
                ),
              ],
              Center(
                child: AppTextButton(
                  label: 'Cancel',
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
