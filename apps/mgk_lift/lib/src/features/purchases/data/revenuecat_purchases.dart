import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as rc;

import '../../entitlement/domain/entitlement.dart';
import '../domain/purchases.dart';

/// [Purchases] over RevenueCat's SDK.
///
/// Ported from Run's `RevenueCatPurchases`, which met real stores first and
/// paid for two lessons this keeps: the customer must be a Supabase user before
/// anything is bought, and a store's product title is not fit to print. The
/// second does not apply here — Lift names its tiers itself
/// ([EntitlementTier.label]) — so only the first is carried.
///
/// **This class never decides what anybody owns.** It offers, it buys, it
/// restores. The row that unlocks the paid half is written by the `revenuecat`
/// Edge Function from a server-to-server webhook and read back through
/// `SupabaseEntitlements`; [PurchaseFlow] waits for that row rather than
/// believing the store.
///
/// ## One RevenueCat customer spans both apps
///
/// Run and Lift share a RevenueCat project and a Supabase login, so the
/// customer this SDK reports holds **Run's** subscriptions too. Everything that
/// reads the customer's purchases filters to Lift's own products first; a Run
/// subscriber pressing Restore in Lift must hear "nothing to restore", not
/// "restored" followed by a paywall that never lifts.
class RevenueCatPurchases implements Purchases {
  RevenueCatPurchases({required String apiKey}) : _apiKey = apiKey;

  final String _apiKey;

  /// Configured lazily rather than in `main()`. Tracking needs no account and
  /// most lifters never open a paywall, so a network-touching SDK has no
  /// business in the launch path.
  bool _configured = false;

  /// The packages behind the last [offers] call, so [buy] can hand the SDK the
  /// object it actually wants rather than a product id.
  final Map<String, rc.Package> _packages = <String, rc.Package>{};

  /// The last user [identify] was asked for, kept so [buy] can retry the
  /// attachment at the one moment it matters.
  String? _userId;

  /// Whether [productId] is one of Lift's, the new tiers or Liftio's legacy
  /// pair. Play reports a subscription as `product:basePlan`, so the prefix is
  /// what is compared.
  @visibleForTesting
  static bool isLiftProduct(String productId) =>
      productId.startsWith('lift.') || productId.startsWith('liftio_');

  /// Which tier a store product buys. The product id is the only thing both
  /// stores agree on, and the webhook maps the same ids the same way through
  /// `REVENUECAT_PRODUCTS`: anything with `premium` in it is Premium Coach.
  @visibleForTesting
  static EntitlementTier tierOf(String productId) =>
      productId.contains('premium')
      ? EntitlementTier.premium
      : EntitlementTier.paid;

  /// An ISO 8601 period as a word the paywall can print after a price.
  @visibleForTesting
  static String periodOf(String? iso) => switch (iso) {
    'P1W' => 'week',
    'P1Y' || 'P12M' => 'year',
    'P3M' => '3 months',
    'P6M' => '6 months',
    _ => 'month',
  };

  Future<bool> _ready() async {
    if (_configured) return true;
    if (_apiKey.isEmpty) return false;
    try {
      await rc.Purchases.configure(rc.PurchasesConfiguration(_apiKey));
      _configured = true;
      return true;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> identify(String userId) async {
    _userId = userId;
    if (!await _ready()) return;
    try {
      await rc.Purchases.logIn(userId);
    } on PlatformException {
      // Quiet on purpose: nothing a lifter could do about it mid-launch, and
      // [_identified] tries again at the point of sale.
    }
  }

  @override
  Future<void> forget() async {
    _userId = null;
    if (!_configured) return;
    try {
      // logOut throws for a customer who is already anonymous, which is the
      // state this is asking for anyway.
      if (await rc.Purchases.isAnonymous) return;
      await rc.Purchases.logOut();
    } on PlatformException {
      // Nothing to undo. The next identify replaces whoever was attached.
    }
  }

  /// Whether the SDK is attached to a real Supabase user, retrying once.
  ///
  /// RevenueCat starts every install on an `$RCAnonymousID:` and the webhook
  /// refuses to write a row for one, so a purchase made in that state takes
  /// money and grants nothing. Run shipped without this check once (build 12,
  /// 2026-09-04) and a paying subscriber sat in front of a paywall no relaunch
  /// could clear.
  Future<bool> _identified() async {
    try {
      if (!await rc.Purchases.isAnonymous) return true;
      final id = _userId;
      if (id == null) return false;
      await rc.Purchases.logIn(id);
      return !await rc.Purchases.isAnonymous;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<List<PurchaseOffer>> offers() async {
    if (!await _ready()) return const <PurchaseOffer>[];
    try {
      final offerings = await rc.Purchases.getOfferings();
      final packages = <rc.Package>[
        for (final p
            in offerings.current?.availablePackages ?? const <rc.Package>[])
          if (isLiftProduct(p.storeProduct.identifier)) p,
      ];
      _packages
        ..clear()
        ..addEntries(
          packages.map((p) => MapEntry(p.storeProduct.identifier, p)),
        );
      final offers = <PurchaseOffer>[
        for (final p in packages)
          PurchaseOffer(
            id: p.storeProduct.identifier,
            tier: tierOf(p.storeProduct.identifier),
            // Formatted by the store in the lifter's own currency. Printed,
            // never parsed.
            price: p.storeProduct.priceString,
            period: periodOf(p.storeProduct.subscriptionPeriod),
          ),
      ];
      // Coach before Premium Coach, whatever order the dashboard holds them
      // in: the paywall reads top to bottom as "more", and a reordered
      // offering should not reorder the argument.
      offers.sort((a, b) => a.tier.index.compareTo(b.tier.index));
      return offers;
    } on PlatformException {
      // An empty shop and a broken shop are the same fact to a lifter, and the
      // paywall says the same true thing about both.
      return const <PurchaseOffer>[];
    }
  }

  @override
  Future<PurchaseStatus> buy(PurchaseOffer offer) async {
    if (!await _ready()) return PurchaseStatus.failed;
    // Before the store, never after. A payment we cannot attribute is worse
    // than a sale we did not make.
    if (!await _identified()) return PurchaseStatus.notSignedIn;

    var package = _packages[offer.id];
    if (package == null) {
      // The offer outlived its packages — a rebuilt sheet, a resumed app.
      // Fetch again rather than fail at the exact moment somebody decided to
      // pay.
      await offers();
      package = _packages[offer.id];
    }
    if (package == null) return PurchaseStatus.failed;

    try {
      await rc.Purchases.purchase(
        rc.PurchaseParams.package(
          package,
          productChangeInfo: await _replacing(offer.id),
        ),
      );
      return PurchaseStatus.entitled;
    } on PlatformException catch (e) {
      return rc.PurchasesErrorHelper.getErrorCode(e) ==
              rc.PurchasesErrorCode.purchaseCancelledError
          ? PurchaseStatus.cancelled
          : PurchaseStatus.failed;
    }
  }

  /// On Play, a switch between tiers has to name the subscription it
  /// replaces, or Google sells a second one beside it and charges for both.
  /// The App Store does this itself from the subscription group, so this is
  /// Android only.
  ///
  /// Rare by construction — the paywall is only shown to somebody the server
  /// says is not entitled — but reachable in the seconds before a webhook
  /// lands, which is exactly when somebody taps twice.
  Future<rc.StoreProductChangeInfo?> _replacing(String productId) async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final info = await rc.Purchases.getCustomerInfo();
      for (final active in info.activeSubscriptions) {
        if (!isLiftProduct(active) || active == productId) continue;
        return rc.StoreProductChangeInfo(
          // Play's old-product id is the subscription, without its base plan.
          active.split(':').first,
          replacementMode: rc.StoreReplacementMode.withTimeProration,
        );
      }
    } on PlatformException {
      // Unknown is treated as none: the store still refuses a genuine
      // duplicate of the same product.
    }
    return null;
  }

  @override
  Future<PurchaseStatus> restore() async {
    if (!await _ready()) return PurchaseStatus.failed;
    // A restore while anonymous attaches the receipt to nobody, and the
    // webhook would refuse it. Saying "sign in first" is the useful answer.
    if (!await _identified()) return PurchaseStatus.notSignedIn;
    try {
      final info = await rc.Purchases.restorePurchases();
      // **The one place the SDK's own view is read, and it grants nothing.**
      // It picks the sentence — restored, or nothing to restore — while the
      // paid half still unlocks only when the server has the row.
      return info.activeSubscriptions.any(isLiftProduct)
          ? PurchaseStatus.entitled
          : PurchaseStatus.nothingToRestore;
    } on PlatformException {
      return PurchaseStatus.failed;
    }
  }
}
