import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_subscription.dart';
import 'package:mgk_run/src/features/legal/domain/account_deleter.dart';
import 'package:mgk_run/src/features/legal/domain/legal_copy.dart';
import 'package:mgk_run/src/features/settings/presentation/account_screen.dart';

class _NeverDeleter implements AccountDeleter {
  @override
  Future<AccountDeletionResult> deleteAccount() async =>
      throw StateError('the test must not reach deletion');
}

/// **"Not included in backup" was a promise nothing kept.**
///
/// The account screen, the photo purpose string and the privacy policy all
/// said the profile photo was excluded from backup, so a new phone started
/// again with initials. Nothing excludes it: no NSURLIsExcludedFromBackupKey,
/// no Android backup rules, and it sits in the documents directory both
/// platforms back up. The same was true of "with it off, your phone is the
/// only copy, and an uninstall loses everything".
///
/// What is true, and what these pin: the photo is never sent to us or to the
/// coach, and the phone's own backup may carry it.
void main() {
  /// Lower case, curly apostrophes straightened, whitespace collapsed: the
  /// app's copy uses ’ and the markdown wraps at 80 columns.
  String flat(String text) => text
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAll(RegExp(r'[*_`]'), '')
      .replaceAll(RegExp(r'\s+'), ' ');

  final renderings = <String, String Function()>{
    'legal_copy.dart': () => flat(privacyPolicy.allText.join(' ')),
    'docs/privacy-policy.md': () =>
        flat(File('docs/privacy-policy.md').readAsStringSync()),
    'the published page': () => flat(
      File('../../web/public/run/privacy-policy.html').readAsStringSync(),
    ),
  };

  renderings.forEach((where, read) {
    test('$where no longer promises what backup does not do', () {
      final text = read();
      for (final claim in <String>[
        'not included in backup',
        'a new phone starts again with your initials',
        'your phone is the only copy',
        'an uninstall loses everything',
      ]) {
        expect(text, isNot(contains(claim)), reason: '$where: "$claim"');
      }
      expect(text, contains('never uploaded to us or sent to your coach'));
      expect(text, contains("phone's own backup"));
    });
  });

  test('the photo purpose string makes only the claim that holds', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final string = RegExp(
      r'<key>NSPhotoLibraryUsageDescription</key>\s*<string>([^<]*)</string>',
    ).firstMatch(plist)!.group(1)!;

    expect(string, isNot(contains('backup')));
    expect(string, contains('never uploaded to us'));
    expect(string, contains('never sent to your coach'));
  });

  testWidgets('the account screen says the same where the photo is chosen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: AccountScreen(
          auth: FakeAuthRepository(signedIn: true, email: 'sam@example.com'),
          deleter: _NeverDeleter(),
          subscription: CoachSubscription.none,
          memberSince: null,
          name: 'Sam',
          photo: null,
          onSignOut: () async {},
          onEditName: () async {},
          onPickPhoto: () async {},
          onRemovePhoto: null,
          onCreateAccount: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('not included in backup'), findsNothing);
    expect(find.textContaining('never uploaded to us'), findsOneWidget);
    expect(find.textContaining("phone's own backup"), findsOneWidget);
  });
}
