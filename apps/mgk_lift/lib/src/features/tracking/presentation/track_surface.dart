import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';

import '../../../core/brand.dart';
import '../../planning/domain/standing_plan.dart';
import '../../stats/domain/training_stats.dart';
import '../../sync/presentation/backup_messages.dart';
import '../../sync/presentation/backup_scheduler.dart';
import '../domain/session.dart';

/// **Track** — the front page, and the part that has to work in a basement.
///
/// This is the surface a lifter opens standing at a rack. Everything here is
/// offline-first: the on-device database owns a session in progress, and
/// Supabase is backup and cross-device store, never the source of truth for a
/// set being logged right now. A gym with no signal is the normal case, not the
/// edge case.
///
/// **Rebuilt 2026-10-01 as a front page** (docs/lift-2.0.0-track.md, TR1 to
/// TR7), on the layout Run's Home uses. The version before it led with a
/// photograph, one big number and a pill anchored at the foot; this one is a
/// greeting and three cards over a quiet backdrop:
///
/// - **Today**, which says what today is and carries the button that acts on
///   it (TR1, TR2);
/// - **This week**, which shows when the lifter trained, not how much (TR4);
/// - **Last session**, with how long it took (TR6).
///
/// The saved workouts are not here any more (TR3): *Start a session* opens
/// them.
class TrackSurface extends StatelessWidget {
  const TrackSurface({
    super.key,
    this.onStartSession,
    this.onOpenLibrary,
    this.openSession,
    this.log = const <Session>[],
    this.plan,
    this.today,
    this.onStartPlanned,
    this.movedDay,
    this.onOpenSession,
    this.onOpenPlan,
    this.backup,
    this.onBackupAction,
  });

  /// Where backup stands. A notice appears **only when something needs the
  /// lifter** — see [trackBackupMessage]; null or all well shows nothing.
  final BackupStatus? backup;

  /// What the notice's action does — retry, sign in, or review in Settings.
  final ValueChanged<BackupAction>? onBackupAction;

  /// Resumes the open session, and starts a blank one in a build with no
  /// library to choose from. Null while the recorder is not wired up, which
  /// reads as an unavailable action rather than an error.
  final VoidCallback? onStartSession;

  /// Opens *Your workouts*, which is what *Start a session* does (TR2): a
  /// saved workout or a blank session is one more tap from there. Null is a
  /// build with no on-device database, and the button starts a blank session
  /// instead.
  final VoidCallback? onOpenLibrary;

  /// The open session — usually because the app was killed mid-workout. The
  /// one state where the lifter has genuinely lost their place, so the card
  /// says what they were doing, not only that something is open.
  final Session? openSession;

  /// Finished sessions, for the week and the last one.
  final List<Session> log;

  /// The live block, when there is one. Null is the free tier's honest state,
  /// not a degraded one.
  final StandingPlan? plan;

  /// Injected so "what is today" is testable without waiting for Thursday.
  final DateTime? today;

  /// Starts a planned session, given the day of the split it is.
  final ValueChanged<String>? onStartPlanned;

  /// Another day's session, brought forward to today from Plan (R8, *Do it
  /// today*). It takes today's place on this screen, and says where it came
  /// from.
  final String? movedDay;

  /// Opens a finished session's own page, from *Last session*.
  final ValueChanged<Session>? onOpenSession;

  /// Opens the Plan tab, from *This week*. Only used when there is a plan to
  /// open onto: sending somebody without one to the tab that sells it, from a
  /// card about their own week, would be an advert dressed as a fact.
  final VoidCallback? onOpenPlan;

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

  @override
  Widget build(BuildContext context) {
    final status = backup;
    final notice = status == null ? null : trackBackupMessage(status);
    final now = _now;

    final finished = <Session>[
      for (final s in log)
        if (!s.isInProgress) s,
    ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final last = finished.isEmpty ? null : finished.first;
    final day = _TodayState.of(
      now: now,
      open: openSession,
      plan: plan,
      plannedDay: _todays,
      movedDay: movedDay,
      finished: finished,
    );

    return PhotoBackdrop(
      image: 'assets/images/backgrounds/hero_track.webp',
      // Texture, not subject (TR7). The same strength Run's Home sets its
      // photograph at, and `balanced` for the same reason: the content starts
      // at the top and scrolls, so the photo breathes through the middle.
      opacity: 0.32,
      alignment: Alignment.topCenter,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
            // The nav bar and the coach's mark float over this tab. The shell
            // says how much room they take (as the bottom padding); the
            // device's own inset is under that.
            AppSpacing.lg * 2 +
                MediaQuery.paddingOf(context).bottom +
                MediaQuery.viewPaddingOf(context).bottom,
          ),
          children: <Widget>[
            Entrance(child: _Header(now: now)),
            if (notice != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: _BackupNotice(message: notice, onAction: onBackupAction),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),

            // Today leads, because it is the question the app is opened to
            // answer, and it carries the action as well as the answer.
            Entrance(
              index: 1,
              child: _TodayCard(
                now: now,
                state: day,
                onResume: onStartSession,
                // With no library there is nothing to pick from, so starting
                // is a blank session.
                onPick: onOpenLibrary ?? onStartSession,
                hasLibrary: onOpenLibrary != null,
                onStartPlanned: onStartPlanned,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Entrance(
              index: 2,
              child: _WeekCard(
                now: now,
                finished: finished,
                plan: plan,
                // The Today card has already said what is next on a rest day.
                showNext: day.kind != _TodayKind.rest,
                onOpenPlan: onOpenPlan,
              ),
            ),

            // Skipped when the card above is already showing this session: the
            // same session twice on one screen reads as a bug, however correct
            // both copies are.
            if (last == null || last.id != day.done?.id) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Entrance(
                index: 3,
                child: _LastSessionCard(session: last, onOpen: onOpenSession),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

const List<String> _weekdays = <String>[
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', //
  'Friday', 'Saturday', 'Sunday',
];

const List<String> _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// `18:30`, or `6:30pm` on a phone set to the twelve-hour clock. Short on
/// purpose: it has to fit under a day's letter in the week.
String _clock(BuildContext context, DateTime at) {
  final minutes = at.minute.toString().padLeft(2, '0');
  if (MediaQuery.alwaysUse24HourFormatOf(context)) {
    return '${at.hour.toString().padLeft(2, '0')}:$minutes';
  }
  final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
  return '$hour:$minutes${at.hour < 12 ? 'am' : 'pm'}';
}

/// `48m`, or `1h 02m`.
String _span(Duration d) {
  final minutes = d.inMinutes < 1 ? 1 : d.inMinutes;
  if (minutes < 60) return '${minutes}m';
  return '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
}

/// How long a finished session ran.
Duration _length(Session s) =>
    (s.endedAt ?? s.startedAt).difference(s.startedAt).abs();

String _count(int n, String one) => '$n ${n == 1 ? one : '${one}s'}';

/// The next day the plan trains on after [weekday], looking a week ahead.
({String day, int weekday})? _nextPlanned(StandingPlan plan, int weekday) {
  for (var step = 1; step <= 7; step++) {
    final candidate = (weekday - 1 + step) % 7 + 1;
    final i = plan.weekdays.indexOf(candidate);
    if (i >= 0 && i < plan.dayOrder.length) {
      return (day: plan.dayOrder[i], weekday: candidate);
    }
  }
  return null;
}

/// What today is, decided once so the headline and the button cannot disagree.
enum _TodayKind {
  /// A session is open. Resuming beats everything: a second start on top of
  /// one already running is a lie about what happens.
  open,

  /// The plan has a session today and it has not been done.
  planned,

  /// Trained already today.
  done,

  /// The plan has nothing today.
  rest,

  /// No plan, nothing today, but a log.
  free,

  /// Nothing logged, ever.
  first,
}

class _TodayState {
  const _TodayState._(
    this.kind, {
    this.open,
    this.plannedDay,
    this.movements = 0,
    this.movedFrom,
    this.done,
    this.next,
  });

  factory _TodayState.of({
    required DateTime now,
    required Session? open,
    required StandingPlan? plan,
    required String? plannedDay,
    required String? movedDay,
    required List<Session> finished,
  }) {
    if (open != null) return _TodayState._(_TodayKind.open, open: open);

    final todays = <Session>[
      for (final s in finished)
        if (_sameDay(s.startedAt, now)) s,
    ];

    if (plan != null && plannedDay != null) {
      // A planned session is named for its day, which is how it is recognised
      // as done.
      final planned = plannedDay.toLowerCase();
      for (final s in todays) {
        if (s.name.toLowerCase() == planned) {
          return _TodayState._(_TodayKind.done, done: s);
        }
      }
      String? movedFrom;
      if (plannedDay == movedDay) {
        final i = plan.dayOrder.indexOf(plannedDay);
        if (i >= 0 && i < plan.weekdays.length) {
          movedFrom = _weekdays[plan.weekdays[i] - 1];
        }
      }
      return _TodayState._(
        _TodayKind.planned,
        plannedDay: plannedDay,
        movements: plan.slots[plannedDay]?.length ?? 0,
        movedFrom: movedFrom,
      );
    }

    if (todays.isNotEmpty) {
      return _TodayState._(_TodayKind.done, done: todays.first);
    }
    if (plan != null) {
      return _TodayState._(
        _TodayKind.rest,
        next: _nextPlanned(plan, now.weekday),
      );
    }
    return _TodayState._(finished.isEmpty ? _TodayKind.first : _TodayKind.free);
  }

  final _TodayKind kind;
  final Session? open;
  final String? plannedDay;
  final int movements;

  /// `Thursday`, when today's planned day was brought forward.
  final String? movedFrom;

  /// The session today's card is showing as done.
  final Session? done;

  final ({String day, int weekday})? next;
}

/// The app's name, and a greeting. The date is on the Today card and the week
/// is in the tile under it, so nothing about where the lifter stands is missing
/// from here.
class _Header extends StatelessWidget {
  const _Header({required this.now});

  final DateTime now;

  static String _greeting(DateTime at) {
    if (at.hour < 12) return 'Morning';
    if (at.hour < 17) return 'Afternoon';
    return 'Evening';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          kAppName.toUpperCase(),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _greeting(now),
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.05,
          ),
        ),
      ],
    );
  }
}

/// Today: what it is, and the button that acts on it (TR1). One object, so the
/// answer and the action cannot drift apart the way a headline and a pill at
/// opposite ends of the screen could.
class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.now,
    required this.state,
    required this.onResume,
    required this.onPick,
    required this.hasLibrary,
    required this.onStartPlanned,
  });

  final DateTime now;
  final _TodayState state;

  /// Whether [onPick] opens *Your workouts*, or has only a blank session to
  /// offer.
  final bool hasLibrary;

  /// Back into the open session.
  final VoidCallback? onResume;

  /// To *Your workouts*, to choose what to start.
  final VoidCallback? onPick;

  final ValueChanged<String>? onStartPlanned;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (headline, line) = _words(context);
    final planned = state.plannedDay;

    return GlassSurface(
      padding: const EdgeInsets.all(AppSpacing.xl),
      tintOpacity: 0.12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Stretched: glass sizes to its content, and this is the width of
          // the page whatever it says.
          const SizedBox(width: double.infinity),
          SectionLabel(
            'Today · ${_weekdays[now.weekday - 1]} ${now.day} '
            '${_months[now.month - 1]}',
            emphasis: LabelEmphasis.stat,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            headline,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            line,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          switch (state.kind) {
            _TodayKind.open => _StartButton(
              label: 'Resume session',
              onTap: onResume,
            ),
            _TodayKind.planned => _StartButton(
              // The day's name, not "today's session": the card has already
              // said it is today.
              label: 'Start ${planned!.toLowerCase()}',
              onTap: onStartPlanned == null
                  ? null
                  : () => onStartPlanned!(planned),
            ),
            _TodayKind.done => _StartButton(
              label: 'Start another session',
              onTap: onPick,
            ),
            // A rest day is an answer, so nothing here pushes a session. One
            // is still a tap away, offered rather than encouraged.
            _TodayKind.rest => _SecondaryAction(
              label: 'Start a session anyway',
              onPressed: onPick,
            ),
            _TodayKind.free || _TodayKind.first => _StartButton(
              label: 'Start a session',
              onTap: onPick,
            ),
          },
          // On a planned day the button starts the plan, so starting
          // something else is under it, quietly: offered, not pushed.
          if (state.kind == _TodayKind.planned && onPick != null) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            _SecondaryAction(label: 'Start something else', onPressed: onPick),
          ],
        ],
      ),
    );
  }

  /// The headline and the line under it.
  (String, String) _words(BuildContext context) {
    switch (state.kind) {
      case _TodayKind.open:
        final open = state.open!;
        final sets = open.completedSets;
        final movements = open.exercises.length;
        final today = _sameDay(open.startedAt, now);
        return (
          open.name,
          <String>[
            // The app knowing something the lifter has forgotten, and saying
            // so: a session a day old is still theirs to finish.
            if (!today) 'Left open ${_ago(open.startedAt, now)}',
            if (sets > 0) '${_count(sets, 'set')} in',
            if (movements > 0) _count(movements, 'movement'),
            if (today) 'started ${_clock(context, open.startedAt)}',
          ].join(' · '),
        );
      case _TodayKind.planned:
        return (
          state.plannedDay!,
          <String>[
            // A count and nothing more (TR5). The movements, with last time's
            // numbers, are one tap away inside the session.
            _count(state.movements, 'movement'),
            if (state.movedFrom != null) 'moved from ${state.movedFrom}',
          ].join(' · '),
        );
      case _TodayKind.done:
        final done = state.done!;
        return (
          done.name,
          <String>[
            'Done at ${_clock(context, done.endedAt ?? done.startedAt)}',
            _span(_length(done)),
            _count(done.completedSets, 'set'),
          ].join(' · '),
        );
      case _TodayKind.rest:
        final next = state.next;
        return (
          'Rest day',
          next == null
              ? 'Nothing owed today.'
              : 'Next: ${next.day} on ${_weekdays[next.weekday - 1]}.',
        );
      case _TodayKind.free:
        return (
          'No session yet today',
          hasLibrary
              ? 'Pick a workout, or start blank.'
              : 'Add movements as you go.',
        );
      case _TodayKind.first:
        return (
          'Ready when you are',
          'Log a session set by set. It works with no signal and backs up '
              'when you are back.',
        );
    }
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

/// The one physical action on Track: start, or resume.
///
/// The shape Run's Home uses for *Record a run*: a silver slab the width of
/// the card, inside the card that says what it starts. Lift's own copy, since
/// sharing it means editing Run (docs/lift-2.0.0-track.md, *Left for later*).
class _StartButton extends StatelessWidget {
  const _StartButton({required this.label, required this.onTap});

  final String label;

  /// Null draws it unavailable: a build with no recorder.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      // The same acknowledgement every other control gives (principle 9).
      child: PressScale(
        enabled: onTap != null,
        child: Material(
          color: AppColors.primary,
          borderRadius: AppRadius.cardAll,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Icon(
                    Icons.play_arrow_rounded,
                    color: AppColors.onPrimary,
                    size: 24,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppColors.onPrimary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The second thing the card can do. Outlined, so it reads as a control
/// without arguing with the start button above it.
class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppOutlinedButton(
      label: label,
      onPressed: onPressed,
      // As wide as the start button, so the two edges agree.
      expand: true,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.elevated),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardAll),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        textStyle: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// The week: which days, at what time, and how long in all (TR4).
///
/// **When, not how much.** Volume says nothing across a leg day and an arm
/// day; the hour a lifter was in the gym is the same kind of fact every day.
/// Streak, volume and the rest stay on Profile.
class _WeekCard extends StatelessWidget {
  const _WeekCard({
    required this.now,
    required this.finished,
    required this.plan,
    required this.showNext,
    required this.onOpenPlan,
  });

  final DateTime now;

  /// Finished sessions, newest first.
  final List<Session> finished;

  final StandingPlan? plan;
  final bool showNext;
  final VoidCallback? onOpenPlan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monday = TrainingStats.startOfWeek(now);
    final week = <Session>[
      for (final s in finished)
        if (!TrainingStats.startOfWeek(s.startedAt).isBefore(monday)) s,
    ];
    final time = week.fold<Duration>(
      Duration.zero,
      (sum, s) => sum + _length(s),
    );
    final planned = plan?.weekdays.length;
    final next = plan == null || !showNext
        ? null
        : _nextPlanned(plan!, now.weekday);
    final opens = plan != null && onOpenPlan != null;

    return HomeTile(
      label: 'This week',
      onTap: opens ? onOpenPlan : null,
      trailing: opens
          ? const Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.textTertiary,
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              for (var weekday = 1; weekday <= 7; weekday++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: weekday == 7 ? 0 : AppSpacing.xs,
                    ),
                    child: _DayCell(
                      weekday: weekday,
                      // Oldest first, so the time shown is the day's first.
                      sessions: <Session>[
                        for (final s in week.reversed)
                          if (s.startedAt.weekday == weekday) s,
                      ],
                      planned: plan?.weekdays.contains(weekday) ?? false,
                      isToday: weekday == now.weekday,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: planned == null
                    ? StatBlock(
                        label: 'Sessions',
                        // A dash, not a zero. A week nothing has happened in
                        // has no count to report, and the strip above has
                        // already shown the days going by.
                        value: week.isEmpty ? '—' : '${week.length}',
                        valueColor: week.isEmpty
                            ? AppColors.textTertiary
                            : null,
                      )
                    : StatBlock(
                        label: 'Sessions',
                        // Zero is a fact here, because the plan gives it a
                        // denominator: "0 of 4" says there are four to do.
                        value: '${week.length} of $planned',
                      ),
              ),
              Expanded(
                child: StatBlock(
                  label: 'Time',
                  value: week.isEmpty ? '—' : _span(time),
                  valueColor: week.isEmpty ? AppColors.textTertiary : null,
                ),
              ),
            ],
          ),
          if (next != null) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Next · ${next.day} on ${_weekdays[next.weekday - 1]}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One day of the week: its letter, a dot for each session, and the time the
/// first one started. A ring is a day the plan trains on and nothing has been
/// logged for.
///
/// **A day without a session is a gap, not a cross.** Most days of most weeks
/// are that, by design, and a row of marks for them would turn a fact into a
/// scorecard.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.weekday,
    required this.sessions,
    required this.planned,
    required this.isToday,
  });

  final int weekday;
  final List<Session> sessions;
  final bool planned;
  final bool isToday;

  /// Two sessions in a day is two dots. Past three they stop being countable
  /// at this size, and nobody trains four times a day.
  static const int _maxDots = 3;

  @override
  Widget build(BuildContext context) {
    final name = _weekdays[weekday - 1];
    final ink = isToday ? AppColors.onPrimary : AppColors.textTertiary;
    final dot = isToday ? AppColors.onPrimary : AppColors.primary;
    final time = sessions.isEmpty
        ? null
        : _clock(context, sessions.first.startedAt);

    return Semantics(
      label: <String>[
        name,
        if (isToday) 'today',
        if (time != null)
          sessions.length == 1
              ? 'trained at $time'
              : '${sessions.length} sessions, the first at $time'
        else if (planned)
          'planned',
      ].join(', '),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: isToday ? AppColors.primary : Colors.transparent,
          borderRadius: AppRadius.chipAll,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              name.substring(0, 1),
              // Not scaled with the phone's text size: seven of these share
              // one row, and the day is in the label above for a reader.
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                color: ink,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              height: 10,
              child: sessions.isNotEmpty
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        for (
                          var i = 0;
                          i < sessions.length && i < _maxDots;
                          i++
                        )
                          Container(
                            width: 9,
                            height: 9,
                            margin: EdgeInsets.only(left: i == 0 ? 0 : 2),
                            decoration: BoxDecoration(
                              color: dot,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    )
                  : planned
                  ? Center(
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: ink, width: 1.5),
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              height: 12,
              child: time == null
                  ? null
                  // Scaled down rather than clipped: a twelve-hour time is
                  // wider than the cell on a narrow phone.
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Text(
                          time,
                          maxLines: 1,
                          softWrap: false,
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                            color: isToday
                                ? AppColors.onPrimary
                                : AppColors.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
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

/// The last session: what it was, when, and how long it took (TR6). The
/// lifter's own numbers, so none of it is gated.
class _LastSessionCard extends StatelessWidget {
  const _LastSessionCard({required this.session, required this.onOpen});

  final Session? session;
  final ValueChanged<Session>? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = session;
    final opens = last != null && onOpen != null;

    return HomeTile(
      label: 'Last session',
      onTap: opens ? () => onOpen!(last) : null,
      trailing: opens
          ? const Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.textTertiary,
            )
          : null,
      child: last == null
          ? Text(
              'Your latest session lands here, with how long it took.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  last.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${_weekdays[last.startedAt.weekday - 1].substring(0, 3)} '
                  '${last.startedAt.day} '
                  '${_months[last.startedAt.month - 1]}, '
                  '${_clock(context, last.startedAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // "Length", not "Time": the week above has a Time of its
                    // own, and that one is a total.
                    _Figure(label: 'Length', value: _span(_length(last))),
                    _Figure(label: 'Sets', value: '${last.completedSets}'),
                    _Figure(
                      label: 'Movements',
                      value: '${last.exercises.length}',
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

/// One figure in the row: label over value, sharing the width evenly.
class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.textTertiary,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// The one line backup gets on Track, when it needs the lifter: a workout the
/// server refused, a sign-in that lapsed, a failure with work waiting, or work
/// waiting with no connection. Above the Today card, and gone the moment the
/// thing it is about is resolved.
class _BackupNotice extends StatelessWidget {
  const _BackupNotice({required this.message, required this.onAction});

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
