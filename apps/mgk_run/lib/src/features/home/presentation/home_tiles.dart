import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';

/// A headed panel — one of the two pieces of furniture Home is built out of,
/// with [HomeStatTile] as the other.
///
/// Home is a **grid of tiles, each carrying one fact** — the shape an iOS home
/// screen widget takes, and the shape asked for. Before this it was a wordmark,
/// one card and two-thirds of a screen of nothing (IMG_4702), which is a poor
/// front page for a plan and a worse one for a runner who has not bought one.
///
/// Both live in the run app rather than in `packages/mgk_ui` only because that
/// package was not open for editing when they were written. Neither knows
/// anything about running, so both are candidates to move up into the design
/// system the next time it is touched — at which point Lift gets a home screen
/// with the same rhythm for free.
///
/// The eyebrow is not optional, and that is the point of having the component:
/// a tile with no heading is the thing that made the old Today card read as two
/// headings and no sentence.
class HomeTile extends StatelessWidget {
  const HomeTile({
    super.key,
    required this.label,
    required this.child,
    this.trailing,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  final String label;
  final Widget child;

  /// Sits opposite the eyebrow — a count, a date, a chevron.
  final Widget? trailing;

  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: SectionLabel(label)),
              ?trailing,
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

/// One square, one number.
///
/// Label at the top, figure at the bottom, a line of context under it. Square
/// because that is what a widget is, and because a row of two squares reads as
/// a pair of facts where two ragged-height cards read as a layout accident.
///
/// **A dash is an absence; a zero is a claim.** [value] takes whatever the
/// caller decided, and [waiting] steps the whole tile back a shade so a
/// placeholder cannot be mistaken for a figure that has gone wrong — the same
/// treatment the Profile tab's lifetime card uses, for the same reason.
class HomeStatTile extends StatelessWidget {
  const HomeStatTile({
    super.key,
    required this.label,
    required this.value,
    required this.caption,
    this.waiting = false,
    this.onTap,
  });

  final String label;
  final String value;

  /// The line under the figure — what it is of, or when it happened. Always
  /// present, and always **two lines' worth of room** whether it needs them or
  /// not: the figure is bottom-anchored, so a caption that wrapped in one tile
  /// and not in its neighbour pushed the two numbers to different heights and
  /// the grid stopped reading as a grid.
  final String caption;

  /// Draws the tile as held open rather than as filled in.
  final bool waiting;

  final VoidCallback? onTap;

  /// Line height for the caption, and the multiplier the reserved two lines are
  /// measured with. One constant so the box and the text cannot drift apart.
  static const double _captionLeading = 1.3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final captionStyle = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.textTertiary,
      height: _captionLeading,
    );

    return AspectRatio(
      aspectRatio: 1,
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionLabel(label, color: waiting ? AppColors.textTertiary : null),
            const Spacer(),
            // Scaled down rather than clipped. A `Text` inside a bounded box
            // clips silently — no overflow stripe — so an imperial pace losing
            // its suffix would simply look like a shorter string.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                softWrap: false,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                  color: waiting ? AppColors.textTertiary : null,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            SizedBox(
              height: (captionStyle?.fontSize ?? 12) * _captionLeading * 2,
              child: Text(
                caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: captionStyle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two tiles side by side, at the grid's gutter.
///
/// A row rather than a `GridView`: Home is one scrolling column and a nested
/// scrollable inside it is a scroll gesture fighting its parent for no gain.
///
/// `CrossAxisAlignment.start`, never `stretch`. A stretched row hands its
/// children a *tight* height taken from its own constraints, and inside a
/// `ListView` that height is infinite — so the row would throw rather than
/// size two squares.
class HomeTileRow extends StatelessWidget {
  const HomeTileRow({super.key, required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: left),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: right),
      ],
    );
  }
}
