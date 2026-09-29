import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../../entitlement/domain/entitlement.dart';
import '../../purchases/domain/purchases.dart';
import '../../purchases/presentation/restore_button.dart';
import 'package:mgk_units/mgk_units.dart';

import '../../planning/domain/standing_plan.dart';
import '../../planning/presentation/standing_plan_surface.dart';

/// **Plan** — what the coach has you working toward. The paid surface.
///
/// Unlike Track, this one **needs a connection and says so**. Plan generation
/// and every coach turn are model calls, so there is no honest offline story
/// here: the last plan can be read from disk, but building one
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
    this.coachIsOff = false,
    this.onSubscribe,
    this.onRestore,
    this.offers = const <PurchaseOffer>[],
    this.isEntitled = false,
    this.plan,
    this.unit = MassUnit.kilograms,
    this.today,
    this.onOpenSession,
    this.onSwapSlot,
  });

  /// Starts the coach conversation that produces a plan. Null when the coach is
  /// unreachable — no backend wired up, or no connection.
  final VoidCallback? onBuildPlan;

  /// Why [onBuildPlan] is null, when the reason is the lifter rather than
  /// the network.
  ///
  /// Building a plan is an AI request, so the coach switch turns it off
  /// along with everything else — and without this the screen would go on
  /// blaming the connection for a choice somebody made on purpose. A note
  /// that is wrong about the cause is worse than no note: it sends a lifter
  /// to check their signal over a setting.
  final bool coachIsOff;

  /// Opens the store. Null until billing exists.
  final VoidCallback? onSubscribe;

  /// Restore purchases, required of any app selling a subscription
  /// (Guideline 3.1.1) and the only route back for somebody reinstalling.
  /// Null hides the affordance rather than disabling it.
  final Future<void> Function()? onRestore;

  /// What the store says it will sell, and **the only source of a price on this
  /// screen**. Empty when there is no store or it has not answered, in which
  /// case the tiers are still named and described — the copy is the app's — and
  /// the price column says it does not know.
  final List<PurchaseOffer> offers;

  /// Whether this account has the paid tier for Lift. Entitlements are per-app
  /// and client-read-only; the server decides.
  final bool isEntitled;

  /// The live block. Null is a real state for a paid lifter who has not built
  /// one yet, and it is what the offer-shaped "no plan" copy is for.
  final StandingPlan? plan;

  /// How weights are shown. The plan stores kilograms and converts at display,
  /// like everything else.
  final MassUnit unit;

  /// Injected so a preview can sit on a fixed day of the block, and so the
  /// "what is today" logic is testable without waiting for Thursday.
  final DateTime? today;

  /// Opens one session of the plan.
  /// Starts today's session, given the day of the split it is.
  final ValueChanged<String>? onOpenSession;

  /// "I have no cable machine." Reaches SwapSheet from the plan rather than
  /// from a session already underway.
  final void Function(MovementSlot)? onSwapSlot;

  /// Asks the coach to change the week ahead. Null hides the action.

  static const EdgeInsets _padding = EdgeInsets.fromLTRB(
    AppSpacing.lg,
    AppSpacing.xl,
    AppSpacing.lg,
    AppSpacing.xxl,
  );

  /// Whether the live-block layout is in play, which lays out differently from
  /// the two copy states.
  /// Whether there is a live plan to show rather than an offer or an invitation.
  bool get isBlock => isEntitled && plan != null;

  /// No price on the button, because it no longer buys one tier: it opens the
  /// purchase sheet, where both are priced and either can be chosen.
  ///
  /// It read `Start coaching — £1/mo` as a constant until 2026-09-02 (wrong
  /// outside the UK), then named Coach's store price until 2026-09-29, when it
  /// still bought only Coach while the table above it offered Premium Coach.
  static const String _buyLabel = 'Start coaching';

  @override
  Widget build(BuildContext context) {
    // **A live plan is a different screen, not a different branch.**
    //
    // This surface is the paywall and the invitation: photography, a pitch, a
    // price. Once somebody has a plan, none of that is what they came for —
    // they want to know what they are doing today and whether it is ready.
    // StandingPlanSurface answers exactly that, so the live case hands over to
    // it whole rather than trying to render a week inside a sales page.
    final live = plan;
    if (isEntitled && live != null) {
      return StandingPlanSurface(
        plan: live,
        today: today ?? DateTime.now(),
        massUnit: unit,
        onStartToday: onOpenSession == null
            ? null
            : () {
                final day = live.dayFor(today ?? DateTime.now());
                if (day != null) onOpenSession!(day);
              },
        onSwap: onSwapSlot,
        onChangeSplit: onBuildPlan,
      );
    }

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
              // Never below zero. Before the first real layout — the tab is
              // built offstage in the shell's stack — the height can be less
              // than the padding, and a negative minimum threw on every launch.
              constraints: BoxConstraints(
                minHeight: constraints.hasBoundedHeight
                    ? (constraints.maxHeight - _padding.vertical).clamp(
                        0,
                        double.infinity,
                      )
                    : 0,
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
                // Only two states reach here: the live plan returns above.
                children: switch (isEntitled) {
                  false => _offer(context),
                  true => _entitled(context),
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
          text: coachIsOff
              // Says where the switch is, because a note that only states the
              // state leaves somebody hunting for the thing that changes it.
              ? 'The AI coach is off. Turn it back on in Settings to build a '
                    'plan — building one sends your answers to an AI provider.'
              : 'Your coach needs a connection. Tracking carries on without '
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
      _Tiers(offers),
      const SizedBox(height: AppSpacing.lg),
      PrimaryButton(label: _buyLabel, onPressed: onSubscribe),
      RestorePurchasesButton(onRestore: onRestore),
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
///
/// **The two paid tiers hold the same features.** Premium Coach buys more room
/// to talk to the coach and nothing else — no screen, no capability, no extra
/// half of the app. That is worth saying in the copy rather than leaving
/// somebody to infer a feature list from a price difference, and it is why the
/// Premium Coach row says what is the same before it says what differs.
///
/// **Names are the app's; prices are the store's.** The tiers are Coach and
/// Premium Coach — see [EntitlementTier.label] — and the price column is filled
/// in from [PurchaseOffer] or left unknown. Both were hardcoded as `£1` and `£3`
/// until 2026-09-02, which named the tiers after a number that is wrong outside
/// the UK and has to be hunted down the day it changes.
class _Tiers extends StatelessWidget {
  const _Tiers(this.offers);

  final List<PurchaseOffer> offers;

  /// What the tier is for. App copy, so it reads the same whether or not the
  /// store answered.
  static String _detail(EntitlementTier tier) => switch (tier) {
    EntitlementTier.free =>
      'Sessions, templates, history, stats. No limits and no ads.',
    EntitlementTier.paid =>
      'A plan built for you, a coach that adapts it, and progress photos.',
    EntitlementTier.premium =>
      'Everything in Coach, feature for feature. Far more room to talk to '
          'the coach.',
  };

  /// An em dash rather than a guess. Not knowing the price yet is a true thing
  /// to show; inventing one is not.
  String _price(EntitlementTier tier) {
    for (final offer in offers) {
      if (offer.tier == tier) return offer.price;
    }
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _Tier(
            price: 'Free',
            name: 'Everything you are using now',
            detail: _detail(EntitlementTier.free),
          ),
          const _Divider(),
          _Tier(
            price: _price(EntitlementTier.paid),
            name: EntitlementTier.paid.label,
            detail: _detail(EntitlementTier.paid),
            isHighlighted: true,
          ),
          const _Divider(),
          _Tier(
            price: _price(EntitlementTier.premium),
            name: EntitlementTier.premium.label,
            detail: _detail(EntitlementTier.premium),
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

  /// The tier the purchase sheet opens on. Marked by weight rather than by
  /// colour — there is no accent to reach for, which is the constraint the
  /// whole palette is built on.
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
