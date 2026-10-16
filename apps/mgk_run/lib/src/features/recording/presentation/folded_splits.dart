import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../domain/run_split.dart';
import 'recording_readout.dart';

/// A run's splits, folded to one line until the runner asks for the rest.
///
/// **Twenty-two rows was the bottom half of a half marathon's summary.** The
/// full list is the right thing to have and the wrong thing to lead with: on
/// the day of a long run the runner scrolls past a screen of near-identical
/// bars to reach Done, and the two numbers anybody reads off a list that long
/// are the quickest kilometre and the slowest. So those two are said, the
/// shape of the whole run is drawn in one small chart, and the list is a tap
/// away rather than gone (Matthew, after the Royal Parks half, 2026-10-13).
///
/// A short run is not folded at all. Five rows is not a list anybody needs to
/// be protected from, and a fold over three kilometres would be a control with
/// nothing behind it.
class FoldedSplits extends StatefulWidget {
  const FoldedSplits({
    super.key,
    required this.splits,
    required this.unit,
    this.initiallyOpen = false,
  });

  final List<RunSplit> splits;
  final UnitSystem unit;
  final bool initiallyOpen;

  /// Up to this many splits are shown in full, unfolded.
  static const int foldAbove = 5;

  @override
  State<FoldedSplits> createState() => _FoldedSplitsState();
}

class _FoldedSplitsState extends State<FoldedSplits> {
  late bool _open = widget.initiallyOpen;

  /// Only when some split carries one. A column of dashes beside every row of
  /// a run recorded with no heart rate source said nothing twenty-two times.
  bool get _hasHeartRate => widget.splits.any((s) => s.avgHr != null);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final splits = widget.splits;
    final full = SplitList(
      splits: splits,
      unit: widget.unit,
      showHeartRate: _hasHeartRate,
    );

    final label = Text(
      'SPLITS',
      style: theme.textTheme.labelMedium?.copyWith(
        color: AppColors.textSecondary,
        letterSpacing: 3,
      ),
    );

    if (splits.length <= FoldedSplits.foldAbove) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[label, const SizedBox(height: 12), full],
      );
    }

    // Whole kilometres only: the trailing partial is not a kilometre, and a
    // 0.69 km sprint for the line must not be crowned the slowest one.
    final whole = <RunSplit>[
      for (final s in splits)
        if (s.distanceMeters >= 999) s,
    ];
    RunSplit? fastest;
    RunSplit? slowest;
    for (final s in whole) {
      final pace = SplitList.paceSeconds(s);
      if (fastest == null || pace < SplitList.paceSeconds(fastest)) {
        fastest = s;
      }
      if (slowest == null || pace > SplitList.paceSeconds(slowest)) {
        slowest = s;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        label,
        const SizedBox(height: 12),
        _Shape(splits: splits),
        const SizedBox(height: AppSpacing.md),
        if (fastest != null)
          _Extreme(label: 'Fastest', split: fastest, unit: widget.unit),
        if (slowest != null && slowest != fastest) ...<Widget>[
          const SizedBox(height: 6),
          _Extreme(label: 'Slowest', split: slowest, unit: widget.unit),
        ],
        const SizedBox(height: AppSpacing.sm),
        AnimatedSize(
          duration: AppMotion.base,
          curve: AppMotion.standard,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: full,
                )
              : const SizedBox(width: double.infinity),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: AppTextButton(
            label: _open ? 'Hide splits' : 'Show all ${splits.length} splits',
            icon: _open
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
            onPressed: () => setState(() => _open = !_open),
          ),
        ),
      ],
    );
  }
}

/// Every split as one bar, so the shape of the run reads at a glance: taller is
/// slower, the same way round the list's bars are longer for slower.
class _Shape extends StatelessWidget {
  const _Shape({required this.splits});

  final List<RunSplit> splits;

  static const double _height = 36;

  @override
  Widget build(BuildContext context) {
    final paces = splits.map(SplitList.paceSeconds).toList();
    final slowest = paces.fold<double>(1, (a, b) => a > b ? a : b);
    final quickest = paces.fold<double>(slowest, (a, b) => a < b ? a : b);
    // Scaled across this run's own range rather than from zero, or every bar
    // of an evenly paced run is the same height and the chart says nothing.
    // The floor keeps the quickest kilometre visible as a bar.
    final range = slowest - quickest;
    return Semantics(
      label: 'Pace of each split, slower is taller',
      child: SizedBox(
        height: _height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            for (var i = 0; i < splits.length; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 2),
                  child: Container(
                    height:
                        _height *
                        (range <= 0
                            ? 0.6
                            : 0.25 + 0.75 * (paces[i] - quickest) / range),
                    decoration: BoxDecoration(
                      color: splits[i].distanceMeters < 999
                          ? AppColors.elevated
                          : AppColors.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Extreme extends StatelessWidget {
  const _Extreme({
    required this.label,
    required this.split,
    required this.unit,
  });

  final String label;
  final RunSplit split;
  final UnitSystem unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tabular = const <FontFeature>[FontFeature.tabularFigures()];
    return Row(
      children: <Widget>[
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Text(
          // Splits are cut every kilometre whatever the unit (`splitRun`), so
          // this names the kilometre even when the pace beside it is per mile.
          'km ${split.index}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
            fontFeatures: tabular,
          ),
        ),
        const Spacer(),
        Text(
          Pace.secondsPerKilometer(SplitList.paceSeconds(split)).format(unit),
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.textPrimary,
            fontFeatures: tabular,
          ),
        ),
      ],
    );
  }
}
