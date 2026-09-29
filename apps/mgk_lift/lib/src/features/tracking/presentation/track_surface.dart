import 'package:flutter/material.dart';
import 'package:mgk_units/mgk_units.dart';

import 'package:mgk_ui/mgk_ui.dart';

import '../../planning/domain/standing_plan.dart';
import '../../stats/domain/training_stats.dart';
import '../domain/session.dart';
import '../domain/workout_library.dart';
import 'workout_preview_sheet.dart';

/// **Track** — the front page, and the part that has to work in a basement.
///
/// This is the surface a lifter opens standing at a rack. Everything here is
/// offline-first: the on-device database owns a session in progress, and
/// Supabase is backup and cross-device store, never the source of truth for a
/// set being logged right now. A gym with no signal is the normal case, not the
/// edge case.
///
/// That is the opposite posture to [PlanSurface], which needs a connection and
/// says so, and the split is deliberate — this app is AI-driven, but the
/// tracking underneath it is not allowed to depend on the AI being reachable.
class TrackSurface extends StatelessWidget {
  const TrackSurface({
    super.key,
    this.onStartSession,
    this.onOpenPlan,
    this.openSession,
    this.log = const <Session>[],
    this.plan,
    this.unit = MassUnit.kilograms,
    this.today,
    this.onStartPlanned,
    this.workouts = const <SavedWorkout>[],
    this.onStartWorkout,
    this.onOpenLibrary,
  });

  /// The lifter's saved workouts, newest first — the row under *Next up*.
  final List<SavedWorkout> workouts;

  /// Starts a session from one, sets laid out. Null hides the row's cards.
  final ValueChanged<SavedWorkout>? onStartWorkout;

  /// Opens the whole library. **Null hides the section** — a build with no
  /// on-device database.
  ///
  /// Your workouts used to be reachable only from inside an empty session,
  /// which meant starting the clock to browse them.
  final VoidCallback? onOpenLibrary;

  /// Begins or resumes a session. Null while the recorder is not wired up,
  /// which reads as an unavailable action rather than an error.
  final VoidCallback? onStartSession;

  final VoidCallback? onOpenPlan;

  /// The open session — usually because the app was killed mid-workout.
  ///
  /// There used to be a `hasOpenSession` bool alongside this, and the two were
  /// read by different parts of the screen: the headline switched on either,
  /// the card only on the session. Nothing could ever set them apart — the
  /// shell assigned `session != null` to one and `session` to the other in the
  /// same `setState` — but the screen was written as though they could, which
  /// left a branch where the headline announced an interrupted session above a
  /// card showing today's planned one.
  ///
  /// **A different button label was not enough.** An interrupted session is the
  /// one state where the lifter has genuinely lost their place, and the screen
  /// has to say what they were doing rather than only that they were doing
  /// something.
  final Session? openSession;

  /// Finished sessions, for the strip at the foot.
  ///
  /// Track is the screen people open most and it used to tell them nothing they
  /// did not already know. This is the fix, and it is deliberately small: three
  /// figures, not a dashboard.
  final List<Session> log;

  /// The live block, when there is one. Null keeps the free-tier copy, which is
  /// the honest state for most of the app's users and not a degraded one.
  final StandingPlan? plan;

  final MassUnit unit;

  /// Injected so "what is today" is testable without waiting for Thursday.
  final DateTime? today;

  /// Starts a planned session — with its movements AND its targets, which is
  /// the whole difference between a plan and a template.
  /// Starts today's session, given the day of the split it is.
  final ValueChanged<String>? onStartPlanned;

  /// What the screen is about, in three words.
  ///
  /// Reads the same state the card below does, so the two cannot disagree —
  /// which they did: "Ready when you are" sat above a card naming today's
  /// prescribed session.
  ///
  /// **It names the session rather than describing the state.** "Pick up where
  /// you were" sat directly above a card labelled `Where you were`, which is
  /// one thing said twice in the space of a screen — and the vaguer of the two
  /// was the larger. Every branch here now reads like the planned one does.
  String get _headline {
    final open = openSession;
    if (open != null) return '${open.name} is still open';
    final todays = plan?.dayFor(today ?? DateTime.now());
    if (todays != null) {
      return 'Today is ${todays.toLowerCase()}';
    }
    if (plan != null) return 'Nothing scheduled today';
    return 'Ready when you are';
  }

  /// The second line, or null when the card below already carries it.
  String? get _support {
    if (openSession != null) return null;
    if (plan != null) return null;
    return 'Start a session and log it set by set. It works with no signal '
        'and syncs when you are back.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PhotoBackdrop(
      image: 'assets/images/backgrounds/hero_home.webp',
      scrim: ScrimStrength.balanced,
      child: SafeArea(
        // Fills the screen and scrolls past it — the Spacer still pushes the
        // cards to the foot of a tall phone, and a short one can scroll to
        // reach them rather than overflow.
        child: CustomScrollView(
          slivers: <Widget>[
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.xxl,
                  AppSpacing.xl,
                  AppSpacing.xl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const SectionLabel('Today'),
                    const SizedBox(height: AppSpacing.md),
                    Text(_headline, style: theme.textTheme.headlineSmall),
                    // The supporting line is dropped whenever the card below says
                    // the same thing better. It used to run unconditionally, so an
                    // interrupted session was announced twice — vaguely and large at
                    // the top, then precisely and small underneath — and a planned
                    // session sat under free-tier copy about logging set by set.
                    if (_support != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _support!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    const Spacer(),

                    // The interrupted session takes the card when there is one: it is
                    // the most urgent thing on the screen, and what the plan wanted
                    // today is beside the point once you are already mid-workout.
                    if (openSession != null)
                      _Interrupted(
                        session: openSession!,
                        now: today ?? DateTime.now(),
                      )
                    else
                      _NextUp(
                        plan: plan,
                        unit: unit,
                        now: today ?? DateTime.now(),
                      ),

                    if (onOpenLibrary != null) ...<Widget>[
                      const SizedBox(height: AppSpacing.lg),
                      _YourWorkouts(
                        workouts: workouts,
                        log: log,
                        onStart: onStartWorkout,
                        onOpenLibrary: onOpenLibrary!,
                        blocked: openSession != null,
                      ),
                    ],

                    if (log.isNotEmpty) ...<Widget>[
                      const SizedBox(height: AppSpacing.md),
                      _RecentStrip(log: log, now: today ?? DateTime.now()),
                    ],

                    const SizedBox(height: AppSpacing.lg),
                    _StartButton(
                      plan: plan,
                      now: today ?? DateTime.now(),
                      openSession: openSession,
                      onStartSession: onStartSession,
                      onStartPlanned: onStartPlanned,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// **Your workouts**, one tap from Track: the saved ones as glass cards over
/// the photograph — glass has something behind it here — and a way into the
/// whole library.
///
/// A card opens the workout's preview; its Start begins a session with every
/// set laid out. With a session already open, the preview says to finish that
/// one first rather than starting a second over it.
class _YourWorkouts extends StatelessWidget {
  const _YourWorkouts({
    required this.workouts,
    required this.log,
    required this.onStart,
    required this.onOpenLibrary,
    required this.blocked,
  });

  final List<SavedWorkout> workouts;
  final List<Session> log;
  final ValueChanged<SavedWorkout>? onStart;
  final VoidCallback onOpenLibrary;

  /// A session is open, so nothing new can start.
  final bool blocked;

  Future<void> _preview(BuildContext context, SavedWorkout workout) async {
    final action = await WorkoutPreviewSheet.show(
      context,
      workout: workout,
      lastDone: lastDone(workout.id, log),
      blockedReason: blocked
          ? 'Finish or discard the session you have open first.'
          : null,
    );
    if (action == WorkoutAction.start) {
      onStart?.call(workout);
    } else if (action != null) {
      // Edit, duplicate and delete belong to the library, which has the list
      // they change; the preview here hands over to it.
      onOpenLibrary();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Expanded(
              child: SectionLabel(
                'Your workouts',
                emphasis: LabelEmphasis.stat,
              ),
            ),
            AppTextButton(
              label: workouts.isEmpty ? 'Add one' : 'See all',
              onPressed: onOpenLibrary,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        if (workouts.isEmpty)
          Text(
            'Save a session you liked, build one, or add a ready-made one — '
            'then start it from here in one tap.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          )
        else
          // As tall as the cards, not a fixed height: a fixed 104 overflowed
          // once the text was larger than the default. One line each, so every
          // card is the same three lines at whatever size the phone asks for.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final (i, workout) in workouts.indexed) ...<Widget>[
                  if (i > 0) const SizedBox(width: AppSpacing.sm),
                  Entrance(
                    index: i,
                    child: SizedBox(
                      width: 180,
                      child: PressScale(
                        onTap: () => _preview(context, workout),
                        child: GlassSurface(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                workout.name,
                                style: theme.textTheme.titleSmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _counts(workout),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                _lastDoneShort(lastDone(workout.id, log)),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: AppColors.textTertiary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  /// `2 movements · 7 sets` — and `1 movement`, not `1 movements`.
  static String _counts(SavedWorkout w) =>
      '${w.movementCount} ${w.movementCount == 1 ? 'movement' : 'movements'}'
      ' · ${w.setCount} ${w.setCount == 1 ? 'set' : 'sets'}';

  static String _lastDoneShort(DateTime? at) {
    if (at == null) return 'Not done yet';
    const months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return 'Last done ${at.day} ${months[at.month - 1]}';
  }
}

/// What the plan has for today — or, on a rest day, what is next.
///
/// "Nothing scheduled" was a placeholder for exactly this. With no plan it
/// still says that, because for a free lifter it is true and it is not a
/// failure: tracking works without a coach, and the card says so rather than
/// dangling a locked feature.
class _NextUp extends StatelessWidget {
  const _NextUp({required this.plan, required this.unit, required this.now});

  final StandingPlan? plan;
  final MassUnit unit;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = plan;
    final today = p?.dayFor(now);
    final movements = p == null ? const <MovementSlot>[] : p.movementsFor(now);

    // **No "block finished".** There is no end to reach, so the only states are
    // no plan, a training day, and a rest day -- and a rest day is an answer
    // rather than a gap.
    final (String title, String detail) = switch ((p, today)) {
      (null, _) => (
        'Nothing scheduled',
        'Your coach builds the plan. Until then, log whatever you are doing.',
      ),
      (_, final String day) => (
        day,
        // One per line, as on Plan. Middle-dot joined, this wrapped into a
        // dense block nobody reads standing up.
        movements.map((m) => m.movement).join(String.fromCharCode(10)),
      ),
      _ => (
        'Rest day',
        'Nothing owed. Log something anyway if you feel like it.',
      ),
    };

    return GlassSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(width: double.infinity),
          const SectionLabel('Next up', emphasis: LabelEmphasis.stat),
          const SizedBox(height: AppSpacing.sm),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            detail,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// One button, three meanings, and the order matters.
///
/// Resuming beats starting: "Start a session" on top of one already running is
/// a lie about what happens. Starting the planned session beats starting an
/// empty one, because on a day the plan has something, that is what "start" is
/// for — and a lifter who wants something else can still add whatever they like
/// once they are in.
class _StartButton extends StatelessWidget {
  const _StartButton({
    required this.plan,
    required this.now,
    this.openSession,
    this.onStartSession,
    this.onStartPlanned,
  });

  final StandingPlan? plan;

  /// The same session the card above reads, rather than a bool derived from it
  /// — so "Resume session" and "Where you were" cannot describe different
  /// states.
  final Session? openSession;

  final DateTime now;
  final VoidCallback? onStartSession;

  /// Starts today's session, given the day of the split it is.
  final ValueChanged<String>? onStartPlanned;

  @override
  Widget build(BuildContext context) {
    if (openSession != null) {
      return PrimaryButton(label: 'Resume session', onPressed: onStartSession);
    }

    final todays = plan?.dayFor(now);
    if (todays != null && onStartPlanned != null) {
      return PrimaryButton(
        label: 'Start ${todays.toLowerCase()}',
        onPressed: () => onStartPlanned!(todays),
      );
    }

    return PrimaryButton(label: 'Start a session', onPressed: onStartSession);
  }
}

/// The session they were in the middle of.
///
/// Says what it was and how far in, because "Session in progress" plus a button
/// is the app knowing something the lifter has forgotten and not telling them.
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
          // Stretched, because GlassSurface sizes to its content and this card
          // shares a slot with `Next up`. Left alone, the two states of the
          // same position rendered at different widths on the same screen.
          const SizedBox(width: double.infinity),
          const SectionLabel('Where you were', emphasis: LabelEmphasis.stat),
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

/// Three figures about their actual training.
///
/// Not a dashboard — Profile is where the log lives. This is the one line that
/// makes opening Track worth something on a rest day, and the streak in
/// particular is the figure people open an app to check.
class _RecentStrip extends StatelessWidget {
  const _RecentStrip({required this.log, required this.now});

  final List<Session> log;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final stats = TrainingStats.from(log, now: now);
    final finished = log.where((Session s) => !s.isInProgress).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final thisWeek = finished
        .where(
          (Session s) => !TrainingStats.startOfWeek(
            s.startedAt,
          ).isBefore(TrainingStats.startOfWeek(now)),
        )
        .length;

    // StatBlock, not a local widget. This row used to be `_Figure`, a fourth
    // copy of the design system's Stat that put the value above the label —
    // the opposite of Profile and the session header, on the screen a lifter
    // opens most. It also rendered without tabular figures, so a counter
    // changing width shifted the row under it.
    return Row(
      children: <Widget>[
        Expanded(
          child: StatBlock(label: 'this week', value: '$thisWeek'),
        ),
        Expanded(
          child: StatBlock(
            label: 'week streak',
            value: '${stats.currentWeekStreak}',
          ),
        ),
        if (finished.isNotEmpty)
          Expanded(
            child: StatBlock(
              label: 'last session',
              value: _ago(finished.first.startedAt, now),
              // 'a month ago' in a third of a phone's width.
              shrinkToFit: true,
            ),
          ),
      ],
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
