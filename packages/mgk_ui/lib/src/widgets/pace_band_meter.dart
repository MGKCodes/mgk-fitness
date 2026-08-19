import 'package:flutter/material.dart';

import '../motion/app_motion.dart';
import '../theme/app_colors.dart';

/// Where the current effort sits inside the band the plan asked for.
///
/// Three states, not a signed delta. A band is what the coaching domain
/// actually prescribes — a single target pace is false precision twice over,
/// since it hangs off a Riegel extrapolation from one time trial and nobody
/// holds a pace to the second into a headwind. "12 seconds too fast" invites a
/// runner to treat a rolling mile as a failure; "inside the band" does not.
enum PaceStanding {
  /// Slower than the band's slow edge.
  under,

  /// Inside the band — what the session asked for.
  inBand,

  /// Faster than the band's fast edge.
  over,

  /// Not enough recent movement to say. The first half-minute of a run, or
  /// standing at a light. An absent verdict, never a wrong one.
  unknown,
}

/// The band, and a marker for where the runner currently is inside it.
///
/// **Greyscale, so the signal is position rather than hue** (ADR-0009): there is
/// no red for "too fast". The band is a lit segment of a darker rail, and the
/// marker slides along it. Being outside the band is legible because the marker
/// is off the lit part, not because it changed colour — which also means it
/// survives being read at arm's length, in sun, by someone who is colourblind.
///
/// [position] is 0..1 across the *rail*, with the band occupying
/// [bandStart]..[bandEnd]. Callers clamp; this widget only draws.
class PaceBandMeter extends StatelessWidget {
  const PaceBandMeter({
    super.key,
    required this.standing,
    required this.position,
    this.slowLabel,
    this.fastLabel,
    this.bandStart = defaultBandStart,
    this.bandEnd = defaultBandEnd,
    this.height = 6,
  });

  /// Where the lit segment sits when the band has two edges.
  ///
  /// Named so a caller that needs to move one edge — a session where the band
  /// is a ceiling rather than a corridor, and everything slower is fine — can
  /// say `bandStart: 0` without restating the other end as a magic number that
  /// then drifts from this one.
  static const double defaultBandStart = 0.32;
  static const double defaultBandEnd = 0.68;

  final PaceStanding standing;

  /// Where the marker sits along the rail, 0 (slowest shown) to 1 (fastest).
  final double position;

  /// The band's two edges, written under the ends of the rail.
  ///
  /// **Without them the meter cannot be read.** A rail with a lit middle and a
  /// dot says nothing about which way is faster, so the verdict underneath ends
  /// up carrying all the meaning and the meter is decoration until somebody is
  /// taught it. Naming the ends is what turns it into a scale. Slow sits left
  /// because a pace gets *smaller* as it gets faster, and a runner reading
  /// left-to-right expects the numbers to fall.
  final String? slowLabel;
  final String? fastLabel;

  /// The lit segment's edges, as fractions of the rail.
  final double bandStart;
  final double bandEnd;

  final double height;

  @override
  Widget build(BuildContext context) {
    // Nothing honest to draw: the rail alone, so the row does not change height
    // when a verdict arrives and the layout under it never jumps.
    final showMarker = standing != PaceStanding.unknown;

    final theme = Theme.of(context);
    final endStyle = theme.textTheme.bodySmall?.copyWith(
      color: AppColors.textTertiary,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final rail = SizedBox(
          height: height * 2,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: <Widget>[
              // The rail — the full range of paces the meter can show.
              Container(
                height: height,
                decoration: BoxDecoration(
                  color: AppColors.elevated,
                  borderRadius: BorderRadius.circular(height / 2),
                ),
              ),
              // The band — what the session asked for.
              Positioned(
                left: width * bandStart,
                width: width * (bandEnd - bandStart),
                child: Container(
                  height: height,
                  decoration: BoxDecoration(
                    color: AppColors.textPrimary.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(height / 2),
                  ),
                ),
              ),
              if (showMarker)
                AnimatedPositioned(
                  duration: AppMotion.base,
                  curve: AppMotion.standard,
                  // Travel is inset by the marker's own width so it stays whole
                  // at both ends — at position 0 a centre-based offset hangs
                  // half the dot off the left edge of the rail.
                  left: (width - height * 2) * position.clamp(0.0, 1.0),
                  child: Container(
                    width: height * 2,
                    height: height * 2,
                    decoration: BoxDecoration(
                      color: AppColors.textPrimary,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.bg, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        );

        if (slowLabel == null && fastLabel == null) return rail;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            rail,
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(slowLabel ?? '', style: endStyle),
                Text(fastLabel ?? '', style: endStyle),
              ],
            ),
          ],
        );
      },
    );
  }
}
