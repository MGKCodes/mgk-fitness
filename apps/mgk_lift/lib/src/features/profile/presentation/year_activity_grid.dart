import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../../stats/domain/activity_window.dart';

/// A year of training, one square per day.
///
/// Ported from Liftio's `YearActivityGrid`, which sat at the top of its log
/// tab. The arithmetic — the rolling window, the median/95th-percentile
/// thresholds, where the month labels land — is in [ActivityWindow]; this file
/// is only the drawing. That split is the point: the shading rule is the part
/// worth being sure about, and in Liftio it could only be checked by squinting
/// at a screenshot.
///
/// ## It lives in Lift
///
/// A candidate for `mgk_ui` on the face of it, and deliberately not there. Run
/// has no surface that shows one square per day, so a shared version would be a
/// component with one caller, designed against one app's needs and then bent
/// when the second one arrived. [ActivityWindow] already takes the app-neutral
/// step — it is a list of days and a shade, not a list of sessions — so the day
/// Run wants a year grid, moving this is a file move rather than a rewrite.
///
/// ## Painted, not built
///
/// 364 squares is 364 render objects if each is a widget, rebuilt every time
/// Profile rebuilds — which it does on a tab switch and on a unit change. One
/// [CustomPaint] draws the same thing. It also lets the squares take a
/// fractional width: 52 columns rarely divide a phone evenly, and rounding each
/// square to a whole pixel accumulates into a grid that stops short of the card
/// edge.
class YearActivityGrid extends StatelessWidget {
  const YearActivityGrid({super.key, required this.window});

  final ActivityWindow window;

  /// Liftio's `SQUARE_GAP`. Not an [AppSpacing] step, and should not be: this
  /// is the hairline between two 4pt squares, an order of magnitude below the
  /// scale that governs the gaps between things a lifter reads.
  static const double _gap = 2;

  /// Room for the month row above the squares.
  static const double _monthLabelHeight = 14;

  /// Roughly how wide a three-letter month label sets at [_monthLabelSize].
  /// Used to drop a label that would run past the right edge — a month clipped
  /// to `AU` reads as a rendering fault rather than as a label.
  static const double _monthLabelWidth = 24;

  static const double _monthLabelSize = 9;

  /// Five shades, evenly spread. Liftio's ramp, kept: below 40% the lightest
  /// trained day is hard to tell from a rest day on a phone in a gym.
  static const List<double> tierOpacities = <double>[0.40, 0.55, 0.70, 0.85, 1];

  /// What colour a square is, or null for a square that is not drawn at all.
  ///
  /// Separate from the painter so it can be asserted directly. Liftio's white
  /// at an opacity, expressed as the token that white already is.
  static Color? cellColour(ActivityDay day) {
    if (day.isFuture) return null;
    final tier = day.tier;
    if (tier == null) return AppColors.elevated;
    return AppColors.textPrimary.withValues(alpha: tierOpacities[tier]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trained = window.trainedDays;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final width = constraints.maxWidth;
              final cell = (width - (window.weeks - 1) * _gap) / window.weeks;
              final pitch = cell + _gap;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    height: _monthLabelHeight,
                    width: width,
                    child: Stack(
                      children: <Widget>[
                        for (final label in window.monthLabels)
                          if (label.week * pitch <= width - _monthLabelWidth)
                            Positioned(
                              left: label.week * pitch,
                              top: 0,
                              child: Text(
                                label.label.toUpperCase(),
                                maxLines: 1,
                                softWrap: false,
                                style: const TextStyle(
                                  color: AppColors.textTertiary,
                                  fontSize: _monthLabelSize,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                  height: 1.2,
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Semantics(
                    // The squares themselves carry nothing a screen reader can
                    // read, so the grid announces its summary and stops. The
                    // figures behind it are on this screen as text anyway.
                    label: trained == 0
                        ? 'Activity grid, no days trained in the last year'
                        : 'Activity grid, $trained '
                              'day${trained == 1 ? '' : 's'} trained in the '
                              'last year',
                    excludeSemantics: true,
                    child: SizedBox(
                      width: width,
                      height:
                          cell * ActivityWindow.daysPerWeek +
                          _gap * (ActivityWindow.daysPerWeek - 1),
                      child: CustomPaint(
                        painter: _ActivityPainter(window: window, cell: cell),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            trained == 0
                // Said in the future tense on purpose. An empty grid is what a
                // new lifter sees first, and it should read as a thing waiting
                // to be filled rather than as a year of missed days.
                ? 'Every day you train fills a square.'
                : '$trained day${trained == 1 ? '' : 's'} trained · '
                      'darker is longer',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityPainter extends CustomPainter {
  const _ActivityPainter({required this.window, required this.cell});

  final ActivityWindow window;
  final double cell;

  /// The squares are about 4pt across on a phone, so this is a softened corner
  /// rather than a rounded one — at [AppRadius.chip] a square this size would
  /// be a dot. A paint geometry constant, not a surface style: nothing in the
  /// radius scale is meant to describe something smaller than a character.
  static const double _cornerRadius = 1;

  @override
  void paint(Canvas canvas, Size size) {
    final pitch = cell + YearActivityGrid._gap;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var w = 0; w < window.weeks; w++) {
      for (var d = 0; d < ActivityWindow.daysPerWeek; d++) {
        final colour = YearActivityGrid.cellColour(window.dayAt(w, d));
        // A future day is not drawn at all, rather than drawn transparent —
        // the difference is invisible here and the intent is not.
        if (colour == null) continue;
        paint.color = colour;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * pitch, d * pitch, cell, cell),
            const Radius.circular(_cornerRadius),
          ),
          paint,
        );
      }
    }
  }

  /// Identity on the window rather than a field-by-field compare. Profile folds
  /// a new one out of the log on every build, so a value comparison would walk
  /// 364 days to discover what a rebuild already told us.
  @override
  bool shouldRepaint(_ActivityPainter old) =>
      !identical(old.window, window) || old.cell != cell;
}
