import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';

/// The brand entry point: a monochrome photo behind the RUNIO wordmark and a
/// single silver call to action. Implements the greyscale photo-scrim treatment
/// from docs/design/design-system.md.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.onGetStarted,
    required this.onHaveAccount,
  });

  final VoidCallback onGetStarted;
  final VoidCallback onHaveAccount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: PhotoBackdrop(
        image: 'assets/images/backgrounds/onboarding.jpg',
        opacity: 0.34,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Text(
                  'RUNIO',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
                const Spacer(),
                Text(
                  'Every run,\ncoached.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  // Not "a coach in your ear": that is in-run audio, which
                  // ADR-0006 defers to post-v1. It was the second thing the
                  // app promised, on the first screen, and it is the one
                  // thing here Runio cannot currently do.
                  'Your runs tracked, your history kept,\n'
                  'and a plan whenever you want one.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const Spacer(),
                PrimaryButton(label: 'Get started', onPressed: onGetStarted),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onHaveAccount,
                  child: const Text('I already have an account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
