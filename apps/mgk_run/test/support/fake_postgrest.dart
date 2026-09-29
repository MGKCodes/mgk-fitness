import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// A PostgREST that answers on localhost and writes down what it was asked.
///
/// **Real requests, from the real client.** The data classes that talk to
/// Supabase build their queries with `supabase_flutter`, and the thing worth
/// asserting is the query itself -- which schema, which table, which filters.
/// A fake of the client's builder chain would test the fake; this lets the
/// client build and send exactly what it would in the app, and records it.
///
/// Plain `test()` only. `testWidgets` installs an HTTP override that answers
/// every request with a 400, so nothing would reach this.
class FakePostgrest {
  FakePostgrest._(this._server);

  final HttpServer _server;

  /// Every request, in the order it arrived.
  final List<PostgrestCall> calls = <PostgrestCall>[];

  /// What a read returns, by table. A read of a table with no entry gets an
  /// empty list. Writes get an empty success.
  final Map<String, List<Map<String, Object?>>> rows =
      <String, List<Map<String, Object?>>>{};

  static Future<FakePostgrest> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakePostgrest._(server);
    server.listen(fake._answer);
    return fake;
  }

  String get url => 'http://${_server.address.host}:${_server.port}';

  /// A client pointed at this server, signed in as [userId] when given --
  /// the mirror stamps rows with the session's user and refuses without one.
  Future<SupabaseClient> client({String? userId}) async {
    final client = SupabaseClient(
      url,
      'publishable-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    if (userId != null) {
      // An access token that is not a JWT has no expiry to check, so this
      // sets the session without a round trip.
      await client.auth.recoverSession(
        jsonEncode(<String, Object?>{
          'access_token': 'token',
          'token_type': 'bearer',
          'user': <String, Object?>{
            'id': userId,
            'aud': 'authenticated',
            'created_at': '2026-09-01T00:00:00Z',
            'app_metadata': <String, Object?>{},
            'user_metadata': <String, Object?>{},
          },
        }),
      );
    }
    return client;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _answer(HttpRequest request) async {
    final text = await utf8.decoder.bind(request).join();
    final call = PostgrestCall(
      method: request.method,
      uri: request.uri,
      schema:
          request.headers.value('content-profile') ??
          request.headers.value('accept-profile'),
      body: text.isEmpty ? null : jsonDecode(text),
    );
    calls.add(call);
    final response = request.response..headers.contentType = ContentType.json;
    if (call.method == 'GET') {
      response
        ..statusCode = 200
        ..write(jsonEncode(rows[call.table] ?? const <Object?>[]));
    } else {
      response.statusCode = 204;
    }
    await response.close();
  }
}

/// One request, as PostgREST would have seen it.
class PostgrestCall {
  const PostgrestCall({
    required this.method,
    required this.uri,
    required this.schema,
    required this.body,
  });

  final String method;
  final Uri uri;

  /// The Postgres schema, from the profile header the client sends.
  final String? schema;

  /// The decoded JSON body of a write, or null.
  final Object? body;

  /// The table, from `/rest/v1/<table>`.
  String get table => uri.pathSegments.last;

  /// A filter's raw value, e.g. `eq.run` for `app`.
  String? filter(String column) => uri.queryParameters[column];

  @override
  String toString() => '$method ${schema ?? '?'}.$table ${uri.query}';
}
