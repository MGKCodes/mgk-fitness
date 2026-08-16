import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../domain/live_metrics.dart';
import '../domain/run_split.dart';

/// The pieces the in-run readout is built from.
///
/// Extracted rather than grown inside `RecordingScreen`, per design principle 9
/// — a rule that lives in one screen is a rule the next screen will miss. The
/// splits list in particular is the same data the summary shows, so it is one
/// component with the summary rather than a second rendering of it (principle
/// 4: two renderings of one thing is a bug with a delay on it).

/// A live figure with its label — the supporting row under the hero numeral.
class RunStat extends StatelessWidget {
  const RunStat({
    super.key,
    required this.label,
    required this.value,
    this.muted = false,
  });

  final String label;
  final String value;

  /// For a value that is honestly absent rather than zero — dashes for a pace
  /// there is not yet enough movement to compute (principle 7: null is a value,
  /// not a gap).
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return StatBlock(
      label: label,
      value: value,
      size: StatSize.hero,
      align: CrossAxisAlignment.center,
      valueColor: muted ? AppColors.textTertiary : null,
    );
  }
}

/// Signal strength, as four bars that fill.
///
/// Greyscale, so strength is height and opacity rather than colour (ADR-0009).
/// This exists because a stationary app and a searching one were previously
/// indistinguishable: both showed a pulsing "Recording" over zeroes.
class GpsSignalBars extends StatelessWidget {
  const GpsSignalBars({super.key, required this.signal});

  final GpsSignal signal;

  int get _filled => switch (signal) {
    GpsSignal.none => 0,
    GpsSignal.weak => 1,
    GpsSignal.fair => 2,
    GpsSignal.good => 3,
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        for (var i = 0; i < 3; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 3),
          AnimatedContainer(
            duration: AppMotion.base,
            curve: AppMotion.standard,
            width: 3,
            height: 5.0 + i * 3,
            decoration: BoxDecoration(
              color: i < _filled
                  ? AppColors.textPrimary
                  : AppColors.textPrimary.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
        ],
      ],
    );
  }
}

/// Today's prescribed session and how the run is tracking against it.
///
/// The differentiator: a generic tracker cannot tell a runner they are ahead of
/// the pace their coach set, because it does not know there was one. The band
/// is the claim; the verdict underneath is what makes it useful mid-stride.
class TargetBand extends StatelessWidget {
  const TargetBand({
    super.key,
    required this.title,
    required this.unit,
    required this.doneMeters,
    this.targetMeters = 0,
  });

  /// What the session is: "Easy 5k", "Long run".
  final String title;
  final UnitSystem unit;

  /// How far the runner has come.
  final double doneMeters;

  /// The prescribed distance. Zero when the session names none — an open-ended
  /// easy run is a real prescription, and inventing a number for it would be
  /// exactly the thing the validator rule exists to stop.
  final double targetMeters;

  bool get _hasTarget => targetMeters > 0;

  double get _progress =>
      _hasTarget ? (doneMeters / targetMeters).clamp(0.0, 1.0) : 0;

  /// Pace targets are deliberately absent for now.
  ///
  /// A band would have to come from the runner's threshold and a percentage —
  /// derived from a formula, never a copied VDOT table — and that derivation
  /// does not exist yet in the coaching domain. Showing the distance the plan
  /// actually names is honest; a made-up pace would not be.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const SectionLabel('TODAY', emphasis: LabelEmphasis.stat),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (_hasTarget) ...<Widget>[
              const SizedBox(width: AppSpacing.md),
              Text(
                '${Distance.meters(doneMeters).inDisplayUnit(unit).toStringAsFixed(2)}'
                ' of ${Distance.meters(targetMeters).format(unit)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ],
        ),
        if (_hasTarget) ...<Widget>[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Stack(
              children: <Widget>[
                Container(height: 4, color: AppColors.elevated),
                AnimatedFractionallySizedBox(
                  duration: AppMotion.base,
                  curve: AppMotion.standard,
                  widthFactor: _progress,
                  child: Container(height: 4, color: AppColors.primary),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Completed splits with a bar per kilometre, relative to the slowest.
///
/// The shared rendering: the summary screen shows the same thing about the same
/// data, and two versions of it would drift apart within a week.
class SplitList extends StatelessWidget {
  const SplitList({
    super.key,
    required this.splits,
    required this.unit,
    this.maxRows,
    this.newestFirst = false,
    this.showHeartRate = false,
  });

  final List<RunSplit> splits;
  final UnitSystem unit;

  /// Adds the per-split average HR column. Off in-run, where there is no live
  /// HR source; on in the summary, where a synced workout may carry one. A
  /// split with no HR renders an em dash rather than a zero (principle 7).
  final bool showHeartRate;

  /// Caps how many rows are drawn. The in-run screen shows the last few — a
  /// runner mid-effort is not reading kilometre two — while the summary shows
  /// the lot.
  final int? maxRows;

  final bool newestFirst;

  static double paceSeconds(RunSplit split) =>
      split.duration.inSeconds / (split.distanceMeters / 1000);

  @override
  Widget build(BuildContext context) {
    if (splits.isEmpty) return const SizedBox.shrink();

    // Scaled against the slowest split so the bars compare within this run
    // rather than against an absolute nobody has.
    final slowest = splits
        .map(paceSeconds)
        .fold<double>(1, (a, b) => a > b ? a : b);

    var rows = splits;
    if (maxRows != null && rows.length > maxRows!) {
      rows = rows.sublist(rows.length - maxRows!);
    }
    if (newestFirst) rows = rows.reversed.toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
            child: _SplitRow(
              split: rows[i],
              unit: unit,
              fraction: (paceSeconds(rows[i]) / slowest).clamp(0.08, 1.0),
              // The trailing partial is not a kilometre and must not be read
              // as one — principle 7, the absence is meaningful.
              partial: rows[i].distanceMeters < 999,
              showHeartRate: showHeartRate,
            ),
          ),
      ],
    );
  }
}

class _SplitRow extends StatelessWidget {
  const _SplitRow({
    required this.split,
    required this.unit,
    required this.fraction,
    required this.partial,
    required this.showHeartRate,
  });

  final RunSplit split;
  final UnitSystem unit;
  final double fraction;
  final bool partial;
  final bool showHeartRate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pace = Pace.secondsPerKilometer(SplitList.paceSeconds(split));
    final label = partial
        ? Distance.meters(split.distanceMeters).format(unit, fractionDigits: 2)
        : '${split.index}';

    return Row(
      children: <Widget>[
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: partial ? AppColors.textTertiary : AppColors.textSecondary,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fraction,
                child: AnimatedContainer(
                  duration: AppMotion.base,
                  curve: AppMotion.standard,
                  height: 6,
                  decoration: BoxDecoration(
                    // A partial split is still running, so it reads as
                    // provisional rather than as a slow kilometre.
                    color: partial ? AppColors.elevated : AppColors.primary,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        SizedBox(
          width: 68,
          child: Text(
            pace.format(unit),
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textPrimary,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
        if (showHeartRate)
          SizedBox(
            width: 46,
            child: Text(
              split.avgHr != null ? '${split.avgHr}' : '—',
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
      ],
    );
  }
}
