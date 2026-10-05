import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import 'app_card.dart';
import 'section_label.dart';

/// One day of an [ActivityYearGrid].
@immutable
class ActivityYearDay {
  const ActivityYearDay({
    required this.date,
    required this.active,
    this.isFuture = false,
    this.isToday = false,
    this.detail,
  });

  final DateTime date;

  /// Whether anything was done on it: a run, a session.
  final bool active;

  /// After today. Drawn barely, because a day that has not happened is not one
  /// that was missed.
  final bool isFuture;

  final bool isToday;

  /// What the day held, as the line under the grid says it when the day is
  /// tapped: `5.2 km`, `2,830 kg`. Null for a day with nothing in it.
  final String? detail;
}

/// **The year, seven rows deep and fifty-odd columns wide**, in both apps.
///
/// Drawn the same way in Run and in Lift, which is why it lives here: the one
/// account's two apps should not keep two different pictures of a year.
///
/// Seven rows of fifty-two is a shape you take in at a glance; fifty-two rows
/// of seven is a list nobody scrolls to the bottom of, which is why every
/// contribution graph is oriented this way.
///
/// **Attendance, not amount.** Squares are two-tone: white for a day with
/// something in it, the empty grey for a day without. It used to shade by
/// amount across four buckets, and at eleven points across four greys between
/// #404040 and #C0C0C0 are four shades nobody can separate without the legend.
/// A grid you have to consult a legend to read is not one you take in at a
/// glance. The amount is not lost: the line under the grid gives it exactly for
/// the day you tap.
///
/// The two tones are the suite's own greys, and the distinction survives being
/// printed, dimmed or read by somebody colour-blind, which a ramp of one hue
/// does not.
class ActivityYearGrid extends StatefulWidget {
  const ActivityYearGrid({
    super.key,
    required this.weeks,
    required this.summary,
    required this.activeLabel,
    required this.inactiveDetail,
  });

  /// Weeks as columns, oldest first, each running Monday to Sunday.
  final List<List<ActivityYearDay>> weeks;

  /// The line under the heading: how many days and how much, or, before there
  /// is anything, what will appear.
  final String summary;

  /// The key's word for a white square: `Ran`, `Trained`.
  final String activeLabel;

  /// What the line under the grid says for a tapped day with nothing in it:
  /// `no run`, `rest day`.
  final String inactiveDetail;

  @override
  State<ActivityYearGrid> createState() => _ActivityYearGridState();
}

class _ActivityYearGridState extends State<ActivityYearGrid> {
  final ScrollController _scroll = ScrollController();

  /// The day that was tapped, or null.
  ///
  /// A square is eleven points across, too small to carry its own label and
  /// too small to be sure you hit the one you meant. So the readout is one
  /// line under the grid rather than a tooltip under your own thumb.
  ActivityYearDay? _picked;

  @override
  void initState() {
    super.initState();
    // Opens on the present. A year view scrolled to last September opens on a
    // fact about the past, and the question it is asked is almost always about
    // the last month.
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
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionLabel('The year'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            widget.summary,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // A fixed gutter, outside the scroll view. Without it the rows are
              // seven anonymous stripes: you can see somebody is consistent
              // without being able to see they never train on a Tuesday. It
              // cannot scroll with the grid, or it would be a label that leaves.
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
                                        inactiveDetail: widget.inactiveDetail,
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
          _Readout(
            picked: _picked,
            activeLabel: widget.activeLabel,
            inactiveDetail: widget.inactiveDetail,
          ),
        ],
      ),
    );
  }
}

/// Mon / Wed / Fri down the left, aligned to their rows.
///
/// Three of seven, which is what makes it legible: an eleven-point square has
/// no room for a label beside it at a readable size, so every other row is
/// left blank and the eye interpolates. Naming the odd rows keeps the weekend
/// at the bottom identifiable by position.
class _WeekdayGutter extends StatelessWidget {
  const _WeekdayGutter();

  /// A square plus the gap under it. One constant, because the gutter and the
  /// grid have to agree about it exactly.
  static const double _row = 14;

  static const List<String> _labels = <String>['M', '', 'W', '', 'F', '', ''];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      // Clears the month row above the grid, so the M lines up with Monday.
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

/// Month names over the column each month starts in, and nowhere else.
class _MonthRow extends StatelessWidget {
  const _MonthRow({required this.weeks});

  final List<List<ActivityYearDay>> weeks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    var lastMonth = -1;
    final labels = <Widget>[];
    for (final week in weeks) {
      final monday = week.first.date;
      // On the first column whose Monday is in a new month, so the label sits
      // at the month's leading edge rather than floating mid-month.
      final isNew = monday.month != lastMonth;
      lastMonth = monday.month;
      labels.add(
        SizedBox(
          width: 14,
          child: isNew
              ? Text(
                  _months[monday.month - 1],
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

/// One day, eleven points square.
class _YearCell extends StatelessWidget {
  const _YearCell({
    required this.day,
    required this.inactiveDetail,
    required this.selected,
    required this.onTap,
  });

  final ActivityYearDay day;
  final String inactiveDetail;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color fill;
    if (day.isFuture) {
      // Not an absence: barely drawn.
      fill = AppColors.elevated.withValues(alpha: 0.45);
    } else {
      fill = day.active ? AppColors.textPrimary : AppColors.elevated;
    }

    return Semantics(
      label:
          '${day.date.day}/${day.date.month}: '
          '${day.active ? day.detail ?? '' : inactiveDetail}',
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(3),
            // Today is outlined rather than filled: an open day is not a
            // finished one.
            border: selected
                ? Border.all(color: AppColors.primary, width: 1.6)
                : day.isToday && !day.active
                ? Border.all(color: AppColors.primary, width: 1.6)
                : null,
          ),
        ),
      ),
    );
  }
}

/// The line under the grid: what the tapped square was, or the key.
class _Readout extends StatelessWidget {
  const _Readout({
    required this.picked,
    required this.activeLabel,
    required this.inactiveDetail,
  });

  final ActivityYearDay? picked;
  final String activeLabel;
  final String inactiveDetail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final day = picked;
    if (day == null) {
      // The key, which is only worth its line while nothing is selected. Two
      // entries rather than a ramp under "Less" and "More": read once, and the
      // grid never needs it again.
      return Row(
        children: <Widget>[
          for (final (Color fill, String label) in <(Color, String)>[
            (AppColors.textPrimary, activeLabel),
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
      '$when · ${day.active ? day.detail ?? '' : inactiveDetail}',
      style: theme.textTheme.bodyMedium?.copyWith(
        color: AppColors.textSecondary,
      ),
    );
  }
}

const List<String> _months = <String>[
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
