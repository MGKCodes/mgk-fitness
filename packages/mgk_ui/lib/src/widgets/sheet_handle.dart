import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';

/// The grab bar at the top of a bottom sheet.
///
/// **It is the only thing on a sheet that says the sheet can be dismissed.** A
/// sheet closes on a downward drag or a tap on the scrim, and neither gesture
/// is discoverable on its own — the handle is what tells you they are there.
///
/// This exists as a component because the suite had five hand-written copies of
/// the same eight lines and two sheets with none. The copies had already
/// drifted: Lift drew the bar in [AppColors.textTertiary] and Run in
/// [AppColors.elevated], which on a `surface` card is nearly invisible. The two
/// without one were the photo-source picker and the progress-photo actions —
/// and the second is the worst place in the app to omit it, because its most
/// prominent control is a red `Delete photo` and a mistap lands you there with
/// nothing on screen offering a way out.
///
/// `textTertiary` won because this is a control, not a divider, and it has to
/// be seen to do its job.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key, this.bottomSpacing = AppSpacing.md});

  /// Gap between the handle and whatever follows it. A sheet with a section
  /// label under it wants less room than one opening straight onto a list.
  final double bottomSpacing;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.textTertiary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
      SizedBox(height: bottomSpacing),
    ],
  );
}
