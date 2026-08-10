import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../../health/data/health_kit_workouts.dart';
import '../../health/domain/workout_source.dart';
import '../../onboarding/data/intro_permission_requester.dart';
import '../../onboarding/presentation/intro_screen.dart';
import 'settings_screen.dart' show SettingsTile;

/// Location and Health: what they are set to, and how to change them.
///
/// **An app cannot revoke its own permissions on iOS, and cannot ask twice.**
/// Those two facts decide everything on this screen. The system records an
/// answer the first time it is given and never shows that sheet again for the
/// life of the install, and there is no API to hand a permission back. So the
/// honest thing this section can offer is: say what the state is where the
/// state is knowable, replay the conversation for anyone who wants to read it
/// again, and give the exact path on the phone for the part only the phone can
/// do.
///
/// Anything that promised to "turn these off" would be a button that quietly
/// does nothing.
class PermissionsSection extends StatefulWidget {
  const PermissionsSection({super.key, this.health, this.startIndex = 4});

  /// Injected for tests; the real reader otherwise.
  final WorkoutSource? health;

  /// Where this section sits in the settings entrance animation.
  final int startIndex;

  @override
  State<PermissionsSection> createState() => _PermissionsSectionState();
}

class _PermissionsSectionState extends State<PermissionsSection> {
  late final WorkoutSource _health = widget.health ?? HealthKitWorkouts();

  LocationPermission? _location;
  String? _healthResult;
  bool _healthBusy = false;

  @override
  void initState() {
    super.initState();
    _readLocation();
  }

  Future<void> _readLocation() async {
    try {
      final p = await Geolocator.checkPermission();
      if (mounted) setState(() => _location = p);
    } on Object {
      // A platform without location is not an error state, it is a blank one.
      if (mounted) setState(() => _location = null);
    }
  }

  /// **There is deliberately no equivalent for Health.** iOS will not say
  /// whether a read was granted, so any status shown for it would be invented.
  /// The row below reports what a read actually returned instead, which is the
  /// only true thing available.
  String get _locationLabel => switch (_location) {
    LocationPermission.always => 'On, including in the background',
    LocationPermission.whileInUse => 'On while the app is open',
    LocationPermission.denied => 'Off — runs will not record a route',
    LocationPermission.deniedForever =>
      'Off — runs will not record a route. Change it in iOS Settings.',
    LocationPermission.unableToDetermine || null => 'Not set yet',
  };

  Future<void> _readHealth() async {
    setState(() {
      _healthBusy = true;
      _healthResult = null;
    });
    await _health.requestAccess();
    final found = await _health.since(
      DateTime.now().subtract(const Duration(days: 90)),
    );
    if (!mounted) return;
    setState(() {
      _healthBusy = false;
      // A count, never a verdict. Empty covers "you declined" and "you have no
      // workouts" equally and iOS does not distinguish them, so neither does
      // this. The count is also the only part safe to put on screen: the
      // workouts themselves are special-category data.
      _healthResult = found.isEmpty
          ? 'Nothing came back. Health answers the same way whether you '
                'declined or have nothing there.'
          : '${found.length} workout${found.length == 1 ? '' : 's'} in the '
                'last 90 days, duplicates removed.';
    });
  }

  /// Replays the intro conversation.
  ///
  /// Pushed as its own route rather than resetting any stored flag, because
  /// there is no flag: the intro belongs to the sign-up path, and sending
  /// somebody back through that would mean a new account. This walks the same
  /// screen with the same wiring — the words, the buttons, the coach's replies.
  /// The system dialogs only appear for a permission not yet answered.
  Future<void> _replayIntro() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => IntroScreen(
          requestPermission: (p) => requestIntroPermission(p, health: _health),
          onBack: () => Navigator.of(context).maybePop(),
          onDone: (_) => Navigator.of(context).maybePop(),
        ),
      ),
    );
    if (mounted) await _readLocation();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Entrance(
          index: widget.startIndex,
          child: const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.sm,
              AppSpacing.xl,
              AppSpacing.xs,
            ),
            child: SectionLabel('Permissions'),
          ),
        ),

        Entrance(
          index: widget.startIndex,
          child: SettingsTile(
            icon: Icons.location_on_outlined,
            title: 'Location',
            subtitle: _locationLabel,
            showChevron: false,
            // Opens this app's own page in iOS Settings, which is where the
            // location switch lives. There is no such page for Health.
            onTap: () => Geolocator.openAppSettings(),
          ),
        ),

        Entrance(
          index: widget.startIndex,
          child: SettingsTile(
            icon: Icons.favorite_border,
            title: 'Apple Health',
            subtitle: _healthBusy
                ? 'Reading…'
                : _healthResult ??
                      'Bring in runs from your watch or another app',
            showChevron: false,
            onTap: _healthBusy ? null : _readHealth,
          ),
        ),

        Entrance(
          index: widget.startIndex + 1,
          child: SettingsTile(
            icon: Icons.replay,
            title: 'Run setup again',
            subtitle: 'Walk through the coach\'s first conversation',
            showChevron: false,
            onTap: _replayIntro,
          ),
        ),

        Entrance(
          index: widget.startIndex + 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.sm,
              AppSpacing.xl,
              AppSpacing.md,
            ),
            // The part the app genuinely cannot do for you. Written out rather
            // than linked because the Health path is four levels deep and
            // nobody finds it by guessing, and because iOS offers no
            // App-Store-safe deep link to it at all.
            child: Text(
              'iOS only asks once. To be asked again, or to turn either off:\n\n'
              '• Location — Settings › Runio › Location\n'
              '• Health — Settings › Privacy & Security › Health › Runio, or '
              'the Health app › Sharing › Apps › Runio\n\n'
              'Deleting and reinstalling Runio resets both prompts, and takes '
              'any runs that have not been backed up with it.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textTertiary,
                height: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
