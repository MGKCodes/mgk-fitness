import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

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
  });

  /// Starts the coach conversation that produces a plan. Null when the coach is
  /// unreachable — no backend wired up, or no connection.
  final VoidCallback? onBuildPlan;

  /// Opens the store. Null until billing exists.
  final VoidCallback? onSubscribe;

  /// Whether this account has the paid tier for Lift. Entitlements are per-app
  /// and client-read-only; the server decides.
  final bool isEntitled;

  static const EdgeInsets _padding = EdgeInsets.fromLTRB(
    AppSpacing.lg,
    AppSpacing.xl,
    AppSpacing.lg,
    AppSpacing.xxl,
  );

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
                mainAxisAlignment: MainAxisAlignment.center,
                children: isEntitled ? _entitled(context) : _offer(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

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
          text: 'Your coach needs a connection. Tracking carries on without '
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
        body: 'Weeks that build and taper toward what you are training for, '
            'on the days you said you can train.',
      ),
      const _Point(
        icon: Icons.trending_up,
        title: 'Numbers from your numbers',
        body: 'Targets come from what you have actually lifted — read off '
            'your log, not from a table.',
      ),
      const _Point(
        icon: Icons.chat_bubble_outline,
        title: 'It answers back',
        body: '"Shoulder is sore, can we move Thursday?" It proposes the '
            'change; you approve it.',
      ),
      const _Point(
        icon: Icons.directions_run,
        title: 'It sees your running too',
        body: 'If you use Run, the coach counts that as training rather than '
            'planning on top of it.',
        isLast: true,
      ),

      const SizedBox(height: AppSpacing.xl),
      const _Tiers(),
      const SizedBox(height: AppSpacing.lg),
      PrimaryButton(label: 'Start coaching — £1/mo', onPressed: onSubscribe),
      const SizedBox(height: AppSpacing.md),
      _Note(
        text: 'Cancel whenever. Your log stays yours either way, and Lift and '
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
            detail: 'Sessions, templates, history, stats. No limits and no ads.',
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
    child: SizedBox(
      height: 1,
      child: ColoredBox(color: AppColors.elevated),
    ),
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
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: AppColors.textTertiary,
      ),
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
          SectionLabel('It starts as a conversation',
              emphasis: LabelEmphasis.stat),
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
