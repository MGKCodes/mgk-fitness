import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../motion/app_motion.dart';

/// How far through a fixed set of questions somebody is.
///
/// **Chrome, not conversation.** A coach that says "question two of four" out
/// loud is reading its own progress bar aloud, and it turns a conversation into
/// a form with a friendly voice. The count belongs in the frame around the
/// talking, where it answers "how much longer" without being said.
///
/// Segments rather than a continuous bar, because the questions are countable
/// and few. A bar at 50% invites the reader to work out what half of an unknown
/// total is; four marks with two filled says it exactly.
///
/// Only worth showing for a sequence with a known end. A conversation that
/// could go on indefinitely has no honest progress to report, and inventing one
/// is how a product promises something it cannot deliver.
class StepProgress extends StatelessWidget {
  const StepProgress({
    super.key,
    required this.step,
    required this.total,
    this.width = 18,
  });

  /// 1-based, and clamped: a step past the total draws as complete rather than
  /// overflowing the row.
  final int step;
  final int total;

  /// Each segment's length. Small — this sits beside a label, not across the
  /// screen, and a wide one starts competing with the question being asked.
  final double width;

  @override
  Widget build(BuildContext context) {
    final done = step.clamp(0, total);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < total; i++)
          Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
            child: AnimatedContainer(
              duration: AppMotion.base,
              curve: AppMotion.standard,
              width: width,
              height: 3,
              decoration: BoxDecoration(
                color: i < done ? AppColors.textPrimary : AppColors.elevated,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
      ],
    );
  }
}
