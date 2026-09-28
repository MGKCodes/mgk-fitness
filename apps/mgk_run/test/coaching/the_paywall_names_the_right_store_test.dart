import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/data/revenuecat_purchases.dart';
import 'package:mgk_run/src/features/coaching/presentation/purchase_screen.dart';

/// **The paywall told Android customers about their Apple ID.**
///
/// Found 2026-09-11, the first time this screen was opened on Android with a
/// real `goog_` key behind it. Three sentences, all false, all within a tap of
/// a payment:
///
///   * "Payment is charged to your **Apple ID** … Manage or cancel it in your
///     Apple ID settings." — the auto-renew disclosure, which is the one
///     sentence on the screen a store actually checks.
///   * "No previous subscription found on this **Apple ID**."
///   * "Could not reach **the App Store**."
///
/// And the product rows read:
///
/// > Coach (com.mgkcodes.fitness.run (unreviewed))
///
/// because Google Play returns a product title with the app's name appended,
/// where the App Store returns the name alone.
///
/// **Nothing could have caught any of it before a real Play storefront
/// existed.** The preview harness and every existing test use fakes whose
/// titles are written by hand, and the disclosure was a const string that no
/// test read — it was correct for the only platform anybody had run.
void main() {
  group('the disclosure names the store taking the money', () {
    test('Android is told about Google Play', () {
      final wording = renewalWording(TargetPlatform.android);

      expect(wording, contains('Google Play account'));
      expect(wording, contains('Play Store'));
      expect(
        wording,
        isNot(contains('Apple')),
        reason:
            'a billing disclosure naming the wrong payment method is what '
            'Google checks rather than what it overlooks',
      );
    });

    test('iOS keeps Apple\'s own required phrasing, unchanged', () {
      final wording = renewalWording(TargetPlatform.iOS);

      expect(wording, contains('Apple ID at confirmation of purchase'));
      expect(wording, contains('Apple ID settings'));
      expect(wording, isNot(contains('Google')));
    });

    test('both say the four things a disclosure has to say', () {
      // Renews, when it is charged, how much notice cancelling needs, and where
      // to do it. Apple prescribes the sentence; Play prescribes the facts.
      for (final wording in <String>[
        renewalWording(TargetPlatform.iOS),
        renewalWording(TargetPlatform.android),
      ]) {
        expect(wording, contains('renew'));
        expect(wording, contains('24 hours'));
        expect(wording, contains('cancel'));
      }
    });
  });

  group('a product title does not repeat the app it belongs to', () {
    test('Play appends the app name, and it comes back off', () {
      // The exact string observed on the emulator, nested parentheses and all.
      expect(
        productTitle('Coach (com.mgkcodes.fitness.run (unreviewed))'),
        'Coach',
        reason:
            'cutting at the LAST bracket would leave '
            '"Coach (com.mgkcodes.fitness.run", which is worse than the bug',
      );
      // And what it will look like once Play has reviewed the listing.
      expect(productTitle('Premium Coach (MGKFitness: Run)'), 'Premium Coach');
    });

    test('an App Store title is already clean and stays that way', () {
      expect(productTitle('Coach'), 'Coach');
      expect(productTitle('Premium Coach'), 'Premium Coach');
    });

    test(
      'a title that is nothing but a parenthetical does not vanish oddly',
      () {
        // Defensive: whatever comes back, the result is a trimmed string rather
        // than a crash. An empty title is a storefront problem, not ours.
        expect(productTitle('(MGKFitness: Run)'), '');
      },
    );
  });
}
