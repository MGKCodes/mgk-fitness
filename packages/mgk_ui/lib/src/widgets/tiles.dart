import 'package:flutter/material.dart';

import '../motion/app_motion.dart';
import '../motion/count_up.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import 'app_card.dart';
import 'glass_surface.dart';
import 'section_label.dart';

/// A headed panel — one of the pieces of furniture a front page is built out
/// of, with [HomeStatTile] and [HeroStatTile] as the others.
///
/// Run's Home is a **grid of tiles, each carrying one fact** — the shape an iOS
/// home screen widget takes, and the shape asked for. Before this it was a
/// wordmark, one card and two-thirds of a screen of nothing (IMG_4702), which
/// is a poor front page for a plan and a worse one for a runner who has not
/// bought one.
///
/// These lived in the run app until 2026-09-30, only because this package was
/// not open for editing when they were written; neither knew anything about
/// running. They moved here when Lift's Track was rebuilt from them (the
/// redesign's R12), so the two front pages share a rhythm. The names are the
/// ones they started with.
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
/// A row rather than a `GridView`: a front page is one scrolling column and a
/// nested scrollable inside it is a scroll gesture fighting its parent for no
/// gain.
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

/// The one number a front page leads with: full width, on glass, big.
///
/// The references Lift's redesign drew on put a single large figure in a wide
/// tile over the photograph ("84 Your Hiking Score"), and that is this. It is
/// glass rather than a card because it sits over the photograph, which is the
/// only place glass has something to show (see [GlassSurface]).
///
/// **One per screen.** Two of these side by side is [HomeTileRow] of
/// [HomeStatTile]s; a big number only reads as the point of the screen when
/// nothing else is set at its size.
class HeroStatTile extends StatelessWidget {
  const HeroStatTile({
    super.key,
    required this.label,
    required this.count,
    this.format = _whole,
    this.suffix,
    this.caption,
    this.onTap,
  });

  /// The eyebrow: `THIS WEEK`.
  final String label;

  /// The figure. Counts up from nothing the first time it is shown, and
  /// tweens between values after, like every other headline figure.
  final double count;

  final String Function(double value) format;

  /// Set small beside the figure: `of 4`. Part of the sentence the figure
  /// starts, so it is secondary ink rather than a unit.
  final String? suffix;

  /// The line under: what the figure counts.
  final String? caption;

  final VoidCallback? onTap;

  static String _whole(double value) => '${value.round()}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const numeral = TextStyle(
      color: AppColors.textPrimary,
      fontSize: 64,
      fontWeight: FontWeight.w200,
      height: 1,
      letterSpacing: -1.5,
      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
    );

    return GlassSurface(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Stretched: glass sizes to its content, and a front page's lead
          // figure is the full width of the page whatever it says.
          const SizedBox(width: double.infinity),
          SectionLabel(label),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              CountUp(
                value: count,
                format: format,
                duration: AppMotion.slow,
                style: numeral,
              ),
              if (suffix != null) ...<Widget>[
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    suffix!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (caption != null) ...<Widget>[
            const SizedBox(height: AppSpacing.xs),
            Text(
              caption!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
