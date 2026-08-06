import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// A movement's form illustration, treated to belong here.
///
/// The source images are **black line art on white** — fine in Liftio, which
/// had a light theme, and wrong in a suite whose whole visual identity is
/// greyscale on charcoal (ADR-0009). Dropped in untreated they read as bright
/// cut-outs punched into the page, and the eye goes to them instead of to the
/// numbers, which are the thing a lifter is here for.
///
/// Inverting fixes it exactly: line art has no colour to lose, so white-on-dark
/// is the same drawing with the polarity flipped. It costs one matrix and keeps
/// the images useful rather than dropping all 522 of them for looking wrong.
///
/// Note this is a **render-time** filter: the files on disk are untouched, so
/// nothing here changes what the assets are or where they came from.
class ExerciseThumb extends StatelessWidget {
  const ExerciseThumb({super.key, this.asset, this.size = 52});

  /// Null for a movement the lifter typed themselves — a first-class case, not
  /// a missing image.
  final String? asset;

  final double size;

  /// Flips black-on-white to white-on-black. Alpha is untouched, so the corner
  /// radius still clips cleanly.
  static const ColorFilter _invert = ColorFilter.matrix(<double>[
    -1, 0, 0, 0, 255, //
    0, -1, 0, 0, 255, //
    0, 0, -1, 0, 255, //
    0, 0, 0, 1, 0, //
  ]);

  @override
  Widget build(BuildContext context) {
    final path = asset;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: SizedBox(
        width: size,
        height: size,
        child: path == null
            ? _placeholder(size)
            : ColoredBox(
                color: AppColors.bg,
                child: ColorFiltered(
                  colorFilter: _invert,
                  child: Image.asset(
                    path,
                    fit: BoxFit.cover,
                    // A missing image must never take a card down — the name is
                    // the content and the picture is the affordance.
                    errorBuilder: (_, _, _) => _placeholder(size),
                  ),
                ),
              ),
      ),
    );
  }

  static Widget _placeholder(double size) => ColoredBox(
    color: AppColors.elevated,
    child: Icon(
      Icons.fitness_center,
      size: size * 0.38,
      color: AppColors.textTertiary,
    ),
  );
}
