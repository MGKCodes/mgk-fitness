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
    await _ensurePermission();
    _controller ??= StreamController<RunPoint>.broadcast();
    _subscription = Geolocator.getPositionStream(
      locationSettings: _settings,
    ).listen((position) => _controller?.add(_toRunPoint(position)));
  }

  @override
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _controller?.close();
    _controller = null;
  }

  Future<void> _ensurePermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const LocationPermissionDeniedException();
    }
  }

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

/// Thrown by [GeolocatorLocationSource.start] when location permission is not
/// granted. A denied read is designed for (see the health-data rules), not
/// surfaced as a crash.
class LocationPermissionDeniedException implements Exception {
  const LocationPermissionDeniedException();

  @override
  String toString() =>
      'LocationPermissionDeniedException: '
      'location permission was not granted';
}
