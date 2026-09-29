import '../domain/coach_offer.dart';

/// Presents what is for sale and takes a payment. **That is all it does.**
///
/// ## It is deliberately not asked what the runner owns
///
/// There is no `isSubscribed` on this interface and there will not be one.
/// RevenueCat's SDK can answer that question on device — `CustomerInfo`
/// carries active entitlements — and using the answer would replace a fact
/// with a claim, which is the exact property `coach_access.dart` exists to
/// hold. What the runner is entitled to is read from `core.entitlements`
/// through [EntitlementRepository], written only by the webhook, and enforced
/// server-side by `tierFor`
/// ([ADR-0030](../../../../docs/decisions/0030-the-coach-is-the-paid-half.md)).
///
/// The seam is the point. A purchase screen that talks to this interface can
/// be driven end to end in a widget test with no store, no network and no
/// native plugin, which is the only way any of this gets tested from Windows.
abstract class PurchaseClient {
  /// Ties purchases to the Supabase user id.
  ///
  /// **Load-bearing.** The webhook keys `core.entitlements` on the app user id
  /// RevenueCat reports, and refuses an `RCAnonymousID:` rather than writing a
  /// row to nobody. A purchase made before this is called is a purchase the
  /// backend cannot attribute.
  Future<void> identify(String userId);

  /// What is on sale, in the runner's own currency.
  ///
  /// Empty is a normal answer, not an error: a build with no key configured, a
  /// storefront with no products yet, or a device that cannot reach the store.
  /// The screen says so rather than showing an empty list of nothing.
  Future<List<CoachOffer>> offers();

  /// Buys [offer]. Returns what happened; throws nothing a caller must catch.
  Future<PurchaseOutcome> buy(CoachOffer offer);

  /// Re-applies a purchase made on another device or before a reinstall.
  ///
  /// **Apple requires this to exist** for any app selling a non-consumable or
  /// a subscription, and requires it to be reachable without buying anything
  /// first. RevenueCat performs it; the app still has to give it a surface.
  ///
  /// Refused with [PurchaseOutcome.notIdentified] while nobody is signed in,
  /// for the reason [buy] is: a receipt restored onto nobody -- or onto
  /// whoever was signed in last -- reaches no coach, or the wrong one.
  Future<PurchaseOutcome> restore();

  /// Detaches purchases from the account that has just left.
  ///
  /// **Nothing called this.** Signing out ended the Supabase session and left
  /// the store attached to the account that had gone, so a purchase made
  /// afterwards -- signed out, or as somebody else before their identify had
  /// landed -- was attributed to the previous account, and the person who
  /// paid got nothing. Must not throw; there is nothing a runner could do
  /// about it on the way out.
  Future<void> logOut();
}
