import 'dart:async';

import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../../coaching/domain/run_note.dart';
import '../../coaching/domain/training_plan.dart';
import '../../coaching/presentation/coach_button.dart' show CoachLetter;
import '../domain/live_metrics.dart';
import '../domain/run_point.dart';
import '../domain/split_marker.dart';
import '../domain/run_summary.dart';
import 'recording_readout.dart';
import 'route_map.dart';

/// Post-run summary: the route, the headline distance, the stats that exist,
/// per-split pace, and what the coach makes of the run. Absent data (no route,
/// no HR, treadmill/manual) is simply not shown — never an error state, and the
/// coach's note is no different: a run there is nothing true to say about shows
/// nothing.
///
/// **Two arrivals at one screen, and only one of them is an arrival.** Opened
/// from the log it is a record being looked up. Reached by pressing Finish it
/// is the end of the thing the run was, and the first field test found out what
/// happens when that is not distinguished: the screen was not reached at all —
/// `_finish()` popped — so an hour of effort ended with the display going away.
/// [justFinished] is what separates the two, and it is deliberately small: the
/// title, the date line, and a Done that has somewhere to go. Everything else
/// is the same screen because it is the same run.
class RunSummaryScreen extends StatelessWidget {
  const RunSummaryScreen({
    super.key,
    required this.summary,
    this.unit = UnitSystem.metric,
    this.onDone,
    this.onEdit,
    this.onAskCoach,
    this.history = const <RunSummary>[],
    this.plannedSession,
    this.justFinished = false,
  });

  final RunSummary summary;

  /// Corrects this run's numbers. Null hides the action. The route is never
  /// touched — see `AppDatabase.updateRunDetails`.
  final VoidCallback? onEdit;

  /// Takes the run to the coach. Null in a build with no coach behind it, and
  /// then the affordance is simply absent rather than inert.
  ///
  /// **The point of a note is that there is more to ask.** `RunNote` says one
  /// true thing and stops — that is its whole design, a coach who says five
  /// things about one run is not coaching — and this is the way past that
  /// ceiling, at the moment the runner cares most about the answer.
  final VoidCallback? onAskCoach;

  final UnitSystem unit;
  final VoidCallback? onDone;

  /// Whether this run was finished seconds ago rather than looked up.
  final bool justFinished;

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
            // "Run complete", not "Run summary", when the run finished seconds
            // ago. A summary is something you go and look at; this is the thing
            // arriving, and the title is the cheapest place to say so.
            title: Text(justFinished ? 'Run complete' : 'Run summary'),
            actions: <Widget>[
              if (onEdit != null)
                AppIconButton(
                  icon: Icons.edit_outlined,
                  tooltip: 'Edit run',
                  onPressed: onEdit,
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
                    _DrawnRoute(
                      points: summary.points,
                      // Derived here rather than stored: the trace already
                      // carries every crossing, and the splits below come from
                      // the same walk, so the pin on the map and the row in the
                      // list can never disagree about kilometre four.
                      markers: splitMarkersFor(summary.points),
                      // Only on arrival. Opening a run from the log is looking
                      // something up, and a route that insists on redrawing
                      // itself every time you check last Tuesday is a flourish
                      // that has outstayed the moment it was for.
                      animate: justFinished,
                    ),
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
                          justFinished: justFinished,
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
                // **The one screen in the app that has earned an entrance.**
                //
                // It arrives the instant a run ends, at the one moment somebody
                // is certainly looking at the phone rather than glancing down
                // at it, and every figure on it is a fact they just went and
                // made. Landing it fully formed in a single frame throws that
                // away. The order is the order they matter in: what you did,
                // then the numbers, then what the coach makes of them, then the
                // splits behind it.
                //
                // Entrance plays once and self-disables under reduced motion,
                // so this is choreography rather than something to sit through.
                if (!summary.hasRoute) ...<Widget>[
                  Entrance(
                    child: _Headline(
                      summary: summary,
                      unit: unit,
                      theme: theme,
                      justFinished: justFinished,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                Entrance(index: 1, child: _StatGrid(tiles: _tiles())),
                // The numbers first — that is what the screen is for — then the
                // coach's read of them, above the splits a pacing note refers
                // to.
                //
                // Present when there is a note, and also when there is only a
                // way in. Silence is a normal output of [RunNote] — most runs
                // are ordinary and the coach says nothing about them — but a
                // runner who wants to know what their coach makes of an
                // ordinary run should not have to go and find the conversation
                // to ask.
                if (note != null || onAskCoach != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.xxl),
                  Entrance(
                    index: 2,
                    child: _CoachBlock(note: note, onAsk: onAskCoach),
                  ),
                ],
                if (summary.splits.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 32),
                  Entrance(
                    index: 3,
                    child: Text(
                      'SPLITS',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.textSecondary,
                        letterSpacing: 3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Entrance(
                    index: 4,
                    child: SplitList(
                      splits: summary.splits,
                      unit: unit,
                      showHeartRate: true,
                    ),
                  ),
                ],
                // Only when there is somewhere to go. A summary opened from the
                // log is dismissed with back, so its "Done" had nothing to do
                // and rendered permanently greyed out — a dead control at the
                // foot of every run the runner opened. Null hides it, the same
                // way it hides [onEdit].
                if (onDone != null) ...<Widget>[
                  const SizedBox(height: 32),
                  // Arrives last, and commits when it goes: closing a finished
                  // run is the end of the thing the run was, so it is felt
                  // rather than merely acted on.
                  Entrance(
                    index: 5,
                    child: PrimaryButton(
                      label: 'Done',
                      onPressed: () {
                        unawaited(AppHaptics.commit());
                        onDone!();
                      },
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  /// The grid, built from what this run actually has.
  ///
  /// **Every tile here is conditional, and that is the extension point.** The
  /// measures Strava carried for the same 10 km and Runio did not — elevation
  /// gain, max elevation, steps — arrive as a value on [RunSummary] and a line
  /// in this list; nothing about the layout has to change, because the grid
  /// wraps whatever it is given.
  ///
  /// **Absence is the common case, not the broken one.** Steps come from
  /// Health, where a denied read is indistinguishable from no data, and the
  /// elevation pair comes from barometric altitude that this app does not yet
  /// have a source for at all (ADR-0024). Every one of those renders as an
  /// absent tile — never a zero, which would be a claim, and never an error,
  /// which would scold a runner for a permission they were entitled to withhold
  /// (CLAUDE.md rule 6).
  List<_Tile> _tiles() {
    final tiles = <_Tile>[_Tile('TIME', summary.duration.hoursMinutesSeconds)];
    final pace = _avgPace();
    if (pace != null) tiles.add(_Tile('AVG PACE', pace.format(unit)));
    // **Two elevation figures, named apart.** A bare "ELEVATION" was
    // unambiguous while it was the only one; beside a high point it is not, and
    // 167 m of gain over a 111 m maximum is a pair of numbers that has to say
    // which is which. The in-run readout still says CLIMB, correctly: there is
    // only ever one elevation figure mid-run and nothing for it to be confused
    // with.
    if (summary.elevationGainMeters != null) {
      tiles.add(
        _Tile('ELEVATION GAIN', '${summary.elevationGainMeters!.round()} m'),
      );
    }
    if (summary.elevationMaxMeters != null) {
      tiles.add(
        _Tile('MAX ELEVATION', '${summary.elevationMaxMeters!.round()} m'),
      );
    }
    if (summary.steps != null) {
      tiles.add(_Tile('STEPS', _grouped(summary.steps!)));
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

/// Thousands separated, because a step count is the one figure on this screen
/// that runs to five digits and `12468` is not a number anybody reads at a
/// glance. Written out rather than pulled from `intl`: the app carries no
/// locale machinery, and inventing one for a single comma would be a
/// dependency for a punctuation mark.
String _grouped(int value) {
  final digits = value.abs().toString();
  final out = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
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

/// What the coach makes of this run, and the way to keep asking.
///
/// The same treatment Home gives a [RunNote]'s sibling, `CoachNote` — card,
/// coach mark, headline over evidence — so one voice reads the same wherever it
/// speaks. The card itself still does not lead anywhere on tap: the note is
/// about the run already on screen, and a card that opened the coach would make
/// the observation a link rather than a remark.
///
/// The button underneath is a different claim, and it says so in its own words.
/// A [RunNote] is one sentence and then silence by design; "Ask your coach"
/// is the acknowledgement that a runner may well have a second question about
/// the run they are looking at, and this is the moment it is worth the most.
class _CoachBlock extends StatelessWidget {
  const _CoachBlock({required this.note, required this.onAsk});

  /// Null when there is nothing true to say about this run — which is most
  /// runs. The card goes; the way in stays.
  final RunNote? note;
  final VoidCallback? onAsk;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final said = note;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (said != null)
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: Center(
                    child: CoachLetter(
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        said.headline,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        said.detail,
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
          ),
        if (onAsk != null)
          Align(
            alignment: Alignment.centerLeft,
            child: AppTextButton(
              // "About this run", not a bare "Ask your coach": the mark
              // floating over every tab already offers a conversation, and this
              // one opens with the run on screen as its subject.
              label: 'Ask your coach about this run',
              onPressed: onAsk,
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
    this.justFinished = false,
  });

  final RunSummary summary;
  final UnitSystem unit;
  final ThemeData theme;
  final bool justFinished;

  /// "Just now" on a run that has this second stopped, and the date otherwise.
  ///
  /// Stamping `24 Aug 2026, 15:00` on a run somebody finished thirty seconds
  /// ago is filing it before they have looked at it — the sentence a log entry
  /// needs, on the one occasion the reader already knows the answer. It reverts
  /// to the date the moment this run is opened again from the log, which is
  /// where a date is worth having.
  String get _when =>
      justFinished ? 'Just now' : _formatDate(summary.startedAt);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '$_when  ·  ${_typeLabel(summary.type)}',
          style: theme.textTheme.labelMedium?.copyWith(
            color: AppColors.textSecondary,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        // Counts up on arrival. ADR-0009 asks for hero numerals that count,
        // and it matters most here: with no accent colour the number *is* the
        // interface, and a distance that lands rather than appears is the
        // difference between a screen that congratulates you and a receipt.
        //
        // Only when just finished. Opening last Tuesday from the log is looking
        // something up, and a number that insists on counting itself out every
        // time is a flourish that has outstayed the moment it was for — the
        // same rule the route below follows.
        if (justFinished)
          CountUp(
            value: summary.distanceMeters,
            format: (m) => Distance.meters(m).format(unit),
            style: theme.textTheme.displayMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          )
        else
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

/// The route, drawing itself on.
///
/// **The one moment this screen has to be an arrival rather than a record.**
/// An hour of running appearing over a second is the shape of the effort played
/// back, and it is the difference between a screen that says well done and a
/// screen that files something.
///
/// Owns its own controller so [RunSummaryScreen] stays stateless and
/// [RouteMap] stays still. The map takes a plain fraction and has no clock of
/// its own, which is also what lets a test pin the route half-drawn rather than
/// wait for it.
///
/// **Off unless the run just finished.** Opening last Tuesday from the log is
/// looking something up, and a route that redraws itself every time is a
/// flourish that has outstayed the moment it was for.
///
/// It also jumps straight to the finished state when the platform asks for
/// reduced motion — vestibular disorders make motion a genuine barrier, and
/// this is a large moving object — which is the same rule, and the same call,
/// `Entrance` makes. That is what keeps `pumpAndSettle` from waiting on it too.
class _DrawnRoute extends StatefulWidget {
  const _DrawnRoute({
    required this.points,
    required this.markers,
    required this.animate,
  });

  final List<RunPoint> points;
  final List<SplitMarker> markers;
  final bool animate;

  @override
  State<_DrawnRoute> createState() => _DrawnRouteState();
}

class _DrawnRouteState extends State<_DrawnRoute>
    with SingleTickerProviderStateMixin {
  /// Long enough to read as a route being traced, short enough that nobody
  /// waiting to see their splits resents it. A run is an hour; this is not a
  /// replay of it.
  static const Duration _draw = Duration(milliseconds: 1100);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _draw,
    // A run opened from the log starts finished, so there is nothing to skip.
    value: widget.animate ? 0 : 1,
  );

  late final Animation<double> _reveal = CurvedAnimation(
    parent: _controller,
    // Out rather than in-out: the line should set off at once and ease into the
    // finish, which is the shape of arriving somewhere rather than of a machine
    // moving a slider.
    curve: Curves.easeOutCubic,
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || !widget.animate) return;
    _started = true;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.value = 1;
      return;
    }
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _reveal,
      builder: (context, _) => RouteMap(
        points: widget.points,
        splitMarkers: widget.markers,
        reveal: _reveal.value,
      ),
    );
  }
}
