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
            // The first screen anybody sees, and it used to arrive in one
            // frame — wordmark, promise and call to action all at once, which
            // reads as a printed page rather than an app opening. Staggered,
            // the eye is walked down it in the order the copy was written to
            // be read. `Entrance` plays once and self-disables under reduced
            // motion, so this costs nothing in accessibility.
            child: Column(
              children: [
                const SizedBox(height: 8),
                const Entrance(child: _Wordmark()),
                const Spacer(),
                Entrance(
                  index: 1,
                  offset: 18,
                  duration: AppMotion.slow,
                  child: Text(
                    'Every run,\ncoached.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Entrance(
                  index: 2,
                  duration: AppMotion.slow,
                  child: Text(
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
                ),
                const Spacer(),
                // Last, and after a longer beat: the action should land once
                // the promise has been read, not compete with it.
                Entrance(
                  index: 4,
                  duration: AppMotion.slow,
                  child: PrimaryButton(
                    label: 'Get started',
                    onPressed: onGetStarted,
                  ),
                ),
                const SizedBox(height: 8),
                Entrance(
                  index: 5,
                  child: TextButton(
                    onPressed: onHaveAccount,
                    child: const Text('I already have an account'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The wordmark.
///
/// Still reads RUNIO while the monorepo calls this app Run and the suite name
/// is not settled (see the repo README). Left alone deliberately — renaming the
/// product is a branding decision, not a layout one, and it wants to change
/// here, in `CFBundleDisplayName`, and in the copy at the same time.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) => Text(
    'RUNIO',
    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: 2,
    ),
  );
}
