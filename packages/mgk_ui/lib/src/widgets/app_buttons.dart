import 'package:flutter/material.dart';

import '../motion/press_scale.dart';

/// The quiet controls — the ones that are offered rather than urged.
///
/// ## Why these exist at all
///
/// Material's own buttons acknowledge a tap through `Feedback.forTap`, which
/// branches on the platform: Android gets a haptic, **iOS gets nothing at all**.
/// So an app built from raw `TextButton`s and `IconButton`s feels different
/// depending on which phone it is running on, and the silent one is the target
/// this suite ships to first.
///
/// [PrimaryButton] and [AppCard] already solve that by going through
/// [PressScale], which calls the engine directly and does not care what platform
/// it is on. These are the same answer for the two controls that make up most of
/// the rest of the app: a cancel, a "not this time", a close, a back arrow.
///
/// They are deliberately thin. Anything Material's button can do that these
/// cannot is a sign the control wants to be a [PrimaryButton] instead — which
/// is usually the right answer anyway.
class AppTextButton extends StatelessWidget {
  const AppTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.style,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Passed straight through. A handful of call sites tint or resize a quiet
  /// control, and those overrides are deliberate — this exists to add the
  /// acknowledgement, not to take away the styling that was already there.
  final ButtonStyle? style;

  /// Disables the control and its acknowledgement together. A thing that
  /// springs under the finger and then does nothing is worse than one that sits
  /// still.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = !busy && onPressed != null;
    return PressScale(
      enabled: enabled,
      // Less travel than the primary's. These sit inline beside other text, and
      // a quiet control that lurches is no longer quiet.
      scale: 0.98,
      child: TextButton(
        onPressed: busy ? null : onPressed,
        style: style,
        child: Text(label),
      ),
    );
  }
}

/// An icon on its own — a close, a back, a refresh.
///
/// [tooltip] is required rather than optional. An icon with no label is the one
/// control that cannot explain itself, so the accessible name is not a nicety
/// here; leaving it off ships a button a screen reader announces as nothing.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.size,
    this.color,
    this.visualDensity,
    this.padding,
    this.constraints,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final double? size;

  /// Passed straight through, for the same reason [AppTextButton.style] is.
  final Color? color;

  /// Also passed straight through, and for the same reason — these three
  /// arrived when Lift's controls were converted. A row of three icons in a
  /// card header is laid out at `VisualDensity.compact` with a hand-set hit
  /// box, and without a way to say so the conversion would have had to choose
  /// between the acknowledgement and the layout. That is a false choice: the
  /// point of these wrappers is to *add* the press feel, not to relitigate
  /// spacing that was already deliberate.
  final VisualDensity? visualDensity;

  final EdgeInsetsGeometry? padding;

  final BoxConstraints? constraints;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      enabled: onPressed != null,
      // Tighter still. An icon button is small, so the same fraction that reads
      // as a settle on a full-width button reads as a twitch here.
      scale: 0.9,
      child: IconButton(
        icon: Icon(icon, size: size),
        tooltip: tooltip,
        color: color,
        visualDensity: visualDensity,
        padding: padding,
        constraints: constraints,
        onPressed: onPressed,
      ),
    );
  }
}
