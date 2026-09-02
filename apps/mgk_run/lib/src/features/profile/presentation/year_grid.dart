import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../../coaching/domain/training_history.dart';

/// **A year of running, seven rows deep and fifty-odd columns wide.**
///
/// Home's [ConsistencyGrid] answers "am I turning up" over eight weeks, which
/// is a question about the habit you are currently in. This answers a different
/// one — "what did this year look like" — and it needs the opposite layout to
/// do it. Fifty-two rows of seven is a list nobody scrolls to the bottom of;
/// seven rows of fifty-two is a shape you take in at a glance, which is why
/// every contribution graph ever built is oriented this way.
///
/// **Attendance, not distance.** Squares are two-tone: white for a day with a
/// run in it, and the empty grey for a day without. Nothing in between.
///
/// This used to shade by distance across four buckets, on the argument that a
/// year of 5 km Tuesdays and a year of building to a marathon should not draw
/// the same grid. The argument was sound and the read was not: at eleven points
/// across, four greys between #404040 and #C0C0C0 are four shades nobody can
/// separate without the legend, and a reader who has to consult a legend to
/// tell two squares apart is not taking anything in at a glance — which is the
/// whole and only reason this grid is seven rows deep rather than fifty-two.
///
/// Distance did not lose its home; it was never this one. The readout under the
/// grid gives the exact figure for the day you tap, to a tenth of a kilometre,
/// which is a better answer than a shade was ever going to be.
///
/// The two tones are the app's own greys
/// ([ADR-0009](../../../../docs/decisions/0009-greyscale-design-language.md)),
/// and the distinction survives being printed, dimmed or read by somebody
/// colour-blind — which a four-step ramp of one hue does not.
class YearGrid extends StatefulWidget {
  const YearGrid({
    super.key,
    required this.weeks,
    this.unit = UnitSystem.metric,
  });

  /// Weeks as columns, oldest first, each running Monday to Sunday — the shape
  /// [runYear] returns.
  final List<List<RunYearDay>> weeks;

  final UnitSystem unit;

  @override
  State<YearGrid> createState() => _YearGridState();
}

class _YearGridState extends State<YearGrid> {
  final ScrollController _scroll = ScrollController();

  /// The day the runner has tapped, or null.
  ///
  /// A square is eleven points across, which is too small to carry its own
  /// label and too small to be sure you hit the one you meant. So the readout
  /// is one line under the grid rather than a tooltip on the square: it says
  /// what you actually selected, which a tooltip under your own thumb does not.
  RunYearDay? _picked;

  @override
  void initState() {
    super.initState();
    // Opens on the present. A year view scrolled to last September opens on a
    // fact about the past, and the question this screen is asked is almost
    // always about the last month.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = widget.weeks.expand((w) => w).toList();
    final ran = days.where((d) => d.ran).toList();
    final total = ran.fold<double>(0, (sum, d) => sum + d.meters);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionLabel('The year'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            ran.isEmpty
                ? 'Every run you record shows up here.'
                : '${ran.length} ${ran.length == 1 ? 'day' : 'days'} run · '
                      '${Distance.meters(total).format(widget.unit, fractionDigits: 0)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // A fixed gutter, outside the scroll view. Without it the rows are
              // seven anonymous stripes — you can see that a runner is
              // consistent without being able to see they never run on a
              // Tuesday, which is the more useful of the two facts. It cannot
              // scroll with the grid, or it would be a label that leaves.
              const _WeekdayGutter(),
              const SizedBox(width: 6),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _MonthRow(weeks: widget.weeks),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          for (final week in widget.weeks)
                            Padding(
                              padding: const EdgeInsets.only(right: 3),
                              child: Column(
                                children: <Widget>[
                                  for (final day in week)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 3),
                                      child: _YearCell(
                                        day: day,
                                        selected: identical(day, _picked),
                                        onTap: day.isFuture
                                            ? null
                                            : () => setState(
                                                () => _picked =
                                                    identical(day, _picked)
                                                    ? null
                                                    : day,
                                              ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _Readout(picked: _picked, unit: widget.unit),
        ],
      ),
    );
  }
}

/// Mon / Wed / Fri down the left, aligned to their rows.
///
/// Three of seven rather than all seven, which is what makes it legible: an
/// eleven-point square has no room for a label beside it at a readable size, so
/// every other row is left blank and the eye interpolates. Naming the odd rows
/// specifically — rather than the first three — keeps the weekend at the bottom
/// identifiable by position.
class _WeekdayGutter extends StatelessWidget {
  const _WeekdayGutter();

  /// A square plus the gap under it. Kept as one constant because the gutter
  /// and the grid have to agree about it exactly, and a label half a row out is
  /// worse than no label.
  static const double _row = 14;

  static const List<String> _labels = <String>['M', '', 'W', '', 'F', '', ''];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      // Clears the month row above the grid, so the M lines up with Monday
      // rather than with the months.
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          for (final label in _labels)
            SizedBox(
              height: _row,
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Month initials over the column each month starts in.
///
/// Only where a month actually begins, rather than every column — a label over
/// every week is fifty-two labels and no information.
class _MonthRow extends StatelessWidget {
  const _MonthRow({required this.weeks});

  final List<List<RunYearDay>> weeks;

  static const List<String> _names = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    var lastMonth = -1;
    final labels = <Widget>[];
    for (final week in weeks) {
      final monday = week.first.date;
      // The label goes on the first column whose Monday is in a new month, so
      // it sits at the month's leading edge rather than floating mid-month.
      final isNew = monday.month != lastMonth;
      lastMonth = monday.month;
      labels.add(
        SizedBox(
          width: 14,
          child: isNew
              ? Text(
                  _names[monday.month - 1],
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w700,
                  ),
                  softWrap: false,
                  overflow: TextOverflow.visible,
                )
              : const SizedBox.shrink(),
        ),
      );
    }
    return Row(children: labels);
  }
}

/// One day. Eleven points, like the eight-week grid's, so the two surfaces
/// read as the same instrument at two lengths.
class _YearCell extends StatelessWidget {
  const _YearCell({
    required this.day,
    required this.selected,
    required this.onTap,
  });

  final RunYearDay day;
  final bool selected;
  final VoidCallback? onTap;

  /// Four steps of distance plus nothing at all.
  ///
  @override
  Widget build(BuildContext context) {
    final Color fill;
    if (day.isFuture) {
      // Not an absence. Barely drawn, exactly as the eight-week grid treats it.
      fill = AppColors.elevated.withValues(alpha: 0.45);
    } else {
      // Ran or did not. `ran` rather than `meters > 0`, so a run the phone
      // logged without a distance still marks the day it happened on.
      fill = day.ran ? AppColors.textPrimary : AppColors.elevated;
    }

    return Semantics(
      label: day.ran
          ? '${day.date.day}/${day.date.month}: '
                '${(day.meters / 1000).toStringAsFixed(1)} km'
          : '${day.date.day}/${day.date.month}: no run',
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(3),
            // Today is outlined rather than filled, matching the eight-week
            // grid — an open day is not a finished one.
            border: selected
                ? Border.all(color: AppColors.primary, width: 1.6)
                : day.isToday && !day.ran
                ? Border.all(color: AppColors.primary, width: 1.6)
                : null,
          ),
        ),
      ),
    );
  }
}

/// The line under the grid: what the tapped square was, or the scale.
class _Readout extends StatelessWidget {
  const _Readout({required this.picked, required this.unit});

  final RunYearDay? picked;
  final UnitSystem unit;

  static const List<String> _months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final day = picked;
    if (day == null) {
      // The key, which is only worth its line while nothing is selected.
      //
      // Two entries rather than a five-step ramp under "Less" and "More". A
      // ramp is a legend you have to *use* — you look back at it to decide
      // which of two greys a square is. This one is a caption: read once, and
      // the grid never needs it again.
      return Row(
        children: <Widget>[
          for (final (Color fill, String label) in <(Color, String)>[
            (AppColors.textPrimary, 'Ran'),
            (AppColors.elevated, 'Rest'),
          ]) ...<Widget>[
            Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(width: 14),
          ],
        ],
      );
    }
    final d = day.date;
    final when = '${d.day} ${_months[d.month - 1]} ${d.year}';
    return Text(
      day.ran
          ? '$when · ${Distance.meters(day.meters).format(unit, fractionDigits: 1)}'
          : '$when · no run',
      style: theme.textTheme.bodyMedium?.copyWith(
        color: AppColors.textSecondary,
      ),
    );
  }
}
