import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import '../../recording/domain/run_point.dart';

/// A cheap, static sketch of a run's route — a normalised polyline painted with
/// a [CustomPainter], NOT a live map instance.
///
/// The history list can show dozens of these while scrolling; a real map per
/// row would be far too heavy (roadmap step 6). Runs without a route (treadmill
/// / manual) show a type glyph instead.
class RouteThumbnail extends StatelessWidget {
  const RouteThumbnail({
    super.key,
    required this.points,
    this.type = 'outdoor',
    this.size = 64,
  });

  final List<RunPoint> points;
  final String type;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: points.length >= 2
          ? CustomPaint(painter: _RoutePainter(points, AppColors.primary))
          : Center(
              child: Icon(
                _glyph(type),
                size: 22,
                color: AppColors.textTertiary,
              ),
            ),
    );
  }

  IconData _glyph(String type) => switch (type) {
    'treadmill' => Icons.fitness_center,
    'manual' => Icons.edit_outlined,
    _ => Icons.route_outlined,
  };
}

class _RoutePainter extends CustomPainter {
  _RoutePainter(this.points, this.color);

  final List<RunPoint> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    // Downsample: a 64px sketch never needs thousands of points.
    final step = (points.length / 120).ceil();
    final sampled = <RunPoint>[
      for (var i = 0; i < points.length; i += step) points[i],
      points.last,
    ];

    var minLat = sampled.first.latitude, maxLat = minLat;
    var minLng = sampled.first.longitude, maxLng = minLng;
    for (final p in sampled) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }

    const pad = 8.0;
    final lngScale = math.cos(((minLat + maxLat) / 2) * math.pi / 180);
    final spanX = math.max((maxLng - minLng) * lngScale, 1e-9);
    final spanY = math.max(maxLat - minLat, 1e-9);
    final availW = size.width - pad * 2;
    final availH = size.height - pad * 2;
    final scale = math.min(availW / spanX, availH / spanY);
    final drawW = spanX * scale;
    final drawH = spanY * scale;
    final offX = pad + (availW - drawW) / 2;
    final offY = pad + (availH - drawH) / 2;

    Offset project(RunPoint p) => Offset(
      offX + (p.longitude - minLng) * lngScale * scale,
      offY + drawH - (p.latitude - minLat) * scale, // invert: north is up
    );

    final path = Path()
      ..moveTo(project(sampled.first).dx, project(sampled.first).dy);
    for (final p in sampled.skip(1)) {
      final o = project(p);
      path.lineTo(o.dx, o.dy);
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RoutePainter old) =>
      old.points != points || old.color != color;
}
