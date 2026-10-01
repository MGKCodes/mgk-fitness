import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mgk_run/preview/fake_run_recorder.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';
import 'package:mgk_run/src/features/recording/presentation/recording_screen.dart';
import 'package:mgk_run/src/features/recording/presentation/route_map.dart';
import 'package:mgk_run/src/features/recording/presentation/run_start_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// **The basemap is Esri's from build 27**, and two things about it are not
/// true of the provider it replaced.
///
/// Its tiles are 512 pixels on a grid one level behind everybody else's, and
/// drawn on the usual grid they still load: every label at half size, and four
/// times the tiles fetched against a free monthly allowance that stops the map
/// when it runs out. Nothing fails, so nothing but a test would say.
///
/// And its terms want the credit where it can be seen. On the in-run screen
/// the map's own bottom edge is behind the panel, which is where the credit
/// had been drawn since the map first had tiles.
const String _esri =
    'https://static-map-tiles-api.arcgis.com/arcgis/rest/services/'
    'static-basemap-tiles-service/v1/arcgis/dark-gray/static/tile/'
    '{z}/{y}/{x}?token=test';

const String _credit =
    'Powered by Esri | Sources: Esri, TomTom, Garmin, FAO, NOAA, USGS, '
    '© OpenStreetMap contributors, and the GIS User Community';

RunPoint _p(double lat, double lng) => RunPoint(
  latitude: lat,
  longitude: lng,
  accuracyMeters: 5,
  timestamp: DateTime(2026, 10, 1, 8),
);

Future<void> _pumpMap(
  WidgetTester tester, {
  required String tiles,
  required String credit,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: SizedBox(
          width: 393,
          height: 400,
          child: RouteMap(
            points: <RunPoint>[_p(51.5, -0.12), _p(51.501, -0.121)],
            tileUrlTemplate: tiles,
            attribution: credit,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('the tile grid is read off the template', () {
    test('Esri static tiles are 512 points, one level behind', () {
      final TileGrid grid = TileGrid.of(_esri);
      expect(grid.dimension, 512);
      expect(grid.zoomOffset, -1);
    });

    test('everybody else is on the standard grid, retina or not', () {
      for (final String template in <String>[
        'https://api.maptiler.com/maps/backdrop-dark/{z}/{x}/{y}@2x.png?key=k',
        'https://tiles.example/{z}/{x}/{y}.png',
        '',
      ]) {
        expect(TileGrid.of(template).dimension, 256, reason: template);
        expect(TileGrid.of(template).zoomOffset, 0, reason: template);
      }
    });

    testWidgets('and the map hands it to the tile layer', (tester) async {
      await _pumpMap(tester, tiles: _esri, credit: _credit);

      final TileLayer layer = tester.widget<TileLayer>(find.byType(TileLayer));
      expect(layer.tileDimension, 512);
      expect(layer.zoomOffset, -1);
      // Row before column, as the service asks for it.
      expect(layer.urlTemplate, contains('{z}/{y}/{x}'));
    });
  });

  group('the credit', () {
    testWidgets('names Esri always, and the sources on a tap', (tester) async {
      await _pumpMap(tester, tiles: _esri, credit: _credit);

      expect(find.text('Powered by Esri'), findsOneWidget);
      expect(find.textContaining('TomTom'), findsNothing);

      await tester.tap(find.byType(MapCredit));
      await tester.pump();

      expect(find.textContaining('Powered by Esri'), findsOneWidget);
      expect(find.textContaining('Sources: Esri, TomTom'), findsOneWidget);
      expect(find.textContaining('OpenStreetMap contributors'), findsOneWidget);

      await tester.tap(find.byType(MapCredit));
      await tester.pump();
      expect(find.textContaining('TomTom'), findsNothing);
    });

    testWidgets('fits a 320pt map when it is open', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 300,
              child: RouteMap(
                points: <RunPoint>[_p(51.5, -0.12), _p(51.501, -0.121)],
                tileUrlTemplate: _esri,
                attribution: _credit,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(MapCredit));
      await tester.pump();

      final Rect credit = tester.getRect(find.byType(MapCredit));
      final Rect map = tester.getRect(find.byType(RouteMap));
      expect(credit.left, greaterThanOrEqualTo(map.left));
      expect(credit.top, greaterThanOrEqualTo(map.top));
      expect(tester.takeException(), isNull);
    });

    testWidgets('with nothing to open is shown whole', (tester) async {
      await _pumpMap(
        tester,
        tiles: 'https://tiles.example/{z}/{x}/{y}.png',
        credit: '© OpenStreetMap contributors',
      );

      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    });
  });

  group('on the in-run screen', () {
    Future<FakeRunRecorder> pumpRun(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final recorder = FakeRunRecorder();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: RecordingScreen(
            recorder: recorder,
            tileUrlTemplate: _esri,
            attribution: _credit,
          ),
        ),
      );
      // Fixed pumps: the fake recorder emits on a repeating timer, so the tree
      // never goes quiet and `pumpAndSettle` waits forever.
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      return recorder;
    }

    testWidgets('the credit is above the panel, not behind it', (tester) async {
      final recorder = await pumpRun(tester);

      expect(find.byType(MapCredit), findsOneWidget);
      final Rect credit = tester.getRect(find.text('Powered by Esri'));
      final Rect panel = tester.getRect(find.byType(SheetHandle));
      expect(
        credit.bottom,
        lessThanOrEqualTo(panel.top),
        reason:
            'the map under the panel cannot be seen, so neither can a '
            'credit drawn on it',
      );
      expect(
        tester.widget<RouteMap>(find.byType(RouteMap)).showCredit,
        isFalse,
        reason: 'one credit, drawn by the screen',
      );
      await recorder.stop();
    });

    testWidgets('and beside the recentre control, not under it', (
      tester,
    ) async {
      final recorder = await pumpRun(tester);
      tester.widget<RouteMap>(find.byType(RouteMap)).onUserPan!();
      await tester.pump();

      final Rect credit = tester.getRect(find.text('Powered by Esri'));
      final Rect recentre = tester.getRect(find.byTooltip('Recentre'));
      expect(credit.overlaps(recentre), isFalse);
      await recorder.stop();
    });
  });

  testWidgets('on the start screen it clears the home indicator', (
    tester,
  ) async {
    // The start screen reads the compiled-in config, which a test cannot set,
    // so this pins the inset the screen asks for rather than the pixels.
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(393, 852),
            padding: EdgeInsets.only(top: 59, bottom: 34),
          ),
          child: RunStartScreen(
            focus: const LatLng(53.8008, -1.5491),
            onStart: () {},
            onCancel: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    final RouteMap map = tester.widget<RouteMap>(find.byType(RouteMap));
    expect(map.creditInsets.bottom, 38);
  });
}
