import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../domain/intro_script.dart';

/// The coach's first lines, before the app.
///
/// **Run's intro, in Lift's words** (ADR-0006): the coach's lines arrive one at
/// a time, a beat apart with the coach composing in between, over the same
/// photograph as the welcome, and the button comes last. It looks like the
/// coach because it is the coach, in the voice the coach keeps afterwards; it
/// is a script underneath (see `intro_script.dart` for why).
///
/// **Nothing is asked.** Run's asks a name and the permissions a tracker needs.
/// Lift needs no permission, and the name is the account's, asked after an
/// account is made, so this is six lines and one button. Everything a lifter
/// needs to know before their first set is here, and nothing they would have
/// to undo.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, required this.onFinished, this.onBack});

  /// *Start training*, pressed. The gate records it and opens the app.
  final VoidCallback onFinished;

  /// Back to the welcome. **Null draws no back**: somebody who arrived here
  /// through sign-in is signed in, and the welcome they would go back to
  /// offers to sign them in.
  final VoidCallback? onBack;

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final ScrollController _scroll = ScrollController();

  /// Lines that are in the script but not on screen yet.
  ///
  /// **The button waits for the last line**, as Run's input waits for the
  /// question it answers. A button painted under the first line invites a tap
  /// that skips the five after it, and the lines are the point of the screen.
  /// Counted down from the length of the script by [SequencedReveal]'s
  /// callback, one per line landed.
  int _pending = kIntroLines.length;

  /// Opens the button if the reveal goes quiet. See [_revealBudget].
  Timer? _failsafe;

  /// The OS asked for less movement. [SequencedReveal] then paints every line
  /// in one frame and never calls back, so the button must not wait on it.
  /// Widget tests take this path too.
  bool _reducedMotion = false;

  /// *Start training* has been pressed. A second tap must not finish twice.
  bool _finished = false;

  /// How long the button waits on one pending line before arriving anyway.
  ///
  /// [SequencedReveal] beats at 620ms, so this is headroom rather than a race.
  /// **The button must always arrive.** A screen whose only way out waits on a
  /// callback is one dropped callback from stranding somebody on their first
  /// screen with nothing to tap: Run's reason, and the same here.
  static const Duration _revealBudget = Duration(milliseconds: 900);

  /// Slack on top of [_revealBudget], so the failsafe cannot fire between the
  /// last line landing and its callback being handled.
  static const Duration _revealSlack = Duration(seconds: 1);

  /// The height the button's slot holds while it is empty, the primary
  /// button's minimum in `AppTheme`, so the lines do not lurch up when it
  /// arrives.
  static const double _buttonSlotHeight = 52;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _armFailsafe();
  }

  @override
  void dispose() {
    _failsafe?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  bool get _canStart => _reducedMotion || _pending == 0;

  /// A line landed: one fewer between the lifter and the button, and the view
  /// follows the conversation down.
  void _onRevealed() {
    if (_pending > 0) setState(() => _pending--);
    _armFailsafe();
    _toEnd();
  }

  void _armFailsafe() {
    _failsafe?.cancel();
    _failsafe = null;
    if (_reducedMotion || _pending == 0) return;
    _failsafe = Timer(_revealBudget * _pending + _revealSlack, () {
      _failsafe = null;
      if (!mounted || _pending == 0) return;
      // Better the button a beat early than a first screen with no way out.
      setState(() => _pending = 0);
    });
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      unawaited(
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: AppMotion.base,
          curve: AppMotion.entrance,
        ),
      );
    });
  }

  void _start() {
    if (_finished) return;
    _finished = true;
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final back = widget.onBack;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: back == null
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              leading: AppIconButton(
                icon: backIcon(context),
                tooltip: 'Back',
                onPressed: back,
              ),
            ),
      body: PhotoBackdrop(
        // The welcome's photograph, so the two screens read as one place.
        // `grounded`, as Run's intro: the lines stack from the foot up, so the
        // scrim is heaviest where they are.
        image: 'assets/images/backgrounds/hero_onboarding.webp',
        opacity: 0.34,
        scrim: ScrimStrength.grounded,
        child: SafeArea(
          child: Column(
            children: <Widget>[
              // **Grows from the bottom**, as a conversation does: the newest
              // line always sits just above the button, and a short exchange is
              // not stranded under the status bar half a phone from it.
              Expanded(
                child: ConversationView(
                  controller: _scroll,
                  anchor: ConversationAnchor.bottom,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.xl,
                    AppSpacing.xl,
                    AppSpacing.lg,
                  ),
                  children: <Widget>[
                    // **The pacing is the content**, for Run's reason: six
                    // lines painted in one frame read as a page of text, and
                    // this is meant to read as somebody talking.
                    SequencedReveal(
                      onRevealed: _onRevealed,
                      children: <Widget>[
                        for (final line in kIntroLines) ScriptedLine(line),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  AppSpacing.xl,
                ),
                // **Nothing until the last line has landed**, in a slot that
                // keeps its height so the lines do not jump when it arrives.
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: _buttonSlotHeight,
                  ),
                  child: _canStart
                      ? Entrance(
                          child: PrimaryButton(
                            label: kIntroStart,
                            onPressed: _start,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
