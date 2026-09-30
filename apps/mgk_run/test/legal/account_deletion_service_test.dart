import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mgk_auth/mgk_auth.dart';
import 'package:mgk_run/src/features/legal/data/account_deletion_service.dart';
import 'package:mgk_run/src/features/legal/domain/account_deleter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What the service sends to `delete-account`, and when it sends nothing.
void main() {
  late List<Map<String, Object?>> sent;

  AccountDeletionService service(AppleRevocation apple) =>
      AccountDeletionService(
        client: SupabaseClient(
          'https://project.example',
          'publishable',
          httpClient: MockClient((request) async {
            sent.add(jsonDecode(request.body) as Map<String, Object?>);
            return http.Response(
              jsonEncode(<String, Object?>{
                'account_deleted': true,
                'deleted_rows': <String, int>{},
              }),
              200,
              headers: <String, String>{'content-type': 'application/json'},
            );
          }),
        ),
        apple: (_) async => apple,
      );

  setUp(() => sent = <Map<String, Object?>>[]);

  test("an Apple account's code goes with the request", () async {
    await service(
      const AppleCode(code: 'fresh', clientId: 'com.mgkcodes.fitness.run'),
    ).deleteAccount();

    expect(sent.single, <String, Object?>{
      'app': 'run',
      'apple': <String, Object?>{
        'code': 'fresh',
        'client_id': 'com.mgkcodes.fitness.run',
      },
    });
  });

  test('with no code, the request names the app alone', () async {
    await service(const NoAppleCode()).deleteAccount();

    expect(sent.single, <String, Object?>{'app': 'run'});
  });

  test("closing Apple's sheet deletes nothing, and says so", () async {
    await expectLater(
      service(const AppleDeclined()).deleteAccount(),
      throwsA(
        isA<AccountDeletionException>().having(
          (e) => e.message,
          'message',
          startsWith('Nothing was deleted.'),
        ),
      ),
    );
    expect(sent, isEmpty);
  });
}
