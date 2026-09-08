import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';

/// The mark at rest. Shared with `CoachReveal`, which retracts to exactly this.
const double kCoachMarkSize = 44;

/// Where a rounded square stops looking like a circle. A third of the side,
/// against the card radius's near-70% of one.
const double markRadius = 14;

/// Room the mark needs, including the space its unread dot overhangs into.
const double kCoachMarkExtent = kCoachMarkSize + 8;

/// Room a scrolling tab must leave at its foot so its last row is not tucked
/// under the floating mark.
///
/// Lives here, beside the mark's own size, rather than on the Plan tab that
/// first needed it. The mark floats over **every** tab — that is the whole point
/// of it replacing the dock — so a clearance owned by one tab was a clearance
/// two other tabs did not apply, and Home's last run and Profile's log both ran
/// underneath it.
const double kCoachMarkClearance =
    kCoachMarkSize + AppSpacing.lg * 2 + AppSpacing.md;

/// Room a scrolling tab must leave for **everything** floating at its foot: the
/// nav pill, the gap above it, and the mark stacked above that.
///
/// Replaces [kCoachMarkClearance] at every surface, because since the nav bar
/// started floating (ADR-0033) the mark is no longer the lowest thing down
/// there. Both are kept: the mark's own clearance is still the honest figure
/// for a surface with no nav bar under it, and deleting it would leave the next
/// such surface reaching for this one and over-padding.
///
/// **Does not include the safe-area inset**, which is not a constant — read it
/// with `MediaQuery.paddingOf(context).bottom` at the surface and add it here.
const double kFloatingChromeClearance =
    kNavPillHeight + AppSpacing.md + kCoachMarkExtent + AppSpacing.lg * 2;

/// The way into the conversation, floating over whatever the runner is reading.
///
/// **A letter, not a picture.** The coach is called "Coach", so the mark is a
/// C — the name and the mark are the same thing rather than a metaphor for each
/// other, and it is set in the app's own Inter rather than drawn, which is why
/// it costs no bespoke artwork to own.
///
/// It deliberately is not the sparkle. `Icons.auto_awesome` is on every AI
/// feature shipped in the last three years, and this whole surface has been
/// built to read as a coach rather than as a chatbot bolted to a plan — the
/// week became instructions, the pace became an effort, the confirmation moved
/// into the conversation. Wearing the universal chatbot badge would undo it.
///
/// **A rounded square, not a circle.** A circle bottom-right is Material's
/// signature and would read as someone else's app. The first attempt used the
/// card radius, and rendering it proved the point badly: 18 on a 52px square is
/// 69% of a full circle — close enough that the distinction the shape exists to
/// make was invisible.
class CoachButton extends StatelessWidget {
  const CoachButton({super.key, this.onTap, this.hasUnread = false});

  final VoidCallback? onTap;

  /// Something the coach has noticed and the runner has not seen.
  ///
  /// A dot rather than a count. The coach is not a queue, and a number would
  /// invite the runner to clear it rather than read it.
  final bool hasUnread;

  @override
  Widget build(BuildContext context) => CoachMarkFrame(
    hasUnread: hasUnread,
    child: CoachMarkSurface(
      width: kCoachMarkSize,
      onTap: onTap,
      child: const CoachMarkGlyph(),
    ),
  );
}

/// The box the mark and the reveal both sit in.
///
/// They were built separately and drifted: the reveal closed to a 17.4px C at
/// one offset and the resting mark drew a 19.4px C eight pixels lower, so the
/// hand-off between them jumped. One frame, one glyph, one surface — the swap
/// is invisible because there is nothing left to differ.
class CoachMarkFrame extends StatelessWidget {
  const CoachMarkFrame({
    super.key,
    required this.child,
    this.hasUnread = false,
  });

  final Widget child;
  final bool hasUnread;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: kCoachMarkExtent,
    child: Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomRight,
      children: <Widget>[
        Padding(padding: const EdgeInsets.only(top: 8), child: child),
        if (hasUnread)
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.bg, width: 2),
              ),
            ),
          ),
      ],
    ),
  );
}

/// The C at whatever size the surface needs.
///
/// Extracted so the coach has **one mark**. It used to be a C here and
/// `Icons.auto_awesome` everywhere the coach actually spoke — the chat bubble,
/// the session brief, the note on Home, the standing on Profile — which meant
/// Runio shipped the universal chatbot badge on every surface a runner reads
/// and the considered mark only on the button. Two marks, one coach. This is
/// the one.
class CoachLetter extends StatelessWidget {
  const CoachLetter({
    super.key,
    this.size = 19,
    this.color = AppColors.textPrimary,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    'C',
    style: TextStyle(
      color: color,
      fontSize: size,
      fontWeight: FontWeight.w700,
      height: 1,
      // Inter's C sits fractionally left of its box; at these sizes that reads
      // as a wonky mark rather than as kerning. Scaled so the correction holds
      // at every size rather than only at the button's.
      letterSpacing: size / 19,
    ),
  );
}

/// The C, at one size, so nothing changes when the reveal closes into the mark.
class CoachMarkGlyph extends StatelessWidget {
  const CoachMarkGlyph({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: kCoachMarkSize,
    height: kCoachMarkSize,
    child: Center(child: CoachLetter()),
  );
}

/// The mark's surface: a solid fill and a lit edge, **no blur**.
///
/// It began as `GlassSurface`, and rendering it showed the blur buying almost
/// nothing — the mark lives over the foot of the backdrop where the scrim is
/// densest by design, so there is little behind it to refract, and the gradient
/// edge was doing the lifting on its own. Worse, the reveal animates this
/// surface's width, and re-compositing a `BackdropFilter` every frame is what
/// made the retraction stutter. Dropping it costs no visible quality and buys a
/// smooth animation.
///
/// No drop shadow either — that is the other Material tell.
class CoachMarkSurface extends StatelessWidget {
  const CoachMarkSurface({
    super.key,
    required this.child,
    required this.width,
    this.height = kCoachMarkSize,
    this.onTap,
  });

  final Widget child;
  final double width;

  /// Taller than [kCoachMarkSize] while the reveal is open, since two lines of
  /// speech do not fit in a square.
  final double height;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(markRadius);
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: AppColors.elevated,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: CustomPaint(
            foregroundPainter: _LitEdge(radius: radius),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A gradient stroke, bright where light would catch it and gone by the
/// opposite corner. A uniform border reads as a box; this reads as a bevel, and
/// it is what lifts the mark off the photograph now the blur is gone.
class _LitEdge extends CustomPainter {
  const _LitEdge({required this.radius});

  final BorderRadius radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      radius.toRRect(rect).deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          rect.bottomRight,
          <Color>[
            Colors.white.withValues(alpha: 0.34),
            Colors.white.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0.05),
          ],
          <double>[0, 0.5, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(_LitEdge oldDelegate) => oldDelegate.radius != radius;
}
