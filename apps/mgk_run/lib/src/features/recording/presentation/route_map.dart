import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config/app_config.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../domain/route_metrics.dart';
import '../domain/run_point.dart';
import '../domain/split_marker.dart';

/// How much of the basemap shows through, over the app's charcoal base.
///
/// The decision this encodes: a coloured or fully-lit basemap does real
/// wayfinding work — green means park, blue means water — but at full strength
/// it competes with the route, and the route is what the screen is about.
/// Blending toward [AppColors.bg] keeps the information and gives back the
/// contrast, which is the reason a stock style can be used rather than a
/// bespoke one.
///
/// Set by eye against real MapTiler `backdrop-dark` tiles at zoom 14–16, which
/// is where a run is actually read. Backdrop is already a recessive style — it
/// is MapTiler's canvas, built to be drawn on — so it needs less taking away
/// than a fuller one would: `dataviz-v4-dark` wants nearer 0.72 for the same
/// result. Anything below about 0.6 stops being recessive and starts being fog.
const double kBasemapOpacity = 0.85;

/// Draws a run's route as a silver polyline over a dark basemap — used both for
/// the live in-run map and the post-run route view.
///
/// Camera behaviour: the first build fits the whole route (the post-run view);
/// as points are appended it *follows* the latest fix at the current zoom (the
/// live view). So the same widget serves both a finished trace and a growing
/// one.
///
/// The basemap comes from [AppConfig.mapTileUrlTemplate] — the provider named in
/// the privacy policy, with a restricted key supplied at build time. (MapTiler
/// restricts on a User-Agent substring rather than a bundle id, and the one it
/// matches is [TileLayer.userAgentPackageName] below.) A
/// build with none configured draws the route on the charcoal base alone, which
/// is deliberate: shipping a hard-coded provider would mean calling a host the
/// policy doesn't declare. Tiles load over the network, so widget tests and
/// offline use show only the polyline either way.
class RouteMap extends StatefulWidget {
  const RouteMap({
    super.key,
    required this.points,
    this.splitMarkers = const <SplitMarker>[],
    this.strokeWidth = 4,
    this.interactive = true,
    this.followZoom = 16,
    this.basemapOpacity = kBasemapOpacity,
    this.focus,
    this.showPosition = false,
    this.emptyLabel = 'Finding you',
    String? tileUrlTemplate,
    String? attribution,
  }) : _tileUrlTemplate = tileUrlTemplate,
       _attribution = attribution;

  final List<RunPoint> points;

  /// Where each kilometre turned over, pinned on the route.
  ///
  /// **Empty in-run, and that is the point.** A runner mid-effort is looking at
  /// a number, not reading their own route back; pins would be ten pieces of
  /// furniture on the one part of the screen that is meant to just show where
  /// they are. Afterwards they are the whole reason to look at the map at all —
  /// which kilometre was the hill, where the run came apart — so the finished
  /// run's map passes them and the live one does not.
  final List<SplitMarker> splitMarkers;

  final double strokeWidth;
  final bool interactive;

  /// Where to look before there is a route — the device's last known position,
  /// supplied by the caller.
  ///
  /// Without this the map opened on a hard-coded Westminster while a runner in
  /// Leeds waited for their first fix, which reads as a broken map rather than
  /// an empty one. Null is handled honestly: see the acquiring state in [build].
  final LatLng? focus;

  /// What the map says when it has nothing to draw and nowhere to look.
  ///
  /// Null says nothing at all, which is the honest state when recording has
  /// *failed* rather than not started yet: "Finding you" over a run whose
  /// location permission was refused promises a search that is not happening,
  /// in the one state where the app has just finished explaining that it
  /// cannot. The panel carries the message; the map should not contradict it.
  final String? emptyLabel;

  /// Marks the newest fix with a live position dot. On for the in-run map, off
  /// for a finished trace, where "latest" is just the end.
  final bool showPosition;

  /// Overrides the configured basemap. Exists for the preview harness, which is
  /// a dev tool and may point at a keyless dev basemap; the app leaves it null
  /// and gets [AppConfig.current].
  final String? _tileUrlTemplate;
  final String? _attribution;

  String get tileUrlTemplate =>
      _tileUrlTemplate ?? AppConfig.current.mapTileUrlTemplate;

  String get attribution => _attribution ?? AppConfig.current.mapAttribution;

  /// Zoom used when following the live route.
  final double followZoom;

  /// How much of the basemap comes through, over the charcoal base beneath it.
  ///
  /// **The route has to stay the loudest thing on the map**, and this is the
  /// dial that guarantees it without changing provider. A stock dark basemap
  /// sits somewhere between "readable" and "recessive"; blending it toward
  /// `AppColors.bg` moves it along that line, so the streets stay legible
  /// enough to recognise while the silver line stays the brightest mark.
  ///
  /// The default was chosen by eye against real tiles, not derived. Change it
  /// by looking, not by reasoning.
  final double basemapOpacity;

  @override
  State<RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<RouteMap> {
  final MapController _controller = MapController();
  int? _lastLength;

  /// The trace, accuracy-filtered and broken wherever recording stopped.
  ///
  /// Segments rather than one polyline because a paused run — or a signal lost
  /// in an underpass — would otherwise be drawn as a straight line through
  /// whatever lies between, which is a route nobody ran. Same rule the distance
  /// uses, from the same function, so the picture and the number agree.
  List<List<LatLng>> get _segments => <List<LatLng>>[
    for (final segment in traceSegments(widget.points))
      <LatLng>[
        for (final point in segment) LatLng(point.latitude, point.longitude),
      ],
  ];

  @override
  Widget build(BuildContext context) {
    final segments = _segments;
    final drawn = segments.where((s) => s.length >= 2).toList();
    final all = <LatLng>[for (final segment in segments) ...segment];
    final hasRoute = all.isNotEmpty;

    // Nothing to show and nowhere to look. Rendering a map of somewhere the
    // runner has never been is worse than saying so.
    if (!hasRoute && widget.focus == null) {
      return _AcquiringMap(label: widget.emptyLabel);
    }

    // First build fits the route (via initialCameraFit below); later growth
    // follows the newest fix without changing zoom.
    if (_lastLength != null && all.length != _lastLength && all.isNotEmpty) {
      final target = all.last;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          _controller.move(target, _controller.camera.zoom);
        } catch (_) {
          // Map not ready yet; the next append will retry.
        }
      });
    }
    _lastLength = all.length;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCameraFit: all.length >= 2
                ? CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(all),
                    padding: const EdgeInsets.all(36),
                  )
                : null,
            initialCenter: hasRoute ? all.first : widget.focus!,
            initialZoom: widget.followZoom,
            // Charcoal under the tiles, so a build with no basemap — or a tile
            // that hasn't loaded yet — shows the route on the app's own
            // background rather than flutter_map's default light grey.
            backgroundColor: AppColors.bg,
            interactionOptions: InteractionOptions(
              flags: widget.interactive
                  ? InteractiveFlag.all
                  : InteractiveFlag.none,
            ),
          ),
          children: <Widget>[
            // Only ever the configured provider — the one the privacy policy
            // names. With none configured the route draws on the charcoal base
            // alone, which is a legitimate build state, not an error to surface.
            if (widget.tileUrlTemplate.isNotEmpty)
              // Blended toward the charcoal base beneath it, so the basemap
              // reads as context rather than content and the silver route stays
              // the loudest mark.
              //
              // `Opacity` around the whole layer, not `TileDisplay`'s per-tile
              // alpha, which flutter_map documents as unsafe for exactly this:
              // a transparent tile lets the *previous* zoom level's tiles show
              // through the new ones until they finish loading. This map changes
              // zoom every time the strip is expanded, so that is not
              // hypothetical. Fading stays on underneath.
              Opacity(
                opacity: widget.basemapOpacity,
                child: TileLayer(
                  urlTemplate: widget.tileUrlTemplate,
                  // Also the value MapTiler's key restriction matches on:
                  // flutter_map sends `User-Agent: flutter_map (<this>)`, and a
                  // reverse-DNS bundle id is a distinctive enough substring that
                  // no other app will satisfy it by accident.
                  userAgentPackageName: 'com.mgkcodes.fitness.run',
                  // A tile that will not load leaves the charcoal base showing,
                  // which is the same picture as a build with no basemap. Better
                  // a quiet hole than flutter_map's default broken-image glyph
                  // tiled across the screen.
                  errorTileCallback: (_, _, _) {},
                ),
              ),
            if (drawn.isNotEmpty)
              PolylineLayer<Object>(
                polylines: <Polyline<Object>>[
                  for (final segment in drawn)
                    Polyline<Object>(
                      points: segment,
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
                  // Under the endpoints, so a kilometre that happens to turn
                  // over on the start line does not hide where the run began.
                  for (final marker in widget.splitMarkers) _split(marker),
                  _endpoint(all.first, filled: false), // start (outlined)
                  if (widget.showPosition)
                    _position(all.last)
                  else
                    _endpoint(all.last, filled: true), // end
                ],
              ),
          ],
        ),
        // Required by every provider's terms, and read from the same config as
        // the tiles so the two can never disagree about who is being credited.
        if (widget.tileUrlTemplate.isNotEmpty && widget.attribution.isNotEmpty)
          Positioned(
            right: 6,
            bottom: 4,
            child: _Attribution(text: widget.attribution),
          ),
      ],
    );
  }

  /// A kilometre, pinned where it turned over and labelled with its number.
  ///
  /// **The number is on the map and the time is one press away.** Ten pins each
  /// carrying a number and a clock reading is a route you cannot see for the
  /// labels on it, and on a loop the later kilometres would sit on top of the
  /// early ones. The index alone is enough to read the shape of the run — where
  /// four was, how far apart six and seven fell — and the crossing time is on
  /// the tooltip for the one somebody actually wants to know about.
  ///
  /// Both times, because they answer different questions: the clock says when
  /// they were there, the elapsed figure says how far into the run that was.
  Marker _split(SplitMarker marker) => Marker(
    point: LatLng(marker.latitude, marker.longitude),
    width: 22,
    height: 22,
    child: Tooltip(
      message:
          '${marker.index} km · ${_clock(marker.at)} · '
          '${marker.elapsed.hoursMinutesSeconds} elapsed',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.bg,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.textPrimary, width: 1.5),
        ),
        child: Center(
          child: Text(
            '${marker.index}',
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 11,
              height: 1,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ),
    ),
  );

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

  /// Where the runner is now: a bright dot with a soft halo, so it reads as a
  /// live position rather than the end of a finished line.
  Marker _position(LatLng at) => Marker(
    point: at,
    width: 28,
    height: 28,
    child: DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.textPrimary.withValues(alpha: 0.18),
      ),
      child: Center(
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: AppColors.textPrimary,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.bg, width: 2),
          ),
        ),
      ),
    ),
  );
}

/// What the map shows before the first fix — which is the first ten to thirty
/// seconds of every run, and used to be a map of Westminster.
class _AcquiringMap extends StatelessWidget {
  const _AcquiringMap({required this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = label;
    if (text == null) return const ColoredBox(color: AppColors.bg);
    return ColoredBox(
      color: AppColors.bg,
      child: Center(
        child: Text(
          text,
          style: theme.textTheme.labelLarge?.copyWith(
            color: AppColors.textTertiary,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }
}

/// The provider credit. Small, but never absent while tiles are on screen.
class _Attribution extends StatelessWidget {
  const _Attribution({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.bg.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          text,
          style: const TextStyle(fontSize: 9, color: AppColors.textTertiary),
        ),
      ),
    );
  }
}

/// A wall-clock time of day, for a split marker's tooltip.
///
/// Hours and minutes only. A kilometre is not a stopwatch reading — the second
/// it turned over on is in the elapsed figure beside it, where it means
/// something.
String _clock(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:'
    '${at.minute.toString().padLeft(2, '0')}';
