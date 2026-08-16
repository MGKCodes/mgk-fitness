import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../domain/run_point.dart';
import 'location_source.dart';

/// [LocationSource] backed by the `geolocator` plugin — the production source on
/// iOS.
///
/// UNVERIFIED on this machine: geolocator's background location only behaves
/// correctly on a real device, so this must be exercised with a **TestFlight
/// build** (background updates, the permission prompt, and the blue in-use
/// indicator can't be checked in a simulator or on desktop/web). See
/// docs/architecture/run-recording.md.
///
/// Altitude is deliberately NOT taken from GPS — GPS elevation is visibly wrong.
/// Barometric altitude via `CMAltimeter` is a separate platform channel (TODO).
class GeolocatorLocationSource implements LocationSource {
  GeolocatorLocationSource({LocationSettings? settings})
    : _settings = settings ?? _iosRunSettings();

  final LocationSettings _settings;

  StreamController<RunPoint>? _controller;
  StreamSubscription<Position>? _subscription;

  @override
  Stream<RunPoint> get fixes =>
      (_controller ??= StreamController<RunPoint>.broadcast()).stream;

  @override
  Future<void> start() async {
    await _ensureAvailable();
    final controller = _controller ??= StreamController<RunPoint>.broadcast();
    _subscription = Geolocator.getPositionStream(locationSettings: _settings)
        .listen(
          (position) => controller.add(_toRunPoint(position)),
          // Without this the platform's failure is an unhandled async error:
          // the stream stops, the screen keeps pulsing "Recording", and the
          // run quietly stops existing. Forwarding it means the recorder finds
          // out and can say so.
          onError: (Object error, StackTrace stack) => controller.addError(
            LocationUnavailable(_reasonFor(error), error),
            stack,
          ),
          cancelOnError: false,
        );
  }

  @override
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _controller?.close();
    _controller = null;
  }

  /// Both preconditions, in the order the runner would fix them.
  ///
  /// The services check comes first and did not exist before: with the system
  /// location switch off, `requestPermission` can return a perfectly granted
  /// permission and the position stream then delivers nothing at all. That is a
  /// working app with no fixes — the hardest state to diagnose from the screen.
  Future<void> _ensureAvailable() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationUnavailable(
        LocationUnavailableReason.servicesDisabled,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationUnavailable(
        LocationUnavailableReason.permissionDeniedForever,
      );
    }
    if (permission == LocationPermission.denied) {
      throw const LocationUnavailable(
        LocationUnavailableReason.permissionDenied,
      );
    }
  }

  LocationUnavailableReason _reasonFor(Object error) => switch (error) {
    LocationServiceDisabledException() =>
      LocationUnavailableReason.servicesDisabled,
    PermissionDeniedException() => LocationUnavailableReason.permissionDenied,
    _ => LocationUnavailableReason.failed,
  };

  RunPoint _toRunPoint(Position position) => RunPoint(
    latitude: position.latitude,
    longitude: position.longitude,
    accuracyMeters: position.accuracy,
    altitudeMeters: null, // GPS altitude is unreliable — CMAltimeter TODO.
    timestamp: position.timestamp,
  );
}

/// iOS settings tuned for run recording: best accuracy, fitness activity type,
/// and background updates so the run keeps recording with the screen locked.
LocationSettings _iosRunSettings() => AppleSettings(
  accuracy: LocationAccuracy.best,
  activityType: ActivityType.fitness,
  distanceFilter: 0,
  pauseLocationUpdatesAutomatically: false,
  allowBackgroundLocationUpdates: true,
  showBackgroundLocationIndicator: true,
);
