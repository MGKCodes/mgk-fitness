import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../../planning/domain/plan.dart';

/// **Plan** — what the coach has you working toward. The paid surface.
///
/// Unlike Track, this one **needs a connection and says so**. Plan generation
/// and every coach turn are model calls, so there is no honest offline story
/// here: the last plan can be read from disk, but building or adapting one
/// cannot happen without a network.
///
/// ## What this screen is for
///
/// The first version was a headline, a paragraph, and a disabled button with
/// nine hundred pixels of nothing between them. It occupied a third of the
/// app's navigation and sold nothing.
///
/// A paid surface shown to someone who has not paid has one job: make the offer
/// legible. So it says what the coach actually does, in the lifter's terms, and
/// what it costs. It does **not** hide tracking behind a lock — tracking is free
/// and complete, and pretending otherwise would make the free app feel like a
/// demo rather than a product.
class PlanSurface extends StatelessWidget {
  const PlanSurface({
    super.key,
    this.onBuildPlan,
    this.onSubscribe,
    this.isEntitled = false,
    this.plan,
    this.unit = MassUnit.kilograms,
    this.today,
    this.onOpenSession,
    this.onAdapt,
  });

  /// Starts the coach conversation that produces a plan. Null when the coach is
  /// unreachable — no backend wired up, or no connection.
  final VoidCallback? onBuildPlan;

  /// Opens the store. Null until billing exists.
  final VoidCallback? onSubscribe;

  /// Whether this account has the paid tier for Lift. Entitlements are per-app
  /// and client-read-only; the server decides.
  final bool isEntitled;

  /// The live block. Null is a real state for a paid lifter who has not built
  /// one yet, and it is what the offer-shaped "no plan" copy is for.
  final Plan? plan;

  /// How weights are shown. The plan stores kilograms and converts at display,
  /// like everything else.
  final MassUnit unit;

  /// Injected so a preview can sit on a fixed day of the block, and so the
  /// "what is today" logic is testable without waiting for Thursday.
  final DateTime? today;

  /// Opens one session of the plan.
  final ValueChanged<PlanSession>? onOpenSession;

  /// Asks the coach to change the week ahead. Null hides the action.
  final VoidCallback? onAdapt;

  static const EdgeInsets _padding = EdgeInsets.fromLTRB(
    AppSpacing.lg,
    AppSpacing.xl,
    AppSpacing.lg,
    AppSpacing.xxl,
  );

  /// Whether the live-block layout is in play, which lays out differently from
  /// the two copy states.
  bool get isBlock => isEntitled && (plan?.isActive ?? false);

  @override
  Widget build(BuildContext context) {
    return PhotoBackdrop(
      image: 'assets/images/backgrounds/hero_paywall.webp',
      // `grounded`, not `quiet`. Quiet is nearly opaque, and on this image it
      // erased the photograph entirely — a flat dark screen next to Track,
      // where the same treatment is the most striking thing in the app. With no
      // accent colour, this photography *is* the brand (ADR-0009), and the
      // surface asking for money is the last place to throw it away.
      //
      // Grounded is light at the top where the headline sits and heavy at the
      // base, so the photo is present behind the pitch and gone under the price.
      scrim: ScrimStrength.grounded,
      child: SafeArea(
        // Centred when the content is shorter than the screen, scrolling when
        // it is longer. A plain ListView top-anchors, which is what left the
        // "paid, no plan yet" state as a third of a screen of content above
        // nine hundred pixels of nothing — the same fault the offer had.
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: _padding,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - _padding.vertical,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                // Centred for the two states that are a fixed lump of copy —
                // the offer and "no plan yet" — and TOP-ALIGNED for the live
                // block, which is a list. Centring a list marooned two sessions
                // in the middle of the screen with seven hundred pixels of
                // nothing under them, and would push five off the bottom. It is
                // the same fault this file already records fixing for the offer.
                mainAxisAlignment: isBlock
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: switch ((isEntitled, plan)) {
                  (false, _) => _offer(context),
                  (true, final Plan p) when p.isActive => _block(context, p),
                  (true, _) => _entitled(context),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Paid, with a live block. What the surface exists to show.
  ///
  /// The week the lifter is IN, not the whole block. A twelve-week plan
  /// rendered in full is a document; what somebody opens Plan to find out is
  /// what is on this week and what is next.
  List<Widget> _block(BuildContext context, Plan plan) {
    final theme = Theme.of(context);
    final now = today ?? DateTime.now();
    final weekNumber = plan.weekOf(now);
    final week = weekNumber == null
        ? null
        : plan.arc.where((PlanWeek w) => w.number == weekNumber).firstOrNull;
    final sessions =
        plan.sessions
            .where((PlanSession s) => s.weekNumber == weekNumber)
            .toList()
          ..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));

    return <Widget>[
      const SectionLabel('Plan'),
      const SizedBox(height: AppSpacing.md),
      Text(
        weekNumber == null
            ? 'Block finished'
            : 'Week $weekNumber of ${plan.weeks}',
        style: theme.textTheme.headlineSmall,
      ),
      if (week != null) ...<Widget>[
        const SizedBox(height: AppSpacing.xs),
        Text(
          week.intent?.isNotEmpty ?? false
              ? week.intent!
              : '${week.phase.label} week.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
      ],
      const SizedBox(height: AppSpacing.xl),

      if (sessions.isEmpty)
        _Note(
          text:
              'This week is written closer to the time, once your coach has '
              'seen how the last one went.',
        )
      else
        for (final session in sessions)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _PlannedSessionRow(
              session: session,
              unit: unit,
              isToday: _sameDay(session.scheduledDate, now),
              onTap: onOpenSession == null
                  ? null
                  : () => onOpenSession!(session),
            ),
          ),

      if (onAdapt != null) ...<Widget>[
        const SizedBox(height: AppSpacing.md),
        // Deliberately quiet. Changing the week is a real capability and the
        // sales copy promises it, but it is not what somebody opens Plan to do
        // — a second primary button here would compete with starting a session.
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onAdapt,
            icon: const Icon(Icons.edit_calendar_outlined, size: 18),
            label: const Text('Something changed?'),
          ),
        ),
      ],
    ];
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Paid, but no plan yet.
  List<Widget> _entitled(BuildContext context) {
    final theme = Theme.of(context);
    return <Widget>[
      const SectionLabel('Plan'),
      const SizedBox(height: AppSpacing.md),
      Text('No plan yet', style: theme.textTheme.headlineSmall),
      const SizedBox(height: AppSpacing.sm),
      Text(
        'Tell your coach what you are working toward. It builds the block '
        'around the days you can actually train.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: AppSpacing.xl),
      const _Conversation(),
      const SizedBox(height: AppSpacing.xl),
      PrimaryButton(label: 'Build a plan', onPressed: onBuildPlan),
      if (onBuildPlan == null) ...<Widget>[
        const SizedBox(height: AppSpacing.sm),
        _Note(
          text:
              'Your coach needs a connection. Tracking carries on without '
              'one.',
        ),
      ],
    ];
  }

  /// Not paid: the offer.
  List<Widget> _offer(BuildContext context) {
    final theme = Theme.of(context);
    return <Widget>[
      const SectionLabel('Plan'),
      const SizedBox(height: AppSpacing.md),
      Text('Train with a coach', style: theme.textTheme.headlineSmall),
      const SizedBox(height: AppSpacing.sm),
      Text(
        'Not a template you follow until it stops fitting. A block built '
        'around your lifts and your week, that moves when life does.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: AppSpacing.xl),

      const _Point(
        icon: Icons.calendar_month_outlined,
        title: 'A block, not a list',
        body:
            'Weeks that build and taper toward what you are training for, '
            'on the days you said you can train.',
      ),
      const _Point(
        icon: Icons.trending_up,
        title: 'Numbers from your numbers',
        body:
            'Targets come from what you have actually lifted — read off '
            'your log, not from a table.',
      ),
      const _Point(
        icon: Icons.chat_bubble_outline,
        title: 'It answers back',
        body:
            '"Shoulder is sore, can we move Thursday?" It proposes the '
            'change; you approve it.',
      ),
      const _Point(
        icon: Icons.directions_run,
        title: 'It sees your running too',
        body:
            'If you use Run, the coach counts that as training rather than '
            'planning on top of it.',
        isLast: true,
      ),

      const SizedBox(height: AppSpacing.xl),
      const _Tiers(),
      const SizedBox(height: AppSpacing.lg),
      PrimaryButton(label: 'Start coaching — £1/mo', onPressed: onSubscribe),
      const SizedBox(height: AppSpacing.md),
      _Note(
        text:
            'Cancel whenever. Your log stays yours either way, and Lift and '
            'Run are paid for separately.',
      ),
    ];
  }
}

/// The three tiers, in one block.
///
/// All three, not just the one being sold. Showing Free at the top is the point:
/// it is the row that proves tracking is not the thing behind the paywall, which
/// a screen that only listed the paid tiers would quietly imply.
class _Tiers extends StatelessWidget {
  const _Tiers();

  @override
  Widget build(BuildContext context) {
    return const GlassSurface(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _Tier(
            price: 'Free',
            name: 'Everything you are using now',
            detail:
                'Sessions, templates, history, stats. No limits and no ads.',
          ),
          _Divider(),
          _Tier(
            price: '£1',
            name: 'Coaching',
            detail: 'A plan built for you, and a coach that adapts it.',
            isHighlighted: true,
          ),
          _Divider(),
          _Tier(
            price: '£3',
            name: 'Premium',
            detail: 'The same coach, with far more room to talk to it.',
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
    child: SizedBox(height: 1, child: ColoredBox(color: AppColors.elevated)),
  );
}

class _Tier extends StatelessWidget {
  const _Tier({
    required this.price,
    required this.name,
    required this.detail,
    this.isHighlighted = false,
  });

  final String price;
  final String name;
  final String detail;

  /// The tier the button below buys. Marked by weight rather than by colour —
  /// there is no accent to reach for, which is the constraint the whole palette
  /// is built on.
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 52,
          child: Text(
            price,
            style: theme.textTheme.titleMedium?.copyWith(
              color: isHighlighted
                  ? AppColors.textPrimary
                  : AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                name,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: isHighlighted
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One thing the coach does. Icon, claim, and the concrete version of it —
/// a bare claim is marketing, the example is what makes it credible.
class _Point extends StatelessWidget {
  const _Point({
    required this.icon,
    required this.title,
    required this.body,
    this.isLast = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
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

/// A quiet aside. Used for the honest caveats rather than the sales copy.
class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
    );
  }
}

/// A sample of what asking the coach looks like.
///
/// Shown to a paying lifter with no plan yet, because "build a plan" is
/// otherwise an instruction with no picture attached.
class _Conversation extends StatelessWidget {
  const _Conversation();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionLabel(
            'It starts as a conversation',
            emphasis: LabelEmphasis.stat,
          ),
          SizedBox(height: AppSpacing.md),
          _Line(text: 'What are you training for?', fromCoach: true),
          _Line(text: 'Want my bench past 100 by Christmas'),
          _Line(
            text: 'How many days a week can you get to the gym?',
            fromCoach: true,
          ),
          _Line(text: 'Four, but not Fridays'),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.text, this.fromCoach = false});

  final String text;
  final bool fromCoach;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Align(
        alignment: fromCoach ? Alignment.centerLeft : Alignment.centerRight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fromCoach ? AppColors.elevated : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: fromCoach
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One planned session in the week's list.
///
/// Says what it is, when, and how loaded it actually is. A session whose
/// movements have no targets is not broken — it is what the coach can honestly
/// prescribe for a movement it has not seen — so it renders as sets and reps
/// rather than as a gap where a number should be.
class _PlannedSessionRow extends StatelessWidget {
  const _PlannedSessionRow({
    required this.session,
    required this.unit,
    required this.isToday,
    this.onTap,
  });

  final PlanSession session;
  final MassUnit unit;
  final bool isToday;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = session.status == PlanSessionStatus.completed;

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  session.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: done ? AppColors.textTertiary : null,
                  ),
                ),
              ),
              Text(
                done
                    ? 'Done'
                    : isToday
                    ? 'Today'
                    : _shortWeekday(session.weekday),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isToday && !done
                      ? AppColors.textPrimary
                      : AppColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          // One per line, like PlanReviewScreen. Joined with middle dots this
          // wrapped into a dense two-line block that cannot be scanned standing
          // up holding a phone, which is the only posture that matters here.
          for (final movement in session.movements)
            Text(
              '${movement.name} — ${movement.render(unit)}',
              maxLines: 1,
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

String _shortWeekday(int weekday) => switch (weekday) {
  1 => 'Mon',
  2 => 'Tue',
  3 => 'Wed',
  4 => 'Thu',
  5 => 'Fri',
  6 => 'Sat',
  7 => 'Sun',
  _ => '',
};
