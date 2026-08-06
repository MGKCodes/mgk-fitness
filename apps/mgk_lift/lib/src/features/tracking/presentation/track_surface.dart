import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// **Track** — the front page, and the part that has to work in a basement.
///
/// This is the surface a lifter opens standing at a rack. Everything here is
/// offline-first: the on-device database owns a session in progress, and
/// Supabase is backup and cross-device store, never the source of truth for a
/// set being logged right now. A gym with no signal is the normal case, not the
/// edge case.
///
/// That is the opposite posture to [PlanSurface], which needs a connection and
/// says so, and the split is deliberate — this app is AI-driven, but the
/// tracking underneath it is not allowed to depend on the AI being reachable.
class TrackSurface extends StatelessWidget {
  const TrackSurface({
    super.key,
    this.onStartSession,
    this.onOpenPlan,
    this.hasOpenSession = false,
  });

  /// Begins or resumes a session. Null while the recorder is not wired up,
  /// which reads as an unavailable action rather than an error.
  final VoidCallback? onStartSession;

  final VoidCallback? onOpenPlan;

  /// True when a session is already open — usually because the app was killed
  /// mid-workout. The button then offers to go back to it, because "Start a
  /// session" over the top of one already running is a lie about what happens.
  final bool hasOpenSession;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PhotoBackdrop(
      image: 'assets/images/backgrounds/hero_home.webp',
      scrim: ScrimStrength.balanced,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xxl,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SectionLabel('Today'),
              const SizedBox(height: AppSpacing.md),
              Text(
                hasOpenSession ? 'Session in progress' : 'Ready when you are',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                hasOpenSession
                    ? 'You have a session open. Pick up where you left off.'
                    : 'Start a session and log it set by set. It works with no '
                          'signal and syncs when you are back.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              GlassSurface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const SectionLabel(
                      'Next up',
                      emphasis: LabelEmphasis.stat,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Nothing scheduled',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Your coach builds the plan. Until then, log whatever you '
                      'are doing.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: hasOpenSession ? 'Resume session' : 'Start a session',
                onPressed: onStartSession,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
