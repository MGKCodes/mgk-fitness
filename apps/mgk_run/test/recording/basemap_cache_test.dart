import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:mgk_run/src/features/recording/data/basemap_cache.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';
import 'package:mgk_run/src/features/recording/presentation/route_map.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// **The map keeps what it has been shown, on the phone, and uses it when the
/// network cannot be.**
///
/// Asked for on 1 October 2026: a runner who loses signal should not lose the
/// map, and the map should already be there when they press Start. The first
/// half was nearly true and failing quietly. flutter_map saved every tile, and
/// then drew nothing over the saved copy once it was a day old and the network
/// was down, which is the only moment the copy was for.
///
/// What is not here is an offline map. Nothing downloads an area: the
/// provider's terms forbid it, and the warm-up below asks only for the tiles
/// the start screen is about to draw.
const String _esri =
    'https://static-map-tiles-api.arcgis.com/arcgis/rest/services/'
    'static-basemap-tiles-service/v1/arcgis/dark-gray/static/tile/'
    '{z}/{y}/{x}?token=first-key';

/// Leeds, where the tile under the centre of the map at the run's zoom is
/// row 10551, column 16242 of Esri's level 15.
const LatLng _leeds = LatLng(53.8008, -1.5491);

final Uint8List _png = Uint8List.fromList(<int>[1, 2, 3, 4]);

/// The cache, held in memory: what was saved, under the key the app uses.
class _MemoryCache implements MapCachingProvider {
  final Map<String, CachedMapTile> saved = <String, CachedMapTile>{};
  bool supported = true;

  @override
  bool get isSupported => supported;

  @override
  Future<CachedMapTile?> getTile(String url) async =>
      saved[basemapTileKey(url)];

  @override
  Future<void> putTile({
    required String url,
    required CachedMapTileMetadata metadata,
    Uint8List? bytes,
  }) async {
    final String key = basemapTileKey(url);
    saved[key] = (bytes: bytes ?? saved[key]!.bytes, metadata: metadata);
  }

  Future<void> hold(String url, Uint8List bytes) => putTile(
    url: url,
    // Stale since yesterday, as a tile from last week's run is.
    metadata: CachedMapTileMetadata(
      staleAt: DateTime.timestamp().subtract(const Duration(days: 1)),
      lastModified: null,
      etag: null,
    ),
    bytes: bytes,
  );
}

Uri _tile(int level, int row, int column, {String token = 'first-key'}) =>
    Uri.parse(
      _esri
          .replaceAll('{z}', '$level')
          .replaceAll('{y}', '$row')
          .replaceAll('{x}', '$column')
          .replaceAll('first-key', token),
    );

void main() {
  group('a saved tile is named without its token', () {
    test('so rotating the key does not orphan the cache', () {
      expect(
        basemapTileKey(_tile(15, 10551, 16242).toString()),
        basemapTileKey(_tile(15, 10551, 16242, token: 'second-key').toString()),
      );
    });

    test('and two tiles never share a name', () {
      expect(
        basemapTileKey(_tile(15, 10551, 16242).toString()),
        isNot(basemapTileKey(_tile(15, 10551, 16243).toString())),
      );
    });
  });

  group('when the network cannot answer', () {
    late _MemoryCache cache;
    final Uri url = _tile(15, 10551, 16242);

    setUp(() => cache = _MemoryCache());

    http.Client down() =>
        MockClient((_) => throw const SocketException('Failed host lookup'));

    test('a working network is left alone', () async {
      await cache.hold(url.toString(), _png);
      final client = OfflineTileClient(
        cache: cache,
        inner: MockClient((_) async => http.Response.bytes(<int>[9, 9], 200)),
      );

      final response = await client.get(url);

      expect(response.statusCode, 200);
      expect(response.bodyBytes, <int>[9, 9]);
    });

    test('the saved copy is drawn, however old it is', () async {
      await cache.hold(url.toString(), _png);
      final client = OfflineTileClient(cache: cache, inner: down());

      final response = await client.get(url);

      expect(response.statusCode, 200);
      expect(response.bodyBytes, _png);
    });

    test('and is held for five minutes rather than asked for again', () async {
      // The answer goes back through flutter_map's own loader, which works
      // out freshness from these headers. They have to parse, and they have
      // to say "not stale yet", or a dead spot asks the network for the same
      // tile every time the map moves.
      await cache.hold(url.toString(), _png);
      final client = OfflineTileClient(cache: cache, inner: down());

      final response = await client.get(url);
      final metadata = CachedMapTileMetadata.fromHttpHeaders(response.headers);

      expect(metadata.isStale, isFalse);
      expect(
        metadata.staleAt.difference(DateTime.timestamp()).inMinutes,
        inInclusiveRange(4, 5),
      );
    });

    test('a copy saved under last year\'s key still answers', () async {
      await cache.hold(_tile(15, 10551, 16242, token: 'old').toString(), _png);
      final client = OfflineTileClient(cache: cache, inner: down());

      expect((await client.get(url)).bodyBytes, _png);
    });

    test('with nothing saved the failure is the network\'s own', () async {
      final client = OfflineTileClient(cache: cache, inner: down());

      await expectLater(client.get(url), throwsA(isA<SocketException>()));
    });

    test('a refusal is a failure too: the allowance spent', () async {
      // The free tier stops serving at its monthly limit. A map that goes
      // blank for everybody that day is worse than one that keeps the streets
      // it has.
      await cache.hold(url.toString(), _png);
      final client = OfflineTileClient(
        cache: cache,
        inner: MockClient((_) async => http.Response('limit reached', 429)),
      );

      final response = await client.get(url);

      expect(response.statusCode, 200);
      expect(response.bodyBytes, _png);
    });

    test('and a refusal with nothing saved is passed on as it came', () async {
      final client = OfflineTileClient(
        cache: cache,
        inner: MockClient((_) async => http.Response('limit reached', 429)),
      );

      expect((await client.get(url)).statusCode, 429);
    });

    test('a tile the map no longer wants is not answered at all', () async {
      // An aborted request is flutter_map moving on, not the network failing.
      // Answering it from the cache would decode a tile nobody is waiting for.
      await cache.hold(url.toString(), _png);
      final client = OfflineTileClient(
        cache: cache,
        inner: MockClient((_) => throw http.RequestAbortedException(url)),
      );

      await expectLater(
        client.get(url),
        throwsA(isA<http.RequestAbortedException>()),
      );
    });

    test('a cache that cannot be read fails as the network did', () async {
      cache.supported = false;
      final client = OfflineTileClient(cache: cache, inner: down());

      await expectLater(client.get(url), throwsA(isA<SocketException>()));
    });
  });

  group('when the app opens', () {
    late _MemoryCache cache;
    late List<Uri> asked;

    setUp(() {
      cache = _MemoryCache();
      asked = <Uri>[];
    });

    http.Client network({int status = 200}) => MockClient((request) async {
      asked.add(request.url);
      return http.Response.bytes(
        _png,
        status,
        headers: <String, String>{'cache-control': 'max-age=86400', 'age': '0'},
      );
    });

    BasemapWarmUp warmUp({
      LatLng? at = _leeds,
      String template = _esri,
      http.Client? client,
    }) => BasemapWarmUp(
      urlTemplate: template,
      cache: cache,
      position: () async => at,
      client: client ?? network(),
    );

    test('the tiles around the runner are fetched and kept', () async {
      await warmUp().run();

      expect(asked, isNotEmpty);
      expect(cache.saved, hasLength(asked.length));
      expect(
        asked.map((u) => u.path),
        contains(endsWith('/static/tile/15/10551/16242')),
        reason:
            'the tile under the runner, at the level the map draws: one '
            'behind the zoom, row before column',
      );
      expect(
        asked.every((u) => u.queryParameters['token'] == 'first-key'),
        isTrue,
      );
    });

    test('and only those: a screen and one ring, not an area', () async {
      // The line between loading a map and downloading one. The provider's
      // terms forbid systematic requests for offline use, so the warm-up asks
      // for what the start screen draws and nothing further out.
      await warmUp().run();

      expect(asked.length, lessThanOrEqualTo(20));
      final rows = asked.map(
        (u) => int.parse(u.pathSegments.reversed.elementAt(1)),
      );
      final columns = asked.map((u) => int.parse(u.pathSegments.last));
      expect(rows.every((r) => (r - 10551).abs() <= 2), isTrue);
      expect(columns.every((c) => (c - 16242).abs() <= 2), isTrue);
      expect(asked.toSet(), hasLength(asked.length), reason: 'no tile twice');
    });

    test('opening it again in the same place asks for nothing', () async {
      final BasemapWarmUp warm = warmUp();
      await warm.run();
      asked.clear();

      await warm.run();

      expect(asked, isEmpty);
    });

    test(
      'and nor does the next launch, with the tiles already saved',
      () async {
        await warmUp().run();
        asked.clear();

        await warmUp().run();

        expect(asked, isEmpty);
      },
    );

    test('a different place is fetched, and the first one is kept', () async {
      final BasemapWarmUp leeds = warmUp();
      await leeds.run();
      final int kept = cache.saved.length;
      asked.clear();

      await warmUp(at: const LatLng(51.5072, -0.1276)).run();

      expect(asked, isNotEmpty);
      expect(cache.saved.length, kept + asked.length);
    });

    test('with no position there is nothing to warm', () async {
      // No permission, or a phone that has never had a fix. The seam that
      // reads the position never prompts; this is what it answers then.
      await warmUp(at: null).run();

      expect(asked, isEmpty);
    });

    test('nor with no basemap configured, or no cache to keep it in', () async {
      await warmUp(template: '').run();
      cache.supported = false;
      await warmUp().run();

      expect(asked, isEmpty);
    });

    test('a refusal is not saved as though it were a tile', () async {
      await warmUp(client: network(status: 429)).run();

      expect(asked, isNotEmpty);
      expect(cache.saved, isEmpty);
    });

    test(
      'a dead network is no error, and the next opening tries again',
      () async {
        var calls = 0;
        final BasemapWarmUp warm = warmUp(
          client: MockClient((_) {
            calls++;
            throw const SocketException('Failed host lookup');
          }),
        );

        await warm.run();
        await warm.run();

        expect(calls, 2, reason: 'one attempt each time, not a retry storm');
        expect(cache.saved, isEmpty);
      },
    );
  });

  group("through flutter_map's own tile loader", () {
    // The join the tests above cannot see: the client's answer has to survive
    // the loader that asked for it, which reads the headers, writes the cache
    // and decodes the bytes. A real PNG, a real loader, and no network.
    const TileCoordinates tile = TileCoordinates(16242, 10551, 16);

    /// Resolved inside `runAsync`, start to finish: the loader's futures are
    /// real ones (a cache read, an image decode), and made in the test's fake
    /// zone they would wait for a pump that never comes.
    Future<ImageInfo?> load(WidgetTester tester, _MemoryCache cache) =>
        tester.runAsync(() {
          // Flutter keeps decoded images in memory by address, live ones
          // included, so the second test would otherwise be handed the first
          // one's tile.
          imageCache.clear();
          imageCache.clearLiveImages();
          final provider = NetworkTileProvider(
            httpClient: OfflineTileClient(
              cache: cache,
              inner: MockClient(
                (_) => throw const SocketException('Failed host lookup'),
              ),
            ),
            cachingProvider: cache,
          );
          final layer = TileLayer(
            urlTemplate: _esri,
            tileDimension: TileGrid.of(_esri).dimension,
            zoomOffset: TileGrid.of(_esri).zoomOffset,
            tileProvider: provider,
          );
          final done = Completer<ImageInfo>();
          provider
              .getImageWithCancelLoadingSupport(
                tile,
                layer,
                Completer<void>().future,
              )
              .resolve(ImageConfiguration.empty)
              .addListener(
                ImageStreamListener(
                  (info, _) => done.complete(info),
                  onError: (error, stack) => done.completeError(error, stack),
                ),
              );
          return done.future.timeout(const Duration(seconds: 10));
        });

    testWidgets('a day-old tile is drawn with the network down', (
      tester,
    ) async {
      final cache = _MemoryCache();
      await cache.hold(
        _tile(15, 10551, 16242).toString(),
        TileProvider.transparentImage,
      );

      final ImageInfo? drawn = await load(tester, cache);

      expect(drawn, isNotNull);
      expect(drawn!.image.width, greaterThan(0));
    });

    testWidgets('and a tile never seen is still a failure, not a blank', (
      tester,
    ) async {
      // `runAsync` hands a thrown error to the framework and answers null.
      final ImageInfo? drawn = await load(tester, _MemoryCache());

      expect(drawn, isNull);
      expect(tester.takeException(), isA<SocketException>());
    });
  });

  testWidgets('every map draws through the cache', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SizedBox(
            width: 393,
            height: 400,
            child: RouteMap(
              points: <RunPoint>[
                RunPoint(
                  latitude: 53.8008,
                  longitude: -1.5491,
                  accuracyMeters: 5,
                  timestamp: DateTime(2026, 10, 1, 8),
                ),
                RunPoint(
                  latitude: 53.8018,
                  longitude: -1.5501,
                  accuracyMeters: 5,
                  timestamp: DateTime(2026, 10, 1, 8, 1),
                ),
              ],
              tileUrlTemplate: _esri,
              attribution: 'Powered by Esri',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final TileLayer layer = tester.widget<TileLayer>(find.byType(TileLayer));
    final provider = layer.tileProvider;
    expect(provider, isA<NetworkTileProvider>());
    expect(
      (provider as NetworkTileProvider).cachingProvider,
      isA<BuiltInMapCachingProvider>(),
    );
  });
}
