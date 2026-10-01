import 'package:flutter/material.dart';

import '../motion/app_motion.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import 'glass_surface.dart';

/// One destination on a [FloatingNavBar].
///
/// Carries its own icons and label rather than being indexed into a table the
/// component owns: the two apps do not agree on their first tab. Run's is
/// *Home*, a summary of the day; Lift's is *Track*, the thing you are actually
/// doing in the gym. Baking either in would make the other one wrong.
class NavPillDestination {
  const NavPillDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// The height a [FloatingNavBar] occupies, before the safe-area inset.
///
/// Exported because every scrolling surface under one has to leave room for it,
/// and a surface that guesses is a surface with a row hidden behind glass.
const double kNavPillHeight = 64;

/// The three tab roots, as a floating pill over the content rather than a bar
/// beneath it.
///
/// **It floats, and that is a layout decision with a history.** As a
/// `Scaffold.bottomNavigationBar` it reserved its own height and every surface
/// got that for free. Floating, it does not — so each scrolling surface pads
/// its own foot by [kNavPillHeight] plus whatever else floats there.
///
/// The obvious shortcut is to inject fake `MediaQuery` bottom padding for the
/// subtree and keep every surface unchanged. **Do not.** That was tried, and it
/// shortened the viewport a `SafeArea` was measuring rather than the content
/// inside it: Plan's last card was sliced off and a black band appeared above
/// the bar. Reading `MediaQuery` at the widget that needs it is the opposite of
/// overriding it for everything below.
///
/// Labels are real [Text], not tooltips or semantics-only. Seventeen tests
/// across the two apps change tab by tapping one, and more importantly a bar
/// whose icons alone must be recognised is a bar people learn by trial.
///
/// **The selection is a thing that moves.** It used to be a property of each
/// tab: one went bright and another went dim in the same frame, so a change of
/// tab was two unrelated things happening at once. A soft plate now sits
/// behind the selected tab and travels to the next one, and the icons and
/// labels cross from dim to bright over the same time, so the eye is carried
/// from where it was to where it is going. Immediate with Reduce Motion on.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<NavPillDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final bool still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final Duration duration = still ? Duration.zero : AppMotion.slow;
    final int count = destinations.length;
    return GlassSurface(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: SizedBox(
        height: kNavPillHeight,
        child: Stack(
          children: <Widget>[
            if (count > 1)
              Positioned.fill(
                child: AnimatedAlign(
                  // -1 is the first tab's slot and +1 the last one's.
                  alignment: Alignment(
                    -1 + 2 * selectedIndex.clamp(0, count - 1) / (count - 1),
                    0,
                  ),
                  duration: duration,
                  curve: AppMotion.entrance,
                  child: FractionallySizedBox(
                    widthFactor: 1 / count,
                    heightFactor: 1,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: AppSpacing.sm - 2,
                      ),
                      child: _SelectionPlate(),
                    ),
                  ),
                ),
              ),
            Row(
              children: <Widget>[
                for (var i = 0; i < count; i++)
                  Expanded(
                    child: _Tab(
                      destination: destinations[i],
                      selected: i == selectedIndex,
                      duration: duration,
                      onTap: () => onSelected(i),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// What sits behind the selected tab. Barely there: the palette has no accent
/// to select with (ADR-0009), and the brightness of the tab above it still
/// does the telling. This is here to be seen moving.
class _SelectionPlate extends StatelessWidget {
  const _SelectionPlate();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.textPrimary.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(AppRadius.pill),
    ),
  );
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.destination,
    required this.selected,
    required this.duration,
    required this.onTap,
  });

  final NavPillDestination destination;
  final bool selected;

  /// How long the tab takes to go from dim to bright, or back.
  final Duration duration;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Dimmed rather than tinted, because the palette has no accent to select
    // with (ADR-0009). Weight carries it as well as opacity: on a greyscale
    // pill, brightness alone is a difference people miss in daylight.
    final Color color = selected
        ? AppColors.textPrimary
        : AppColors.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: color),
        duration: duration,
        curve: AppMotion.standard,
        builder: (context, tint, _) => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              selected ? destination.selectedIcon : destination.icon,
              size: 22,
              color: tint ?? color,
            ),
            const SizedBox(height: 2),
            Text(
              destination.label,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                color: tint ?? color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
