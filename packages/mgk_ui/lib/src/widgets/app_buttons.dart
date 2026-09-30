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
    this.icon,
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

  /// A leading icon — `+ Add set`. Optional, because most quiet controls are
  /// words alone; added when Lift's most-tapped control turned out to be a raw
  /// `TextButton.icon` that the first sweep missed, dead under the finger on
  /// iOS.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = !busy && onPressed != null;
    final pressed = busy ? null : onPressed;
    return PressScale(
      enabled: enabled,
      // Less travel than the primary's. These sit inline beside other text, and
      // a quiet control that lurches is no longer quiet.
      scale: 0.98,
      child: icon == null
          ? TextButton(onPressed: pressed, style: style, child: Text(label))
          : TextButton.icon(
              onPressed: pressed,
              style: style,
              icon: Icon(icon, size: 16),
              label: Text(label),
            ),
    );
  }
}

/// A filled button that is not the page's primary — compact, inline, sized to
/// its label. Finish in a session header; the confirm in a dialog.
///
/// [PrimaryButton] is the full-width call to action and already settles under
/// the finger. This is the same fill at the size of its words, and it exists
/// for the reason every wrapper here does: a raw `FilledButton` is silent under
/// the finger on iOS, and in Lift that included Finish — the heaviest decision
/// on the session screen, acknowledged by nothing.
class AppFilledButton extends StatelessWidget {
  const AppFilledButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.style,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  /// Passed straight through, as [AppTextButton.style] is.
  final ButtonStyle? style;

  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final pressed = busy ? null : onPressed;
    final Widget child = busy
        ? const SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(label);
    return PressScale(
      enabled: !busy && onPressed != null,
      child: icon == null
          ? FilledButton(onPressed: pressed, style: style, child: child)
          : FilledButton.icon(
              onPressed: pressed,
              style: style,
              icon: Icon(icon, size: 18),
              label: child,
            ),
    );
  }
}

/// The outlined button — a real action that is not the screen's main one.
/// *Add exercise*, *Your workouts*, *Build one*.
///
/// [expand] makes it full width, the way [PrimaryButton] always is, so the two
/// can sit stacked in one column without their edges disagreeing.
class AppOutlinedButton extends StatelessWidget {
  const AppOutlinedButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.style,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Passed straight through, as [AppTextButton.style] is.
  final ButtonStyle? style;

  final bool expand;

  @override
  Widget build(BuildContext context) {
    final Widget button = icon == null
        ? OutlinedButton(onPressed: onPressed, style: style, child: Text(label))
        : OutlinedButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: 18),
            label: Text(label),
          );
    return PressScale(
      enabled: onPressed != null,
      child: expand ? SizedBox(width: double.infinity, child: button) : button,
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
