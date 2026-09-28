import 'dart:io' show Platform;

import 'package:health/health.dart';

import '../domain/run_health_metrics.dart';

/// Reads what Health noticed while a run was happening — steps, today.
///
/// **Everything here fails to nothing**, the same contract `HealthKitWorkouts`
/// keeps and for the same reason: iOS makes a refused read indistinguishable
/// from an absence, so an error state here would be the app inventing a fault
/// out of a permission the runner is entitled to withhold (CLAUDE.md rule 6).
/// A declined read, a locked store, a platform without Health and a plugin
/// throwing all end at [RunHealthMetrics.none].
///
/// **Nothing here logs a value.** Health data is special-category data. A step
/// count in a crash report is a data leak, and the stack traces below are
/// caught precisely so nothing carrying one escapes.
class HealthKitRunMetrics implements RunHealthSource {
  HealthKitRunMetrics({
    Health? health,
    this.timeout = const Duration(seconds: 6),
  }) : _injected = health;

  final Health? _injected;

  /// Built on first use rather than in the constructor, because the recorder
  /// defaults to one of these and unit tests construct recorders by the dozen.
  /// Nothing should touch a plugin just by existing.
  late final Health _health = _injected ?? Health();

  /// **Shorter than the workout import's twenty seconds, on purpose.** That one
  /// runs behind a screen that can show it is working; this one is on the
  /// critical path of the Finish button, with a runner standing still watching
  /// a screen that has no busy state. Six seconds is long enough for a healthy
  /// store and short enough that a stalled one costs a pause rather than a hang
  /// — and the run is already safe on the phone before this is asked at all.
  final Duration timeout;

  bool _configured = false;

  /// True where Health exists at all.
  ///
  /// The same rule `runSettingsForPlatform` uses in the recorder: anything that
  /// is not iOS or Android is a test host or a preview, where the plugin has no
  /// implementation and every call would throw a `MissingPluginException` for
  /// the catch below to swallow. Answering "nothing" up front keeps the desktop
  /// harness honest and quiet instead of exception-driven.
  bool get _platformHasHealth => Platform.isIOS || Platform.isAndroid;

  @override
  Future<RunHealthMetrics> forInterval({
    required DateTime start,
    required DateTime end,
  }) async {
    // A window that runs backwards is not a run; HealthKit would reject it and
    // there is nothing to ask about anyway.
    if (!end.isAfter(start)) return RunHealthMetrics.none;
    if (!_platformHasHealth) return RunHealthMetrics.none;

    try {
      if (!_configured) {
        await _health.configure();
        _configured = true;
      }
      // The aggregate query rather than a walk over raw samples: a run's worth
      // of pedometer samples is a lot of special-category data to pull across
      // a platform channel to add up, and HealthKit already knows the total.
      //
      // `includeManualEntry` left at its default — a step a person typed in is
      // still a step they say they took, and second-guessing that would be this
      // app deciding which of somebody's own health records it believes.
      final int? steps = await _health
          .getTotalStepsInInterval(start, end)
          .timeout(timeout);
      // Zero from Health means "asked, nothing counted" — a phone left on a
      // desk while its owner ran with a watch. That is genuinely no step data
      // for this run, and drawing `0` under STEPS would tell a runner who just
      // covered 10 km that they took none. Absent is the honest reading.
      if (steps == null || steps <= 0) return RunHealthMetrics.none;
      return RunHealthMetrics(steps: steps);
    } on Object {
      // Deliberately everything, deliberately silent, and deliberately without
      // the object: see the class doc. There is no failure here that a runner
      // could act on and none that may be printed.
      return RunHealthMetrics.none;
    }
  }
}
