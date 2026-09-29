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

  /// **Refused before the store was called**, because the SDK is still on an
  /// anonymous id and the backend could not have attributed the payment.
  ///
  /// Distinct from [failed] on purpose: nothing was attempted, so nothing was
  /// charged and nothing needs undoing. Build 12 shipped without this and the
  /// first real sandbox purchase proved why — it went through as an
  /// `RCAnonymousID:`, the webhook refused to write a row to nobody
  /// (`unknown_app_user_id`), and the runner was left having paid with a coach
  /// that never unlocked and no relaunch that could fix it. Refusing to sell is
  /// the only outcome better than selling something we cannot deliver.
  notIdentified,

  /// The store has the payment and has not settled it -- a bank's extra
  /// check, a parent's approval, a slow payment method. **Not a failure**:
  /// the money may still move, and a runner told it failed would try again
  /// and could pay twice.
  pending,

  /// No connection to the store. Whether anything was charged is not
  /// something a dropped connection can say, so the screen does not say it.
  offline,

  /// This store account already has the subscription, or its receipt is
  /// attached to another account. Restoring is the way to it, not buying
  /// again.
  alreadyOwned,

  /// Anything else the store refused, or an SDK that is not configured.
  ///
  /// **Every refusal used to land here**, and the screen answered all of them
  /// with "Nothing has been charged" -- including a payment still pending,
  /// which may well be charged, and a subscription the runner already owns.
  failed;

  bool get isPurchased => this == PurchaseOutcome.purchased;
}
