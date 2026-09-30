import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// Restore purchases.
///
/// **Guideline 3.1.1 requires this of any app selling a subscription**, and it
/// is checked mechanically rather than judged — so its absence is a rejection
/// rather than a risk. It was missing from this app entirely until 2026-09-02,
/// and missing from the release plan too: Phase 3 mentioned restoring only as a
/// *sandbox test step*, which quietly assumed a button nobody had built.
///
/// It earns its place beyond compliance. Somebody reinstalling, or signing in
/// on a second device, has no other route back to what they paid for.
///
/// Lives here rather than in `mgk_ui` because run has no payments to restore.
/// It moves when that stops being true, not before.
class RestorePurchasesButton extends StatefulWidget {
  const RestorePurchasesButton({super.key, required this.onRestore});

  /// Null hides the button, on the rule this app applies everywhere else: an
  /// affordance with nothing behind it is worse than no affordance. A build
  /// with no store cannot restore anything, and should not offer to.
  final Future<void> Function()? onRestore;

  @override
  State<RestorePurchasesButton> createState() => _RestorePurchasesButtonState();
}

class _RestorePurchasesButtonState extends State<RestorePurchasesButton> {
  bool _busy = false;

  Future<void> _run() async {
    final onRestore = widget.onRestore;
    if (onRestore == null || _busy) return;
    setState(() => _busy = true);
    try {
      await onRestore();
    } finally {
      // A restore that fails still has to give the button back, or the only
      // way to try again is to relaunch.
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onRestore == null) return const SizedBox.shrink();

    // The press feel without AppTextButton, whose busy state keeps the label:
    // this one swaps it for a spinner the size of the text.
    return PressScale(
      enabled: !_busy,
      scale: 0.98,
      child: TextButton(
        onPressed: _busy ? null : _run,
        child: _busy
            // Sized to the text it replaces, so the row does not jump and the
            // layout around it does not reflow mid-tap.
            ? const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                'Restore purchases',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.textTertiary,
                ),
              ),
      ),
    );
  }
}
