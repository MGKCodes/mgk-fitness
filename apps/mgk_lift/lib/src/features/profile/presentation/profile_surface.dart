import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../../stats/domain/activity_window.dart';
import '../../stats/domain/training_stats.dart';
import '../../tracking/domain/session.dart';

/// **Profile** — the long view, and where settings live.
///
/// **Built as Run's profile is**, section for section, because the two apps
/// are one account and should not look like two (decided 4 October 2026, from
/// the two screen boards side by side): a title bar over the photograph, the
/// lifetime total leading in a card of its own, records, a table, the year,
/// and the log at the foot. What is Lift's is what fills them — volume where
/// Run has distance, the movements trained most where Run has typical times.
///
/// Everything here is a fold over the log rather than a stored counter. Nothing
/// to migrate, nothing to get out of step, and deleting a session corrects every
/// figure at once.
///
/// **An empty log does not empty the screen.** The real layout renders either
/// way, with dashes standing in for figures that have no value yet and one
/// sentence under the lifetime figures saying what will build there, as Run's
/// does. The labels are the point: they say what this becomes.
class ProfileSurface extends StatefulWidget {
  const ProfileSurface({
    super.key,
    this.log = const <Session>[],
    this.massUnit = MassUnit.kilograms,
    this.now,
    this.onOpenSettings,
    this.onOpenPhotos,
    this.onOpenSession,
    this.onOpenHistory,
    this.onOpenMovement,
  });

  /// Opens a movement's stats from the most-trained table, which is where its
  /// best lives. Null leaves the rows as text.
  final ValueChanged<String>? onOpenMovement;

  /// Opens a session from the log — to read it, edit it, delete it.
  final ValueChanged<Session>? onOpenSession;

  /// Every session, grouped by week (F16). Null hides *See all*.
  final VoidCallback? onOpenHistory;

  /// Finished sessions, newest first.
  final List<Session> log;

  /// What the lifter works in. Every figure here honours it, so Profile and
  /// the session screen cannot report the same training in two units.
  final MassUnit massUnit;

  /// Injected so a test can pin the clock: the streak and the year both have a
  /// today-shaped edge.
  final DateTime? now;

  final VoidCallback? onOpenSettings;

  /// Opens progress photos. Null hides the row rather than showing an inert
  /// one.
  final VoidCallback? onOpenPhotos;

  /// How many sessions the log at the foot shows before *See all*.
  ///
  /// Run lists every run here. Lift has a screen of its own for every session,
  /// grouped by week, so the foot shows the recent ones and hands over.
  static const int recent = 5;

  @override
  State<ProfileSurface> createState() => _ProfileSurfaceState();
}

class _ProfileSurfaceState extends State<ProfileSurface> {
  final ScrollController _scroll = ScrollController();
  double _offset = 0;

  /// How far the photograph may drift, as on Run's profile: a third of the
  /// scroll, and no further than this, so a long page never walks it off the
  /// top and leaves bare charcoal behind the cards.
  static const double _maxDrift = 120;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final next = _scroll.hasClients ? _scroll.offset : 0.0;
      if ((next - _offset).abs() > 0.5) setState(() => _offset = next);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clock = widget.now ?? DateTime.now();
    final finished = widget.log.where((s) => !s.isInProgress).toList();
    final stats = TrainingStats.from(widget.log, now: clock);
    final unit = widget.massUnit;
    final shown = finished.take(ProfileSurface.recent).toList();

    return Scaffold(
      body: PhotoBackdrop(
        image: 'assets/images/backgrounds/hero_profile.webp',
        scrim: ScrimStrength.grounded,
        alignment: Alignment.topCenter,
        offset: -(_offset / 3).clamp(0.0, _maxDrift),
        child: CustomScrollView(
          controller: _scroll,
          slivers: <Widget>[
            SliverAppBar(
              pinned: true,
              // A tab's root: there is nothing behind it to go back to, even
              // where it happens to be pushed, as the preview harness does.
              automaticallyImplyLeading: false,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              // Glass, as Run's: there is always something behind a pinned bar
              // here, the photograph at rest and the cards once moving.
              // `SizedBox.expand`, because a bare ColoredBox takes the smallest
              // size the flexible space allows, which is none.
              flexibleSpace: ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: const SizedBox.expand(
                    child: ColoredBox(color: Color(0x991A1A1A)),
                  ),
                ),
              ),
              title: const Text('Profile'),
              actions: <Widget>[
                if (widget.onOpenSettings != null)
                  AppIconButton(
                    icon: Icons.settings_outlined,
                    tooltip: 'Settings',
                    onPressed: widget.onOpenSettings,
                  ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.sm,
                AppSpacing.xl,
                0,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate(<Widget>[
                  Entrance(
                    child: _Lifetime(stats: stats, unit: unit),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Entrance(
                    index: 1,
                    child: _Records(sessions: finished, unit: unit),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Entrance(
                    index: 2,
                    child: _MostTrained(
                      rows: TrainingStats.byFrequency(widget.log).take(5),
                      onOpen: widget.onOpenMovement,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Entrance(
                    index: 3,
                    child: _year(widget.log, now: clock, unit: unit),
                  ),
                  if (widget.onOpenPhotos != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.xl),
                    Entrance(
                      index: 4,
                      child: _PhotosRow(onTap: widget.onOpenPhotos!),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  Entrance(
                    index: 5,
                    child: _LogHeader(
                      count: finished.length,
                      onSeeAll: widget.onOpenHistory,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (finished.isEmpty)
                    const Entrance(index: 6, child: _LogPlaceholder()),
                ]),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                // The nav bar and the coach's mark float over this tab. The
                // shell says how much room they take, as the bottom padding;
                // the device's own inset is under that.
                AppSpacing.lg * 2 +
                    MediaQuery.paddingOf(context).bottom +
                    MediaQuery.viewPaddingOf(context).bottom,
              ),
              sliver: SliverList.separated(
                itemCount: shown.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, i) => Entrance(
                  index: i + 6,
                  child: _SessionTile(
                    session: shown[i],
                    unit: unit,
                    onTap: widget.onOpenSession == null
                        ? null
                        : () => widget.onOpenSession!(shown[i]),
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

/// Lifetime totals, in Run's card: the volume counts up, because it is the
/// number the screen is about, and sessions, time and streak sit under it as
/// Run's runs, time and streak do.
///
/// **Before the first session this card is the empty state**, rather than being
/// swapped out for one: the four figures held open as dashes, a step back from
/// full strength, with the sentence that says what will build here underneath.
/// The unit rides on the dash, so `— kg` promises kilograms where a blank
/// promises nothing.
class _Lifetime extends StatelessWidget {
  const _Lifetime({required this.stats, required this.unit});

  final TrainingStats stats;
  final MassUnit unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final empty = stats.sessions == 0;
    final waiting = empty ? AppColors.textTertiary : null;
    final heroStyle = theme.textTheme.displayMedium?.copyWith(
      fontWeight: FontWeight.w700,
      height: 1,
      color: waiting,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionLabel('Lifetime', emphasis: LabelEmphasis.stat),
          const SizedBox(height: AppSpacing.xs),
          if (empty)
            Text('$_dash ${unit.suffix}', style: heroStyle)
          else
            CountUp(
              value: stats.totalVolume.inDisplayUnit(unit),
              format: (v) => compactVolume(v, unit),
              style: heroStyle,
            ),
          const SizedBox(height: AppSpacing.md),
          Row(
            // Labels on one line, as on Run's: centred columns drop an
            // eyebrow the moment one value shrinks to fit.
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: StatBlock(
                  label: 'Sessions',
                  value: empty ? _dash : '${stats.sessions}',
                  valueColor: waiting,
                ),
              ),
              Expanded(
                child: StatBlock(
                  label: 'Time',
                  value: empty ? _dash : stats.totalTime.totalHours,
                  valueColor: waiting,
                  shrinkToFit: true,
                ),
              ),
              Expanded(
                child: StatBlock(
                  label: 'Streak',
                  // A dash on a log that has sessions is a lapsed streak, not
                  // a placeholder, and keeps its full strength.
                  value: stats.currentWeekStreak <= 0
                      ? _dash
                      : '${stats.currentWeekStreak} wk',
                  valueColor: waiting,
                ),
              ),
            ],
          ),
          if (empty) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Log your first session and your totals, records and streak '
              'will build here.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tonnes past four figures. `47,500 kg` is a number you read; `47.5 t` is one
/// you take in. [value] is already in [unit].
///
/// Pounds get thousands separators instead: a short ton is 2,000 lb, and
/// nobody measures barbell volume in it.
String compactVolume(double value, MassUnit unit) {
  if (unit == MassUnit.pounds) {
    return value >= 10000
        ? '${_thousands(value.round())} ${unit.suffix}'
        : '${value.round()} ${unit.suffix}';
  }
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)} t';
  return '${value.round()} ${unit.suffix}';
}

String _thousands(int n) {
  final digits = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// Two bests, in Run's two tiles: the heaviest weight on any working set, and
/// the most load moved in one session. Run's are the longest run and the
/// fastest pace.
class _Records extends StatelessWidget {
  const _Records({required this.sessions, required this.unit});

  final List<Session> sessions;
  final MassUnit unit;

  @override
  Widget build(BuildContext context) {
    var heaviest = 0.0;
    var biggest = 0.0;
    for (final session in sessions) {
      biggest = math.max(biggest, session.volumeKg);
      for (final set in session.workingSets) {
        heaviest = math.max(heaviest, set.weightKg);
      }
    }
    final empty = heaviest == 0 && biggest == 0;
    final waiting = empty ? AppColors.textTertiary : null;
    String figure(double kg) =>
        kg == 0 ? _dash : Mass.kilograms(kg).label(unit);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionLabel('Records'),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: <Widget>[
            Expanded(
              child: AppCard(
                child: StatBlock(
                  label: 'Heaviest lift',
                  value: figure(heaviest),
                  valueColor: waiting,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: AppCard(
                child: StatBlock(
                  label: 'Biggest session',
                  value: figure(biggest),
                  valueColor: waiting,
                  shrinkToFit: true,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The movements trained most, as a table in one card: Run's *Typical*, with
/// the movement where Run has the distance and the number of sessions where Run
/// has the time.
class _MostTrained extends StatelessWidget {
  const _MostTrained({required this.rows, this.onOpen});

  final Iterable<ExerciseCount> rows;
  final ValueChanged<String>? onOpen;

  /// How many rows the table stands up before there is anything to put in
  /// them: enough to read as a table, not so many it becomes a page of dashes.
  static const int _ghostRows = 3;

  @override
  Widget build(BuildContext context) {
    final list = rows.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // The count needs a unit. A bare "3" beside a movement could be
        // sessions, sets or kilos.
        const Row(
          children: <Widget>[
            Expanded(
              child: SectionLabel('Most trained', emphasis: LabelEmphasis.stat),
            ),
            SectionLabel(
              'Sessions',
              emphasis: LabelEmphasis.stat,
              color: AppColors.textTertiary,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (list.isEmpty)
                for (var i = 0; i < _ghostRows; i++)
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : AppSpacing.md),
                    child: const _MovementRow(name: null, sessions: null),
                  )
              else
                for (final (i, row) in list.indexed)
                  Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : AppSpacing.md),
                    child: _MovementRow(
                      name: row.name,
                      sessions: row.sessions,
                      onTap: onOpen == null ? null : () => onOpen!(row.name),
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One row of the table: the movement as a label, as Run sets "5K", and the
/// count as its figure. A null name is a row held open before the first
/// session.
class _MovementRow extends StatelessWidget {
  const _MovementRow({required this.name, required this.sessions, this.onTap});

  final String? name;
  final int? sessions;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Expanded(
          child: SectionLabel(name ?? _dash, emphasis: LabelEmphasis.stat),
        ),
        Text(
          sessions == null ? _dash : '$sessions',
          style: theme.textTheme.titleMedium?.copyWith(
            color: sessions == null ? AppColors.textTertiary : null,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        if (onTap != null) ...<Widget>[
          const SizedBox(width: AppSpacing.xs),
          const Icon(
            Icons.chevron_right,
            size: 20,
            color: AppColors.textTertiary,
          ),
        ],
      ],
    );
    final tap = onTap;
    if (tap == null) return row;
    return Semantics(
      button: true,
      hint: 'Shows $name over time',
      onTap: tap,
      child: PressScale(
        haptic: false,
        onTap: tap,
        child: ColoredBox(color: Colors.transparent, child: row),
      ),
    );
  }
}

/// The year, drawn by the grid Run draws its year with. A day's figure is its
/// load, in the lifter's unit.
Widget _year(
  List<Session> log, {
  required DateTime now,
  required MassUnit unit,
}) {
  final window = ActivityWindow.from(log, now: now);
  final today = DateTime(now.year, now.month, now.day);
  final load = <DateTime, double>{};
  for (final session in log) {
    if (session.isInProgress) continue;
    final at = session.startedAt;
    final day = DateTime(at.year, at.month, at.day);
    load[day] = (load[day] ?? 0) + session.volumeKg;
  }
  var total = 0.0;
  final days = <ActivityYearDay>[
    for (final day in window.days)
      ActivityYearDay(
        date: day.date,
        active: day.isTrained,
        isFuture: day.isFuture,
        isToday: day.date == today,
        detail: day.isTrained
            ? (load[day.date] ?? 0) > 0
                  ? Mass.kilograms(load[day.date]!).label(unit)
                  : 'trained'
            : null,
      ),
  ];
  for (final day in days) {
    if (day.active) total += load[day.date] ?? 0;
  }
  final n = window.trainedDays;
  return ActivityYearGrid(
    weeks: <List<ActivityYearDay>>[
      for (var w = 0; w < window.weeks; w++)
        days.sublist(
          w * ActivityWindow.daysPerWeek,
          (w + 1) * ActivityWindow.daysPerWeek,
        ),
    ],
    summary: n == 0
        ? 'Every session you log shows up here.'
        : '$n ${n == 1 ? 'day' : 'days'} trained · '
              '${compactVolume(Mass.kilograms(total).inDisplayUnit(unit), unit)}',
    activeLabel: 'Trained',
    inactiveDetail: 'rest day',
  );
}

/// The way into progress photos. Lift's alone: Run has nothing like it.
class _PhotosRow extends StatelessWidget {
  const _PhotosRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.photo_camera_outlined,
            size: 20,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('Progress photos', style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  'One a week, same spot, same light',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right,
            size: 20,
            color: AppColors.textTertiary,
          ),
        ],
      ),
    );
  }
}

/// The heading over the log: the count and the order, as Run's, or the
/// section's name before there is anything to count. *See all* opens every
/// session, grouped by week.
class _LogHeader extends StatelessWidget {
  const _LogHeader({required this.count, this.onSeeAll});

  final int count;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        SectionLabel(switch (count) {
          0 => 'Your sessions',
          1 => '1 session',
          _ => '$count sessions',
        }),
        if (count > ProfileSurface.recent && onSeeAll != null)
          AppTextButton(
            label: 'See all',
            onPressed: onSeeAll,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              visualDensity: VisualDensity.compact,
            ),
          )
        else if (count > 0)
          Text(
            'Newest first',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
      ],
    );
  }
}

/// One session in the log, in Run's run tile: the name as the headline, and
/// the date, length, sets and load beneath.
class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session, required this.unit, this.onTap});

  final Session session;
  final MassUnit unit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sets = session.completedSets;
    final volume = session.volumeKg;
    final subtitle = <String>[
      _shortDate(session.startedAt),
      if (session.endedAt case final ended?)
        ended.difference(session.startedAt).hoursMinutesSeconds,
      '$sets set${sets == 1 ? '' : 's'}',
      if (volume > 0) Mass.kilograms(volume).label(unit),
    ].join('  ·  ');
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  session.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null)
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.textTertiary,
            ),
        ],
      ),
    );
  }
}

/// The shape a session takes in the log, before there is one: two rows, the
/// second quieter, so it reads as a list that carries on. Nothing to tap.
class _LogPlaceholder extends StatelessWidget {
  const _LogPlaceholder();

  static const List<double> _fade = <double>[1, 0.55];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: <Widget>[
        for (final (i, opacity) in _fade.indexed)
          Padding(
            padding: EdgeInsets.only(
              bottom: i == _fade.length - 1 ? 0 : AppSpacing.sm,
            ),
            child: Opacity(
              opacity: opacity,
              child: AppCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            _dash,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textTertiary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Date  ·  time  ·  sets  ·  load',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// An em dash, standing for "no value yet".
const String _dash = '—';

String _shortDate(DateTime d) {
  const months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]}';
}
