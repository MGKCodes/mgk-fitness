import 'package:flutter/services.dart';
import 'package:mgk_units/mgk_units.dart';

import '../domain/live_readout.dart';

/// [LiveRunReadout] over the app's own platform channel.
///
/// The native half is small and in two places: `MainActivity.kt` posts and
/// updates a notification, and `LiveRunChannel.swift` starts and updates a
/// Live Activity that the `RunLiveActivity` extension draws. No package does
/// this for both platforms without also wanting an App Group and a shared
/// store on the iPhone, which this has no use for: ActivityKit carries the
/// figures to the extension itself.
///
/// Everything is caught. A build with no native half (a widget test, the web
/// preview) throws `MissingPluginException` on every call, and that is the
/// same answer as a phone where the runner has said no.
class PlatformLiveReadout implements LiveRunReadout {
  const PlatformLiveReadout();

  /// Also written in `MainActivity.kt` and `LiveRunChannel.swift`.
  static const MethodChannel channel = MethodChannel(
    'com.mgkcodes.fitness.run/live',
  );

  @override
  Future<void> prepare() => _call('prepare');

  @override
  Future<void> show(LiveRunStatus status) => _call('show', <String, Object>{
    'distance': status.distance,
    'pace': status.pace,
    'elapsedSeconds': status.elapsed.inSeconds,
    // For the paused state, where nothing counts and the figure is drawn as
    // it stands.
    'elapsed': status.elapsed.hoursMinutesSeconds,
    'paused': status.paused,
  });

  @override
  Future<void> end() => _call('end');

  Future<void> _call(String method, [Map<String, Object>? arguments]) async {
    try {
      await channel.invokeMethod<void>(method, arguments);
    } catch (_) {
      // Deliberate: see the class doc. The readout is never why a run fails.
    }
  }
}
