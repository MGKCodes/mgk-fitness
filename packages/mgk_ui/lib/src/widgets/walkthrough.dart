/// A walkthrough over the real app: one control at a time, lit through a
/// dimmed screen, with the coach saying what it is for beside it.
///
/// **Over the app itself, not a picture of it.** Lift's owner looked at a first
/// open made of the coach's lines on a screen of their own (29 October 2026)
/// and asked instead for "a walkthrough in the UI ... a full run through where
/// it takes you through the app". So nothing here draws a screen: the app is
/// running underneath, on its real tabs with its real controls, and this lays
/// a veil over it with a hole cut where the control being talked about is.
///
/// Three pieces, so an app can point at its own controls without this package
/// knowing what they are:
///
/// - [WalkthroughTarget] marks a widget as something a step can point at, by
///   an id the app chooses. With no [WalkthroughScope] above it, it is
///   nothing: the child, unwrapped, which is every screen the walkthrough is
///   not running over.
/// - [WalkthroughTargets] is where they are kept, and answers where one is on
///   screen **now**, measured after layout. A step names a control, never a
///   position, so the hole follows the layout as it is: another phone's
///   width, a larger text size, a tab sliding in.
/// - [WalkthroughOverlay] is the veil, the hole and the card, driven by
///   whatever app code sequences the steps.
///
/// **No package.** A veil with a hole is a path filled even-odd, and a hole a
/// finger can reach through is a hit test that declines inside it; both are a
/// few lines, and in the suite's greys rather than a tour library's palette.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../motion/app_motion.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import 'app_buttons.dart';
import 'coach_mark.dart';

/// The controls a walkthrough can point at, by id.
///
/// One instance per walkthrough host, handed down by a [WalkthroughScope].
/// Each [WalkthroughTarget] under that scope registers itself here while it
/// is mounted and has an id.
class WalkthroughTargets {
  final Map<Object, Set<_WalkthroughTargetState>> _byId =
      <Object, Set<_WalkthroughTargetState>>{};

  void _add(Object id, _WalkthroughTargetState target) =>
      (_byId[id] ??= <_WalkthroughTargetState>{}).add(target);

  void _remove(Object id, _WalkthroughTargetState target) {
    final Set<_WalkthroughTargetState>? targets = _byId[id];
    if (targets == null) return;
    targets.remove(target);
    if (targets.isEmpty) _byId.remove(id);
  }

  /// Where [id] is drawn now, in global coordinates, or null when nothing
  /// registered as [id] is showing.
  ///
  /// **Showing** means mounted, laid out, on the route at the top of its
  /// navigator, and not inside an [Offstage] that is hiding it: a tab kept
  /// alive behind the one on screen still has a size and a position, and a
  /// hole cut there would point at nothing. With several showing (one tick
  /// per set, say) the one highest on screen, then furthest left, answers:
  /// the first a reader would reach.
  Rect? rectOf(Object id) => _showing(id)?.rect;

  /// The widget [id] names, where it is showing, for scrolling it into view.
  BuildContext? contextOf(Object id) => _showing(id)?.context;

  ({BuildContext context, Rect rect})? _showing(Object id) {
    ({BuildContext context, Rect rect})? best;
    for (final _WalkthroughTargetState target
        in _byId[id] ?? const <_WalkthroughTargetState>{}) {
      final Rect? rect = target._rect();
      if (rect == null) continue;
      final ({BuildContext context, Rect rect})? so = best;
      if (so == null ||
          rect.top < so.rect.top - 0.5 ||
          ((rect.top - so.rect.top).abs() <= 0.5 && rect.left < so.rect.left)) {
        best = (context: target.context, rect: rect);
      }
    }
    return best;
  }
}

/// Hands [targets] to the [WalkthroughTarget]s below it.
///
/// A route pushed from inside the scope is not below it (routes are siblings
/// in the navigator's overlay), so a walkthrough that opens a screen of its
/// own wraps that screen in another scope with the same [targets].
class WalkthroughScope extends InheritedWidget {
  const WalkthroughScope({
    super.key,
    required this.targets,
    required super.child,
  });

  final WalkthroughTargets targets;

  /// The nearest scope's targets, or null with none above [context].
  static WalkthroughTargets? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WalkthroughScope>()?.targets;

  @override
  bool updateShouldNotify(WalkthroughScope oldWidget) =>
      !identical(targets, oldWidget.targets);
}

/// Marks [child] as something a walkthrough step can point at.
///
/// **Always in the tree, even when it points at nothing.** A null [id] still
/// builds this widget, so a control whose id comes and goes (the tick of
/// whichever set is next) keeps its element and its state when it does.
/// Wrapping and unwrapping would rebuild the control under it from scratch,
/// animations and all.
///
/// Draws nothing and changes nothing: it returns [child] as given, and costs
/// a map entry while a [WalkthroughScope] is above it.
class WalkthroughTarget extends StatefulWidget {
  const WalkthroughTarget({super.key, required this.id, required this.child});

  /// What a step calls this. Null registers nothing.
  final Object? id;

  final Widget child;

  @override
  State<WalkthroughTarget> createState() => _WalkthroughTargetState();
}

class _WalkthroughTargetState extends State<WalkthroughTarget> {
  WalkthroughTargets? _targets;
  Object? _id;

  /// The route this is drawn on, so a control on a route covered by another
  /// is not taken for one on screen.
  ModalRoute<Object?>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _register(WalkthroughScope.maybeOf(context), widget.id);
  }

  @override
  void didUpdateWidget(WalkthroughTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) _register(_targets, widget.id);
  }

  @override
  void dispose() {
    _register(null, null);
    super.dispose();
  }

  void _register(WalkthroughTargets? targets, Object? id) {
    if (identical(targets, _targets) && id == _id) return;
    final Object? was = _id;
    if (was != null) _targets?._remove(was, this);
    _targets = targets;
    _id = id;
    if (id != null) targets?._add(id, this);
  }

  /// Where this is on screen, or null when it is not showing. See
  /// [WalkthroughTargets.rectOf].
  Rect? _rect() {
    if (!mounted) return null;
    final ModalRoute<Object?>? route = _route;
    if (route != null && !route.isCurrent) return null;
    final RenderObject? box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    if (box.size.isEmpty) return null;
    for (RenderObject? node = box; node != null; node = node.parent) {
      if (node is RenderOffstage && node.offstage) return null;
    }
    return MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// One step, as the overlay draws it.
@immutable
class WalkthroughFrame {
  const WalkthroughFrame({
    required this.line,
    this.target,
    this.interactive = false,
    this.next = 'Next',
    this.skip = 'Skip',
  });

  /// What the coach says.
  final String line;

  /// The [WalkthroughTarget.id] to light. Null lights nothing: the card sits
  /// in the middle of a veiled screen, saying something about the whole of it.
  final Object? target;

  /// Whether the lit control takes a tap. Everything else on screen is behind
  /// the veil and takes none, here as on every step; this lets one control
  /// through, for a step that wants it done once for real.
  final bool interactive;

  /// The card's button.
  final String next;

  /// The card's way out. **Null draws none**, for a last step whose own button
  /// is the way out.
  final String? skip;
}

/// The veil, the hole and the coach's card, over everything under it.
///
/// Meant for an [OverlayEntry] in the root overlay, which keeps it above every
/// route pushed after it. It holds no sequence of its own: [frame] says what
/// to draw, and null is the moment between two steps, when the veil stays up,
/// the last hole stays lit and the card is gone.
///
/// **It takes every tap.** Nothing under the veil can be reached, except the
/// lit control on an [WalkthroughFrame.interactive] step; and nothing under
/// it can be reached by a screen reader either, which hears each step's line
/// as it arrives and finds the card's two buttons. The hole is measured after
/// every frame the app draws (and only then: nothing here keeps the screen
/// awake), so it follows its control wherever layout takes it.
class WalkthroughOverlay extends StatefulWidget {
  const WalkthroughOverlay({
    super.key,
    required this.targets,
    required this.frame,
    required this.onNext,
    required this.onSkip,
  });

  final WalkthroughTargets targets;
  final ValueListenable<WalkthroughFrame?> frame;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  State<WalkthroughOverlay> createState() => _WalkthroughOverlayState();
}

class _WalkthroughOverlayState extends State<WalkthroughOverlay>
    with SingleTickerProviderStateMixin {
  /// The step on screen, or null between two.
  WalkthroughFrame? _shown;

  /// The target the hole follows: the step's, and between two steps the last
  /// one's, so the hole does not close and reopen on the same control.
  Object? _following;

  /// Where [_following] is, in this overlay's coordinates.
  Rect? _hole;

  bool _measuring = false;

  /// The hole as drawn, on its way from where it was to [_hole]: it moves
  /// from one control to the next rather than jumping, opens from the
  /// control's centre and closes into it.
  late final AnimationController _move = AnimationController(
    vsync: this,
    duration: AppMotion.base,
    value: 1,
  );
  late final Animation<double> _moving = CurvedAnimation(
    parent: _move,
    curve: AppMotion.entrance,
  );
  final _HoleTween _drawn = _HoleTween();

  /// Room around a control inside the hole, so its edge is not the veil's.
  static const double _pad = 6;

  @override
  void initState() {
    super.initState();
    widget.frame.addListener(_onFrame);
    _shown = widget.frame.value;
    _following = _shown?.target;
    _measureAfterEveryFrame();
  }

  @override
  void didUpdateWidget(WalkthroughOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.frame != widget.frame) {
      oldWidget.frame.removeListener(_onFrame);
      widget.frame.addListener(_onFrame);
      _onFrame();
    }
  }

  @override
  void dispose() {
    widget.frame.removeListener(_onFrame);
    _move.dispose();
    super.dispose();
  }

  void _onFrame() {
    final WalkthroughFrame? frame = widget.frame.value;
    setState(() {
      _shown = frame;
      if (frame != null) _following = frame.target;
    });
    if (frame != null) _announce(frame.line);
    _measure();
  }

  /// Says the line where the platform takes an announcement (iOS). Android
  /// has retired announcements, and hears the card's live region instead.
  void _announce(String line) {
    if (!MediaQuery.supportsAnnounceOf(context)) return;
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        line,
        Directionality.of(context),
      ),
    );
  }

  /// After each frame the app draws, and never otherwise: a post-frame
  /// callback schedules no frame of its own, so an app at rest stays at rest
  /// and a test's `pumpAndSettle` settles. Anything that moves the control
  /// draws frames, and each one is measured.
  void _measureAfterEveryFrame() {
    if (_measuring) return;
    _measuring = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _measuring = false;
      if (!mounted) return;
      _measure();
      _measureAfterEveryFrame();
    });
  }

  void _measure() {
    if (!mounted) return;
    final Object? id = _following;
    Rect? rect = id == null ? null : widget.targets.rectOf(id);
    final RenderObject? self = context.findRenderObject();
    if (rect != null && self is RenderBox && self.hasSize) {
      rect = rect.shift(-self.localToGlobal(Offset.zero));
    }
    if (_same(rect, _hole)) return;
    setState(() => _hole = rect);
    _aim(rect?.inflate(_pad));
  }

  /// Sends the drawn hole to [to] from wherever it is now.
  void _aim(Rect? to) {
    _drawn
      ..begin = _drawn.evaluate(_moving)
      ..end = to;
    final bool still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _move.value = 1;
    } else {
      _move.forward(from: 0);
    }
  }

  static bool _same(Rect? a, Rect? b) {
    if (a == null || b == null) return a == b;
    return (a.left - b.left).abs() < 0.5 &&
        (a.top - b.top).abs() < 0.5 &&
        (a.right - b.right).abs() < 0.5 &&
        (a.bottom - b.bottom).abs() < 0.5;
  }

  @override
  Widget build(BuildContext context) {
    final bool still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final WalkthroughFrame? frame = _shown;
    final Rect? hole = _hole?.inflate(_pad);
    final EdgeInsets padding = MediaQuery.paddingOf(context);

    // Everything painted before this drops out for a screen reader, as it
    // does under a dialog's barrier: what is behind the veil cannot be
    // reached by touch, so it must not be reachable by a double tap either.
    return BlockSemantics(
      child: _Barrier(
        letThrough: frame != null && frame.interactive ? hole : null,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: still ? Duration.zero : AppMotion.base,
          curve: AppMotion.entrance,
          builder: (context, shown, child) =>
              Opacity(opacity: shown, child: child),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ExcludeSemantics(
                child: AnimatedBuilder(
                  animation: _moving,
                  builder: (context, _) => CustomPaint(
                    painter: _Veil(hole: _drawn.evaluate(_moving)),
                  ),
                ),
              ),
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: still ? Duration.zero : AppMotion.fast,
                  switchInCurve: AppMotion.entrance,
                  switchOutCurve: AppMotion.exit,
                  layoutBuilder: (current, previous) => Stack(
                    fit: StackFit.expand,
                    children: <Widget>[...previous, ?current],
                  ),
                  child: frame == null
                      ? const SizedBox.shrink(key: ValueKey<String>('between'))
                      : CustomSingleChildLayout(
                          key: ObjectKey(frame),
                          delegate: _CardPlacement(
                            hole: hole,
                            padding: padding,
                          ),
                          child: _Card(
                            frame: frame,
                            onNext: widget.onNext,
                            onSkip: widget.onSkip,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The coach's card: the small C, the line, and the step's buttons.
class _Card extends StatelessWidget {
  const _Card({
    required this.frame,
    required this.onNext,
    required this.onSkip,
  });

  final WalkthroughFrame frame;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final String? skip = frame.skip;
    // A live region, so TalkBack reads each step's line as the card changes;
    // a container, so the line and its buttons are one place to land on.
    return Semantics(
      container: true,
      liveRegion: true,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardAll,
          side: const BorderSide(color: AppColors.elevated),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Scrolls rather than overflows: at the largest text sizes a
              // line can be taller than the room the step leaves it.
              Flexible(
                child: SingleChildScrollView(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Padding(
                        padding: EdgeInsets.only(top: 1),
                        child: CoachAvatar(),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          frame.line,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              // Side by side while they fit, stacked when a large text size
              // makes them not.
              OverflowBar(
                alignment: skip == null
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.spaceBetween,
                overflowAlignment: OverflowBarAlignment.end,
                children: <Widget>[
                  if (skip != null)
                    AppTextButton(
                      label: skip,
                      onPressed: onSkip,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                      ),
                    ),
                  AppFilledButton(label: frame.next, onPressed: onNext),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Puts the card beside the hole: under it when the hole is in the top half
/// of the screen, over it in the bottom half, on whichever side has room when
/// the preferred one has none, and in the middle when there is no hole.
class _CardPlacement extends SingleChildLayoutDelegate {
  const _CardPlacement({required this.hole, required this.padding});

  final Rect? hole;
  final EdgeInsets padding;

  static const double _margin = AppSpacing.lg;
  static const double _gap = AppSpacing.md;

  /// A tablet's card is a phone's card, not a banner across the screen.
  static const double _maxWidth = 420;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final double width = math.max(
      0,
      math.min(constraints.maxWidth - _margin * 2, _maxWidth),
    );
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: math.max(
        0,
        constraints.maxHeight - padding.vertical - _margin * 2,
      ),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final double left = (size.width - childSize.width) / 2;
    final double top = padding.top + _margin;
    final double bottom = size.height - padding.bottom - _margin;
    final Rect? lit = hole;
    double y;
    if (lit == null) {
      y = (size.height - childSize.height) / 2;
    } else {
      final double above = lit.top - _gap - childSize.height;
      final double below = lit.bottom + _gap;
      final bool roomAbove = above >= top;
      final bool roomBelow = below + childSize.height <= bottom;
      final bool lower = lit.center.dy > size.height / 2;
      y = lower
          ? (roomAbove || !roomBelow ? above : below)
          : (roomBelow || !roomAbove ? below : above);
    }
    final double lowest = math.max(top, bottom - childSize.height);
    return Offset(left, y.clamp(top, lowest));
  }

  @override
  bool shouldRelayout(_CardPlacement oldDelegate) =>
      hole != oldDelegate.hole || padding != oldDelegate.padding;
}

/// Grows a hole from its own centre, and closes one into it, rather than
/// from the screen's corner, which is where [Rect.lerp] starts from nothing.
class _HoleTween extends Tween<Rect?> {
  _HoleTween();

  @override
  Rect? lerp(double t) {
    final Rect? from = begin;
    final Rect? to = end;
    if (from == null && to == null) return null;
    if (from == null) {
      return Rect.lerp(
        Rect.fromCenter(center: to!.center, width: 0, height: 0),
        to,
        t,
      );
    }
    if (to == null) {
      if (t >= 1) return null;
      return Rect.lerp(
        from,
        Rect.fromCenter(center: from.center, width: 0, height: 0),
        t,
      );
    }
    return Rect.lerp(from, to, t);
  }
}

/// The veil, with the hole cut out of it and a hairline round the hole.
class _Veil extends CustomPainter {
  const _Veil({required this.hole});

  final Rect? hole;

  /// The app's own ground, most of the way to opaque: the screen behind is
  /// still there to be recognised, and the lit control is the only thing at
  /// full strength.
  static final Color _veil = AppColors.bg.withValues(alpha: 0.82);
  static final Color _edge = AppColors.textPrimary.withValues(alpha: 0.5);

  @override
  void paint(Canvas canvas, Size size) {
    final Rect screen = Offset.zero & size;
    final Paint veil = Paint()..color = _veil;
    final Rect? lit = hole;
    if (lit == null || lit.isEmpty) {
      canvas.drawRect(screen, veil);
      return;
    }
    final RRect cut = RRect.fromRectAndRadius(
      lit,
      Radius.circular(math.min(AppRadius.card, lit.shortestSide / 2)),
    );
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(screen)
        ..addRRect(cut),
      veil,
    );
    canvas.drawRRect(
      cut,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = _edge,
    );
  }

  /// Paint only: the [_Barrier] decides what a tap reaches.
  @override
  bool? hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_Veil oldDelegate) => hole != oldDelegate.hole;
}

/// Takes every tap that lands on it, except one inside [letThrough], which it
/// declines so the overlay passes it to whatever is drawn underneath.
class _Barrier extends SingleChildRenderObjectWidget {
  const _Barrier({required this.letThrough, super.child});

  final Rect? letThrough;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBarrier(letThrough);

  @override
  void updateRenderObject(BuildContext context, _RenderBarrier renderObject) {
    renderObject.letThrough = letThrough;
  }
}

class _RenderBarrier extends RenderProxyBox {
  _RenderBarrier(this.letThrough);

  Rect? letThrough;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    // The card first, wherever it is: its buttons win even over the hole.
    if (hitTestChildren(result, position: position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    final Rect? hole = letThrough;
    if (hole != null && hole.contains(position)) return false;
    // Claimed, and handled by nothing: the tap stops here.
    result.add(BoxHitTestEntry(this, position));
    return true;
  }
}
