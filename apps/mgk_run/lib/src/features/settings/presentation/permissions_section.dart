import '../../../core/brand.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../../health/data/health_kit_workouts.dart';
import '../../health/domain/workout_source.dart';
import '../../onboarding/data/intro_permission_requester.dart';
import '../../onboarding/presentation/intro_screen.dart';
import 'settings_tile.dart';

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
/// The one-word version of the location state, for the settings index.
///
/// Short on purpose: the index prints what a setting is *set to* and this is
/// the only permission whose state the app can actually read. The sentence
/// version, with what to do about it, is on the screen this row opens.
/// Names the permission, not just its state. A row called *Permissions* whose
/// value reads `Off` says the whole section is off, which is not what is being
/// reported — location is the only permission whose state the app can read, and
/// on Android it is the only one it asks for at all.
String locationRowValue(LocationPermission? p) => switch (p) {
  LocationPermission.always || LocationPermission.whileInUse => 'Location on',
  LocationPermission.denied ||
  LocationPermission.deniedForever => 'Location off',
  LocationPermission.unableToDetermine || null => 'Not set',
};

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

  /// Asks for what the app reads, which is steps, and says what follows.
  ///
  /// It used to read 90 days of workouts to print how many there were, which
  /// was the only thing workouts were ever read for. The permission went and
  /// so did the count (see `kHealthReadTypes`). Nothing is read here now: iOS
  /// will not say what was granted, and a step total fetched only to prove the
  /// permission works would be health data read for a label.
  Future<void> _readHealth() async {
    setState(() {
      _healthBusy = true;
      _healthResult = null;
    });
    final asked = await _health.requestAccess();
    if (!mounted) return;
    setState(() {
      _healthBusy = false;
      _healthResult = asked
          ? 'Asked. If Health allows it, steps show on the runs you record. '
                'Health does not tell apps what you chose.'
          : 'Health could not be asked on this phone.';
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
        // No `auth`, so the conversation stops after the last permission
        // instead of walking a signed-in runner into making a second profile.
        builder: (_) => IntroScreen(
          requestPermission: (p) => requestIntroPermission(p, health: _health),
          onBack: () => Navigator.of(context).maybePop(),
          onFinished: (_) => Navigator.of(context).maybePop(),
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

        // **Apple Health does not exist on Android, and this row said it did.**
        //
        // Found 2026-09-11 by opening Settings on an Android emulator. The
        // intro had the same defect and was fixed in fe14c82
        // (`introPermissionsFor`); this screen keeps its own copy of the list
        // and was never touched, so the fix reached the first run and not the
        // place somebody goes to check afterwards. Run requests no health
        // permission on Android at all, so the row offered something the
        // platform cannot grant.
        if (defaultTargetPlatform != TargetPlatform.android)
          Entrance(
            index: widget.startIndex,
            child: SettingsTile(
              icon: Icons.favorite_border,
              title: 'Apple Health',
              subtitle: _healthBusy
                  ? 'Reading…'
                  : _healthResult ??
                        'Steps and cadence for the runs you record here',
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
            //
            // Two texts, because the platforms differ in the way that matters
            // here: iOS asks once and never again, Android lets a permission
            // be changed back and forth from its own settings. The iOS version
            // was shown on both until 2026-09-11, telling Android runners about
            // a Health permission this app never requests there and a
            // "Privacy & Security" path their phone does not have.
            child: Text(
              defaultTargetPlatform == TargetPlatform.android
                  ? 'To change location access: Settings › Apps › $kAppName › '
                        'Permissions › Location.\n\n'
                        'Choose "Allow all the time" if runs stop recording '
                        'when the screen locks — some phones also hold a '
                        'separate battery setting that suspends background '
                        'apps.'
                  : 'iOS only asks once. To be asked again, or to turn either '
                        'off:\n\n'
                        '• Location — Settings › $kAppName › Location\n'
                        '• Health — Settings › Privacy & Security › Health › '
                        '$kAppName, or the Health app › Sharing › Apps › '
                        '$kAppName\n\n'
                        'Deleting and reinstalling the app resets both '
                        'prompts, and takes any runs that have not been backed '
                        'up with it.',
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
