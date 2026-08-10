import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import '../domain/intake_slots.dart';
import 'chat_widgets.dart';
import 'onboarding_controller.dart';

/// The slot-filling onboarding conversation — a chat, not a form (onboarding.md).
/// The coach greets on open, batches its questions, and the input locks the
/// moment Dart decides the intake is complete (or the turn cap is hit), handing
/// off to the editable confirmation screen.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.controller,
    required this.onReview,
    this.onExit,
  });

  final OnboardingController controller;

  /// Called with the gathered slots when the runner taps "Review details".
  final void Function(IntakeSlots slots) onReview;

  /// Called to leave the conversation (a close button in the bar). Null hides
  /// it — the standalone preview has nowhere to go.
  final VoidCallback? onExit;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  OnboardingController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChange);
    _c.start();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _submit() {
    final text = _input.text;
    if (text.trim().isEmpty || !_c.canSend) return;
    _input.clear();
    _c.send(text);
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Off the slots themselves, not off a constant. This divided by a
    // hardcoded 6 — the block count — so a rhythm runner's bar stalled at four
    // sixths on a conversation that had finished, and a log runner's sat at
    // zero throughout (ADR-0011).
    final required = _c.slots.requiredSlots.length;
    final filled = required - _c.slots.missingRequired.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your coach'),
        leading: widget.onExit == null
            ? null
            : IconButton(
                icon: const Icon(Icons.close),
                onPressed: widget.onExit,
                tooltip: 'Close',
              ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: LinearProgressIndicator(
            // A shape with nothing required — a runner who only wants their
            // runs logged — is finished the moment it is established, so the
            // bar is full rather than dividing by zero.
            value: required == 0 ? 1 : filled / required,
            minHeight: 2,
            backgroundColor: AppColors.elevated,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Bottom-anchored. A ListView top-anchors, which left the coach's
            // opening question stranded at the top of the very first screen a
            // runner ever sees, with a screen of nothing between it and the
            // box they are meant to type in.
            //
            // ConversationView carries the anchoring and nothing else, so this
            // keeps Run's own bubbles — the same component Lift's two
            // conversations use, for the same reason.
            Expanded(
              child: ConversationView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                children: <Widget>[
                  for (final message in _c.messages)
                    ChatBubble(text: message.text, isUser: message.isUser),
                  if (_c.isBusy) const TypingBubble(),
                ],
              ),
            ),
            if (_c.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.xs,
                ),
                child: Text(
                  _c.error!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 13),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: _c.isFinished
                  ? PrimaryButton(
                      label: 'Review details',
                      onPressed: () => widget.onReview(_c.slots),
                    )
                  : ChatComposer(
                      controller: _input,
                      enabled: _c.canSend,
                      onSend: _submit,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
