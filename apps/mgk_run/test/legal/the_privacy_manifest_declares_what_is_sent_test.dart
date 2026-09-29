import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **The privacy manifest declared three kinds of data and the app sends
/// nine.**
///
/// `PrivacyInfo.xcprivacy` listed health, precise location and an email
/// address. The coach sends the runner's own messages and their runs to the
/// AI provider, the account carries a name and an id, RevenueCat holds the
/// purchase, and the usage ledger records every request. A manifest that
/// under-declares against the App Privacy answers is the comparison App
/// Review makes, and it is not a comparison anyone makes by eye.
void main() {
  /// Each collected type, with its purposes, read out of the plist's XML.
  Map<String, Set<String>> declared() {
    final plist = File(
      'ios/Runner/PrivacyInfo.xcprivacy',
    ).readAsStringSync().replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
    final start = plist.indexOf('<key>NSPrivacyCollectedDataTypes</key>');
    final end = plist.indexOf('<key>NSPrivacyAccessedAPITypes</key>');
    final collected = plist.substring(start, end);
    return <String, Set<String>>{
      for (final entry in RegExp(
        r'<dict>(.*?)</dict>',
        dotAll: true,
      ).allMatches(collected))
        RegExp(
          r'<key>NSPrivacyCollectedDataType</key>\s*<string>(\w+)</string>',
        ).firstMatch(entry.group(1)!)!.group(1)!: <String>{
          for (final purpose in RegExp(
            r'<string>(NSPrivacyCollectedDataTypePurpose\w+)</string>',
          ).allMatches(entry.group(1)!))
            purpose.group(1)!,
        },
    };
  }

  const appFunctionality = 'NSPrivacyCollectedDataTypePurposeAppFunctionality';

  test('every kind of data the app sends is declared', () {
    expect(declared().keys, <String>{
      'NSPrivacyCollectedDataTypeHealth',
      'NSPrivacyCollectedDataTypePreciseLocation',
      'NSPrivacyCollectedDataTypeEmailAddress',
      'NSPrivacyCollectedDataTypeName',
      'NSPrivacyCollectedDataTypeUserID',
      'NSPrivacyCollectedDataTypePurchaseHistory',
      'NSPrivacyCollectedDataTypeOtherUserContent',
      'NSPrivacyCollectedDataTypeFitness',
      'NSPrivacyCollectedDataTypeProductInteraction',
    });
  });

  test('each is for the app working, and purchases for analytics too', () {
    for (final MapEntry(key: type, value: purposes) in declared().entries) {
      expect(purposes, contains(appFunctionality), reason: type);
    }
    expect(
      declared()['NSPrivacyCollectedDataTypePurchaseHistory'],
      contains('NSPrivacyCollectedDataTypePurposeAnalytics'),
      reason: 'RevenueCat describes its own collection that way',
    );
  });

  test('nothing is declared as tracking', () {
    final plist = File('ios/Runner/PrivacyInfo.xcprivacy').readAsStringSync();
    expect(
      RegExp(
        r'<key>NSPrivacyCollectedDataTypeTracking</key>\s*<true/>',
      ).hasMatch(plist),
      isFalse,
    );
    expect(
      RegExp(r'<key>NSPrivacyTracking</key>\s*<false/>').hasMatch(plist),
      isTrue,
    );
  });
}
