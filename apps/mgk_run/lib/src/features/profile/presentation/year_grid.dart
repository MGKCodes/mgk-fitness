import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../../coaching/domain/training_history.dart';

/// **A year of running**, drawn by the suite's [ActivityYearGrid] so that Run
/// and Lift keep one picture of a year between them.
///
/// Home's [ConsistencyGrid] answers "am I turning up" over eight weeks, which
/// is a question about the habit you are in now. This answers "what did this
/// year look like", which needs the opposite layout; the grid's own comment
/// says why it is two-tone and seven rows deep.
///
/// What is Run's here is the words and the amounts: a day's distance in the
/// runner's units for the line under the grid, and the year's days and distance
/// over it.
class YearGrid extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final ran = weeks.expand((w) => w).where((d) => d.ran).toList();
    final total = ran.fold<double>(0, (sum, d) => sum + d.meters);
    return ActivityYearGrid(
      weeks: <List<ActivityYearDay>>[
        for (final week in weeks)
          <ActivityYearDay>[
            for (final day in week)
              ActivityYearDay(
                date: day.date,
                // `ran` rather than `meters > 0`, so a run the phone logged
                // without a distance still marks the day it happened on.
                active: day.ran,
                isFuture: day.isFuture,
                isToday: day.isToday,
                detail: day.ran
                    ? Distance.meters(
                        day.meters,
                      ).format(unit, fractionDigits: 1)
                    : null,
              ),
          ],
      ],
      summary: ran.isEmpty
          ? 'Every run you record shows up here.'
          : '${ran.length} ${ran.length == 1 ? 'day' : 'days'} run · '
                '${Distance.meters(total).format(unit, fractionDigits: 0)}',
      activeLabel: 'Ran',
      inactiveDetail: 'no run',
    );
  }
}
