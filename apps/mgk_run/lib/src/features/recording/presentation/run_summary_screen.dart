import 'dart:async';

import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../../coaching/domain/plan_history.dart';
import '../../coaching/domain/prescribed_distance.dart' show raceName;
import '../../coaching/domain/race_finish.dart';
import '../../coaching/domain/run_note.dart';
import '../../coaching/domain/training_plan.dart';
import '../domain/best_effort.dart';
import '../domain/live_metrics.dart';
import '../domain/race_breakdown.dart';
import '../domain/run_point.dart';
import '../domain/run_race.dart';
import '../domain/run_summary.dart';
import '../domain/split_marker.dart';
import 'folded_splits.dart';
import 'race_parts.dart';
import 'race_sheet.dart';
import 'route_map.dart';

/// What saving a race did, so the screen can say so.
enum RaceSaveOutcome {
  /// The run's race was written.
  saved,

  /// It was written, and it was the race the active plan was aimed at, so the
  /// plan closed with it (ADR-0027, reached from the run rather than from
  /// Home's card).
  savedAndPlanFinished,
}

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
///
/// **A race is drawn differently, and that is the one branch on what the run
/// was** (ADR-0049). A training run leads with how far; a race was decided in
/// advance how far, so it leads with the time (the official one where the
/// runner gave it), then where it stands among their races, how it was run,
/// and the plan behind it. The splits fold away on both: twenty-two rows was
/// the bottom half of a half marathon's screen.
///
/// Stateful only for the race. Marking a run as one, or adding the chip time a
/// few hours later, redraws this screen in place rather than sending the
/// runner back to the log to open it again.
class RunSummaryScreen extends StatefulWidget {
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
    this.onSaveRace,
    this.racePlan,
    this.planFinished = false,
  });

  final RunSummary summary;

  /// Writes the run's race (marked, corrected, or cleared with null) and
  /// answers what happened, or null when it could not be saved. Null hides
  /// every way to mark a race: a summary of seeded data has no row to write.
  final Future<RaceSaveOutcome?> Function(RunRace? race)? onSaveRace;

  /// The plan that was aimed at this run's race day, if one was. Only drawn
  /// once the run is a race; without a plan the training section is absent.
  final LabelledPlan? racePlan;

  /// The plan behind this race closed on the way here (Home's card), so the
  /// training section says the Plan tab is now clear.
  final bool planFinished;

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
  State<RunSummaryScreen> createState() => _RunSummaryScreenState();
}

class _RunSummaryScreenState extends State<RunSummaryScreen> {
  /// The run as it stands now: the summary handed in, with whatever race the
  /// runner has marked on it since.
  late RunSummary _summary = widget.summary;

  /// The plan closed because this race was marked, which the training section
  /// says so the empty Plan tab is not a surprise.
  late bool _planFinished = widget.planFinished;

  RunSummary get summary => _summary;
  UnitSystem get unit => widget.unit;
  List<RunSummary> get history => widget.history;
  bool get justFinished => widget.justFinished;
  VoidCallback? get onDone => widget.onDone;
  VoidCallback? get onEdit => widget.onEdit;
  VoidCallback? get onAskCoach => widget.onAskCoach;

  /// Opens the race sheet and writes what the runner says.
  ///
  /// The screen changes only once the write has succeeded: a race shown as
  /// marked over a row that never took it would be the screen and the log
  /// disagreeing about the same run, which is the failure ADR-0023 exists for.
  Future<void> _editRace() async {
    final save = widget.onSaveRace;
    if (save == null) return;
    final answer = await RaceSheet.show(context, run: _summary, unit: unit);
    if (answer == null || !mounted) return;
    final outcome = await save(answer.race);
    if (!mounted) return;
    if (outcome == null) {
      AppToast.show(context, 'The race could not be saved. Try again.');
      return;
    }
    unawaited(AppHaptics.commit());
    setState(() {
      _summary = _summary.withRace(answer.race);
      if (outcome == RaceSaveOutcome.savedAndPlanFinished) {
        _planFinished = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final race = summary.race;
    if (race != null) return _buildRace(context, race);
    final theme = Theme.of(context);
    final note = RunNote.forRun(
      summary,
      history: history,
      planned: widget.plannedSession,
      unit: unit,
    );
    final offer = widget.onSaveRace == null
        ? null
        : suggestedRaceDistance(summary);
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
                // A record set, said once, above the numbers that contain it.
                //
                // The screen already had everything needed to know: the run
                // carries its own best efforts, and `history` is the log to
                // measure them against. Not saying it meant a runner could set
                // their fastest 10K and find out by opening a different tab.
                if (_records().isNotEmpty) ...<Widget>[
                  Entrance(index: 1, child: _RecordBanner(records: _records())),
                  const SizedBox(height: 16),
                ],
                Entrance(index: 2, child: _StatGrid(tiles: _tiles())),
                // Under the numbers, where a runner who has just finished a
                // half marathon is already looking, and only on a run that is
                // near a race distance, so it is not on every Tuesday.
                if (offer != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  Entrance(
                    index: 2,
                    child: RaceOffer(
                      label: raceLabel(offer, unit),
                      onTap: () => unawaited(_editRace()),
                    ),
                  ),
                ],
                // What is written on the run, under the numbers it is about.
                //
                // It was only ever in Edit › Notes, so a run the app finished
                // itself after being killed carried "Recovered automatically"
                // where nobody reading the run would see it (board F7, test
                // sheet C21), and a runner's own note was as hidden.
                if (_writtenNote case final written?) ...<Widget>[
                  const SizedBox(height: AppSpacing.xl),
                  Entrance(index: 2, child: _WrittenNote(text: written)),
                ],
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
                    child: _CoachBlock(
                      headline: note?.headline,
                      detail: note?.detail,
                      onAsk: onAskCoach,
                    ),
                  ),
                ],
                if (summary.splits.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 32),
                  Entrance(
                    index: 3,
                    child: FoldedSplits(splits: summary.splits, unit: unit),
                  ),
                ],
                // Any run can be marked, not only one near a named distance:
                // a 15 km race or a 10-miler is still a race. Quiet and at the
                // foot, because on most runs it is the wrong question.
                if (offer == null &&
                    widget.onSaveRace != null &&
                    summary.type != 'treadmill') ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AppTextButton(
                      label: 'Mark as a race',
                      icon: Icons.flag_outlined,
                      onPressed: () => unawaited(_editRace()),
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

  /// The race layout: the time first, then what it means, how it was run, the
  /// plan behind it, and the run's own figures underneath.
  ///
  /// **The order is the order a runner asks the questions in** after a race:
  /// what was my time, is that good, where did it go right or wrong, what got
  /// me here. The measures a training run leads with (distance, pace) are
  /// answered by the headline already, so the grid below keeps only what the
  /// headline does not say.
  Widget _buildRace(BuildContext context, RunRace race) {
    final theme = Theme.of(context);
    final breakdown = raceBreakdownFor(summary.splits, race.distanceMeters);
    final standing = raceStandingFor(summary, history, unit: unit);
    final records = recordsInsideRace(_records(), race);
    final raceNote = breakdown == null
        ? null
        : raceNoteFor(breakdown, unit: unit);
    // Without a breakdown (no splits, or a recording too far from the course
    // to measure against), the run's own note is still true and still said.
    final runNote = raceNote == null
        ? RunNote.forRun(summary, history: history, unit: unit)
        : null;
    final plan = widget.racePlan;
    final tiles = _tiles(forRace: true);

    final headline = _RaceHeadline(
      summary: summary,
      race: race,
      unit: unit,
      theme: theme,
      justFinished: justFinished,
    );

    return Scaffold(
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.bg,
            title: Text(justFinished ? 'Race complete' : 'Race summary'),
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
                      markers: splitMarkersFor(summary.points),
                      animate: justFinished,
                    ),
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
                        child: headline,
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
                if (!summary.hasRoute) ...<Widget>[
                  Entrance(child: headline),
                  const SizedBox(height: 24),
                ],
                Entrance(
                  index: 1,
                  child: RaceTimeLine(
                    run: summary,
                    race: race,
                    unit: unit,
                    onEdit: widget.onSaveRace == null
                        ? null
                        : () => unawaited(_editRace()),
                  ),
                ),
                if (standing != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  Entrance(
                    index: 1,
                    child: RaceStandingCard(standing: standing),
                  ),
                ],
                if (records.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.md),
                  Entrance(index: 1, child: _RecordBanner(records: records)),
                ],
                if (breakdown != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.xxl),
                  Entrance(
                    index: 2,
                    child: RaceBreakdownCard(breakdown: breakdown, unit: unit),
                  ),
                ],
                if (raceNote != null ||
                    runNote != null ||
                    onAskCoach != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.xl),
                  Entrance(
                    index: 2,
                    child: _CoachBlock(
                      headline: raceNote?.headline ?? runNote?.headline,
                      detail: raceNote?.detail ?? runNote?.detail,
                      onAsk: onAskCoach,
                      askLabel: 'Ask your coach about this race',
                    ),
                  ),
                ],
                if (plan != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.xxl),
                  Entrance(
                    index: 3,
                    child: RaceBuildUpSection(
                      buildUp: buildUpFor(plan, history),
                      unit: unit,
                      planFinished: _planFinished,
                    ),
                  ),
                ],
                if (tiles.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.xxl),
                  Entrance(index: 3, child: _StatGrid(tiles: tiles)),
                ],
                if (_writtenNote case final written?) ...<Widget>[
                  const SizedBox(height: AppSpacing.xl),
                  Entrance(index: 3, child: _WrittenNote(text: written)),
                ],
                if (summary.splits.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 32),
                  Entrance(
                    index: 4,
                    child: FoldedSplits(splits: summary.splits, unit: unit),
                  ),
                ],
                if (onDone != null) ...<Widget>[
                  const SizedBox(height: 32),
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
  /// The distances this run set a personal best over.
  ///
  /// **Strictly faster than everything before it, and never on a tie.** A
  /// repeat of a time already held is not a new record, and saying it is
  /// devalues the banner the one time it matters.
  ///
  /// Compared against [history] rather than a stored best, because the log is
  /// what Profile reads a moment later and two sources would eventually
  /// disagree. A run sharing this one's id is skipped: the log usually already
  /// contains the run being shown, and a run cannot beat itself.
  List<BestEffort> _records() {
    if (summary.bestEfforts.isEmpty) return const <BestEffort>[];
    final others = <RunSummary>[
      for (final run in history)
        if (run.id == null || run.id != summary.id) run,
    ];
    return <BestEffort>[
      for (final effort in summary.bestEfforts)
        if (others.every(
          (run) => run.bestEfforts.every(
            (prior) =>
                prior.distanceMeters != effort.distanceMeters ||
                prior.duration > effort.duration,
          ),
        ))
          effort,
    ];
  }

  /// The run's note, trimmed; null when there is nothing written.
  String? get _writtenNote {
    final text = summary.notes?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  ///
  /// [forRace] drops time and pace, which a race's headline already gives
  /// over the course distance; the phone's versions of them are in the line
  /// under it, labelled as the phone's.
  List<_Tile> _tiles({bool forRace = false}) {
    final tiles = <_Tile>[
      if (!forRace) _Tile('TIME', summary.duration.hoursMinutesSeconds),
    ];
    final pace = forRace ? null : _avgPace();
    if (pace != null) tiles.add(_Tile('AVG PACE', pace.format(unit)));
    // **Two elevation figures, named apart.** A bare "ELEVATION" was
    // unambiguous while it was the only one; beside a high point it is not, and
    // 167 m of gain over a 111 m maximum is a pair of numbers that has to say
    // which is which. The in-run readout still says CLIMB, correctly: there is
    // only ever one elevation figure mid-run and nothing for it to be confused
    // with.
    if (summary.elevationGainMeters != null) {
      tiles.add(
        _Tile(
          'ELEVATION GAIN',
          Elevation.metres(summary.elevationGainMeters!).label(unit),
        ),
      );
    }
    if (summary.elevationMaxMeters != null) {
      tiles.add(
        _Tile(
          'MAX ELEVATION',
          Elevation.metres(summary.elevationMaxMeters!).label(unit),
        ),
      );
    }
    if (summary.steps != null) {
      tiles.add(_Tile('STEPS', _grouped(summary.steps!)));
      // **The sixth tile, and the one that closes the row.** Five tiles wrap to
      // 3 + 2 and leave a hole in the bottom right that reads as a measure that
      // failed to load rather than as the end of the list.
      //
      // Derived rather than sourced: cadence is steps over time, both of which
      // are already here, so it costs no permission the runner has not already
      // given and no field the recorder does not already write. It is the one
      // measure on this screen that says something about *how* the run was run
      // rather than how far or how high — two runners with the same 10 km and
      // the same pace can be forty steps a minute apart.
      //
      // Elapsed rather than moving time, because moving time is not recorded.
      // A long pause therefore drags it down; that is a real property of the
      // figure and the reason it is labelled AVG.
      final seconds = summary.duration.inSeconds;
      if (seconds > 0) {
        tiles.add(
          _Tile(
            'AVG CADENCE',
            '${(summary.steps! / (seconds / 60)).round()} spm',
          ),
        );
      }
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
  const _CoachBlock({
    required this.headline,
    required this.detail,
    required this.onAsk,
    this.askLabel = 'Ask your coach about this run',
  });

  /// Null when there is nothing true to say about this run, which is most
  /// runs. The card goes; the way in stays.
  final String? headline;
  final String? detail;
  final VoidCallback? onAsk;
  final String askLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final said = headline == null || detail == null
        ? null
        : (headline: headline!, detail: detail!);
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
              label: askLabel,
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

/// A race's headline: when and what, the time in large, and the race with its
/// pace over the course.
///
/// The time is the official one where the runner gave it and the phone's
/// otherwise, and the pace is over the race distance rather than the trace's,
/// so 2:00:30 over a half marathon reads 5:43 /km whatever the phone measured.
class _RaceHeadline extends StatelessWidget {
  const _RaceHeadline({
    required this.summary,
    required this.race,
    required this.unit,
    required this.theme,
    required this.justFinished,
  });

  final RunSummary summary;
  final RunRace race;
  final UnitSystem unit;
  final ThemeData theme;
  final bool justFinished;

  @override
  Widget build(BuildContext context) {
    final time = race.timeFor(summary.duration);
    final pace = Pace.secondsPerKilometer(
      time.inSeconds / (race.distanceMeters / 1000),
    ).format(unit);
    final when = justFinished ? 'Just now' : _formatDate(summary.startedAt);
    final style = theme.textTheme.displayMedium?.copyWith(
      fontWeight: FontWeight.w700,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '$when  ·  ${race.name ?? 'Race'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            color: AppColors.textSecondary,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        // Counts up on arrival, the way a training run's distance does: on a
        // race the time is the number that was earned.
        if (justFinished)
          CountUp(
            value: time.inSeconds.toDouble(),
            format: (s) => Duration(seconds: s.round()).hoursMinutesSeconds,
            style: style,
          )
        else
          Text(time.hoursMinutesSeconds, style: style),
        const SizedBox(height: 2),
        Text(
          '${raceLabel(race.distanceMeters, unit)}  ·  $pace',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
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

/// "Fastest 10K yet", on the screen where it happened.
///
/// One banner rather than a card per distance: a long run can set three at once
/// — 5K, 10K and half all fall inside a marathon — and three of these would bury
/// the run under its own confetti. Listed shortest first, which is the order
/// they were run through.
class _RecordBanner extends StatelessWidget {
  const _RecordBanner({required this.records});

  final List<BestEffort> records;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final named = <BestEffort>[
      for (final r in records)
        if (raceName(r.distanceMeters) != null) r,
    ];
    if (named.isEmpty) return const SizedBox.shrink();

    final names = <String>[for (final r in named) raceName(r.distanceMeters)!];
    final what = names.length == 1
        ? names.single
        : '${names.take(names.length - 1).join(', ')} and ${names.last}';

    final tabular = const <FontFeature>[FontFeature.tabularFigures()];
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Fastest $what yet',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            // States the rule rather than only the result. A record set
            // inside a longer run is otherwise surprising: somebody who ran
            // 12 km is not expecting to be told about a 10K.
            named.length == 1
                ? 'Your fastest unbroken stretch of it, in any run so far.'
                : 'Your fastest unbroken stretch of each, in any run so far.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // **Every record beside its own time.** This used to show only the
          // shortest one's time, at the end of a line naming all of them, so
          // "Fastest 5K, 10K and Half marathon yet · 25:16" read as a 25-minute
          // half marathon. One row each is a short table, and it is the only
          // way the time cannot be read against the wrong name.
          for (final r in named)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: <Widget>[
                  Text(
                    raceName(r.distanceMeters)!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    r.duration.hoursMinutesSeconds,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: tabular,
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

/// The note on a run, headed the way the splits are and set in the quieter
/// ink: it is about the run rather than a measure of it.
class _WrittenNote extends StatelessWidget {
  const _WrittenNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'NOTES',
          style: theme.textTheme.labelMedium?.copyWith(
            color: AppColors.textSecondary,
            letterSpacing: 3,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}
