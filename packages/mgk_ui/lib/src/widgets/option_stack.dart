import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';

/// The options the coach offered, one per row.
///
/// Replaces the wrapping chip row. Wrapped, five options broke three-and-two
/// with a hole under the first row, and each one was a different width — so the
/// eye had to find every target separately instead of running down a column.
///
/// **One per row, full width, in the order the coach offered them.** That order
/// is meaningful: the coach puts the likeliest first, and a Wrap reflows it by
/// string length, which quietly reorders the recommendation by how long its
/// words are.
class OptionStack extends StatelessWidget {
  const OptionStack({
    super.key,
    required this.options,
    required this.onSelected,
    this.dense = false,
  });

  final List<String> options;

  /// Given the exact text that was offered — the caller sends that, not a
  /// paraphrase, or the transcript stops matching what was said.
  final ValueChanged<String> onSelected;

  /// Tighter rows, for a stack that has to share the screen with a slider.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final o in options)
          Padding(
            padding: EdgeInsets.only(top: dense ? 6 : 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onSelected(o),
                borderRadius: BorderRadius.circular(AppRadius.control),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: dense ? 11 : 14,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    border: Border.all(color: AppColors.elevated),
                    // A fill as well as an edge. Over glass an outline alone
                    // loses its bottom half against a bright patch of the photo
                    // behind it, and the row stops looking tappable.
                    color: AppColors.surface.withValues(alpha: 0.55),
                  ),
                  child: Text(
                    o,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
