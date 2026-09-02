import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../data/entitlement_repository.dart';
import '../data/purchase_client.dart';
import '../domain/plan_gate_copy.dart';
import 'purchase_screen.dart';

/// What a runner without a subscription gets when they reach for the coach.
///
/// **A door, not an error.** Before
/// [ADR-0030](../../../../docs/decisions/0030-the-coach-is-the-paid-half.md)
/// the app offered the coach to everybody and let the Edge Function refuse,
/// which surfaced as *"The coach hit a problem. Please try again."* — a
/// sentence that is untrue, invites a retry guaranteed to fail, and makes a
/// working paywall look like broken software.
///
/// It says what is free first, because most of the app is: recording, the log,
/// splits, records and the runner's whole history cost nothing and always will
/// ([ADR-0019](../../../../docs/decisions/0019-onboarding-is-two-moments.md)).
/// Leading with the price would misdescribe the product.
///
/// **It quotes no figure.** A price compiled into the binary is right in one
/// storefront and wrong in every other, so the sentence names the tier and
/// [PurchaseScreen] shows what the store says it costs.
///
/// **The way through is conditional, and honestly so.** Given a
/// [PurchaseClient] this offers to open the paywall; without one it says the
/// coach cannot be bought here and stops. A button that cannot take money is
/// worse than no button, because it fails at the moment somebody has decided
/// to pay, which is the worst moment available.
class CoachGateSheet extends StatelessWidget {
  const CoachGateSheet({
    super.key,
    this.purchases,
    this.entitlements,
    this.onUnlocked,
  });

  /// Null in a build with no RevenueCat key, which is a normal state. See
  /// `AppConfig.canSell`.
  final PurchaseClient? purchases;

  /// Needed alongside [purchases]: the paywall waits for the *server* to agree
  /// that the purchase landed before it reports success.
  final EntitlementRepository? entitlements;

  /// Fired when the coach actually came unlocked, so the shell can re-read what
  /// this runner is entitled to rather than assume.
  final VoidCallback? onUnlocked;

  static Future<void> show(
    BuildContext context, {
    PurchaseClient? purchases,
    EntitlementRepository? entitlements,
    VoidCallback? onUnlocked,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CoachGateSheet(
      purchases: purchases,
      entitlements: entitlements,
      onUnlocked: onUnlocked,
    ),
  );

  bool get _canSell => purchases != null && entitlements != null;

  Future<void> _openPaywall(BuildContext context) async {
    final NavigatorState navigator = Navigator.of(context);
    // The sheet closes first. Leaving it under the paywall would put two
    // scrims over the app and strand the runner behind both if the push failed.
    navigator.pop();
    final bool unlocked = await PurchaseScreen.show(
      context,
      purchases: purchases!,
      entitlements: entitlements!,
    );
    if (unlocked) onUnlocked?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // **A surface of its own.** `showModalBottomSheet` is given a transparent
    // background above so the sheet can draw its own corners — which means a
    // child that draws nothing gets no panel at all, only the barrier's dim.
    // This shipped that way: the copy rendered straight over Home, the last
    // run's figures reading through the middle of the price. The board caught
    // it the first time the screen was ever plated. Same solid fill and top
    // radius as the conversation sheet — glass wants something behind it to
    // distort, and behind a sheet is a scrim.
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            bottom: AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.md),
                child: SheetHandle(),
              ),
              Text(
                'The coach is part of the subscription',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                planGateCostsCopy,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (!_canSell) ...<Widget>[
                Text(
                  'Not available to buy in this build yet.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              SizedBox(
                width: double.infinity,
                child: _canSell
                    ? PrimaryButton(
                        label: 'See the plans',
                        onPressed: () => _openPaywall(context),
                      )
                    : PrimaryButton(
                        label: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
              ),
              if (_canSell) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Center(
                  child: AppTextButton(
                    label: 'Not now',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
