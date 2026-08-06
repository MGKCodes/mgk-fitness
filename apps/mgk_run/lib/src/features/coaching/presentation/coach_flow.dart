import 'package:flutter/material.dart';

import '../../../core/units/unit_system.dart';
import '../../legal/data/disclaimer_store_factory.dart';
import '../../legal/domain/disclaimer_store.dart';
import '../../legal/presentation/medical_disclaimer_screen.dart';
import '../data/coach_client.dart';
import '../domain/intake_slots.dart';
import '../domain/plan_shape.dart';
import '../domain/runner_profile.dart';
import '../domain/stored_plan.dart';
import 'onboarding_controller.dart';
import 'onboarding_screen.dart';
import 'plan_reveal_screen.dart';
import 'profile_confirmation_screen.dart';
import 'shape_question_screen.dart';

/// The coach **setup flow** as a single route: the medical disclaimer, the
/// shape question, the onboarding conversation, the editable confirmation, and
/// then the plan itself. Navigation is contained and unambiguous:
///  - declining the disclaimer exits the flow (pops with no result);
///  - backing out of the shape question exits the flow;
///  - closing onboarding exits the flow (pops with no result);
///  - the confirmation's back returns to the conversation;
///  - confirming builds the plan and pops the flow with the [StoredPlan].
///
/// The Plan tab pushes this and awaits the plan, so the flow flows cleanly in
/// (from the tab) and out (back to the tab, with or without a plan).
///
/// ## The flow does not end before the plan does
///
/// It used to pop a [RunnerProfile] the moment the runner confirmed, and the
/// tab underneath then built the plan behind its own spinner. So four questions
/// about yourself ended with a screen disappearing, and the plan turned up
/// afterwards somewhere else, unannounced. There was no moment to mark because
/// there was structurally no moment: the flow was already over.
///
/// [buildPlan] is injected rather than reached for, so this route still knows
/// nothing about `PlanRepository` — it knows that something turns a profile
/// into a plan and that it should not leave until that has happened.
///
/// ## This is moment two
///
/// Onboarding is two moments (ADR-0019). The first ends with a free account and
/// a working run tracker. This is the second, entered only when a runner asks
/// for a plan, and it owns every question a plan needs — including "what are
/// you after?", which used to be asked before there was an account at all.
///
/// ## The disclaimer gate
///
/// Runio prescribes physical load, so `docs/medical-disclaimer.md` requires the
/// disclaimer at onboarding, **before a plan is generated**. This flow is the
/// only door to plan generation, so the gate belongs here: nothing downstream —
/// not the shape, not the conversation, certainly not a plan — happens until the
/// runner has accepted.
///
/// It stays *first* within this flow for a commercial reason as well as a legal
/// one: when the paywall lands it goes in front of this whole route, and a
/// runner who pays and only then meets a disclaimer they decline is a refund.
///
/// Acknowledgement is remembered by [disclaimer] so returning runners are not
/// nagged. Every failure mode of that store resolves to *show the gate again*,
/// never to skip it.
class CoachFlow extends StatefulWidget {
  const CoachFlow({
    super.key,
    required this.coach,
    required this.buildPlan,
    this.now = DateTime.now,
    this.disclaimer,
    this.initialSlots = const IntakeSlots(),
    this.name,
    this.unit = UnitSystem.metric,
  });

  final CoachClient coach;
  final DateTime Function() now;

  /// Turns the confirmed profile into a persisted plan. May throw; the reveal
  /// step catches it and offers a retry rather than dropping the runner back
  /// out with nothing to show for the conversation they just had.
  final Future<StoredPlan> Function(RunnerProfile profile) buildPlan;

  /// How distances read on the reveal. Everything is stored metric regardless
  /// (CLAUDE.md rule 4).
  final UnitSystem unit;

  /// What the coach calls this runner, from the intro. Used only to address the
  /// shape question; null simply loses the name from that one line.
  final String? name;

  /// Anything already known before the flow opens. The shape chosen on the
  /// first step is merged over this, so a caller can still seed the intake in
  /// tests and the preview harness.
  final IntakeSlots initialSlots;

  /// Where the medical-disclaimer acknowledgement is remembered. Defaults to the
  /// platform store (a file on iOS, in-memory on web). Tests and the preview
  /// inject their own.
  final DisclaimerStore? disclaimer;

  @override
  State<CoachFlow> createState() => _CoachFlowState();
}

/// Which step of the flow is on screen.
enum _Step {
  checkingDisclaimer,
  disclaimer,
  shape,
  conversation,
  confirmation,
  reveal,
}

class _CoachFlowState extends State<CoachFlow> {
  /// Built when the shape is chosen, not in `initState`, because the slots it
  /// is seeded with are not known until then. Null before that step.
  OnboardingController? _controller;

  late final DisclaimerStore _disclaimer =
      widget.disclaimer ?? createDisclaimerStore();

  _Step _step = _Step.checkingDisclaimer;
  IntakeSlots? _slots;

  @override
  void initState() {
    super.initState();
    _checkDisclaimer();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _checkDisclaimer() async {
    final acknowledged = await _disclaimer.isAcknowledged();
    if (!mounted) return;
    setState(() => _step = acknowledged ? _Step.shape : _Step.disclaimer);
  }

  Future<void> _acknowledge() async {
    // Persist first: if the write somehow fails the store swallows it, and the
    // runner sees the gate again next time. Never the other way round.
    await _disclaimer.acknowledge();
    if (!mounted) return;
    setState(() => _step = _Step.shape);
  }

  /// Null is a real answer here ("I'm not sure yet") and is merged in as null,
  /// leaving the coach to settle it on its first turn.
  void _chooseShape(PlanShape? shape) {
    setState(() {
      _controller = OnboardingController(
        coach: widget.coach,
        initialSlots: widget.initialSlots.merge(IntakeSlots(shape: shape)),
      );
      _step = _Step.conversation;
    });
  }

  void _exit() => Navigator.of(context).pop();

  void _backToChat() => setState(() {
    _slots = null;
    _step = _Step.conversation;
  });

  /// The confirmed profile, held so the reveal can rebuild from it on a retry
  /// without sending the runner back through the conversation.
  RunnerProfile? _profile;

  @override
  Widget build(BuildContext context) {
    final atConfirm = _step == _Step.confirmation;
    return PopScope<StoredPlan>(
      // At the conversation, the shape question or the gate, a system back
      // exits the flow. At the confirmation, it returns to the conversation
      // instead of leaving.
      canPop: !atConfirm,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && atConfirm) _backToChat();
      },
      child: switch (_step) {
        // A frame or two while the store is read. Blank rather than a spinner:
        // flashing a loader before a legal notice looks like a glitch.
        _Step.checkingDisclaimer => const Scaffold(body: SizedBox.shrink()),
        _Step.disclaimer => MedicalDisclaimerScreen(
          onAcknowledge: _acknowledge,
          onDecline: _exit,
        ),
        _Step.shape => ShapeQuestionScreen(
          name: widget.name,
          onChosen: _chooseShape,
          onBack: _exit,
        ),
        _Step.conversation => OnboardingScreen(
          controller: _controller!,
          onExit: _exit,
          onReview: (slots) => setState(() {
            _slots = slots;
            _step = _Step.confirmation;
          }),
        ),
        _Step.confirmation => ProfileConfirmationScreen(
          slots: _slots!,
          now: widget.now,
          onBack: _backToChat,
          onConfirm: (profile) => setState(() {
            _profile = profile;
            _step = _Step.reveal;
          }),
        ),
        // Keyed on the profile so a retry after a failure rebuilds the screen
        // and re-runs its build, rather than reusing a state that has already
        // decided it failed.
        _Step.reveal => PlanRevealScreen(
          key: ValueKey<RunnerProfile>(_profile!),
          build: () => widget.buildPlan(_profile!),
          unit: widget.unit,
          now: widget.now,
          onDone: (plan) => Navigator.of(context).pop(plan),
        ),
      },
    );
  }
}
