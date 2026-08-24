import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../domain/rest_timer.dart';

/// The rest countdown, pinned under the session list.
///
/// **A bar, not a dialog.** Rest is the part of a session where the lifter is
/// doing something else — putting plates back, replying to a message, sitting
/// down. A modal countdown would block the log at exactly the moment they might
/// want to fix the reps they just typed, so this takes a strip at the bottom and
/// nothing else. Everything behind it stays live.
///
/// It is also not a phase the app enforces. There is no "rest" mode to leave:
/// tick the next set and the timer restarts, ignore it and it sits there. The
/// clock is information, not a gate.
///
/// **It draws its own shape from `mgk_ui`'s tokens, not from a number.** This
/// bar shipped to TestFlight with no shape at all — a bare `Material` on a
/// square edge — while `AppRadius` sat in the package this file already
/// imports. That is the same defect as the coach mark, and it was found the
/// same way: by looking at it on a phone.
class RestBar extends StatelessWidget {
  const RestBar({
    super.key,
    required this.timer,
    required this.now,
    required this.onAdjust,
    required this.onDismiss,
  });

  final RestTimer timer;

  /// Driven from the screen's existing one-second ticker rather than a second
  /// one here. See [RestTimer] for why the ticker only controls repainting.
  final DateTime now;

  /// Adds or removes rest. Negative shortens.
  final void Function(Duration by) onAdjust;

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = timer.remainingAt(now);
    final done = timer.isDoneAt(now);

    return Material(
      color: AppColors.surface,
      // Top corners only, because it is pinned to the bottom edge — rounding
      // all four would float it off a surface it is attached to. The token
      // rather than a number: `exercise_picker_sheet.dart` already rounds its
      // top by exactly this, and the two rise from the same edge.
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.sheet),
      ),
      // Without this the progress indicator, which is the first child and sits
      // flush with the top edge, keeps its square corners and pokes through the
      // rounding.
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Draining left to right. The number is the precise answer; this is
            // the one you can read without focusing, which is the point when
            // you are mid-rack.
            LinearProgressIndicator(
              value: timer.progressAt(now),
              minHeight: 2,
              backgroundColor: AppColors.elevated,
              valueColor: AlwaysStoppedAnimation<Color>(
                done ? AppColors.success : AppColors.primary,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        SectionLabel(
                          done ? 'Rest over' : 'Resting',
                          emphasis: LabelEmphasis.stat,
                          color: done
                              ? AppColors.success
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          RestTimer.format(remaining),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            // Tabular, or the whole row twitches sideways every
                            // second as the digit widths change.
                            fontFeatures: const <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Hidden once rest is over: adding thirty seconds to a
                  // finished timer is not what anyone means by "+30".
                  if (!done) ...<Widget>[
                    _Adjust(
                      label: '−30s',
                      onTap: () => onAdjust(const Duration(seconds: -30)),
                    ),
                    _Adjust(
                      label: '+30s',
                      onTap: () => onAdjust(const Duration(seconds: 30)),
                    ),
                  ],
                  AppTextButton(
                    label: done ? 'Done' : 'Skip',
                    onPressed: onDismiss,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Adjust extends StatelessWidget {
  const _Adjust({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppTextButton(
    label: label,
    onPressed: onTap,
    style: TextButton.styleFrom(
      foregroundColor: AppColors.textSecondary,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    ),
  );
}
