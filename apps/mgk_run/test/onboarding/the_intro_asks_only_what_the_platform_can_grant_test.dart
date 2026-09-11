import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_permission.dart';

/// **Android cannot ask for Health, and the intro offered it anyway.**
///
/// Found on 2026-09-11 by installing build 22 on an Android emulator — the
/// first time this app had ever run on Android as a release build rather than
/// as a preview harness. Tapping "Allow Health" logs
/// `FLUTTER_HEALTH: Permission launcher not found`, because
/// `AndroidManifest.xml` declares no Health Connect permissions and the plugin
/// has nothing to launch. The request resolves to *not granted*, so the
/// conversation renders the runner's answer as **"Not now"** and the coach
/// replies "That is fine. We will start from the runs we do together instead."
///
/// The runner tapped **Allow** and was told they declined, on the screen whose
/// entire job is persuading a stranger to trust the app with their location
/// ninety seconds after meeting it.
///
/// It failed in the safe direction — a permission that cannot be granted reads
/// as refused, which is what `HealthKitWorkouts` documents for every one of its
/// own paths. That is why nothing caught it: no crash, no error, no red screen.
/// Only a person watching the wrong words appear.
void main() {
  group('the intro asks only for what the platform can grant', () {
    test('Android is not offered Health', () {
      final asked = introPermissionsFor(TargetPlatform.android);

      expect(
        asked.map((p) => p.kind),
        isNot(contains(IntroPermissionKind.healthKit)),
        reason:
            'Android has no Health Connect permissions in its manifest, so '
            'the step can only resolve to a refusal the runner did not make',
      );
      expect(
        asked.map((p) => p.kind),
        contains(IntroPermissionKind.location),
        reason: 'location is what recording needs and Android can grant it',
      );
    });

    test('iOS is offered both, unchanged', () {
      expect(
        introPermissionsFor(TargetPlatform.iOS).map((p) => p.kind),
        <IntroPermissionKind>[
          IntroPermissionKind.location,
          IntroPermissionKind.healthKit,
        ],
        reason:
            'the HealthKit path is real on iOS and this fix must not touch '
            'the platform it was written for',
      );
    });

    test('the order survives filtering', () {
      // Location first is a decision, not an accident: it is what recording
      // needs, so it is the one worth spending the runner's patience on. A
      // filter that reversed or reordered would be a silent regression, since
      // every caller indexes into this list by position.
      for (final platform in <TargetPlatform>[
        TargetPlatform.android,
        TargetPlatform.iOS,
      ]) {
        expect(
          introPermissionsFor(platform).first.kind,
          IntroPermissionKind.location,
        );
      }
    });

    test('the catalogue itself is untouched', () {
      // `introPermissionsFor` filters a view; it must not mutate the source.
      // Both entries stay, because the fix is about what Android is ASKED, not
      // about what the app knows how to ask for — and when Health Connect is
      // wired, removing the filter is the whole change.
      expect(introPermissions, hasLength(2));
    });
  });
}
