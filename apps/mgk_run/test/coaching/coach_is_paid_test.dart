import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/data/coach_errors.dart';
import 'package:mgk_run/src/features/coaching/data/entitlement_repository.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_access.dart';

/// The coach is the paid half, and the app has to say so rather than fail.
///
/// See [ADR-0030](../../docs/decisions/0030-the-coach-is-the-paid-half.md). The
/// server half — `tierFor` refusing an unentitled caller — is asserted in
/// `supabase/functions/coach/entitlements_test.ts` against the real policy
/// function. This is the client half: what it reads, which direction it fails
/// in, and that a refusal is a door rather than an error.
void main() {
  group('reading what was bought', () {
    test('an active paid or premium row unlocks the coach', () {
      for (final product in <String>['paid', 'premium']) {
        expect(
          SupabaseEntitlements.accessFrom(<String, dynamic>{
            'product': product,
            'status': 'active',
          }),
          CoachAccess.subscribed,
          reason: '$product should unlock',
        );
      }
    });

    test('only active counts, and grace is the tempting mistake', () {
      // It reads like "still fine" and means "the store has not been paid".
      for (final status in <String>[
        'expired',
        'grace',
        'refunded',
        'revoked',
        'ACTIVE',
      ]) {
        expect(
          SupabaseEntitlements.accessFrom(<String, dynamic>{
            'product': 'premium',
            'status': status,
          }),
          CoachAccess.free,
          reason: '$status must not unlock',
        );
      }
    });

    test('no row, and an unknown product, are free', () {
      expect(SupabaseEntitlements.accessFrom(null), CoachAccess.free);
      for (final product in <String>['', 'pro', 'PAID', 'lifetime', 'paid ']) {
        expect(
          SupabaseEntitlements.accessFrom(<String, dynamic>{
            'product': product,
            'status': 'active',
          }),
          CoachAccess.free,
          reason: '${product.isEmpty ? '<empty>' : product} must not unlock',
        );
      }
    });
  });

  group('a refusal is a door, not a fault', () {
    test('it does not read as something to retry', () {
      const gate = CoachNotEntitledException();
      final message = gate.message.toLowerCase();

      // The sentence this replaced was "The coach hit a problem. Please try
      // again." — untrue, and it invites a retry guaranteed to be refused.
      expect(message, isNot(contains('problem')));
      expect(message, isNot(contains('try again')));
      expect(message, isNot(contains('error')));
      expect(message, isNot(contains('failed')));
    });

    test('it says what is still free, because most of the app is', () {
      final message = const CoachNotEntitledException().message.toLowerCase();
      expect(message, contains('subscription'));
      expect(message, contains('free'));
    });

    test('it is not a limit, because a limit clears on its own', () {
      // CoachLimitException means "come back later". This one never clears
      // without a purchase, so anything catching a limit to say "try in an
      // hour" must not catch this too.
      expect(
        const CoachNotEntitledException(),
        isNot(isA<CoachLimitException>()),
      );
      expect(const CoachNotEntitledException(), isA<CoachException>());
    });
  });
}
