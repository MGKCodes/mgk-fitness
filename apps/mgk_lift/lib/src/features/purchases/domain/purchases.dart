import 'package:meta/meta.dart';

import '../../entitlement/domain/entitlement.dart';

/// Buying the paid half, and getting it back.
///
/// A seam rather than a direct RevenueCat call, for the reason every other
/// `data`/`domain` split here exists: the paywall and the restore flow are
/// testable without a store, and the SDK stays in one file that can be replaced
/// without touching a screen. `docs/release-2.0.0.md` already names the exit —
/// if RevenueCat becomes the constraint, the webhook is swapped for two
/// validators and nothing client-side moves.

/// A tier the store will sell, as the store describes it.
///
/// **The price is a string from the store, never a constant here.** Apple and
/// Google localise price and currency per territory, so a hardcoded currency
/// symbol is simply wrong for most of the world, and it is the kind of wrong
/// that arrives with a screenshot attached to a rejection.
///
/// The tier's *name* does not come from the store either — see
/// [EntitlementTier.label]. What a tier is called is the app's decision and has
/// to read the same everywhere; what it costs is the store's answer and differs
/// by territory. Keeping the two in different places is the point.
@immutable
class PurchaseOffer {
  const PurchaseOffer({
    required this.id,
    required this.tier,
    required this.price,
    required this.period,
  });

  /// The store product identifier. Opaque here on purpose — mapping it to a
  /// tier is the webhook's job on the way in, and this field exists so support
  /// can match a screen to a receipt.
  final String id;

  /// Which tier this buys. Also where its name comes from —
  /// [EntitlementTier.label] — rather than from whatever was typed into App
  /// Store Connect, so the two stores cannot disagree about what a tier is
  /// called.
  final EntitlementTier tier;

  /// Localised and formatted by the store: `£1.00`, `$1.99`, `1,09 €`.
  final String price;

  /// Localised billing period: `month`. Kept separate from [price] so copy can
  /// join the two without parsing a string the store composed.
  final String period;
}

/// What happened, from the store's point of view and then the server's.
enum PurchaseStatus {
  /// Bought or restored, **and** `core.entitlements` now grants it. The only
  /// status that should change what the app shows.
  entitled,

  /// The store took the purchase and the server has not caught up.
  ///
  /// A real state rather than a failure, and the one most likely to be got
  /// wrong. RevenueCat's webhook writes `core.entitlements` asynchronously, so
  /// there is a window — usually a second, occasionally longer — where the
  /// person has paid and the row does not exist. Treating that as failure tells
  /// somebody their payment did not work when it did.
  pending,

  /// Backed out of the store sheet. **Not an error**, and must not be shown as
  /// one; the commonest reason to open a paywall is to look at the price.
  cancelled,

  /// Restore found nothing to restore. Distinct from a failure because the
  /// honest message is different — "there is nothing on this Apple ID" rather
  /// than "something went wrong" — and because Apple exercises this path.
  nothingToRestore,

  /// The store or the network refused. Carries a message safe to show.
  failed,
}

@immutable
class PurchaseResult {
  const PurchaseResult(this.status, {this.message});

  final PurchaseStatus status;

  /// Only set for [PurchaseStatus.failed], and only ever a sentence written for
  /// a person. Store SDKs surface internal codes; none of them belong on screen.
  final String? message;

  bool get changedEntitlement => status == PurchaseStatus.entitled;
}

/// The store, as this app needs it.
abstract interface class Purchases {
  /// What can be bought, in the order the paywall should show it. Empty when
  /// the store cannot be reached, which the paywall renders as "not open yet"
  /// rather than as an empty list of tiers.
  Future<List<PurchaseOffer>> offers();

  Future<PurchaseStatus> buy(PurchaseOffer offer);

  /// **Required by Guideline 3.1.1** for any app selling a subscription, and
  /// the only route back for somebody reinstalling or on a second device.
  Future<PurchaseStatus> restore();
}

/// Buying, and then agreeing with the server about it.
///
/// The two halves are deliberately separate. The store says whether money
/// moved; `core.entitlements` says what the app may show, and it is written by
/// the webhook rather than by anything here. This class is the join, and the
/// join is where the race lives.
class PurchaseFlow {
  const PurchaseFlow({
    required this.purchases,
    required this.gate,
    this.settleAttempts = 6,
    this.settleDelay = const Duration(milliseconds: 800),
  });

  final Purchases purchases;
  final EntitlementGate gate;

  /// How many times to re-ask the server after the store says yes.
  ///
  /// Six at 800ms is a little under five seconds. Long enough for the webhook
  /// on a normal day, short enough that somebody is not left watching a
  /// spinner — and when it runs out the answer is [PurchaseStatus.pending],
  /// which is honest, rather than a failure, which would not be.
  final int settleAttempts;
  final Duration settleDelay;

  Future<PurchaseResult> buy(PurchaseOffer offer) =>
      _settle(() => purchases.buy(offer));

  Future<PurchaseResult> restore() => _settle(purchases.restore);

  Future<PurchaseResult> _settle(Future<PurchaseStatus> Function() act) async {
    final PurchaseStatus store;
    try {
      store = await act();
    } on Object {
      // A throwing SDK is a failed purchase, not a crashed app. Nothing here
      // knows a message worth showing, so it does not invent one.
      return const PurchaseResult(
        PurchaseStatus.failed,
        message: 'The store could not complete that. Nothing has been charged.',
      );
    }

    // Cancelled, failed and nothing-to-restore all mean the entitlement cannot
    // have changed, so none of them are worth asking the server about.
    if (store != PurchaseStatus.entitled) return PurchaseResult(store);

    for (var attempt = 0; attempt < settleAttempts; attempt++) {
      if (await gate.isEntitled()) {
        return const PurchaseResult(PurchaseStatus.entitled);
      }
      // No sleep after the last look — it would only delay the answer.
      if (attempt < settleAttempts - 1) await Future<void>.delayed(settleDelay);
    }

    return const PurchaseResult(PurchaseStatus.pending);
  }
}

/// A scripted store, for tests and the preview.
class FakePurchases implements Purchases {
  FakePurchases({
    List<PurchaseOffer>? offers,
    this.onBuy = PurchaseStatus.entitled,
    this.onRestore = PurchaseStatus.entitled,
    this.throwOnBuy = false,
  }) : _offers = offers ?? const <PurchaseOffer>[coach, premiumCoach];

  /// Stand-ins for what a store would answer. **The prices here are fixtures,
  /// not the product's prices** — the real ones live in App Store Connect and
  /// Play Console and reach the app only through [Purchases.offers].
  static const PurchaseOffer coach = PurchaseOffer(
    id: 'lift.coach.monthly',
    tier: EntitlementTier.paid,
    price: '£1.00',
    period: 'month',
  );

  static const PurchaseOffer premiumCoach = PurchaseOffer(
    id: 'lift.premium_coach.monthly',
    tier: EntitlementTier.premium,
    price: '£3.00',
    period: 'month',
  );

  final List<PurchaseOffer> _offers;
  PurchaseStatus onBuy;
  PurchaseStatus onRestore;
  bool throwOnBuy;

  /// Every offer that was actually bought, so a test can assert the tier the
  /// person chose reached the store rather than the one the button defaulted to.
  final List<PurchaseOffer> bought = <PurchaseOffer>[];

  @override
  Future<List<PurchaseOffer>> offers() async => _offers;

  @override
  Future<PurchaseStatus> buy(PurchaseOffer offer) async {
    if (throwOnBuy) throw StateError('store unavailable');
    bought.add(offer);
    return onBuy;
  }

  @override
  Future<PurchaseStatus> restore() async => onRestore;
}
