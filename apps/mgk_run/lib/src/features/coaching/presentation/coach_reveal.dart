import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import '../domain/coach_note.dart';

/// How long the reveal takes: arrive, type, hold, retract.
///
/// Long enough to read the line, short enough that it is over before it is in
/// the way.
const Duration kCoachRevealDuration = Duration(milliseconds: 3400);

/// The coach says its piece, then goes back to its corner.
///
/// **Both versions were half right.** The dock had presence and cost 76px of
/// every screen forever; the mark costs 44px and says nothing. A runner opening
/// the tab wants to be told the one thing worth knowing — and then wants their
/// page back. So the mark arrives as a line of speech, types it, holds it long
/// enough to read, and retracts into itself.
///
/// Three rules keep it from becoming the thing everyone turns off:
///
/// **It plays once per observation, not once per visit.** Tied to the same
/// condition as the unread dot: a note the runner has not been shown yet. Open
/// the tab twice and it speaks once.
///
/// **It is skippable and never blocking.** A tap at any point opens the
/// conversation immediately; it sits above the page rather than delaying it,
/// and nothing waits on it.
///
/// **Reduced motion means no motion.** The typing and the retraction are both
/// skipped — the mark is simply there, and the observation is one tap away like
/// any other time.
///
/// It draws the mark from the same [CoachMarkSurface] and [CoachMarkGlyph] the
/// resting button does, so closing into it changes nothing. Built separately,
/// the two drifted — a 17px C at one offset closing into a 19px C eight pixels
/// lower — and the hand-off jumped.
class CoachReveal extends StatefulWidget {
  const CoachReveal({
    super.key,
    required this.note,
    this.locked = false,
    this.onTap,
    this.onFinished,
    this.hasUnread = false,
    this.duration = kCoachRevealDuration,
  });

  /// What the coach has noticed. Null renders the resting mark and nothing
  /// else — there is no such thing as an empty announcement.
  final CoachNote? note;

  /// Whether to play the **locked** line instead, for a runner who has not
  /// bought the coach.
  ///
  /// ## Why this is not filler
  ///
  /// The obvious version of this was a placeholder observation — something
  /// coach-shaped in the bubble so the mark has presence for everybody. It was
  /// rejected, and the reason is written a few lines up in this same file:
  /// the computed note was already at risk of reading as "a machine doing an
  /// impression of noticing", and a line that is *actually* noticing nothing
  /// is that failure on purpose. It would also train runners to ignore the
  /// bubble, which costs the paid line its audience on the day it arrives.
  ///
  /// So the locked state says what it is. It occupies the same bar, moves the
  /// same way and retracts into the same mark — but it is set in
  /// [AppColors.textTertiary] rather than white, and it does **not** type
  /// itself out. Typing is the coach speaking; this is a sign on a door.
  final bool locked;

  /// The line a free runner meets. One place, because the gate sheet says the
  /// same thing at length and two surfaces drifting apart is how a paywall
  /// starts contradicting itself.
  ///
  /// Two lines of detail rather than one, because the bar is a fixed height
  /// sized for the paid note and a single line leaves a visible empty band
  /// under it — which reads as a bubble that failed to load rather than as a
  /// sign. Compare the `coach-locked` and `coach-speaking` plates.
  ///
  /// "buys", not "costs": the gate sheet deliberately quotes no price (the
  /// store does, in the runner's own currency), and promising a figure that the
  /// next screen does not show is a small lie the paywall does not need.
  static const CoachNote lockedNote = CoachNote(
    headline: 'Coaching is a subscription.',
    detail:
        'A plan that moves with you, and a coach reading your training. '
        'Tap to see what it buys.',
  );

  final VoidCallback? onTap;

  /// Fired once the line has been shown, so the caller can record that this
  /// observation has been delivered and not play it again.
  final VoidCallback? onFinished;

  final bool hasUnread;

  /// How long the whole sequence takes. A parameter only so the preview harness
  /// can slow it down enough to inspect a phase — every screenshot at the real
  /// speed lands after it has finished, the same reason `initialTab` exists.
  final Duration duration;

  @override
  State<CoachReveal> createState() => _CoachRevealState();
}

class _CoachRevealState extends State<CoachReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  /// Arrive, type, hold, retract. Typing takes about a fifth of it and the hold
  /// takes half: the point is being read, not being watched being typed.
  static const Interval _arrive = Interval(0, 0.08, curve: AppMotion.entrance);

  /// Eased at both ends. A linear width tween reads as mechanical even when
  /// every frame lands on time, which is most of what "janky" turned out to be.
  static const Interval _retract = Interval(
    0.82,
    1,
    curve: Curves.easeInOutCubic,
  );

  /// How tall the bar is open: a heading, up to two lines under it, and room
  /// to breathe. It retracts to [kCoachMarkSize] square, converging on the mark
  /// from both directions at once.
  static const double _openHeight = 78;

  bool _played = false;
  bool _finished = false;

  /// Told once, whichever route got here. Setting the controller to its end
  /// also completes it, so the reduced-motion path would otherwise report the
  /// observation delivered twice.
  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onFinished?.call();
  }

  @override
  void initState() {
    super.initState();
    _anim.addStatusListener((status) {
      if (status == AnimationStatus.completed) _finish();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybePlay();
  }

  @override
  void didUpdateWidget(CoachReveal old) {
    super.didUpdateWidget(old);
    // The note arrives *after* the first build — the run log is read
    // asynchronously — and `didChangeDependencies` does not fire again for a
    // changed widget. Without this the reveal sat at opacity zero forever,
    // which looks exactly like the mark having been deleted.
    _maybePlay();
  }

  /// What this reveal actually plays: the observation when there is one, the
  /// locked line when the coach has not been bought, and nothing otherwise.
  ///
  /// A real note wins over the locked line so that the two can never race — a
  /// caller that passes both has a bug, and showing the observation is the
  /// half of that bug a paying runner would not notice.
  CoachNote? get _shown =>
      widget.note ?? (widget.locked ? CoachReveal.lockedNote : null);

  void _maybePlay() {
    if (_played || _shown == null) return;
    _played = true;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      // Nothing to watch. The mark is simply there and the note is one tap
      // away, which is what it is for everyone the moment this finishes.
      _anim.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
      return;
    }
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _tap() {
    // Tapping mid-sentence is the runner saying "yes, and?" — take them
    // straight there rather than making them wait for the animation to finish.
    if (_anim.isAnimating) _anim.value = 1;
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final note = _shown;
    if (note == null) {
      // Right-aligned like the open state retracts to. The caller stretches
      // this full width so the line has somewhere to unroll into, which would
      // otherwise leave the resting mark stranded at the far left.
      return Align(
        alignment: Alignment.centerRight,
        child: CoachButton(onTap: widget.onTap, hasUnread: widget.hasUnread),
      );
    }

    // A heading and what follows it, not one run-on line. `CoachNote` already
    // separates the two — "Longest one yet." is the thing, "You went further
    // than you ever have." is why — and setting them at one weight threw that
    // away. It is the same shape the runner sees everywhere else in the app.

    // Measured once, outside the animation. A LayoutBuilder *inside* the
    // builder forced a fresh layout pass every frame, which was the other half
    // of the stutter.
    return LayoutBuilder(
      builder: (context, constraints) {
        final full = constraints.maxWidth;

        // Tall enough for the open bar, bottom-right anchored so it grows
        // upward — growing downward would push it through the tab bar. Sized
        // for the *open* state rather than the resting one: a loosely-fitted
        // Stack child cannot exceed its stack, so a box the height of the mark
        // silently clamped the bar and it never opened past a single line.
        return SizedBox(
          height: _openHeight + 8,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomRight,
            children: <Widget>[
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _anim,
                  // The contents never change shape — only the box around them
                  // does — so they are built once here and reused every frame.
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const SizedBox(
                        width: kCoachMarkSize,
                        height: kCoachMarkSize,
                        child: CoachMarkGlyph(),
                      ),
                      SizedBox(
                        // Clamped, because this crashes the frame otherwise.
                        // `full` comes from the incoming constraints, and a
                        // layout pass that offers zero width — which is what
                        // happens to the tab underneath a full-height modal
                        // sheet — makes this negative. A SizedBox with a
                        // negative width fails an assertion in
                        // BoxConstraints, and the whole route below the sheet
                        // is replaced by the red error screen: found as a red
                        // wash behind the rest-day brief, which is a strange
                        // way to discover a crash.
                        width: (full - kCoachMarkSize - AppSpacing.md).clamp(
                          0.0,
                          double.infinity,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(
                            top: AppSpacing.md,
                            right: AppSpacing.md,
                            bottom: AppSpacing.md,
                          ),
                          child: _TypedNote(
                            note: note,
                            progress: _anim,
                            muted: widget.locked,
                          ),
                        ),
                      ),
                    ],
                  ),
                  builder: (context, child) {
                    final t = _anim.value;
                    final open = 1 - _retract.transform(t);
                    return Opacity(
                      opacity: _arrive.transform(t),
                      child: CoachMarkSurface(
                        width: kCoachMarkSize + (full - kCoachMarkSize) * open,
                        height:
                            kCoachMarkSize +
                            (_openHeight - kCoachMarkSize) * open,
                        onTap: _tap,
                        // Laid out at full size and *clipped* by the shrinking
                        // box. Letting it reflow instead made the line re-wrap
                        // on every frame and stack into a column of single
                        // letters on the way out.
                        child: ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.topLeft,
                            maxWidth: full,
                            maxHeight: _openHeight,
                            child: child,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The observation, appearing a character at a time across both its lines.
///
/// One character budget spanning the heading and the detail, so it reads as one
/// sentence being written rather than as two fields filling in. Its own widget
/// listening to its own animation, so typing rebuilds this and not the bar
/// around it.
class _TypedNote extends StatelessWidget {
  const _TypedNote({
    required this.note,
    required this.progress,
    this.muted = false,
  });

  final CoachNote note;
  final Animation<double> progress;

  /// The locked line: dimmer, and shown whole rather than typed. See
  /// [CoachReveal.locked] for why it does not type.
  final bool muted;

  /// Quick. Slow typing is a novelty the first time and an obstacle every time
  /// after, and the runner came here for the sentence rather than the effect.
  static const Interval _type = Interval(0.08, 0.30, curve: Curves.linear);
  static const Interval _fade = Interval(0.82, 0.93, curve: Curves.easeOut);

  @override
  Widget build(BuildContext context) {
    final headline = note.headline;
    final detail = note.detail;
    // The space between them counts, so the detail does not begin the instant
    // the heading ends.
    final total = headline.length + 1 + detail.length;

    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) {
        final t = progress.value;
        // Whole from the first frame when muted — a sign does not write itself.
        final shown = muted ? total : (total * _type.transform(t)).round();

        return Opacity(
          // Gone before the box finishes closing, so the last thing seen is the
          // mark rather than a half-letter.
          opacity: 1 - _fade.transform(t),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                headline.substring(0, shown.clamp(0, headline.length)),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  color: muted ? AppColors.textTertiary : AppColors.textPrimary,
                  fontSize: 14,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail.substring(
                  0,
                  (shown - headline.length - 1).clamp(0, detail.length),
                ),
                maxLines: 2,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  color: muted
                      ? AppColors.textTertiary
                      : AppColors.textSecondary,
                  fontSize: 12.5,
                  height: 1.3,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
