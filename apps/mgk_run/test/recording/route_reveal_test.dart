import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';
import 'package:mgk_run/src/features/recording/domain/split_marker.dart';
import 'package:mgk_run/src/features/recording/presentation/route_map.dart';

/// **The route draws itself on, and nothing is drawn ahead of the line.**
///
/// The effect is the one moment the finished-run screen has to be an arrival
/// rather than a record. The rule that makes it read as tracing rather than as
/// a rendering fault is that everything follows the head: a pin for a
/// kilometre the line has not reached, or an endpoint sitting at a finish that
/// has not been drawn, is a mark on a route that does not exist yet.
///
/// On a closed loop that mistake is invisible — the end sits under the start —
/// which is exactly why it is asserted here rather than left to the eye.
void main() {
  List<RunPoint> straight(int n) => <RunPoint>[
    for (var i = 0; i < n; i++)
      RunPoint(
        // A straight line east, so "ahead of the head" is unambiguous: longitude
        // only ever increases, and the endpoint's position is checkable.
        latitude: 51.23,
        longitude: -0.2 + i * 0.001,
        accuracyMeters: 5,
        timestamp: DateTime(2026, 8, 23, 14).add(Duration(seconds: i * 10)),
      ),
  ];

  List<SplitMarker> markers(List<RunPoint> pts, int count) => <SplitMarker>[
    for (var i = 1; i <= count; i++)
      SplitMarker(
        index: i,
        latitude: pts[(pts.length * i / (count + 1)).floor()].latitude,
        longitude: pts[(pts.length * i / (count + 1)).floor()].longitude,
        at: pts.first.timestamp,
        elapsed: Duration(minutes: i * 5),
      ),
  ];

  Future<void> pump(
    WidgetTester tester,
    double reveal,
    List<RunPoint> pts,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: RouteMap(
            points: pts,
            splitMarkers: markers(pts, 4),
            reveal: reveal,
            interactive: false,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  int drawnPoints(WidgetTester tester) {
    final layer = tester.widget<PolylineLayer<Object>>(
      find.byType(PolylineLayer<Object>),
    );
    return layer.polylines.fold<int>(0, (n, p) => n + p.points.length);
  }

  testWidgets('a partial reveal draws less of the line than a full one', (
    tester,
  ) async {
    final pts = straight(100);

    await pump(tester, 1, pts);
    final whole = drawnPoints(tester);

    await pump(tester, 0.5, pts);
    final half = drawnPoints(tester);

    expect(half, lessThan(whole));
    expect(half, greaterThan(1));
  });

  testWidgets('a full reveal is the whole trace, so nothing is lost', (
    tester,
  ) async {
    final pts = straight(40);
    await pump(tester, 1, pts);

    // The default for every existing caller — the in-run map above all — so a
    // regression here would quietly shorten a live route.
    expect(drawnPoints(tester), pts.length);
  });

  testWidgets('markers appear only as the line reaches them', (tester) async {
    final pts = straight(100);

    await pump(tester, 0.1, pts);
    final early = tester
        .widgetList<MarkerLayer>(find.byType(MarkerLayer))
        .first
        .markers
        .length;

    await pump(tester, 1, pts);
    final all = tester
        .widgetList<MarkerLayer>(find.byType(MarkerLayer))
        .first
        .markers
        .length;

    // Four splits plus two endpoints at the end; far fewer at a tenth.
    expect(early, lessThan(all));
  });

  testWidgets('the endpoint follows the head rather than the finish', (
    tester,
  ) async {
    final pts = straight(100);
    await pump(tester, 0.4, pts);

    final layer = tester
        .widgetList<MarkerLayer>(find.byType(MarkerLayer))
        .first;
    final east = layer.markers
        .map((m) => m.point.longitude)
        .reduce((a, b) => a > b ? a : b);

    // Nothing may sit east of where the line has been drawn to. The route runs
    // east, so the true finish is the easternmost point of the trace — and at
    // 40% it must not be on screen.
    expect(east, lessThan(pts.last.longitude));
  });
}
