import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../../coaching/domain/run_note.dart';
import '../../coaching/domain/training_plan.dart';
import '../../coaching/presentation/coach_button.dart' show CoachLetter;
import '../domain/run_split.dart';
import '../domain/run_summary.dart';
import 'route_map.dart';

/// Post-run summary: the route, the headline distance, the stats that exist,
/// per-split pace, and what the coach makes of the run. Absent data (no route,
/// no HR, treadmill/manual) is simply not shown — never an error state, and the
/// coach's note is no different: a run there is nothing true to say about shows
/// nothing.
class RunSummaryScreen extends StatelessWidget {
  const RunSummaryScreen({
    super.key,
    required this.summary,
    this.unit = UnitSystem.metric,
    this.onDone,
    this.onEdit,
    this.history = const <RunSummary>[],
    this.plannedSession,
  });

  final RunSummary summary;

  /// Corrects this run's numbers. Null hides the action. The route is never
  /// touched — see `AppDatabase.updateRunDetails`.
  final VoidCallback? onEdit;
  final UnitSystem unit;
  final VoidCallback? onDone;

  /// The runner's other runs, which is what lets the coach say anything
  /// comparative about this one. Passing the whole history is fine — this run
  /// is filtered out of it. Empty means the note falls back to what the run
  /// says about itself, which is usually silence.
  final List<RunSummary> history;

  /// The session prescribed for the day of this run, when it fell on a planned
  /// day. Null on an unplanned day or a rest day.
  final PlannedSession? plannedSession;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = RunNote.forRun(
      summary,
      history: history,
      planned: plannedSession,
      unit: unit,
    );
    return Scaffold(
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.bg,
            title: const Text('Run summary'),
            actions: <Widget>[
              if (onEdit != null)
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: onEdit,
                  tooltip: 'Edit run',
                ),
            ],
          ),
          if (summary.hasRoute)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 300,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    RouteMap(points: summary.points),
                    // The headline reads over the route it describes rather than
                    // below it — the map is the texture the glass needs.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: GlassSurface(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(AppRadius.sheet),
                        ),
                        tintOpacity: 0.14,
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                        child: _Headline(
                          summary: summary,
                          unit: unit,
                          theme: theme,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate(<Widget>[
                // Without a route there is nothing to lay the headline over, so
                // it sits inline on the base instead.
                if (!summary.hasRoute) ...<Widget>[
                  _Headline(summary: summary, unit: unit, theme: theme),
                  const SizedBox(height: 24),
                ],
                _StatGrid(tiles: _tiles()),
                // The numbers first — that is what the screen is for — then the
                // coach's read of them, above the splits a pacing note refers
                // to.
                if (note != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.xxl),
                  _RunNoteCard(note: note),
                ],
                if (summary.splits.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 32),
                  Text(
                    'SPLITS',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppColors.textSecondary,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Splits(splits: summary.splits, unit: unit),
                ],
                // Only when there is somewhere to go. A summary opened from the
                // log is dismissed with back, so its "Done" had nothing to do
                // and rendered permanently greyed out — a dead control at the
                // foot of every run the runner opened. Null hides it, the same
                // way it hides [onEdit].
                if (onDone != null) ...<Widget>[
                  const SizedBox(height: 32),
                  FilledButton(onPressed: onDone, child: const Text('Done')),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  List<_Tile> _tiles() {
    final tiles = <_Tile>[_Tile('TIME', summary.duration.hoursMinutesSeconds)];
    final pace = _avgPace();
    if (pace != null) tiles.add(_Tile('AVG PACE', pace.format(unit)));
    if (summary.elevationGainMeters != null) {
      tiles.add(
        _Tile('ELEVATION', '${summary.elevationGainMeters!.round()} m'),
      );
    }
    if (summary.avgHr != null) {
      tiles.add(_Tile('AVG HR', '${summary.avgHr} bpm'));
    }
    if (summary.caloriesEst != null) {
      tiles.add(
        _Tile('CALORIES (EST)', '${summary.caloriesEst!.round()} kcal'),
      );
    }
    return tiles;
  }

  Pace? _avgPace() {
    if (summary.avgPaceSecondsPerKm != null) {
      return Pace.secondsPerKilometer(summary.avgPaceSecondsPerKm!);
    }
    if (summary.distanceMeters > 0) {
      return Pace.from(
        Distance.meters(summary.distanceMeters),
        summary.duration,
      );
    }
    return null;
  }
}

class _Tile {
  const _Tile(this.label, this.value);
  final String label;
  final String value;
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.tiles});

  final List<_Tile> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = AppSpacing.md;
        final width = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: <Widget>[
            for (final tile in tiles)
              SizedBox(
                width: width,
                child: AppCard(
                  child: StatBlock(label: tile.label, value: tile.value),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// What the coach makes of this run.
///
/// The same treatment Home gives a [RunNote]'s sibling, `CoachNote` — card,
/// spark icon, headline over evidence — so one voice reads the same wherever it
/// speaks. Without the chevron and the tap: this note is about the run already
/// on screen, so there is nowhere for it to lead.
class _RunNoteCard extends StatelessWidget {
  const _RunNoteCard({required this.note});

  final RunNote note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(
            width: 20,
            height: 20,
            child: Center(
              child: CoachLetter(size: 16, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  note.headline,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  note.detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Splits extends StatelessWidget {
  const _Splits({required this.splits, required this.unit});

  final List<RunSplit> splits;
  final UnitSystem unit;

  double _paceSeconds(RunSplit split) =>
      split.duration.inSeconds / (split.distanceMeters / 1000);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slowest = splits
        .map(_paceSeconds)
        .fold<double>(1, (a, b) => a > b ? a : b);
    return Column(
      children: <Widget>[
        for (final split in splits)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 28,
                  child: Text(
                    '${split.index}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: (_paceSeconds(split) / slowest).clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: AppColors.elevated,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 68,
                  child: Text(
                    Pace.secondsPerKilometer(_paceSeconds(split)).format(unit),
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    split.avgHr != null ? '${split.avgHr}' : '—',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
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

String _formatDate(DateTime at) {
  final hh = at.hour.toString().padLeft(2, '0');
  final mm = at.minute.toString().padLeft(2, '0');
  return '${at.day} ${_months[at.month - 1]} ${at.year}, $hh:$mm';
}

String _typeLabel(String type) => switch (type) {
  'treadmill' => 'Treadmill',
  'manual' => 'Manual entry',
  _ => 'Outdoor run',
};

/// Date, type and the run's headline distance. Shared so the glass overlay and
/// the no-route fallback cannot drift apart.
class _Headline extends StatelessWidget {
  const _Headline({
    required this.summary,
    required this.unit,
    required this.theme,
  });

  final RunSummary summary;
  final UnitSystem unit;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '${_formatDate(summary.startedAt)}  ·  ${_typeLabel(summary.type)}',
          style: theme.textTheme.labelMedium?.copyWith(
            color: AppColors.textSecondary,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          Distance.meters(summary.distanceMeters).format(unit),
          style: theme.textTheme.displayMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
