import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../domain/plan_headline.dart';
import '../domain/plan_shape.dart';
import '../domain/stored_plan.dart';
import 'scripted_conversation.dart';

/// The end of the plan flow: the wait, and then the plan.
///
/// ## Why this exists
///
/// Onboarding used to finish by `pop`-ing a profile back to the tab that
/// launched it. The runner answered four questions about themselves, tapped
/// confirm, watched the Plan tab show a spinner, and then a plan was simply
/// *there*. Nothing marked the moment, because structurally there was no moment
/// to mark: the flow had already ended and the plan arrived afterwards, in a
/// different screen, owned by something else.
///
/// So the flow does not end until the plan exists. This screen owns the wait
/// and the arrival, and `PlanRepository.create` already describes that wait as
/// "the one place a wait is honest: the runner has just tapped Build my plan
/// and is watching a spinner that says so". This is that spinner, finally
/// saying so.
///
/// ## What it shows
///
/// Computed facts only — the headline the Plan tab already writes, and numbers
/// read straight off the skeleton. Nothing here is generated prose, so there is
/// nothing here that can be confidently wrong at the exact moment a runner is
/// deciding whether to trust the thing (ADR-0003).
///
/// The numbers are gated on the shape. A block and a horizon climb toward
/// something, so a peak week is the plan's argument for itself; a rhythm does
/// not go anywhere, and telling somebody who runs parkrun every Saturday that
/// they "peak in week 12" would be the app deciding their habit was a project
/// ([ADR-0011](../../../../../docs/decisions/0011-a-plan-has-a-shape.md)).
class PlanRevealScreen extends StatefulWidget {
  const PlanRevealScreen({
    super.key,
    required this.build,
    required this.onDone,
    this.unit = UnitSystem.metric,
    this.now = DateTime.now,
  });

  /// Builds and persists the plan. Called once on open, and again on a retry.
  final Future<StoredPlan> Function() build;

  /// Called with the plan once the runner has seen it, or with null when the
  /// build failed and they backed out.
  final void Function(StoredPlan? plan) onDone;

  final UnitSystem unit;
  final DateTime Function() now;

  @override
  State<PlanRevealScreen> createState() => _PlanRevealScreenState();
}

class _PlanRevealScreenState extends State<PlanRevealScreen> {
  StoredPlan? _plan;
  String? _error;

  @override
  void initState() {
    super.initState();
    _build();
  }

  Future<void> _build() async {
    setState(() => _error = null);
    try {
      final plan = await widget.build();
      if (!mounted) return;
      setState(() => _plan = plan);
    } catch (e) {
      if (!mounted) return;
      // Whatever went wrong, this is not the screen to explain a stack trace
      // on. A `PlanStoreException` carries a runner-readable message; anything
      // else gets one.
      setState(
        () => _error = e is Exception && '$e'.contains(':')
            ? '$e'.split(':').skip(1).join(':').trim()
            : 'The plan could not be built. Please try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    return PopScope<void>(
      // There is nothing to go back *to*: the conversation behind this has been
      // answered and the profile is spent. Leaving is a decision made with the
      // buttons, which say what leaving means.
      canPop: false,
      child: Scaffold(
        body: PhotoBackdrop(
          image: 'assets/images/backgrounds/onboarding.jpg',
          opacity: 0.34,
          scrim: ScrimStrength.grounded,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: _error != null
                  ? _Failed(message: _error!, onRetry: _build, onLeave: _leave)
                  : plan == null
                  ? const _Building()
                  : _Revealed(
                      plan: plan,
                      unit: widget.unit,
                      now: widget.now(),
                      onDone: () => widget.onDone(plan),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  void _leave() => widget.onDone(null);
}

/// The wait. Two LLM calls deep and honestly slow, so it says what is happening
/// rather than spinning silently.
class _Building extends StatelessWidget {
  const _Building();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Said('Right. Give me a moment to put your weeks together.'),
        const SizedBox(height: AppSpacing.xl),
        const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }
}

/// The plan could not be built. Never a dead end: the profile is still in
/// memory upstream, so trying again costs nothing but the wait.
class _Failed extends StatelessWidget {
  const _Failed({
    required this.message,
    required this.onRetry,
    required this.onLeave,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Said('That did not work, and it is on me rather than on you.'),
        const SizedBox(height: AppSpacing.md),
        Text(
          message,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(label: 'Try again', onPressed: onRetry),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: AppTextButton(
            label: 'Not now',
            onPressed: onLeave,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// The plan, the moment it exists.
class _Revealed extends StatelessWidget {
  const _Revealed({
    required this.plan,
    required this.unit,
    required this.now,
    required this.onDone,
  });

  final StoredPlan plan;
  final UnitSystem unit;
  final DateTime now;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headline = planHeadline(plan, now, unit: unit);
    final shape = shapeOf(plan.profile);
    final weeks = plan.skeleton.weeks;

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // The payoff of the whole of onboarding, and it used to land in one
        // frame. The coach says here it is, then the thing itself, then what
        // shape it is — in that order, because that is the order somebody
        // reads it in and the order it was promised in.
        //
        // Entrance rather than SequencedReveal: this is read, not answered, but
        // it is still a screen somebody has been waiting on, and a paced reveal
        // that holds back a plan they have already waited for would be making
        // them wait twice.
        const Entrance(child: Said('Here it is.')),
        const SizedBox(height: AppSpacing.xl),

        Entrance(
          index: 1,
          child: Text(
            headline.goal,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Entrance(
          index: 2,
          child: Text(
            headline.position,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),

        // Only where the plan climbs toward something. A rhythm has no peak to
        // quote, and inventing one would describe a habit as a project.
        if (shape.progresses) ...<Widget>[
          const SizedBox(height: AppSpacing.xl),
          const Entrance(index: 3, child: SectionLabel('The shape of it')),
          const SizedBox(height: AppSpacing.md),
          _Fact(label: 'Length', value: '${weeks.length} weeks'),
          _Fact(
            label: 'Biggest week',
            value: Distance.meters(
              weeks.map((w) => w.volumeMeters).reduce((a, b) => a > b ? a : b),
            ).format(unit, fractionDigits: 0),
          ),
          _Fact(
            label: 'Longest run',
            value: Distance.meters(
              weeks.map((w) => w.longRunMeters).reduce((a, b) => a > b ? a : b),
            ).format(unit, fractionDigits: 0),
          ),
        ],

        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(label: 'See my week', onPressed: onDone),
      ],
    );
  }
}

/// One line of the plan's shape: what it is, and the number.
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
