import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_auth/mgk_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

User _user({
  Map<String, Object?> metadata = const <String, Object?>{},
  List<String> providers = const <String>['email'],
  String createdAt = '2026-10-19T09:00:00Z',
  String? lastSignInAt = '2026-10-19T09:00:05Z',
}) => User.fromJson(<String, Object?>{
  'id': 'user-1',
  'aud': 'authenticated',
  'email': 'you@example.com',
  'created_at': createdAt,
  'last_sign_in_at': lastSignInAt,
  'app_metadata': <String, Object?>{'providers': providers},
  'user_metadata': metadata,
  'identities': <Object?>[
    for (final provider in providers)
      <String, Object?>{
        'id': '$provider-sub',
        'user_id': 'user-1',
        'provider': provider,
        'identity_data': <String, Object?>{'sub': '$provider-sub'},
      },
  ],
})!;

void main() {
  group("the account's name", () {
    test('display_name is the name', () {
      expect(
        displayNameOf(_user(metadata: {'display_name': ' Sam ', 'name': 'X'})),
        'Sam',
      );
    });

    test("Run's old name is read where Google cannot have written it", () {
      expect(displayNameOf(_user(metadata: {'name': 'Sam'})), 'Sam');
    });

    test("on a Google account, name is Google's, so it is not the name", () {
      expect(
        displayNameOf(
          _user(
            metadata: {'name': 'Samuel Smith'},
            providers: ['email', 'google'],
          ),
        ),
        isNull,
      );
    });

    test('blank is no name', () {
      expect(displayNameOf(_user(metadata: {'display_name': '  '})), isNull);
      expect(displayNameOf(null), isNull);
    });
  });

  group("Google's first name, to start the step filled in", () {
    test('the first word of the name Google sent', () {
      expect(
        googleFirstNameOf(
          _user(metadata: {'full_name': 'Samuel Smith'}, providers: ['google']),
        ),
        'Samuel',
      );
    });

    test('nothing for an account without Google, Apple included', () {
      expect(
        googleFirstNameOf(
          _user(metadata: {'full_name': 'Samuel Smith'}, providers: ['apple']),
        ),
        isNull,
      );
    });
  });

  group('whether the account was just made', () {
    test('made moments before this sign-in', () {
      expect(accountIsNew(_user()), isTrue);
    });

    test('made, then confirmed with a code a few minutes later', () {
      expect(accountIsNew(_user(lastSignInAt: '2026-10-19T09:12:00Z')), isTrue);
    });

    test('made days ago and signed into again', () {
      expect(
        accountIsNew(
          _user(
            createdAt: '2026-09-01T09:00:00Z',
            lastSignInAt: '2026-10-19T09:00:00Z',
          ),
        ),
        isFalse,
      );
    });

    test('no sign-in recorded, or no account, is not new', () {
      expect(accountIsNew(_user(lastSignInAt: null)), isFalse);
      expect(accountIsNew(null), isFalse);
    });
  });

  test('either record says which providers an account has', () {
    expect(hasIdentity(_user(providers: ['apple']), 'apple'), isTrue);
    expect(hasIdentity(_user(providers: ['email']), 'apple'), isFalse);
  });
}
