import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config/app_config.dart';
import 'package:mgk_ui/mgk_ui.dart';
import '../domain/run_point.dart';

/// Draws a run's route as a silver polyline over a dark basemap — used both for
/// the live in-run map and the post-run route view.
///
/// Camera behaviour: the first build fits the whole route (the post-run view);
/// as points are appended it *follows* the latest fix at the current zoom (the
/// live view). So the same widget serves both a finished trace and a growing
/// one.
///
/// The basemap comes from [AppConfig.mapTileUrlTemplate] — the provider named in
/// the privacy policy, with a bundle-restricted key supplied at build time. A
/// build with none configured draws the route on the charcoal base alone, which
/// is deliberate: shipping a hard-coded provider would mean calling a host the
/// policy doesn't declare. Tiles load over the network, so widget tests and
/// offline use show only the polyline either way.
class RouteMap extends StatefulWidget {
  const RouteMap({
    super.key,
    required this.points,
    this.strokeWidth = 4,
    this.interactive = true,
    this.followZoom = 16,
    String? tileUrlTemplate,
  }) : _tileUrlTemplate = tileUrlTemplate;

  final List<RunPoint> points;
  final double strokeWidth;
  final bool interactive;

  /// Overrides the configured basemap. Exists for the preview harness, which is
  /// a dev tool and may point at a keyless dev basemap; the app leaves it null
  /// and gets [AppConfig.current].
  final String? _tileUrlTemplate;

  String get tileUrlTemplate =>
      _tileUrlTemplate ?? AppConfig.current.mapTileUrlTemplate;

  /// Zoom used when following the live route.
  final double followZoom;

  @override
  State<RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<RouteMap> {
  final MapController _controller = MapController();
  int? _lastLength;

  List<LatLng> get _route => <LatLng>[
    for (final point in widget.points) LatLng(point.latitude, point.longitude),
  ];

  @override
  Widget build(BuildContext context) {
    final route = _route;
    final hasRoute = route.length >= 2;

    // First build fits the route (via initialCameraFit below); later growth
    // follows the newest fix without changing zoom.
    if (_lastLength != null &&
        route.length != _lastLength &&
        route.isNotEmpty) {
      final target = route.last;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          _controller.move(target, _controller.camera.zoom);
        } catch (_) {
          // Map not ready yet; the next append will retry.
        }
      });
    }
    _lastLength = route.length;

    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCameraFit: hasRoute
            ? CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(route),
                padding: const EdgeInsets.all(36),
              )
            : null,
        initialCenter: route.isNotEmpty
            ? route.first
            : const LatLng(51.5074, -0.1278),
        initialZoom: widget.followZoom,
        // Charcoal under the tiles, so a build with no basemap — or a tile that
        // hasn't loaded yet — shows the route on the app's own background
        // rather than flutter_map's default light grey.
        backgroundColor: AppColors.bg,
        interactionOptions: InteractionOptions(
          flags: widget.interactive
              ? InteractiveFlag.all
              : InteractiveFlag.none,
        ),
      ),
      children: <Widget>[
        // Only ever the configured provider — the one the privacy policy names.
        // With none configured the route draws on the charcoal base alone,
        // which is a legitimate build state, not an error to surface.
        if (widget.tileUrlTemplate.isNotEmpty)
          TileLayer(
            urlTemplate: widget.tileUrlTemplate,
            userAgentPackageName: 'com.mgkcodes.runio',
          ),
        if (hasRoute)
          PolylineLayer<Object>(
            polylines: <Polyline<Object>>[
              Polyline<Object>(
                points: route,
                color: AppColors.primary,
                strokeWidth: widget.strokeWidth,
                borderColor: AppColors.bg,
                borderStrokeWidth: 1,
              ),
            ],
          ),
        if (hasRoute)
          MarkerLayer(
            markers: <Marker>[
              _endpoint(route.first, filled: false), // start (outlined)
              _endpoint(route.last, filled: true), // latest / end (filled)
            ],
          ),
      ],
    );
  }

  Marker _endpoint(LatLng at, {required bool filled}) => Marker(
    point: at,
    width: 16,
    height: 16,
    child: Container(
      decoration: BoxDecoration(
        color: filled ? AppColors.textPrimary : AppColors.bg,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.textPrimary, width: 2),
      ),
    ),
  );
}
