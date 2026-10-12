import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../../tracking/domain/exercise.dart';
import '../../tracking/domain/session.dart';
import '../../tracking/presentation/exercise_thumb.dart';
import '../domain/movement_history.dart';
import '../domain/working_weights.dart';

/// One movement, over everything the log holds of it (R9): its heaviest, what
/// to load for each rep range, how the estimate has moved, the sessions it
/// came from, and how it is done.
///
/// **No one-rep max on show** (#3). It led with *Est. 1RM*, a number nobody
/// loads, next to the heaviest weight they did — so it read as a best they had
/// set. The estimate now turns into working weights instead, and stays only as
/// the line over time, where it is labelled for what it is.
///
/// Reached by tapping a movement's name wherever one is shown — a session, its
/// summary, a past session from the history, and Profile's most trained. It
/// replaced Profile's list of bests, which showed five numbers and nothing
/// behind them: the question a best raises is "since when?", and the answer
/// needs a line, not a row.
class ExerciseStatsScreen extends StatelessWidget {
  const ExerciseStatsScreen({
    super.key,
    required this.name,
    required this.log,
    this.catalogue,
    this.massUnit = MassUnit.kilograms,
    this.onOpenSession,
    this.now,
  });

  final String name;

  /// The log to read it from. In-progress sessions are ignored.
  final List<Session> log;

  /// Its catalogue entry, for the illustrations and what it trains. Null for
  /// a movement the lifter typed, which has neither and loses nothing else.
  final Exercise? catalogue;

  final MassUnit massUnit;

  /// Opens a session from the list. Null leaves the rows as text.
  final ValueChanged<Session>? onOpenSession;

  /// Injected so a date's year, shown only when it is not this one, is
  /// testable.
  final DateTime? now;

  /// Pushes the screen over [context].
  static Future<void> open(
    BuildContext context, {
    required String name,
    required List<Session> log,
    Exercise? catalogue,
    MassUnit massUnit = MassUnit.kilograms,
    ValueChanged<Session>? onOpenSession,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ExerciseStatsScreen(
        name: name,
        log: log,
        catalogue: catalogue,
        massUnit: massUnit,
        onOpenSession: onOpenSession,
      ),
    ),
  );

  /// How many sessions the list shows. The line carries the rest.
  static const int _recent = 8;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final history = MovementHistory.of(log, name);
    final heaviest = history.heaviest;
    final points = history.estimates;
    final exercise = catalogue;
    final today = now ?? DateTime.now();
    final weights = WorkingWeights.of(
      log,
      name,
      now: today,
      unit: massUnit,
      kit: exercise?.category,
    );

    return Scaffold(
      backgroundColor: AppColors.bg,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        flexibleSpace: const GlassSurface.bar(child: SizedBox.expand()),
        leading: AppIconButton(
          icon: backIcon(context),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: PhotoBackdrop(
        image: 'assets/images/backgrounds/hero_home.webp',
        scrim: ScrimStrength.quiet,
        child: Builder(
          builder: (context) => ListView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              MediaQuery.paddingOf(context).top + AppSpacing.sm,
              AppSpacing.lg,
              MediaQuery.paddingOf(context).bottom + AppSpacing.xl,
            ),
            children: <Widget>[
              Text(name, style: theme.textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(
                exercise?.subtitle ?? 'Your own movement',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              if (history.sessions.isEmpty) ...<Widget>[
                Text(
                  'Nothing logged on this yet. Its history starts with the '
                  'first working set you tick.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
              ] else ...<Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _Tile(
                        label: 'Heaviest',
                        value: heaviest == null
                            ? '—'
                            : Mass.kilograms(heaviest.weightKg).label(massUnit),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _Tile(
                        label: 'Sessions',
                        value: '${history.sessions.length}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                // Hidden, not emptied, when nothing in the last six weeks
                // qualifies: an old best is not what somebody can load today.
                if (weights != null) ...<Widget>[
                  _Card(
                    label: 'Working weights',
                    children: <Widget>[
                      for (final band in weights.bands)
                        _BandRow(band: band, massUnit: massUnit),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        // The set behind the numbers, so they can be traced to
                        // a session the lifter remembers.
                        'A guide, not a target. Worked out from '
                        '${weights.from.weight.label(massUnit)} × '
                        '${weights.from.reps} on ${_date(weights.from.on, today)}, '
                        'your best set of the last six weeks, with a rep left '
                        'in the tank.'
                        '${weights.bands.any((b) => b.range.isRough) ? ' The ~ range is the roughest.' : ''}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],

                _Card(
                  label: 'Estimated 1RM over time',
                  children: <Widget>[
                    if (points.length < 2)
                      Text(
                        points.isEmpty
                            ? 'A line appears once a session has a working '
                                  'set of 12 reps or fewer with weight on it.'
                            : 'One session so far. The line starts with the '
                                  'next.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      )
                    else
                      _EstimateChart(
                        points: points,
                        massUnit: massUnit,
                        today: today,
                      ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      // Said where the number is, as Profile said it. It is
                      // the reason a lift somebody is proud of may not count.
                      'Estimated with Epley from each session\'s best working '
                      'set — not a tested max. Nothing over 12 reps counts, '
                      'because past that the formula is guessing.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                _Card(
                  label: 'Recent sessions',
                  children: <Widget>[
                    for (final s in history.sessions.take(_recent))
                      _SessionRow(
                        entry: s,
                        massUnit: massUnit,
                        today: today,
                        onTap: onOpenSession == null
                            ? null
                            : () => onOpenSession!(s.session),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
              ],

              if (exercise != null) ...<Widget>[
                _Card(
                  label: 'How it is done',
                  children: <Widget>[
                    LayoutBuilder(
                      builder: (context, box) {
                        final size = (box.maxWidth - AppSpacing.sm) / 2;
                        return Row(
                          children: <Widget>[
                            ExerciseThumb(
                              asset: exercise.startImage,
                              size: size,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            ExerciseThumb(asset: exercise.endImage, size: size),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => GlassSurface(
    padding: const EdgeInsets.all(AppSpacing.md),
    child: StatBlock(label: label, value: value, shrinkToFit: true),
  );
}

/// One rep range and what to load for it: `7–11 reps · 70–77.5 kg`.
class _BandRow extends StatelessWidget {
  const _BandRow({required this.band, required this.massUnit});

  final WeightBand band;
  final MassUnit massUnit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final range = band.range;
    final high = band.high.label(massUnit);
    final load = band.isSingle ? high : '${_amount(band.low, massUnit)}–$high';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '${range.min}–${range.max} reps',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Text(
            // Approximate where Epley is least sure, and said so on screen
            // rather than only in a footnote.
            range.isRough ? '~$load' : load,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  /// [Mass.label] without its unit, for the first number of a range, so it
  /// reads `70–77.5 kg` rather than `70 kg–77.5 kg`.
  static String _amount(Mass m, MassUnit unit) {
    final v = m.displayValue(unit);
    return v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
  }
}

/// A section on glass: its label, then its rows.
class _Card extends StatelessWidget {
  const _Card({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => GlassSurface(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.lg,
      AppSpacing.md,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionLabel(label),
        const SizedBox(height: AppSpacing.sm),
        ...children,
      ],
    ),
  );
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.entry,
    required this.massUnit,
    required this.today,
    this.onTap,
  });

  final MovementSession entry;
  final MassUnit massUnit;
  final DateTime today;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${_date(entry.on, today)} · ${entry.session.name}',
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  <String>[
                    for (final set in entry.sets) _setLabel(set, massUnit),
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // No estimate at the end of the row (#3): unlabelled, it read as a
          // weight lifted that day. The sets are the record; the line above
          // is where the estimate is drawn, and says what it is.
          if (onTap != null) ...<Widget>[
            const SizedBox(width: AppSpacing.xs),
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.textTertiary,
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return PressScale(
      haptic: false,
      onTap: onTap,
      child: ColoredBox(color: Colors.transparent, child: row),
    );
  }
}

/// The estimate, session by session: a line, not a library.
///
/// Drawn by hand for the reason Profile's bars are: one series against time
/// is all it says, and a chart dependency for that would be the heaviest thing
/// on the screen.
class _EstimateChart extends StatelessWidget {
  const _EstimateChart({
    required this.points,
    required this.massUnit,
    required this.today,
  });

  final List<({DateTime on, Mass estimate})> points;
  final MassUnit massUnit;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final values = <double>[for (final p in points) p.estimate.kilograms];
    final low = values.reduce(math.min);
    final high = values.reduce(math.max);
    final first = points.first;
    final last = points.last;
    final small = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.textTertiary,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );

    return Semantics(
      // What the line says, for anybody who cannot see it, as a stop of its
      // own rather than run into the card's heading.
      container: true,
      label:
          'Estimated one-rep max, ${first.estimate.label(massUnit)} on '
          '${_date(first.on, today)} to ${last.estimate.label(massUnit)} on '
          '${_date(last.on, today)}, over ${points.length} sessions.',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(Mass.kilograms(high).label(massUnit), style: small),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            height: 140,
            child: CustomPaint(
              painter: _LinePainter(values: values, low: low, high: high),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              Text(_date(first.on, today), style: small),
              const Spacer(),
              if (low != high) ...<Widget>[
                Text(
                  'low ${Mass.kilograms(low).label(massUnit)}',
                  style: small,
                ),
                const Spacer(),
              ],
              Text(_date(last.on, today), style: small),
            ],
          ),
        ],
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({required this.values, required this.low, required this.high});

  final List<double> values;
  final double low;
  final double high;

  @override
  void paint(Canvas canvas, Size size) {
    // A flat line sits in the middle rather than on the floor, where it would
    // read as a drop to nothing.
    final span = high - low;
    double y(double v) => span == 0
        ? size.height / 2
        : size.height - (v - low) / span * size.height;
    double x(int i) => values.length == 1
        ? size.width / 2
        : i / (values.length - 1) * size.width;

    final guide = Paint()
      ..color = AppColors.textTertiary.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    canvas
      ..drawLine(Offset.zero, Offset(size.width, 0), guide)
      ..drawLine(
        Offset(0, size.height),
        Offset(size.width, size.height),
        guide,
      );

    final path = Path()..moveTo(x(0), y(values.first));
    for (var i = 1; i < values.length; i++) {
      path.lineTo(x(i), y(values[i]));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    final dot = Paint()..color = AppColors.primary;
    for (var i = 0; i < values.length; i++) {
      canvas.drawCircle(Offset(x(i), y(values[i])), 3, dot);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.low != low || old.high != high || old.values != values;
}

/// As the summary says it: an unloaded set is its reps, since `0 kg × 9`
/// reads as a bug rather than as a pull-up.
String _setLabel(SessionSet set, MassUnit unit) => set.weightKg == 0
    ? '${set.reps} reps'
    : '${Mass.kilograms(set.weightKg).label(unit)} × ${set.reps}';

String _date(DateTime d, DateTime now) {
  const months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return d.year == now.year
      ? '${d.day} ${months[d.month - 1]}'
      : '${d.day} ${months[d.month - 1]} ${d.year}';
}
