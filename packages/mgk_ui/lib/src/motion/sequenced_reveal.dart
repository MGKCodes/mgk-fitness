import 'dart:async';

import 'package:flutter/material.dart';

import 'entrance.dart';
import 'typing_indicator.dart';

/// Reveals its children one at a time, with a beat between, and a typing
/// indicator filling the gap.
///
/// Built for the intro conversation, which is the first thing anybody sees and
/// which arrived fully formed: five bubbles painted in a single frame, so the
/// screen that is supposed to feel like meeting a coach read as a form with the
/// answers already filled in. A conversation is *paced* — that pacing is the
/// content, not decoration on top of it.
///
/// Only new children animate. When the list grows — the runner answered, so
/// three more turns exist — the ones already on screen stay put and the
/// newcomers arrive. Re-running the whole sequence on every rebuild would make
/// the transcript twitch on every keystroke.
///
/// Under reduced motion, or in a widget test, everything is revealed at once:
/// an unfinished timer chain is a hang, and a paced conversation is a barrier
/// to somebody who asked the OS for less movement.
class SequencedReveal extends StatefulWidget {
  const SequencedReveal({
    super.key,
    required this.children,
    this.beat = const Duration(milliseconds: 620),
    this.firstBeat = const Duration(milliseconds: 260),
    this.showTyping = true,
    this.onRevealed,
  });

  /// The turns so far, oldest first.
  final List<Widget> children;

  /// The pause before each subsequent turn — long enough to read as somebody
  /// composing, short enough that nobody taps to skip it.
  final Duration beat;

  /// The pause before the very first turn on a cold screen.
  final Duration firstBeat;

  /// Whether to fill the gap with a [TypingIndicator]. Off where the pending
  /// turn is the runner's own, which nobody waits for.
  final bool showTyping;

  /// Fires after each turn lands, so a scroll view can follow the conversation
  /// down as it grows.
  final VoidCallback? onRevealed;

  @override
  State<SequencedReveal> createState() => _SequencedRevealState();
}

class _SequencedRevealState extends State<SequencedReveal> {
  int _revealed = 0;
  Timer? _timer;
  bool _instant = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _instant = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _schedule();
  }

  @override
  void didUpdateWidget(SequencedReveal old) {
    super.didUpdateWidget(old);
    // The transcript can shrink — the intro rebuilds from a step counter, and
    // stepping back produces fewer turns than are on screen.
    if (widget.children.length < _revealed) {
      _revealed = widget.children.length;
    }
    _schedule();
  }

  void _schedule() {
    if (_instant) {
      if (_revealed != widget.children.length) {
        _revealed = widget.children.length;
      }
      return;
    }
    if (_timer != null || _revealed >= widget.children.length) return;
    _timer = Timer(_revealed == 0 ? widget.firstBeat : widget.beat, () {
      _timer = null;
      if (!mounted) return;
      setState(() => _revealed++);
      widget.onRevealed?.call();
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pending = _revealed < widget.children.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < _revealed; i++)
          // Keyed by position so an already-revealed turn keeps its state and
          // does not replay its entrance when the list grows beneath it.
          KeyedSubtree(
            key: ValueKey<int>(i),
            child: Entrance(child: widget.children[i]),
          ),
        if (pending && widget.showTyping) const TypingIndicator(),
      ],
    );
  }
}
