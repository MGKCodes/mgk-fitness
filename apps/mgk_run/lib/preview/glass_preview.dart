import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';

/// A bench for judging the glass material against Runio's real backgrounds.
///
/// The point of the comparison is the claim that glass needs texture: the same
/// panel is drawn over the signature photography and over the flat charcoal
/// base, side by side, so the difference is visible rather than argued.
final Map<String, WidgetBuilder> glassPreviewScreens = <String, WidgetBuilder>{
  'glass': (_) => const _GlassBench(),
  'glass-flat': (_) => const _GlassBench(background: null),
};

class _GlassBench extends StatelessWidget {
  const _GlassBench({this.background = 'assets/images/backgrounds/in-run.jpg'});

  final String? background;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (background != null)
            Image.asset(
              background!,
              fit: BoxFit.cover,
              opacity: const AlwaysStoppedAnimation<double>(0.55),
            ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: <Widget>[
                SectionLabel(
                  background == null
                      ? 'Over flat charcoal'
                      : 'Over photography',
                ),
                const SizedBox(height: AppSpacing.md),

                // The in-run readout as glass — the case this material exists for.
                GlassSurface(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.xl,
                  ),
                  child: Column(
                    children: <Widget>[
                      const StatBlock(
                        label: 'Distance',
                        value: '5.23 km',
                        size: StatSize.hero,
                        align: CrossAxisAlignment.center,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: const <Widget>[
                          StatBlock(
                            label: 'Time',
                            value: '27:45',
                            align: CrossAxisAlignment.center,
                          ),
                          StatBlock(
                            label: 'Pace',
                            value: '5:18 /km',
                            align: CrossAxisAlignment.center,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Blur ladder: how much frost is too much.
                for (final sigma in <double>[8, 16, 24, 36])
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: GlassSurface(
                      blurSigma: sigma,
                      child: Row(
                        children: <Widget>[
                          SectionLabel('blur $sigma'),
                          const Spacer(),
                          const Text(
                            'Threshold · 8.6 km',
                            style: TextStyle(color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Tint ladder: where it stops being glass and starts being milk.
                for (final tint in <double>[0.04, 0.10, 0.18, 0.30])
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: GlassSurface(
                      tintOpacity: tint,
                      child: Row(
                        children: <Widget>[
                          SectionLabel('tint $tint'),
                          const Spacer(),
                          const Text(
                            'Long run · 18.5 km',
                            style: TextStyle(color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  ),

                // A pill, to check the edge treatment survives a tight radius.
                Align(
                  child: GlassSurface(
                    borderRadius: BorderRadius.circular(999),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                      vertical: AppSpacing.md,
                    ),
                    sheen: false,
                    child: const Text(
                      'Pause',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
