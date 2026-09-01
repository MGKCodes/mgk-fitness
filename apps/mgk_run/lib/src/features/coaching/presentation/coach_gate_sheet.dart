import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../domain/plan_gate_copy.dart';

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
/// **There is no buy button yet**, and there deliberately is not a fake one.
/// RevenueCat is chosen ([ADR-0028](../../../../docs/decisions/0028-revenuecat-is-the-purchase-path.md))
/// and unbuilt, so this states the price and stops. A button that cannot take
/// money is worse than no button: it fails at the moment somebody has decided
/// to pay, which is the worst moment available.
class CoachGateSheet extends StatelessWidget {
  const CoachGateSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const CoachGateSheet(),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
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
            Text(
              'Not available to buy in this build yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
