import 'package:flutter/material.dart';

import '../motion/app_motion.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import 'app_buttons.dart';
import 'glass_surface.dart';

/// The undo and status message, on glass.
///
/// A Material snackbar is a filled bar; this is a pane floating over the
/// screen with the content moving under it — the same material as the bars
/// and the dock, so a message reads as part of the app rather than a system
/// notice. It still rides the [ScaffoldMessenger]: queued, dismissed by a
/// swipe, kept above any bottom bar.
///
/// **The action lives inside the glass,** not in the snackbar's own slot,
/// which sits outside the content. Because it is not a [SnackBarAction], the
/// messenger would not keep the message up for somebody navigating by screen
/// reader — so under accessible navigation it stays longer instead.
abstract final class AppToast {
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> show(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 4),
  }) {
    final messenger = ScaffoldMessenger.of(context);
    final accessible = MediaQuery.maybeAccessibleNavigationOf(context) ?? false;
    messenger.hideCurrentSnackBar();
    return messenger.showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        behavior: SnackBarBehavior.floating,
        duration: accessible ? const Duration(seconds: 12) : duration,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.sheet)),
        ),
        content: _ToastBody(
          message: message,
          actionLabel: actionLabel,
          onAction: onAction == null
              ? null
              : () {
                  messenger.hideCurrentSnackBar(
                    reason: SnackBarClosedReason.action,
                  );
                  onAction();
                },
        ),
      ),
    );
  }
}

class _ToastBody extends StatelessWidget {
  const _ToastBody({required this.message, this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassSurface.dock(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        actionLabel == null ? AppSpacing.lg : AppSpacing.xs,
        AppSpacing.xs,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            if (actionLabel != null && onAction != null)
              AppTextButton(
                label: actionLabel!,
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  textStyle: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A sheet risen from the bottom, on glass: as tall as what is in it, up to
/// [maxHeightFactor] of the screen; inside both safe areas; above the keyboard
/// without climbing under the status bar.
///
/// It replaced solid sheets that were either a fixed 85% of the screen — half
/// empty with three rows in them — or sized to content with no ceiling, and
/// a glass one whose tint sat over the flat charcoal of the screen behind,
/// where glass does nothing (F21). Behind this one is the screen that opened
/// it, dimmed and blurred, which is what the material is for.
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double maxHeightFactor = 0.9,
  bool isDismissible = true,
  bool enableDrag = true,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  isDismissible: isDismissible,
  enableDrag: enableDrag,
  backgroundColor: Colors.transparent,
  elevation: 0,
  barrierColor: Colors.black.withValues(alpha: 0.5),
  sheetAnimationStyle: const AnimationStyle(
    duration: AppMotion.slow,
    curve: AppMotion.gentle,
    reverseDuration: AppMotion.base,
    reverseCurve: AppMotion.exit,
  ),
  builder: (context) {
    final media = MediaQuery.of(context);
    return Padding(
      // The keyboard, when it is up — a search field in the sheet must not be
      // hidden under it.
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: media.size.height * maxHeightFactor,
        ),
        child: GlassSurface.sheet(
          child: SafeArea(top: false, child: builder(context)),
        ),
      ),
    );
  },
);
