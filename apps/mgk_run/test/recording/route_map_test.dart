import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';
import 'package:mgk_run/src/features/recording/presentation/route_map.dart';
import 'package:mgk_ui/mgk_ui.dart';

final _start = DateTime(2026, 1, 1, 8);

RunPoint _p(double lat, double lng, {double accuracy = 5, Duration? at}) =>
    RunPoint(
      latitude: lat,
      longitude: lng,
      accuracyMeters: accuracy,
      timestamp: _start.add(at ?? Duration.zero),
    );

Future<void> _pumpMap(WidgetTester tester, Widget map) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: SizedBox(width: 400, height: 400, child: map)),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('says it is looking rather than showing somewhere else', (
    tester,
  ) async {
    // The map used to open on a hard-coded Westminster while a runner
    // elsewhere waited for their first fix, which reads as broken rather than
    // empty. No points and nowhere to look is a state with its own answer.
    await _pumpMap(tester, const RouteMap(points: <RunPoint>[]));

    expect(find.text('Finding you'), findsOneWidget);
    expect(find.byType(FlutterMap), findsNothing);
  });

  testWidgets('opens on the last known position before the first fix', (
    tester,
  ) async {
    await _pumpMap(
      tester,
      const RouteMap(points: <RunPoint>[], focus: LatLng(53.8008, -1.5491)),
    );

    expect(find.text('Finding you'), findsNothing);
    expect(find.byType(FlutterMap), findsOneWidget);
  });

  group('attribution', () {
    // Not decorative: every provider requires visible credit, so tiles on
    // screen without it is a terms breach the app cannot detect at runtime.
    testWidgets('is shown whenever tiles are', (tester) async {
      await _pumpMap(
        tester,
        RouteMap(
          points: <RunPoint>[_p(51.5, -0.12), _p(51.501, -0.121)],
          tileUrlTemplate: 'https://tiles.example/{z}/{x}/{y}.png',
          attribution: '© MapTiler © OpenStreetMap contributors',
        ),
      );

      expect(
        find.text('© MapTiler © OpenStreetMap contributors'),
        findsOneWidget,
      );
    });

    testWidgets('is absent when there is no basemap to credit', (tester) async {
      await _pumpMap(
        tester,
        RouteMap(
          points: <RunPoint>[_p(51.5, -0.12), _p(51.501, -0.121)],
          tileUrlTemplate: '',
          attribution: '© MapTiler © OpenStreetMap contributors',
        ),
      );

      expect(
        find.text('© MapTiler © OpenStreetMap contributors'),
        findsNothing,
      );
    });
  });

  group('gaps in the trace', () {
    testWidgets('a continuous run draws as one line', (tester) async {
      await _pumpMap(
        tester,
        RouteMap(
          points: <RunPoint>[
            _p(51.500, -0.120),
            _p(51.501, -0.121, at: const Duration(seconds: 3)),
            _p(51.502, -0.122, at: const Duration(seconds: 6)),
          ],
        ),
      );

      final layer = tester.widget<PolylineLayer<Object>>(
        find.byType(PolylineLayer<Object>),
      );
      expect(layer.polylines, hasLength(1));
      expect(layer.polylines.single.points, hasLength(3));
    });

    testWidgets('a paused run is not drawn straight through the pause', (
      tester,
    ) async {
      // Ten minutes and a kilometre between two halves of a run: whatever the
      // runner did in between, they did not run the straight line across it.
      await _pumpMap(
        tester,
        RouteMap(
          points: <RunPoint>[
            _p(51.500, -0.120),
            _p(51.501, -0.121, at: const Duration(seconds: 3)),
            _p(51.520, -0.140, at: const Duration(minutes: 10)),
            _p(51.521, -0.141, at: const Duration(minutes: 10, seconds: 3)),
          ],
        ),
      );

      final layer = tester.widget<PolylineLayer<Object>>(
        find.byType(PolylineLayer<Object>),
      );
      expect(layer.polylines, hasLength(2));
    });
  });
}
