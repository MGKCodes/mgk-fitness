import 'package:flutter/material.dart';
import 'package:mgk_units/mgk_units.dart';

import 'package:mgk_ui/mgk_ui.dart';

import '../../planning/domain/standing_plan.dart';
import '../../stats/domain/training_stats.dart';
import '../../sync/presentation/backup_messages.dart';
import '../../sync/presentation/backup_scheduler.dart';
import '../data/starters.dart';
import '../domain/session.dart';
import '../domain/workout_library.dart';
import '../domain/workout_template.dart';
import 'resume_or_discard.dart';

/// **Track** — the front page, and the part that has to work in a basement.
///
/// This is the surface a lifter opens standing at a rack. Everything here is
/// offline-first: the on-device database owns a session in progress, and
/// Supabase is backup and cross-device store, never the source of truth for a
/// set being logged right now. A gym with no signal is the normal case, not the
/// edge case.
///
/// **Rebuilt 2026-09-30 from the design review** (finding 2: "it doesn't work
/// as it is"). The references it drew on let a photograph carry the top of
/// the screen with the headline set on it, lead with one big number, and give
/// the screen one obvious action anchored low — and that is the shape now:
///
/// - the photograph, strong, fading into the charcoal (R1, [PhotoBackdrop.hero]);
/// - one number, sessions this week (R12, [HeroStatTile]);
/// - today's planned session with last time's numbers, or the open one;
/// - the saved workouts, each startable in one tap (findings 4 and 7);
/// - and the action pill, whose verb comes from the state, in the same row as
///   the coach's mark.
class TrackSurface extends StatelessWidget {
  const TrackSurface({
    super.key,
    this.onStartSession,
    this.openSession,
    this.log = const <Session>[],
    this.plan,
    this.unit = MassUnit.kilograms,
    this.today,
    this.onStartPlanned,
    this.workouts = const <SavedWorkout>[],
    this.onStartWorkout,
    this.onDiscardAndStart,
    this.onOpenLibrary,
    this.onAddStarter,
    this.movedDay,
    this.coachBeside = false,
    this.backup,
    this.onBackupAction,
  });

  /// Where backup stands. A pill appears **only when something needs the
  /// lifter** — see [trackBackupMessage]; null or all well shows nothing.
  final BackupStatus? backup;

  /// What the pill's action does — retry, sign in, or review in Settings.
  final ValueChanged<BackupAction>? onBackupAction;

  /// The lifter's saved workouts, newest first.
  final List<SavedWorkout> workouts;

  /// Starts a session from one, sets laid out. Null hides the Start buttons.
  final ValueChanged<SavedWorkout>? onStartWorkout;

  /// Throws away the open session and starts this one instead — the second
  /// answer to [askResumeOrDiscard]. Null leaves only Resume.
  final ValueChanged<SavedWorkout>? onDiscardAndStart;

  /// Opens the whole library. **Null hides the section** — a build with no
  /// on-device database.
  final VoidCallback? onOpenLibrary;

  /// Adds one of the three starting points (R11). Offered only while nothing
  /// is saved; null hides them.
  final ValueChanged<WorkoutSplit>? onAddStarter;

  /// Begins or resumes a session. Null while the recorder is not wired up,
  /// which reads as an unavailable action rather than an error.
  final VoidCallback? onStartSession;

  /// The open session — usually because the app was killed mid-workout. The
  /// one state where the lifter has genuinely lost their place, so the screen
  /// says what they were doing, not only that something is open.
  final Session? openSession;

  /// Finished sessions, for this week's count and the "last done" lines.
  final List<Session> log;

  /// The live block, when there is one. Null is the free tier's honest state,
  /// not a degraded one.
  final StandingPlan? plan;

  final MassUnit unit;

  /// Injected so "what is today" is testable without waiting for Thursday.
  final DateTime? today;

  /// Starts a planned session, given the day of the split it is.
  final ValueChanged<String>? onStartPlanned;

  /// Another day's session, brought forward to today from Plan (R8, *Do it
  /// today*). It takes today's place on this screen, and says where it came
  /// from.
  final String? movedDay;

  /// Whether the coach's mark sits at the foot of the screen, which the shell
  /// knows. The action pill stops short of it so the two share one row;
  /// without it, the pill takes the full width.
  final bool coachBeside;

  DateTime get _now => today ?? DateTime.now();

  /// The planned day that is today's, whether by the calendar or brought
  /// forward. A moved day beats the calendar: somebody chose it.
  String? get _todays {
    final p = plan;
    if (p == null) return null;
    final moved = movedDay;
    if (moved != null && p.dayOrder.contains(moved)) return moved;
    return p.dayFor(_now);
  }

  /// What the screen is about, in a few words. **It names the session rather
  /// than describing the state**, and reads the same state the pill does, so
  /// the two cannot disagree.
  String get _headline {
    final open = openSession;
    if (open != null) return '${open.name} is still open';
    final todays = _todays;
    if (todays != null) return 'Today is ${todays.toLowerCase()}';
    if (plan != null) return 'A rest day';
    return 'Ready when you are';
  }

  /// The second line, or null when the rest of the screen already says it.
  String? get _support {
    if (openSession != null) return null;
    if (plan != null) {
      return _todays == null
          ? 'Nothing owed today. Log something anyway if you feel like it.'
          : null;
    }
    return 'Log a session set by set. It works with no signal and backs up '
        'when you are back.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = backup;
    final pill = status == null ? null : trackBackupMessage(status);
    final size = MediaQuery.sizeOf(context);
    final support = _support;
    final todays = _todays;

    // Where the shell draws the coach's mark: its bottom edge sits this far up
    // (LiftShell positions it above the nav pill, off the device's own inset).
    // The action pill is centred on it, so the two read as one row.
    final inset = MediaQuery.viewPaddingOf(context).bottom;
    final markBottom = AppSpacing.lg + inset + kNavPillHeight + AppSpacing.md;
    final pillBottom = markBottom - (ActionPill.height - kCoachMarkSize) / 2;
    final pillRight = coachBeside
        ? AppSpacing.lg + kCoachMarkSize + AppSpacing.md
        : AppSpacing.xl;

    return _DriftingHero(
      builder: (scroll) => Stack(
        children: <Widget>[
          CustomScrollView(
            controller: scroll,
            slivers: <Widget>[
              SliverSafeArea(
                bottom: false,
                sliver: SliverPadding(
                  // Room at the foot for the pill floating over it.
                  padding: EdgeInsets.only(
                    top: AppSpacing.xxl,
                    bottom: pillBottom + ActionPill.height + AppSpacing.xl,
                  ),
                  sliver: SliverList.list(
                    children: <Widget>[
                      _Side(
                        Entrance(child: SectionLabel(_eyebrow(_now))),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _Side(
                        Entrance(
                          child: Text(
                            _headline,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              height: 1.1,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                      ),
                      if (support != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.sm),
                        _Side(
                          Entrance(
                            child: Text(
                              support,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (pill != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.md),
                        _Side(
                          _BackupPill(message: pill, onAction: onBackupAction),
                        ),
                      ],

                      // Air for the photograph: the tile lands over its lower
                      // part, the way the references set their figures over
                      // the picture rather than under it.
                      SizedBox(height: (size.height * 0.16).clamp(48, 180)),

                      // Absent beats zero (docs/design.md, principle 6): on day
                      // one there is no number. A nought there reads as a
                      // scoreboard somebody is already losing. Once there is
                      // any history, none this week is a fact worth showing.
                      if (log.any((Session s) => !s.isInProgress))
                        _Side(
                          Entrance(
                            index: 1,
                            child: _ThisWeek(log: log, plan: plan, now: _now),
                          ),
                        ),

                      if (openSession != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.md),
                        _Side(
                          Entrance(
                            index: 2,
                            child: _Interrupted(
                              session: openSession!,
                              now: _now,
                            ),
                          ),
                        ),
                      ] else if (todays != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.md),
                        _Side(
                          Entrance(
                            index: 2,
                            child: _TodaysSession(
                              plan: plan!,
                              day: todays,
                              movedFrom: todays == movedDay
                                  ? _usualWeekday(plan!, todays)
                                  : null,
                              unit: unit,
                            ),
                          ),
                        ),
                      ],

                      if (onOpenLibrary != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.xl),
                        Entrance(
                          index: 3,
                          child: _YourWorkouts(
                            workouts: workouts,
                            log: log,
                            onStart: onStartWorkout == null
                                ? null
                                : (w) => _start(context, w),
                            onOpenLibrary: onOpenLibrary!,
                            onAddStarter: onAddStarter,
                          ),
                        ),
                      ],

                      // On a planned day the pill starts the plan, so starting
                      // something else is here, quietly: offered, not pushed.
                      if (openSession == null &&
                          todays != null &&
                          onStartSession != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.sm),
                        Center(
                          child: AppTextButton(
                            label: 'Start something else',
                            onPressed: onStartSession,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          // What scrolls under the pill and the nav bar fades into the base
          // rather than peeking out between them — seen on the first capture,
          // where a card's Start button sat in the gap under the pill.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: pillBottom + ActionPill.height + AppSpacing.xxl,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      AppColors.bg.withValues(alpha: 0),
                      AppColors.bg.withValues(alpha: 0.94),
                      AppColors.bg,
                    ],
                    stops: const <double>[0, 0.3, 1],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: AppSpacing.xl,
            right: pillRight,
            bottom: pillBottom,
            child: Entrance(
              index: 4,
              child: _StartPill(
                plannedDay: todays,
                openSession: openSession,
                onStartSession: onStartSession,
                onStartPlanned: onStartPlanned,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A second Start with a session open asks first — the rule the preview
  /// sheet used to hold (finding 7).
  Future<void> _start(BuildContext context, SavedWorkout workout) async {
    final open = openSession;
    if (open == null) {
      onStartWorkout?.call(workout);
      return;
    }
    final choice = await askResumeOrDiscard(
      context,
      openName: open.name,
      wantedName: workout.name,
    );
    switch (choice) {
      case OpenSessionChoice.resume:
        onStartSession?.call();
      case OpenSessionChoice.discardAndStart:
        onDiscardAndStart?.call(workout);
      case null:
        break;
    }
  }
}

/// `WEDNESDAY 30 SEP` — the day, because "Today" above "Today is upper" said
/// the same word twice.
String _eyebrow(DateTime now) {
  const days = <String>[
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', //
    'Friday', 'Saturday', 'Sunday',
  ];
  return '${days[now.weekday - 1]} ${now.day} ${_months[now.month - 1]}';
}

const List<String> _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// The weekday a plan day normally falls on — `Thursday` for a Thursday
/// session brought forward — or null if the plan does not say.
String? _usualWeekday(StandingPlan plan, String day) {
  const names = <String>[
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', //
    'Friday', 'Saturday', 'Sunday',
  ];
  final i = plan.dayOrder.indexOf(day);
  if (i < 0 || i >= plan.weekdays.length) return null;
  return names[plan.weekdays[i] - 1];
}

/// The one number (R12): sessions this week, and "of 4" when a plan says how
/// many there should be. Streak and volume stay on Profile.
class _ThisWeek extends StatelessWidget {
  const _ThisWeek({required this.log, required this.plan, required this.now});

  final List<Session> log;
  final StandingPlan? plan;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final week = TrainingStats.startOfWeek(now);
    final done = log
        .where(
          (Session s) =>
              !s.isInProgress &&
              !TrainingStats.startOfWeek(s.startedAt).isBefore(week),
        )
        .length;
    final planned = plan?.weekdays.length;
    return HeroStatTile(
      label: 'This week',
      count: done.toDouble(),
      suffix: planned == null ? null : 'of $planned',
      caption: planned == null
          ? '${done == 1 ? 'session' : 'sessions'} since Monday'
          : 'planned sessions done since Monday',
    );
  }
}

/// Today's planned session: what it is, and what each movement was last time
/// (the review's finding 17 moves it here from Plan; O5 in the plan).
class _TodaysSession extends StatelessWidget {
  const _TodaysSession({
    required this.plan,
    required this.day,
    required this.movedFrom,
    required this.unit,
  });

  final StandingPlan plan;
  final String day;

  /// `Thursday`, when this day was brought forward to today.
  final String? movedFrom;

  final MassUnit unit;

  /// Enough to recognise the session; the rest is one tap away, inside it.
  static const int _shown = 5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final slots = plan.slots[day] ?? const <MovementSlot>[];
    final shown = slots.take(_shown).toList();
    final more = slots.length - shown.length;

    return GlassSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(width: double.infinity),
          Row(
            children: <Widget>[
              const Expanded(child: SectionLabel("Today's session")),
              Text(
                '${slots.length} ${slots.length == 1 ? 'movement' : 'movements'}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          if (movedFrom != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Moved from $movedFrom',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          for (final slot in shown) ...<Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Expanded(
                  child: Text(
                    slot.movement,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  _lastTime(slot, unit),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (more > 0)
            Text(
              '+ $more more',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
        ],
      ),
    );
  }

  /// `85 kg × 6`, or the prescription when there is no history yet.
  static String _lastTime(MovementSlot slot, MassUnit unit) {
    final kg = slot.lastTopKg;
    final reps = slot.lastTopReps;
    if (kg == null || reps == null) return '${slot.sets} × ${slot.reps}';
    return '${Mass.kilograms(kg).label(unit)} × $reps';
  }
}

/// One pill, three verbs, and the order matters. Resuming beats starting:
/// "Start a session" on top of one already running is a lie about what
/// happens. The planned session beats an empty one, because on a day the plan
/// has something, that is what starting is for — and something else is still
/// one tap away, under the workouts.
class _StartPill extends StatelessWidget {
  const _StartPill({
    required this.plannedDay,
    required this.openSession,
    required this.onStartSession,
    required this.onStartPlanned,
  });

  final String? plannedDay;
  final Session? openSession;
  final VoidCallback? onStartSession;
  final ValueChanged<String>? onStartPlanned;

  @override
  Widget build(BuildContext context) {
    final open = openSession;
    if (open != null) {
      return ActionPill(label: 'Resume ${open.name}', onPressed: onStartSession);
    }
    final day = plannedDay;
    if (day != null && onStartPlanned != null) {
      return ActionPill(
        label: "Start today's session",
        onPressed: () => onStartPlanned!(day),
      );
    }
    return ActionPill(label: 'Start a session', onPressed: onStartSession);
  }
}

/// The one line backup gets on Track, when it needs the lifter: a workout the
/// server refused, a sign-in that lapsed, a failure with work waiting, or work
/// waiting with no connection. Glass over the photograph, and gone the moment
/// the thing it is about is resolved.
class _BackupPill extends StatelessWidget {
  const _BackupPill({required this.message, required this.onAction});

  final BackupMessage message;
  final ValueChanged<BackupAction>? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (message.action) {
      BackupAction.retry => 'Retry',
      BackupAction.signIn => 'Sign in',
      BackupAction.review => 'Review',
      BackupAction.none => null,
    };
    return Entrance(
      child: GlassSurface(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          label == null ? AppSpacing.md : AppSpacing.xs,
          AppSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.cloud_off_outlined,
              size: 16,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Text(
                  message.text,
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (label != null && onAction != null)
              AppTextButton(
                label: label,
                onPressed: () => onAction!(message.action),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// **Your workouts**, each with its own Start (finding 7: the preview was one
/// step too many). Before anything is saved, the three starting points take
/// the row instead (R11).
class _YourWorkouts extends StatelessWidget {
  const _YourWorkouts({
    required this.workouts,
    required this.log,
    required this.onStart,
    required this.onOpenLibrary,
    required this.onAddStarter,
  });

  final List<SavedWorkout> workouts;
  final List<Session> log;
  final ValueChanged<SavedWorkout>? onStart;
  final VoidCallback onOpenLibrary;
  final ValueChanged<WorkoutSplit>? onAddStarter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final starters = workouts.isEmpty && onAddStarter != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _Side(
          Row(
            children: <Widget>[
              Expanded(
                child: SectionLabel(
                  starters ? 'Start from one of these' : 'Your workouts',
                ),
              ),
              if (!starters)
                AppTextButton(
                  label: 'See all',
                  onPressed: onOpenLibrary,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (workouts.isEmpty && !starters)
          _Side(
            Text(
              'Finish a session and save it as a workout, and it will be '
              'here to start in one tap.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          )
        else
          // The page's margin is on the scroll, not around it: the first card
          // lines up with everything above, and the row runs off the edge of
          // the screen — so a third card shows its edge instead of sitting out
          // of sight with nothing to say it is there.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (starters)
                  for (final (i, split) in starterSplits.indexed) ...<Widget>[
                    if (i > 0) const SizedBox(width: AppSpacing.md),
                    Entrance(
                      index: i,
                      child: _StarterCard(
                        split: split,
                        onAdd: () => onAddStarter!(split),
                      ),
                    ),
                  ]
                else
                  for (final (i, workout) in workouts.indexed) ...<Widget>[
                    if (i > 0) const SizedBox(width: AppSpacing.md),
                    Entrance(
                      index: i,
                      child: _WorkoutCard(
                        workout: workout,
                        lastDone: lastDone(workout.id, log),
                        onStart: onStart == null
                            ? null
                            : () => onStart!(workout),
                        onOpen: onOpenLibrary,
                      ),
                    ),
                  ],
              ],
            ),
          ),
      ],
    );
  }
}

/// A saved workout: what it is, when it was last done, and Start.
class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard({
    required this.workout,
    required this.lastDone,
    required this.onStart,
    required this.onOpen,
  });

  final SavedWorkout workout;
  final DateTime? lastDone;
  final VoidCallback? onStart;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 196,
      child: GlassSurface(
        onTap: onOpen,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              workout.name,
              style: theme.textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              '${workout.movementCount} '
              '${workout.movementCount == 1 ? 'movement' : 'movements'}'
              ' · ${workout.setCount} ${workout.setCount == 1 ? 'set' : 'sets'}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _lastDoneShort(lastDone),
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.textTertiary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.md),
            _SmallPill(label: 'Start', onPressed: onStart),
          ],
        ),
      ),
    );
  }

  static String _lastDoneShort(DateTime? at) {
    if (at == null) return 'Not done yet';
    return 'Last done ${at.day} ${_months[at.month - 1]}';
  }
}

/// One of the three starting points, with its photograph.
class _StarterCard extends StatelessWidget {
  const _StarterCard({required this.split, required this.onAdd});

  final WorkoutSplit split;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessions = templatesOf(split);
    return SizedBox(
      width: 196,
      child: GlassSurface(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              height: 96,
              width: double.infinity,
              child: ColorFiltered(
                colorFilter: const ColorFilter.matrix(<double>[
                  0.2126, 0.7152, 0.0722, 0, 0, //
                  0.2126, 0.7152, 0.0722, 0, 0, //
                  0.2126, 0.7152, 0.0722, 0, 0, //
                  0, 0, 0, 1, 0, //
                ]),
                child: Image.asset(
                  split.image,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const ColoredBox(color: AppColors.surface),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(split.name, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    '${split.daysPerWeek} days a week · '
                    '${sessions.length} '
                    '${sessions.length == 1 ? 'workout' : 'workouts'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _SmallPill(label: 'Add', onPressed: onAdd),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The card-sized action: a short silver pill, quieter than the page's own.
class _SmallPill extends StatelessWidget {
  const _SmallPill({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: PressScale(
        enabled: enabled,
        onTap: onPressed,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          decoration: BoxDecoration(
            color: enabled ? AppColors.primary : AppColors.elevated,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: enabled ? AppColors.onPrimary : AppColors.textTertiary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// The session they were in the middle of: what it was and how far in,
/// because "Session in progress" plus a button is the app knowing something
/// the lifter has forgotten and not telling them.
class _Interrupted extends StatelessWidget {
  const _Interrupted({required this.session, required this.now});

  final Session session;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sets = session.completedSets;
    final movements = session.exercises.length;

    return GlassSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(width: double.infinity),
          const SectionLabel('Where you were'),
          const SizedBox(height: AppSpacing.sm),
          Text(session.name, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            <String>[
              if (sets > 0) '$sets ${sets == 1 ? 'set' : 'sets'} in',
              if (movements > 0)
                '$movements ${movements == 1 ? 'movement' : 'movements'}',
              'started ${_ago(session.startedAt, now)}',
            ].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// A gap a person would say out loud.
String _ago(DateTime at, DateTime now) {
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(at.year, at.month, at.day)).inDays;
  if (days <= 0) return 'today';
  if (days == 1) return 'yesterday';
  if (days < 7) return '$days days ago';
  if (days < 14) return 'last week';
  return '${days ~/ 7} weeks ago';
}

/// The photograph, strong at the top and drifting behind the content as it
/// scrolls — the depth cue that says the cards are in front of it rather than
/// printed on it. Owns the scroll controller so the surface can stay
/// stateless.
class _DriftingHero extends StatefulWidget {
  const _DriftingHero({required this.builder});

  final Widget Function(ScrollController scroll) builder;

  @override
  State<_DriftingHero> createState() => _DriftingHeroState();
}

class _DriftingHeroState extends State<_DriftingHero> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = widget.builder(_scroll);
    return AnimatedBuilder(
      animation: _scroll,
      builder: (context, child) => PhotoBackdrop.hero(
        image: 'assets/images/backgrounds/hero_track.webp',
        offset:
            -((_scroll.hasClients ? _scroll.offset : 0).clamp(0, 400)) * 0.25,
        child: child,
      ),
      child: content,
    );
  }
}

/// The page's side margin — on each section rather than around the whole
/// column, so the workouts row can run to the screen's edge.
class _Side extends StatelessWidget {
  const _Side(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
    child: child,
  );
}
