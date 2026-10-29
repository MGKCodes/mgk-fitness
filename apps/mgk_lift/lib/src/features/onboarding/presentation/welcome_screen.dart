import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../../../core/brand.dart';
import '../domain/walkthrough_script.dart';

/// The first screen a new install shows: the name, one promise, and the way
/// in.
///
/// **Run's welcome, in Lift's words** (ADR-0006). The same photograph-and-scrim
/// treatment, the same order down the screen and the same staggered arrival,
/// so the two apps open alike: wordmark, then the headline, then the line under
/// it, then the action once the promise has been read. Lift's own photograph,
/// `hero_onboarding`, the empty gym the coach's sheet is set on, so the room
/// the lifter first meets the coach in is the room they meet it in again.
///
/// **Shown once per install, and never to somebody upgrading from 2.0.0**;
/// that is the gate's to decide (`FirstRunGate`), not this screen's.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.onGetStarted,
    this.onHaveAccount,
  });

  /// Into the app, with the walkthrough over it.
  final VoidCallback onGetStarted;

  /// To Lift's sign-in, and from there into the app, with no walkthrough: an
  /// account has its reason to be here already. **Null hides it**:
  /// a build with no server has no account to sign in to, and a button that
  /// cannot work is worse than none.
  final VoidCallback? onHaveAccount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final haveAccount = onHaveAccount;
    return Scaffold(
      body: PhotoBackdrop(
        image: 'assets/images/backgrounds/hero_onboarding.webp',
        // Run's welcome's strength and scrim: the headline and the action are
        // at opposite ends, and `balanced` is heavy at both.
        opacity: 0.34,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
            // Staggered for Run's reason: arriving in one frame reads as a
            // printed page rather than an app opening. `Entrance` plays once
            // and stands still under reduced motion.
            child: Column(
              children: <Widget>[
                const SizedBox(height: 8),
                const Entrance(child: _Wordmark()),
                const Spacer(),
                Entrance(
                  index: 1,
                  offset: 18,
                  duration: AppMotion.slow,
                  child: Text(
                    kWelcomeHeadline,
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
                    kWelcomeLine,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ),
                const Spacer(),
                // Last, and after a longer beat: the action lands once the
                // promise has been read, not alongside it.
                Entrance(
                  index: 4,
                  duration: AppMotion.slow,
                  child: PrimaryButton(
                    label: kWelcomeStart,
                    onPressed: onGetStarted,
                  ),
                ),
                if (haveAccount != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Entrance(
                    index: 5,
                    child: AppTextButton(
                      label: kWelcomeHaveAccount,
                      onPressed: haveAccount,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The app's name, as Run's welcome sets Run's: this is the one screen whose
/// question is "which app is this", so it carries the app's name rather than
/// the suite's. From [kAppName], so the wordmark and the launcher's label
/// cannot drift apart.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) => Text(
    kAppName.toUpperCase(),
    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: 2,
    ),
  );
}
