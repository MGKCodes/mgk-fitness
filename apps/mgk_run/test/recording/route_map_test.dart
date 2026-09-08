import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';
import 'package:mgk_run/src/features/recording/domain/split_marker.dart';
import 'package:mgk_run/src/features/recording/presentation/route_map.dart';
import 'package:mgk_ui/mgk_ui.dart';

final _start = DateTime(2026, 1, 1, 8);

/// A kilometre turning over at four seconds past a quarter past eight.
final _crossing = DateTime(2026, 1, 1, 8, 15, 4);

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

  group('per-kilometre pins', () {
    final List<SplitMarker> two = <SplitMarker>[
      SplitMarker(
        index: 1,
        latitude: 51.501,
        longitude: -0.121,
        at: _crossing,
        elapsed: Duration(minutes: 5, seconds: 7),
      ),
      SplitMarker(
        index: 2,
        latitude: 51.502,
        longitude: -0.122,
        at: _crossing,
        elapsed: Duration(minutes: 10, seconds: 18),
      ),
    ];

    List<Marker> markersOf(WidgetTester tester) =>
        tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers;

    testWidgets('are drawn on a finished run, with the two endpoints', (
      tester,
    ) async {
      await _pumpMap(
        tester,
        RouteMap(
          points: <RunPoint>[_p(51.5, -0.12), _p(51.503, -0.123)],
          splitMarkers: two,
        ),
      );

      expect(markersOf(tester), hasLength(4)); // two pins, start, end
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('and the end is a finish flag, not a second dot', (
      tester,
    ) async {
      // Asked for off the build 13 field test. Start and finish were the same
      // 16pt circle in two fills, which on a closed loop sit on top of each
      // other and cannot be told apart at all.
      await _pumpMap(
        tester,
        RouteMap(
          points: <RunPoint>[_p(51.5, -0.12), _p(51.503, -0.123)],
          splitMarkers: two,
        ),
      );

      expect(find.byType(FinishFlag), findsOneWidget);
      expect(
        markersOf(tester),
        hasLength(4),
        reason: 'it replaces the end dot rather than joining it',
      );
      expect(
        tester.widgetList<Tooltip>(find.byType(Tooltip)),
        hasLength(2),
        reason: 'the flag says nothing the summary does not say better',
      );
    });

    testWidgets('and the flag waits for the line to arrive', (tester) async {
      // Mid-reveal the end marker follows the *head* of the drawn line, not the
      // true end. A flag planted on a moving head reads as a rendering fault;
      // the dot keeps it company until the line gets there.
      await _pumpMap(
        tester,
        RouteMap(
          points: <RunPoint>[_p(51.5, -0.12), _p(51.503, -0.123)],
          splitMarkers: two,
          reveal: 0.5,
        ),
      );

      expect(find.byType(FinishFlag), findsNothing);
    });

    testWidgets('carry the crossing time, without shouting it', (tester) async {
      // The number is on the map and the time is one press away: ten pins each
      // carrying a clock reading is a route you cannot see for the labels on
      // it, and on a loop the later kilometres sit on top of the early ones.
      await _pumpMap(
        tester,
        RouteMap(
          points: <RunPoint>[_p(51.5, -0.12), _p(51.503, -0.123)],
          splitMarkers: two,
        ),
      );

      final tooltips = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message)
          .toList();
      expect(tooltips, hasLength(2));
      expect(tooltips.first, contains('1 km'));
      expect(tooltips.first, contains('08:15')); // the clock time it happened
      expect(tooltips.first, contains('5:07')); // and how far into the run
      expect(find.text('05:07'), findsNothing, reason: 'not on the map itself');
    });

    testWidgets('are absent in-run, where the map is for where you are', (
      tester,
    ) async {
      // The default. A runner mid-effort is looking at a number, not reading
      // their own route back.
      await _pumpMap(
        tester,
        RouteMap(points: <RunPoint>[_p(51.5, -0.12), _p(51.503, -0.123)]),
      );

      expect(markersOf(tester), hasLength(2)); // start and end only
      expect(find.byType(Tooltip), findsNothing);
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
