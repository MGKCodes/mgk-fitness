import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

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
/// Shown to somebody who has not paid, it says what Plan is for, briefly, and
/// has one button: the sales screen (R6), which every door to paying opens.
/// It used to carry the whole pitch and a price table of its own, and the
/// pitch promised two things nothing ships — moving Thursday's session, and a
/// coach that sees your running. It does **not** hide tracking behind a lock:
/// tracking is free and complete, and it says so.
class PlanSurface extends StatelessWidget {
  const PlanSurface({
    super.key,
    this.onBuildPlan,
    this.isBuilding = false,
    this.coachIsOff = false,
    this.onSubscribe,
    this.onRestore,
    this.isEntitled = false,
    this.plan,
    this.unit = MassUnit.kilograms,
    this.today,
    this.onGoToTrack,
    this.onDoToday,
    this.movedDay,
    this.onSwapSlot,
  });

  /// Starts the coach conversation that produces a plan. Null when the coach is
  /// unreachable — no backend wired up, or no connection.
  final VoidCallback? onBuildPlan;

  /// A plan is being built right now: the intake is done and the coach is
  /// writing the week.
  ///
  /// **Said, not inferred from a null button.** The button is disabled while
  /// a build runs, and this surface used to read every disabled button as
  /// "your coach needs a connection" — so for the minute a plan took, the
  /// lifter was told their signal had failed while it was working perfectly.
  final bool isBuilding;

  /// Why [onBuildPlan] is null, when the reason is the lifter rather than
  /// the network.
  ///
  /// Building a plan is an AI request, so the coach switch turns it off
  /// along with everything else — and without this the screen would go on
  /// blaming the connection for a choice somebody made on purpose. A note
  /// that is wrong about the cause is worse than no note: it sends a lifter
  /// to check their signal over a setting.
  final bool coachIsOff;

  /// Opens the sales screen. Null when this build cannot sell.
  final VoidCallback? onSubscribe;

  /// Restore purchases, required of any app selling a subscription
  /// (Guideline 3.1.1) and the only route back for somebody reinstalling.
  /// Null hides the affordance rather than disabling it.
  final Future<void> Function()? onRestore;

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

  /// Goes to Track, where today's session starts (R8: nothing starts here).
  final VoidCallback? onGoToTrack;

  /// Brings another day's session forward to today — *Do it today*.
  final ValueChanged<String>? onDoToday;

  /// The day already brought forward to today, if one is.
  final String? movedDay;

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

  /// No price on the button: it opens the sales screen, where both tiers are
  /// priced by the store and either can be chosen.
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
        onGoToTrack: onGoToTrack,
        onDoToday: onDoToday,
        movedDay: movedDay,
        onSwap: onSwapSlot,
        onChangeSplit: onBuildPlan,
        isBuilding: isBuilding,
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

  /// Paid, but no plan yet (16): what happens next, in three steps, and one
  /// button. "Build a plan" alone was an instruction with no picture of what
  /// followed it.
  List<Widget> _entitled(BuildContext context) {
    final theme = Theme.of(context);
    return <Widget>[
      const SectionLabel('Plan'),
      const SizedBox(height: AppSpacing.md),
      Text('No plan yet', style: theme.textTheme.headlineSmall),
      const SizedBox(height: AppSpacing.sm),
      Text(
        'Three steps, and the first is a conversation.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: AppSpacing.xl),
      const _Step(
        n: 1,
        title: 'Tell the coach your goal and your days',
        body: 'What you are training for, and when you can get to the gym.',
      ),
      const _Step(
        n: 2,
        title: 'It builds the block',
        body:
            'Weeks that build toward the goal, with targets from what you '
            'have actually lifted.',
      ),
      const _Step(
        n: 3,
        title: "Today's session appears on Track",
        body: 'Started from there, like any other. Plan is the calendar.',
        isLast: true,
      ),
      const SizedBox(height: AppSpacing.xl),
      if (isBuilding) ...<Widget>[
        const PrimaryButton(label: 'Building your plan…', onPressed: null),
        const SizedBox(height: AppSpacing.md),
        const LinearProgressIndicator(),
        const SizedBox(height: AppSpacing.sm),
        const _Note(
          text:
              'Your coach is putting the week together. It can take a '
              'minute, and you can carry on using the app.',
        ),
      ] else ...<Widget>[
        PrimaryButton(label: 'Build a plan', onPressed: onBuildPlan),
      ],
      if (!isBuilding && onBuildPlan == null) ...<Widget>[
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

  /// Not paid: what Plan is for, and the way to the sales screen.
  List<Widget> _offer(BuildContext context) {
    final theme = Theme.of(context);
    return <Widget>[
      const SectionLabel('Plan'),
      const SizedBox(height: AppSpacing.md),
      Text('Train with a coach', style: theme.textTheme.headlineSmall),
      const SizedBox(height: AppSpacing.sm),
      Text(
        'Plan is where a block built for you lives: weeks around your goal '
        'and the days you can train. It comes with a subscription.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: AppSpacing.xl),
      // Two things, both of which ship: lift_plan builds the weeks, and reads
      // the log as the caller to set the targets.
      const _Point(
        icon: Icons.calendar_month_outlined,
        title: 'A block, not a list',
        body:
            'Weeks that build toward what you are training for, on the days '
            'you said you can train.',
      ),
      const _Point(
        icon: Icons.trending_up,
        title: 'Numbers from your numbers',
        body:
            'Targets come from what you have actually lifted — read off '
            'your log, not from a table.',
        isLast: true,
      ),
      const SizedBox(height: AppSpacing.xl),
      PrimaryButton(label: _buyLabel, onPressed: onSubscribe),
      RestorePurchasesButton(onRestore: onRestore),
      const SizedBox(height: AppSpacing.md),
      const _Note(
        text:
            'Tracking stays free, whatever you choose. Cancel whenever; your '
            'log stays yours.',
      ),
    ];
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

/// One of the three steps to a plan: a number, what happens, and what that
/// means.
class _Step extends StatelessWidget {
  const _Step({
    required this.n,
    required this.title,
    required this.body,
    this.isLast = false,
  });

  final int n;
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
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.elevated,
              shape: BoxShape.circle,
            ),
            child: Text('$n', style: theme.textTheme.labelLarge),
          ),
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
