import 'dart:async';

import 'package:health/health.dart';

import '../domain/health_workout.dart';
import '../domain/workout_dedup.dart';
import '../domain/workout_source.dart';
import 'health_read_types.dart';

/// Workouts read from Apple Health (and Health Connect on Android).
///
/// **Everything here fails to empty.** A denied read, a platform without
/// Health, a plugin throwing on an OS that does not implement a type — all of
/// them produce "no workouts", because iOS makes a refusal indistinguishable
/// from an absence and the app is told to design for absence rather than
/// invent an error state (docs/architecture/run-recording.md).
///
/// **Nothing here logs a value.** Health data is special-category data: the
/// counts below are safe to print, the contents are not, and a stack trace
/// carrying somebody's workout is a data leak in a log file.
class HealthKitWorkouts implements WorkoutSource {
  HealthKitWorkouts({
    Health? health,
    this.timeout = const Duration(seconds: 20),
  }) : _health = health ?? Health();

  final Health _health;

  /// Health can block indefinitely on a device with a large store or a stalled
  /// daemon. Same reasoning as the coach's deadline: a call with no bound is a
  /// screen with no way out.
  final Duration timeout;

  bool _configured = false;

  /// What this class *queries* — workouts, and nothing else. Distance and
  /// energy ride on the workout itself, so asking for those quantity types
  /// separately would be reading data twice.
  ///
  /// **Not asked for any more** (see [kHealthReadTypes]). Nothing calls
  /// [since]; an import that wants it has to add `WORKOUT` to that list first,
  /// or this query returns nothing for the life of the install.
  ///
  /// Deliberately not the same list as [kHealthReadTypes], which is what
  /// [requestAccess] asks *permission* for. The app now also reads steps, from
  /// `HealthKitRunMetrics` at the end of a run, and iOS grants read access once
  /// per type at the one moment the sheet appears — so the request has to cover
  /// every type the app will ever read, while each query stays narrow.
  static const List<HealthDataType> _types = <HealthDataType>[
    HealthDataType.WORKOUT,
  ];

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  /// **The app's one Health permission moment, for everything it reads.**
  ///
  /// It asks for [kHealthReadTypes], not [_types]. A second sheet later — at
  /// the end of a first run, to ask for steps — would be a permission prompt
  /// arriving at the worst possible moment, in front of somebody who has just
  /// stopped running and wants to see their numbers. One ask, in onboarding,
  /// covering everything (ADR-0019).
  @override
  Future<bool> requestAccess() async {
    try {
      await _configure();
      return await _health
          .requestAuthorization(
            kHealthReadTypes,
            permissions: kHealthReadAccess,
          )
          .timeout(timeout);
    } on Object {
      // Includes the platform simply not having Health. Not an error worth
      // showing: the screen that asked will carry on with no workouts.
      return false;
    }
  }

  @override
  Future<List<HealthWorkout>> since(DateTime from) async {
    List<HealthDataPoint> points;
    try {
      await _configure();
      points = await _health
          .getHealthDataFromTypes(
            types: _types,
            startTime: from,
            endTime: DateTime.now(),
          )
          .timeout(timeout);
    } on Object {
      return const <HealthWorkout>[];
    }

    final workouts = <HealthWorkout>[
      for (final HealthDataPoint p in points)
        if (_toWorkout(p) case final HealthWorkout w) w,
    ];

    // Deduplicated here rather than by the caller, so there is one place where
    // "the same run reported three times" is dealt with and no way to read this
    // source and forget to.
    return dedupeWorkouts(workouts);
  }

  HealthWorkout? _toWorkout(HealthDataPoint p) {
    final value = p.value;
    if (value is! WorkoutHealthValue) return null;
    return HealthWorkout(
      // On iOS this is the HKSource bundle identifier, which is the whole basis
      // of deduplication — see workout_dedup.dart.
      sourceBundleId: p.sourceId,
      start: p.dateFrom,
      end: p.dateTo,
      distanceMeters: metresFrom(
        value.totalDistance,
        value.totalDistanceUnit?.name,
      ),
      energyKcal: kcalFrom(
        value.totalEnergyBurned,
        value.totalEnergyBurnedUnit?.name,
      ),
      externalId: p.uuid,
    );
  }
}
