import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../../core/config/app_config.dart';
import '../domain/coach_offer.dart';
import 'purchase_client.dart';

/// [PurchaseClient] over RevenueCat's SDK.
///
/// Chosen in
/// [ADR-0028](../../../../docs/decisions/0028-revenuecat-is-the-purchase-path.md):
/// the suite spans Apple and Google, and the five statuses in
/// `core.entitlements` are the hard part rather than the paywall.
///
/// **This class never decides what anybody owns.** It offers, it buys, it
/// restores. The row that grants a coach is written by the `revenuecat` Edge
/// Function from a server-to-server webhook and read back through
/// `SupabaseEntitlements`. Everything the SDK could tell us about entitlements
/// on device is deliberately unused, with one narrow exception noted on
/// [restore].
///
/// ## The key is configuration, not a secret
///
/// RevenueCat's public SDK key is designed to ship in a client, like the
/// Supabase publishable key beside it in `AppConfig`. The **webhook** secret is
/// the one that matters and it never leaves the server. An empty key is a
/// normal state rather than an error: a local build without one, or a build
/// made before the RevenueCat account existed. [isAvailable] answers it, and
/// the paywall says so plainly instead of showing an empty shop.
class RevenueCatPurchases implements PurchaseClient {
  RevenueCatPurchases({String? apiKey})
    : _apiKey = apiKey ?? AppConfig.current.revenueCatKey;

  final String _apiKey;

  /// Configured lazily rather than in `main()`. The app opens on a working
  /// tracker with no account and most runners never reach a paywall, so a
  /// network-touching SDK has no business in the launch path
  /// ([ADR-0019](../../../../docs/decisions/0019-onboarding-is-two-moments.md)).
  bool _configured = false;

  /// The packages behind the last [offers] call, so [buy] can hand the SDK the
  /// object it actually wants rather than a product id.
  final Map<String, Package> _packages = <String, Package>{};

  /// Whether this build can sell anything at all.
  bool get isAvailable => _apiKey.isNotEmpty;

  Future<bool> _ready() async {
    if (_configured) return true;
    if (_apiKey.isEmpty) return false;
    try {
      await Purchases.configure(PurchasesConfiguration(_apiKey));
      _configured = true;
      return true;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> identify(String userId) async {
    if (!await _ready()) return;
    try {
      await Purchases.logIn(userId);
    } on PlatformException {
      // Nothing to do about it here, and nothing to say. A purchase made
      // without this attaches to an anonymous id, which the webhook refuses
      // rather than writing a row to nobody -- so the failure surfaces as an
      // entitlement that never arrives, not as a payment that vanishes.
    }
  }

  @override
  Future<List<CoachOffer>> offers() async {
    if (!await _ready()) return const <CoachOffer>[];
    try {
      final Offerings offerings = await Purchases.getOfferings();
      final List<Package> packages =
          offerings.current?.availablePackages ?? const <Package>[];
      _packages
        ..clear()
        ..addEntries(
          packages.map(
            (Package p) =>
                MapEntry<String, Package>(p.storeProduct.identifier, p),
          ),
        );
      return <CoachOffer>[
        for (final Package p in packages)
          CoachOffer(
            id: p.storeProduct.identifier,
            title: p.storeProduct.title,
            description: p.storeProduct.description,
            // Formatted by the store, in the runner's own currency. The app
            // prints this and does not parse it.
            price: p.storeProduct.priceString,
          ),
      ];
    } on PlatformException {
      // An empty shop and a broken shop look the same to a runner, and the
      // screen says the same true thing about both: not available right now.
      return const <CoachOffer>[];
    }
  }

  @override
  Future<PurchaseOutcome> buy(CoachOffer offer) async {
    if (!await _ready()) return PurchaseOutcome.failed;
    Package? package = _packages[offer.id];
    if (package == null) {
      // The offer outlived its packages -- a rebuilt screen, a resumed app.
      // Re-fetch rather than fail, because failing here fails at the exact
      // moment somebody has decided to pay.
      await offers();
      package = _packages[offer.id];
    }
    if (package == null) return PurchaseOutcome.failed;
    try {
      // `purchase(PurchaseParams)` rather than the deprecated
      // `purchasePackage`. Same call, and the new shape is where win-back and
      // promotional offers live if either is ever worth having.
      await Purchases.purchase(PurchaseParams.package(package));
      return PurchaseOutcome.purchased;
    } on PlatformException catch (e) {
      return PurchasesErrorHelper.getErrorCode(e) ==
              PurchasesErrorCode.purchaseCancelledError
          ? PurchaseOutcome.cancelled
          : PurchaseOutcome.failed;
    }
  }

  @override
  Future<PurchaseOutcome> restore() async {
    if (!await _ready()) return PurchaseOutcome.failed;
    try {
      final CustomerInfo info = await Purchases.restorePurchases();
      // **The one place the SDK's own view is read, and it grants nothing.**
      // This decides which sentence to show -- "restored" or "nothing to
      // restore" -- and the coach still unlocks only when the webhook has
      // written a row and the server has read it back. Believing this instead
      // would replace a fact with a claim, which is what `coach_access.dart`
      // exists to prevent.
      return info.activeSubscriptions.isEmpty
          ? PurchaseOutcome.nothingToRestore
          : PurchaseOutcome.purchased;
    } on PlatformException {
      return PurchaseOutcome.failed;
    }
  }
}
