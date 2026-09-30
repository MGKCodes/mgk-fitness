import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../../stats/domain/activity_window.dart';
import '../../stats/domain/training_stats.dart';
import '../../tracking/data/exercise_lookup.dart';
import '../../tracking/domain/exercise.dart';
import '../../tracking/domain/session.dart';
import 'year_activity_grid.dart';

/// **Profile** — the long view, and where settings live.
///
/// Three things share this surface, which is a consolidation rather than a
/// shortcut: the training log, the numbers, and settings. In Liftio these were
/// separate tabs, which spent a whole navigation slot on a screen people open
/// twice a year.
///
/// Everything here is a fold over the log rather than a stored counter. Nothing
/// to migrate, nothing to get out of step, and deleting a session corrects every
/// figure at once.
///
/// ## An empty log does not empty the screen
///
/// This used to swap the whole surface for a single "nothing logged yet" card,
/// so the one lifter who most needed to know what the app tracks — the one who
/// has not started — was the only one who could not see it. Now the real layout
/// renders either way, with dashes standing in for figures that have no value
/// yet, and one call to action at the top. The labels are the point: `VOLUME`,
/// `STREAK`, `MOST TRAINED` and a year of empty squares say what this becomes
/// far better than a sentence promising it.
class ProfileSurface extends StatelessWidget {
  const ProfileSurface({
    super.key,
    this.log = const <Session>[],
    this.massUnit = MassUnit.kilograms,
    this.now,
    this.lookup,
    this.onOpenSettings,
    this.onOpenTrack,
    this.onOpenPhotos,
    this.onOpenSession,
    this.onOpenHistory,
    this.onOpenMovement,
  });

  /// Opens a movement's stats (R9) from the most-trained list, which is where
  /// its best now lives. Null leaves the rows as text.
  final ValueChanged<String>? onOpenMovement;

  /// Opens a session from the recent list — to read it, edit it, delete it.
  final ValueChanged<Session>? onOpenSession;

  /// Every session, not the last five (F16). Null hides *See all*.
  final VoidCallback? onOpenHistory;

  /// Finished sessions, newest first.
  final List<Session> log;

  /// What the lifter works in. Every figure on this surface honours it, so
  /// Profile and the session screen cannot report the same training in two
  /// different units.
  final MassUnit massUnit;

  /// Injected so a test can pin the clock — a streak that reads `DateTime.now()`
  /// internally cannot be tested. The activity grid needs it for the same
  /// reason: its right-hand edge is today.
  final DateTime? now;

  final ExerciseLookup? lookup;
  final VoidCallback? onOpenSettings;

  /// Sends someone with an empty log back to the thing that fills it.
  final VoidCallback? onOpenTrack;

  /// Opens progress photos. Null hides the row rather than showing an inert
  /// one — the same rule the coach mark follows.
  final VoidCallback? onOpenPhotos;

  /// How many rows a section stands up before there is anything to put in them.
  ///
  /// Three rather than five: enough for the section to read as a list rather
  /// than as a single stray line, without turning the empty screen into a page
  /// of dashes.
  static const int _ghostRows = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clock = now ?? DateTime.now();
    final empty = log.isEmpty;

    final stats = TrainingStats.from(log, now: clock);
    final window = ActivityWindow.from(log, now: clock);
    final movements = TrainingStats.byFrequency(log);
    final frequent = movements.take(5).toList();
    final catalogue = lookup ?? ExerciseLookup();

    return PhotoBackdrop(
      image: 'assets/images/backgrounds/hero_profile.webp',
      scrim: ScrimStrength.quiet,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xxl * 2,
          ),
          children: <Widget>[
            // **An eyebrow and a headline, which is what every other surface
            // in the suite does.** This was a bare `SectionLabel('Profile')`,
            // the same component the sections below it use — so the screen's
            // title and its section headings rendered identically and the
            // surface had no hierarchy at all. Track has carried
            // eyebrow-plus-headline since it was written; Run's profile puts
            // its title in an app bar. This screen was the only one in either
            // app announcing itself in the same voice as its own subsections.
            //
            // Found by photographing the two apps side by side, which is also
            // how the last three layout faults here were found.
            Row(
              children: <Widget>[
                const Expanded(child: SectionLabel('Profile')),
                AppIconButton(
                  onPressed: onOpenSettings,
                  icon: Icons.settings_outlined,
                  color: AppColors.textSecondary,
                  tooltip: 'Settings',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              // Deliberately NOT stateful, unlike Track's. The first attempt
              // read "Nothing logged yet" on an empty log, which is already
              // what the card immediately below says — the screen announced
              // the same fact twice in two sizes, and a test that pins the
              // empty-state copy to one widget caught it. The card owns that
              // message; this is the title.
              'Your training',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.lg),

            // The one call to action, and only while it has a job. Everything
            // below it is the same layout a lifter with ten years of log sees.
            if (empty) ...<Widget>[
              _StartHere(onOpenTrack: onOpenTrack),
              const SizedBox(height: AppSpacing.xl),
            ],

            _HeadlineStats(
              stats: stats,
              massUnit: massUnit,
              placeholder: empty,
            ),

            // **What was done, before what it adds up to** (18). The last
            // five sessions were the last thing on the page, under the year
            // grid and the rankings; they are what somebody opens Profile to
            // look back at, so they come straight after the numbers.
            if (!empty) ...<Widget>[
              const SizedBox(height: AppSpacing.xl),
              _Contained(
                label: 'Previous workouts',
                action: onOpenHistory == null
                    ? null
                    : AppTextButton(
                        label: 'See all',
                        onPressed: onOpenHistory,
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                children: <Widget>[
                  for (final session in log.take(5))
                    _SessionRow(
                      session: session,
                      stats: stats,
                      massUnit: massUnit,
                      onTap: onOpenSession == null
                          ? null
                          : () => onOpenSession!(session),
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.xl),

            const SectionLabel('Last 52 weeks'),
            const SizedBox(height: AppSpacing.md),
            YearActivityGrid(window: window),
            const SizedBox(height: AppSpacing.xl),

            _Consistency(stats: stats, placeholder: empty),
            const SizedBox(height: AppSpacing.xl),

            Row(
              children: <Widget>[
                const Expanded(child: SectionLabel('Most trained')),
                // The count needs a unit. A bare "3" beside a movement name
                // could be sessions, sets or kilos; the same column-header
                // fix the set rows needed.
                const SectionLabel(
                  'Sessions',
                  emphasis: LabelEmphasis.stat,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            // `frequent`, not `empty`: a log of sessions that carry no
            // movements — an in-progress one, or a session finished before an
            // exercise was added — has nothing to rank either, and the header
            // standing over nothing is the gap this state exists to fill.
            if (frequent.isEmpty)
              for (var i = 0; i < _ghostRows; i++) const _GhostRow()
            else
              for (final row in frequent)
                _FrequencyRow(
                  onTap: onOpenMovement == null
                      ? null
                      : () => onOpenMovement!(row.name),
                  row: row,
                  catalogue: catalogue.find(row.name),
                  max: frequent.first.sessions,
                  // A bar is a comparison. When everything shown has the same
                  // count — which is the normal case for a short log, where
                  // every movement has been done once — every bar is full,
                  // and five identical full-width rules read as dividers
                  // rather than as data. Nothing to compare, so no bars.
                  showBars: frequent.first.sessions != frequent.last.sessions,
                ),

            if (onOpenPhotos != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xl),
              AppCard(
                onTap: onOpenPhotos,
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
                          Text(
                            'Progress photos',
                            style: theme.textTheme.titleSmall,
                          ),
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
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeadlineStats extends StatelessWidget {
  const _HeadlineStats({
    required this.stats,
    required this.massUnit,
    this.placeholder = false,
  });

  final TrainingStats stats;
  final MassUnit massUnit;

  /// Draws every figure as a dash.
  ///
  /// A dash rather than a zero. Six blocks reading `0` is a screen reporting
  /// six results, and a lifter who has not trained has not scored zero — they
  /// have not started. The dash says "no value yet" while the label above it
  /// still says what the value will be, which is the whole job of this state.
  final bool placeholder;

  @override
  Widget build(BuildContext context) {
    // Six tiles on glass (18), three to a row, rather than six figures on one
    // card: each number is its own thing to read, and the grid reads as one.
    final tiles = <Widget>[
      StatBlock(label: 'Sessions', value: _or('${stats.sessions}')),
      StatBlock(
        label: 'Volume',
        value: _or(compactVolume(stats.totalVolume, massUnit)),
        shrinkToFit: true,
      ),
      StatBlock(label: 'Sets', value: _or('${stats.totalSets}')),
      StatBlock(
        label: 'Time',
        value: _or(_compactDuration(stats.totalTime)),
        shrinkToFit: true,
      ),
      StatBlock(
        label: 'Per week',
        value: _or(stats.sessionsPerWeek.toStringAsFixed(1)),
      ),
      StatBlock(label: 'Streak', value: _or('${stats.currentWeekStreak}w')),
    ];
    Widget row(List<Widget> three) => Row(
      children: <Widget>[
        for (final (i, tile) in three.indexed) ...<Widget>[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: GlassSurface(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: tile,
            ),
          ),
        ],
      ],
    );
    return Column(
      children: <Widget>[
        row(tiles.sublist(0, 3)),
        const SizedBox(height: AppSpacing.sm),
        row(tiles.sublist(3)),
      ],
    );
  }

  String _or(String value) => placeholder ? _dash : value;

  /// Tonnes past four figures. `47,500 kg` is a number you read; `47.5 t` is one
  /// you take in.
  ///
  /// Follows the lifter's chosen unit, because Profile reporting kilograms
  /// while the session screen reports pounds is the same "two screens, two
  /// answers" fault the warm-up bug was.
  static String compactVolume(Mass m, MassUnit unit) {
    final value = m.inDisplayUnit(unit);
    // A short tonne is 2,000 lb, and nobody means that. Pounds get thousands
    // separators instead of a unit nobody uses for barbell volume.
    if (unit == MassUnit.pounds) {
      return value >= 10000
          ? '${_thousands(value.round())} ${unit.suffix}'
          : '${value.round()} ${unit.suffix}';
    }
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)} t';
    return '${value.round()} ${unit.suffix}';
  }

  static String _thousands(int n) {
    final digits = n.toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }

  static String _compactDuration(Duration d) {
    if (d.inHours >= 1) return '${d.inHours}h';
    return '${d.inMinutes}m';
  }
}

class _Consistency extends StatelessWidget {
  const _Consistency({required this.stats, this.placeholder = false});

  final TrainingStats stats;
  final bool placeholder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = stats.currentWeekStreak;
    final best = stats.longestWeekStreak;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionLabel('Consistency', emphasis: LabelEmphasis.stat),
          const SizedBox(height: AppSpacing.sm),
          Text(
            current == 0
                ? 'No streak running'
                : '$current week${current == 1 ? '' : 's'} in a row',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            current == 0
                ? 'Train this week to start one. A week counts from Monday.'
                : current >= best
                ? 'Your best run yet. A week counts from Monday.'
                : 'A week counts from Monday, so a Sunday session still '
                      'counts toward it.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // `longestWeekStreak` was computed on every build and shown nowhere.
          // It belongs beside the current one, because a streak number on its
          // own has no scale: three weeks is either the best a lifter has ever
          // managed or a quarter of it, and only the pair says which.
          Row(
            children: <Widget>[
              Expanded(
                child: StatBlock(
                  label: 'This run',
                  value: placeholder ? _dash : '${current}w',
                ),
              ),
              Expanded(
                child: StatBlock(
                  label: 'Longest',
                  value: placeholder ? _dash : '${best}w',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FrequencyRow extends StatelessWidget {
  const _FrequencyRow({
    required this.row,
    required this.catalogue,
    required this.max,
    required this.showBars,
    this.onTap,
  });

  /// Opens the movement's stats. Null leaves the row as text.
  final VoidCallback? onTap;

  final ExerciseCount row;
  final Exercise? catalogue;
  final int max;

  /// Whether there is anything to compare. See the call site.
  final bool showBars;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = max == 0 ? 0.0 : row.sessions / max;
    final content = Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  row.name,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${row.sessions}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
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
          ),
          if (showBars) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            // A bar rather than a chart library: one number relative to the top
            // one is all this says, and a dependency for that would be silly.
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 3,
                backgroundColor: AppColors.elevated,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
    final tap = onTap;
    if (tap == null) return content;
    return Semantics(
      button: true,
      hint: 'Shows ${row.name} over time',
      onTap: tap,
      child: PressScale(
        haptic: false,
        onTap: tap,
        child: ColoredBox(color: Colors.transparent, child: content),
      ),
    );
  }
}

/// A section in a card of its own: its label and an action on one line, then
/// its rows on glass. For the lists that should read as finished things on the
/// page rather than as text that runs into the next section (18, R9).
class _Contained extends StatelessWidget {
  const _Contained({required this.label, required this.children, this.action});

  final String label;
  final Widget? action;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: SectionLabel(label)),
              ?action,
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ...children,
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.session,
    required this.stats,
    required this.massUnit,
    this.onTap,
  });

  final Session session;
  final TrainingStats stats;
  final MassUnit massUnit;

  /// Opens the session. A session that could only be counted and never looked
  /// at again could not be fixed either.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final volume = Mass.kilograms(session.volumeKg);
    final row = Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(session.name, style: theme.textTheme.bodyMedium),
                Text(
                  <String>[
                    _shortDate(session.startedAt),
                    if (session.endedAt case final ended?)
                      _HeadlineStats._compactDuration(
                        ended.difference(session.startedAt),
                      ),
                    '${session.completedSets} '
                        'set${session.completedSets == 1 ? '' : 's'}',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            volume.kilograms == 0 ? _dash : volume.label(massUnit),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (onTap != null)
            const Padding(
              padding: EdgeInsets.only(left: AppSpacing.xs),
              child: Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.textTertiary,
              ),
            ),
        ],
      ),
    );
    if (onTap == null) return row;
    // The whole row, not just its words: a transparent fill is what makes the
    // gaps between them part of the target.
    return PressScale(
      onTap: onTap,
      scale: 0.98,
      child: ColoredBox(color: Colors.transparent, child: row),
    );
  }
}

/// A row with a real row's shape and dashes where its numbers go.
///
/// The alternative — leaving a section out until it has content — is what this
/// screen used to do, and it hid the answer to "what does this app track" from
/// the only person still asking.
class _GhostRow extends StatelessWidget {
  const _GhostRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = theme.textTheme.bodyMedium?.copyWith(
      color: AppColors.textTertiary,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(_dash, style: line)),
              Text(_dash, style: line),
            ],
          ),
        ],
      ),
    );
  }
}

/// The one thing to do on an empty Profile.
///
/// One button, at the top, and then the rest of the screen showing what filling
/// it produces. Two calls to action on a screen with no data is one too many —
/// there is only one next step, and it is the same one from every angle.
class _StartHere extends StatelessWidget {
  const _StartHere({this.onOpenTrack});

  final VoidCallback? onOpenTrack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Nothing logged yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Everything below fills in from your sessions — totals, streaks, '
            'what you train most and a year of squares.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (onOpenTrack != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            AppTextButton(label: 'Log a session', onPressed: onOpenTrack),
          ],
        ],
      ),
    );
  }
}

/// An em dash, standing for "no value yet".
///
/// One constant rather than a literal per call site, because this screen now
/// uses it in five places and a stray en dash among them would read as two
/// different states.
const String _dash = '—';

String _shortDate(DateTime d) {
  const months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]}';
}
