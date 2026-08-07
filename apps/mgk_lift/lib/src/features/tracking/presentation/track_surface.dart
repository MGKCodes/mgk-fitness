import 'package:flutter/material.dart';
import 'package:mgk_units/mgk_units.dart';

import 'package:mgk_ui/mgk_ui.dart';

import '../../planning/domain/plan.dart';
import '../../stats/domain/training_stats.dart';
import '../domain/session.dart';

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
    this.hasOpenSession = false,
    this.openSession,
    this.log = const <Session>[],
    this.plan,
    this.unit = MassUnit.kilograms,
    this.today,
    this.onStartPlanned,
  });

  /// Begins or resumes a session. Null while the recorder is not wired up,
  /// which reads as an unavailable action rather than an error.
  final VoidCallback? onStartSession;

  final VoidCallback? onOpenPlan;

  /// True when a session is already open — usually because the app was killed
  /// mid-workout. The button then offers to go back to it, because "Start a
  /// session" over the top of one already running is a lie about what happens.
  final bool hasOpenSession;

  /// The open session itself, when there is one.
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
  final Plan? plan;

  final MassUnit unit;

  /// Injected so "what is today" is testable without waiting for Thursday.
  final DateTime? today;

  /// Starts a planned session — with its movements AND its targets, which is
  /// the whole difference between a plan and a template.
  final ValueChanged<PlanSession>? onStartPlanned;

  /// What the screen is about, in three words.
  ///
  /// Reads the same state the card below does, so the two cannot disagree —
  /// which they did: "Ready when you are" sat above a card naming today's
  /// prescribed session.
  String get _headline {
    if (openSession != null || hasOpenSession) return 'Pick up where you were';
    final todays = plan?.sessionOn(today ?? DateTime.now());
    if (todays != null && todays.status == PlanSessionStatus.planned) {
      return 'Today is ${todays.title.toLowerCase()}';
    }
    if (plan != null) return 'Nothing scheduled today';
    return 'Ready when you are';
  }

  /// The second line, or null when the card below already carries it.
  String? get _support {
    if (openSession != null || hasOpenSession) return null;
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
                _NextUp(plan: plan, unit: unit, now: today ?? DateTime.now()),

              if (log.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                _RecentStrip(log: log, now: today ?? DateTime.now()),
              ],

              const SizedBox(height: AppSpacing.lg),
              _StartButton(
                plan: plan,
                now: today ?? DateTime.now(),
                hasOpenSession: hasOpenSession,
                onStartSession: onStartSession,
                onStartPlanned: onStartPlanned,
              ),
            ],
          ),
        ),
      ),
    );
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

  final Plan? plan;
  final MassUnit unit;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = plan;
    final todays = p?.sessionOn(now);
    final next = todays == null ? p?.nextFrom(now) : null;

    final (String title, String detail) = switch ((p, todays, next)) {
      (null, _, _) => (
        'Nothing scheduled',
        'Your coach builds the plan. Until then, log whatever you are doing.',
      ),
      (_, final PlanSession s, _) => (
        s.title,
        // One per line, as on Plan and the review screen. Middle-dot joined,
        // this wrapped into a dense block nobody reads standing up.
        s.movements.map((m) => '${m.name} — ${m.render(unit)}').join('\n'),
      ),
      (_, _, final PlanSession s) => (
        'Rest day',
        'Next is ${s.title} on ${_weekdayName(s.weekday)}.',
      ),
      _ => ('Block finished', 'Ask your coach what comes next.'),
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
    required this.hasOpenSession,
    this.onStartSession,
    this.onStartPlanned,
  });

  final Plan? plan;
  final DateTime now;
  final bool hasOpenSession;
  final VoidCallback? onStartSession;
  final ValueChanged<PlanSession>? onStartPlanned;

  @override
  Widget build(BuildContext context) {
    if (hasOpenSession) {
      return PrimaryButton(label: 'Resume session', onPressed: onStartSession);
    }

    final todays = plan?.sessionOn(now);
    if (todays != null &&
        todays.status == PlanSessionStatus.planned &&
        onStartPlanned != null) {
      return PrimaryButton(
        label: 'Start ${todays.title.toLowerCase()}',
        onPressed: () => onStartPlanned!(todays),
      );
    }

    return PrimaryButton(label: 'Start a session', onPressed: onStartSession);
  }
}

String _weekdayName(int weekday) => switch (weekday) {
  1 => 'Monday',
  2 => 'Tuesday',
  3 => 'Wednesday',
  4 => 'Thursday',
  5 => 'Friday',
  6 => 'Saturday',
  7 => 'Sunday',
  _ => 'another day',
};

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

    return Row(
      children: <Widget>[
        _Figure(value: '$thisWeek', label: 'this week'),
        _Figure(value: '${stats.currentWeekStreak}', label: 'week streak'),
        if (finished.isNotEmpty)
          _Figure(
            value: _ago(finished.first.startedAt, now),
            label: 'last session',
          ),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(value, style: theme.textTheme.titleMedium),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textTertiary,
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
