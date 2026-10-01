import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';
import 'package:latlong2/latlong.dart';

/// How a tile provider cuts up the world: how large one tile is drawn, and how
/// far its zoom levels sit from the map's own.
///
/// **Read off the template, not configured beside it.** The grid is a fact
/// about the service the template names, so a second setting could only ever
/// agree with the first or be wrong, and wrong is quiet: the tiles still load,
/// at half or twice the size they were meant to be.
class TileGrid {
  const TileGrid({required this.dimension, required this.zoomOffset});

  /// Logical pixels along one side of a tile.
  final int dimension;

  /// Added to the map's zoom to get the level asked of the provider.
  final double zoomOffset;

  /// 256-point tiles whose levels are the map's own, which is what nearly
  /// every provider serves. A `@2x` image on this grid is the same tile drawn
  /// sharper, not a larger one.
  static const TileGrid standard = TileGrid(dimension: 256, zoomOffset: 0);

  /// ArcGIS Static Basemap Tiles: 512-pixel images, drawn at 256 points, on
  /// the map's own levels. Two pixels to the point.
  /// (The same service is why the template reads `{z}/{y}/{x}`, row first.)
  ///
  /// **Sharp, with small labels.** Builds 27 and 28 drew each image at 512
  /// points from the level below, which is the size Esri labels them for. On
  /// a phone that is one image pixel stretched over three of the screen's, and
  /// it was seen at once: "a little more blurry than the MapTiler one", which
  /// had been served at two pixels a point. There is no `@2x` on this service,
  /// so the choice is between the two halves of that sentence. Drawn this way
  /// the streets are crisp and their names are half the size: small, and
  /// legible because they are sharp.
  ///
  /// What it costs: about twice as many tiles for the same map (smaller ones,
  /// so about a fifth more data), against a free allowance of two million a
  /// month. To go back, this is `dimension: 512, zoomOffset: -1`.
  static const TileGrid esriStatic = TileGrid(dimension: 256, zoomOffset: 0);

  static TileGrid of(String urlTemplate) =>
      urlTemplate.contains('static-basemap-tiles-service')
      ? esriStatic
      : standard;
}

/// The basemap tiles this phone has already been shown, kept on the phone.
///
/// **A cache, and only a cache.** flutter_map already keeps every tile it
/// draws in the app's cache directory, which the system may empty when storage
/// is short and which is in no backup of ours: nothing here is sent anywhere,
/// and nothing is stored that the runner's own map did not ask for. What this
/// file adds is three things the default does not do.
///
/// **A saved tile is used when the network cannot be.** The provider marks a
/// tile fresh for a day, after which the default asks again and, with no
/// signal, draws nothing over a copy it is holding. A runner who loses signal
/// on a road they ran last week got a blank ground. See [OfflineTileClient].
///
/// **The key leaves the token out.** The default key is the whole address,
/// token included, so the day the provider's key is rotated every saved tile
/// would be orphaned at once. See [basemapTileKey].
///
/// **The tiles around the runner are loaded when the app opens**, so the map
/// is already there when they press Start. See [BasemapWarmUp].
///
/// What it deliberately is not: an offline map. Nothing downloads an area.
/// Esri's terms forbid "systematically requesting ArcGIS tiles for offline
/// use", and the warm-up asks only for the tiles the start screen is about to
/// draw.
MapCachingProvider basemapCache() =>
    BuiltInMapCachingProvider.getOrCreateInstance(
      // The default is a gigabyte. A year of one runner's streets is a small
      // fraction of this, and a running app has no business holding more.
      maxCacheSize: 200 * 1000 * 1000,
      tileKeyGenerator: basemapTileKey,
    );

/// A saved tile's name: its address without the query, where the token lives.
String basemapTileKey(String url) {
  final int query = url.indexOf('?');
  return BuiltInMapCachingProvider.uuidTileKeyGenerator(
    query < 0 ? url : url.substring(0, query),
  );
}

/// One client for every tile request the app makes, so they share a pool.
///
/// Never closed: it lives as long as the process, like the cache behind it.
final http.Client _network = RetryClient(http.Client());

/// The tile provider every map in the app draws through.
NetworkTileProvider basemapTileProvider() {
  final MapCachingProvider cache = basemapCache();
  return NetworkTileProvider(
    httpClient: OfflineTileClient(cache: cache, inner: _network),
    cachingProvider: cache,
  );
}

/// Answers a tile request from the saved copy when the network cannot.
///
/// HTTP allows exactly this: a cache may use a stale response when it is
/// disconnected. It sits under flutter_map's own loader, which goes on
/// deciding what is fresh; this is asked only once that loader has already
/// chosen to go to the network, and steps in only when the network fails.
///
/// **A refusal counts as a failure.** The provider's free tier stops serving
/// when its monthly allowance is spent, and a map that goes blank for
/// everybody on the 27th is worse than one that keeps drawing the streets it
/// already has.
class OfflineTileClient extends http.BaseClient {
  OfflineTileClient({required this.cache, required http.Client inner})
    : _inner = inner;

  final MapCachingProvider cache;
  final http.Client _inner;

  /// How long an answer given from the saved copy is treated as fresh.
  ///
  /// Long enough that a run through a dead spot does not ask the network for
  /// the same tile every time the map moves; short enough that the real tile
  /// is fetched soon after the signal returns.
  static const Duration heldFor = Duration(minutes: 5);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final http.StreamedResponse response;
    try {
      response = await _inner.send(request);
    } on http.RequestAbortedException {
      // The map moved on and no longer wants this tile. Not a failure.
      rethrow;
    } catch (_) {
      final Uint8List? saved = await _saved(request.url);
      if (saved == null) rethrow;
      return _answer(request, saved);
    }

    if (response.statusCode == 200 || response.statusCode == 304) {
      return response;
    }
    final Uint8List? saved = await _saved(request.url);
    if (saved == null) return response;
    // The refusal's body is not wanted; let its connection go.
    unawaited(response.stream.drain<void>().catchError((Object _) {}));
    return _answer(request, saved);
  }

  Future<Uint8List?> _saved(Uri url) async {
    if (!cache.isSupported) return null;
    try {
      return (await cache.getTile(url.toString()))?.bytes;
    } catch (_) {
      // Unreadable is the same as absent: the caller reports the network's
      // own failure.
      return null;
    }
  }

  http.StreamedResponse _answer(http.BaseRequest request, Uint8List bytes) =>
      http.StreamedResponse(
        Stream<List<int>>.value(bytes),
        200,
        contentLength: bytes.length,
        request: request,
        headers: <String, String>{
          'content-type': 'image/png',
          'cache-control': 'max-age=${heldFor.inSeconds}',
          // With an age, flutter_map needs no date to work out freshness.
          'age': '0',
        },
      );
}

/// Loads the tiles around the runner before they ask for a map.
///
/// **Only what the start screen is about to draw**: the screen at the run's
/// own zoom, and the one ring of tiles flutter_map loads around any map it
/// shows. A few dozen tiles, asked for once per place, and only the ones
/// not already saved. If the runner starts somewhere else the warm-up simply
/// did not help, and the map loads as it always did.
///
/// **It never asks for location.** It reads the phone's last known position,
/// which costs nothing and switches no GPS on, and only when the runner has
/// already allowed location. With no permission or no position it does
/// nothing at all.
class BasemapWarmUp {
  BasemapWarmUp({
    required this.urlTemplate,
    required this.cache,
    required this.position,
    http.Client? client,
    this.zoom = 16,
    this.screen = const Size(430, 932),
  }) : _client = client ?? _network;

  final String urlTemplate;
  final MapCachingProvider cache;

  /// Where the phone last knew it was, or null. Must not prompt.
  final Future<LatLng?> Function() position;

  final http.Client _client;

  /// The zoom the start and in-run maps open at.
  final int zoom;

  /// The largest phone the app supports, so the set covers every smaller one.
  final Size screen;

  /// The centre tile of the last place warmed. Opening the app twice in one
  /// place reads nothing and asks for nothing.
  ({int x, int y})? _warmed;

  Future<void>? _running;

  /// Runs once now and again whenever the app comes back to the front, for
  /// as long as the app lives: the binding holds the listener, and the
  /// listener holds this.
  void start() {
    unawaited(run());
    _resumes ??= AppLifecycleListener(onResume: () => unawaited(run()));
  }

  AppLifecycleListener? _resumes;

  /// Fetches whatever is missing around the last known position. Never throws,
  /// and overlapping calls share one pass.
  Future<void> run() => _running ??= _run().whenComplete(() => _running = null);

  Future<void> _run() async {
    try {
      if (urlTemplate.isEmpty || !cache.isSupported) return;
      final LatLng? at = await position();
      if (at == null) return;

      final ({int x, int y}) here = _tileAt(at);
      if (_warmed == here) return;

      for (final TileCoordinates tile in tilesAround(at)) {
        await _fetch(urlFor(tile));
      }
      _warmed = here;
    } catch (_) {
      // A warm-up that fails is a map that loads when it is opened, which is
      // what happened before there was one.
    }
  }

  ({int x, int y}) _tileAt(LatLng at) {
    final Offset centre = const Epsg3857().latLngToOffset(at, zoom.toDouble());
    final double size = TileGrid.of(urlTemplate).dimension.toDouble();
    return (x: (centre.dx / size).floor(), y: (centre.dy / size).floor());
  }

  /// The tiles a map centred on [at] draws on [screen], with flutter_map's
  /// one-tile ring around them, row by row.
  List<TileCoordinates> tilesAround(LatLng at) {
    final TileGrid grid = TileGrid.of(urlTemplate);
    const Crs crs = Epsg3857();
    final Offset centre = crs.latLngToOffset(at, zoom.toDouble());
    final double size = grid.dimension.toDouble();
    final int x0 = ((centre.dx - screen.width / 2) / size).floor() - 1;
    final int x1 = ((centre.dx + screen.width / 2) / size).floor() + 1;
    final int y0 = ((centre.dy - screen.height / 2) / size).floor() - 1;
    final int y1 = ((centre.dy + screen.height / 2) / size).floor() + 1;
    return <TileCoordinates>[
      for (int y = y0; y <= y1; y++)
        for (int x = x0; x <= x1; x++) TileCoordinates(x, y, zoom),
    ];
  }

  /// The address flutter_map itself would ask for [tile] at, so a tile saved
  /// here is found under the same key when the map wants it.
  String urlFor(TileCoordinates tile) => _addresses.getTileUrl(tile, _layer);

  late final NetworkTileProvider _addresses = NetworkTileProvider(
    httpClient: _client,
    cachingProvider: cache,
  );

  late final TileLayer _layer = TileLayer(
    urlTemplate: urlTemplate,
    tileDimension: TileGrid.of(urlTemplate).dimension,
    zoomOffset: TileGrid.of(urlTemplate).zoomOffset,
    tileProvider: _addresses,
  );

  Future<void> _fetch(String url) async {
    try {
      if (await cache.getTile(url) != null) return;
    } catch (_) {
      // Unreadable: fetch it again below and write over it.
    }
    final http.Response response = await _client
        .get(
          Uri.parse(url),
          headers: const <String, String>{
            'User-Agent': 'flutter_map (com.mgkcodes.fitness.run)',
          },
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) return;
    await cache.putTile(
      url: url,
      metadata: CachedMapTileMetadata.fromHttpHeaders(response.headers),
      bytes: response.bodyBytes,
    );
  }
}
