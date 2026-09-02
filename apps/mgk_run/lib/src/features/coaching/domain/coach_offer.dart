/// What is actually on sale, as the store describes it.
///
/// **Every field here comes from the storefront.** Nothing is computed, and
/// nothing is compiled in. `plan_gate_copy.dart` carries the two figures
/// [ADR-0029](../../../../docs/decisions/0029-what-a-tier-costs-and-buys.md)
/// settled, and carries them as the record `limits.ts` is sized against rather
/// than as anything a runner is shown: a price typed into the binary is right
/// in one storefront and wrong in every other, it is stale the moment pricing
/// moves, and Apple expects the figure on screen to be the localised one
/// StoreKit hands back.
///
/// So [price] is a **string**, not a number. It arrives pre-formatted with its
/// own currency symbol and its own decimal convention, and the app's job is to
/// print it rather than to understand it.
class CoachOffer {
  const CoachOffer({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
  });

  /// The App Store product identifier. The same string
  /// `REVENUECAT_PRODUCTS` maps to a `core.entitlements` product server-side,
  /// which is why it is configuration on both sides rather than code on either.
  final String id;

  /// The tier's name, as written in App Store Connect.
  final String title;

  /// What the tier buys, as written in App Store Connect.
  final String description;

  /// The localised price, formatted by the store. Print it; do not parse it.
  final String price;
}

/// What came back from asking the store for money.
///
/// A closed set, because every one of these needs a different sentence on
/// screen and "something went wrong" is the wrong sentence for three of them.
/// A cancelled purchase in particular is not an error: it is somebody deciding
/// not to buy, and telling them the app failed would be both untrue and rude.
enum PurchaseOutcome {
  /// The store took the money. **This does not mean the coach is unlocked** —
  /// the entitlement is written by the RevenueCat webhook and read back from
  /// `core.entitlements`, and those two things race. See
  /// `PurchaseScreen._afterPurchase`.
  purchased,

  /// The runner backed out. Say nothing; they know what they did.
  cancelled,

  /// A restore that found no previous purchase to restore. Apple requires the
  /// button; it does not promise the button will find anything.
  nothingToRestore,

  /// The store refused, the network died, or the SDK is not configured.
  failed;

  bool get isPurchased => this == PurchaseOutcome.purchased;
}
