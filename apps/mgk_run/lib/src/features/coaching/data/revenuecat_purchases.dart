import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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
/// The product's name, with the app's name taken back off it.
///
/// **Google Play returns a product title as `"Coach (App Name)"`**, appending
/// the app it belongs to; the App Store returns `"Coach"`. Printed straight
/// through, the Android paywall read
///
/// > Coach (com.mgkcodes.fitness.run (unreviewed))
///
/// because before review Play uses the package name as the app name. Even
/// after review it would say "Coach (MGKFitness: Run)" — the app's own name,
/// repeated inside its own paywall, on every row.
///
/// Found 2026-09-11 the first time the paywall was opened on Android with a
/// real `goog_` key behind it. Nothing could have caught it earlier: the
/// preview harness and every test use fakes whose titles are written by hand,
/// so the only source of a Play-shaped title is Play.
///
/// **Strips a trailing parenthetical, greedily from the first `(`.** That
/// matters for the nested case above — cutting at the *last* `(` would leave
/// `"Coach (com.mgkcodes.fitness.run"`, which is worse than the bug. Applied to
/// every store rather than only Android, because a title that ends in its own
/// app name is wrong wherever it comes from, and Apple never produces one.
String productTitle(String raw) =>
    raw.replaceFirst(RegExp(r'\s*\(.*\)\s*$'), '').trim();

/// What a store error means for the runner, by RevenueCat's code for it.
///
/// **Five different things used to be one.** A payment still pending, a dead
/// connection, a subscription already owned and a receipt attached to another
/// account were all `failed`, and the screen told every one of them that
/// nothing had been charged. Two of those are statements about money the app
/// cannot make: a pending payment may well be charged, and a connection that
/// dropped mid-purchase does not say where the purchase got to.
PurchaseOutcome outcomeForError(PurchasesErrorCode code) => switch (code) {
  PurchasesErrorCode.purchaseCancelledError => PurchaseOutcome.cancelled,
  PurchasesErrorCode.paymentPendingError => PurchaseOutcome.pending,
  PurchasesErrorCode.networkError ||
  PurchasesErrorCode.offlineConnectionError => PurchaseOutcome.offline,
  PurchasesErrorCode.productAlreadyPurchasedError ||
  PurchasesErrorCode.receiptAlreadyInUseError ||
  PurchasesErrorCode.receiptInUseByOtherSubscriberError =>
    PurchaseOutcome.alreadyOwned,
  _ => PurchaseOutcome.failed,
};

/// [outcomeForError] for an exception off the platform channel, whose code
/// may not be one of RevenueCat's at all.
PurchaseOutcome _outcomeOf(PlatformException e) {
  try {
    return outcomeForError(PurchasesErrorHelper.getErrorCode(e));
  } on FormatException {
    return PurchaseOutcome.failed;
  }
}

class RevenueCatPurchases implements PurchaseClient {
  /// [AppConfig.storeKey], not `revenueCatKey`: the key differs per store and
  /// the wrong one does not degrade, it fails to configure at all.
  RevenueCatPurchases({String? apiKey})
    : _apiKey = apiKey ?? AppConfig.current.storeKey;

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

  /// The last id [identify] was asked for, kept so [buy] can try again.
  ///
  /// `HomeShell` calls `identify` unawaited from `initState`, so a failure
  /// there is silent and permanent for the session. Holding the id lets the
  /// one moment that actually matters retry it.
  ///
  /// **Cleared by [logOut].** It never was, so it answered for whoever had
  /// last signed in for the rest of the session.
  String? _userId;

  @override
  Future<void> identify(String userId) async {
    _userId = userId;
    if (!await _ready()) return;
    try {
      await Purchases.logIn(userId);
    } on PlatformException {
      // Deliberately quiet here -- there is nothing a runner could do about it
      // mid-launch, and [_identified] retries at the point of sale.
    }
  }

  /// Whether the SDK is attached to **the account signed in now**, retrying
  /// once.
  ///
  /// **This is the guard build 12 did not have.** RevenueCat starts every
  /// install on an `$RCAnonymousID:`, and the webhook refuses to write a row
  /// for one, so a purchase made in that state takes money and grants nothing.
  /// The previous code accepted that, reasoning the failure would surface as
  /// "an entitlement that never arrives" -- which on a real device on
  /// 2026-09-04 surfaced as a paying subscriber staring at a paywall that no
  /// relaunch would clear.
  ///
  /// **And then it asked the wrong question.** It checked only that the SDK
  /// was not anonymous, so once anybody had been identified it answered yes
  /// for good: signed out, or signed in as somebody whose identify had not
  /// landed, a purchase went to the previous account. It now asks whether the
  /// SDK's user *is* the signed-in account, and with nobody signed in the
  /// answer is no.
  Future<bool> _identified() async {
    final String? id = _userId;
    if (id == null) return false;
    try {
      if (await Purchases.appUserID == id) return true;
      // One retry, here rather than at launch: a transient logIn failure is
      // exactly the case worth recovering from, and this is the moment it
      // matters.
      await Purchases.logIn(id);
      return await Purchases.appUserID == id;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> logOut() async {
    _userId = null;
    // Never configures the SDK to do it. An SDK this process never set up has
    // nobody attached in this session, and a stale id from an earlier one is
    // refused at the point of sale by [_identified] rather than cleared here
    // at the cost of a network call on the way out.
    if (!_configured) return;
    try {
      // RevenueCat refuses to log out an anonymous user, and there is nothing
      // to detach from one.
      if (await Purchases.isAnonymous) return;
      await Purchases.logOut();
    } on PlatformException {
      // Deliberate. With [_userId] gone, [_identified] refuses the next sale
      // until an account is identified again, whatever the SDK still holds.
    }
  }

  /// The management page RevenueCat holds for this runner's subscription.
  ///
  /// **Not StoreKit's in-app sheet, because the plugin does not expose it.**
  /// `purchases_flutter` 10.10 has no `showManageSubscriptions`, so this opens
  /// the `managementURL` the SDK reports for the active subscription -- the
  /// App Store's subscriptions page for an Apple one. When the plugin gains
  /// the call, it replaces the body of this method and nothing else.
  @override
  Future<bool> showManageSubscriptions() async {
    if (!await _ready()) return false;
    try {
      final CustomerInfo info = await Purchases.getCustomerInfo();
      final String? url = info.managementURL;
      if (url == null) return false;
      return await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } on Object {
      return false;
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
            title: productTitle(p.storeProduct.title),
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
    // Before the store, never after. A payment we cannot attribute is worse
    // than a sale we did not make.
    if (!await _identified()) return PurchaseOutcome.notIdentified;
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
      return _outcomeOf(e);
    }
  }

  @override
  Future<PurchaseOutcome> restore() async {
    if (!await _ready()) return PurchaseOutcome.failed;
    // Same rule as [buy], for the same reason: a receipt restored while the SDK
    // is attached to nobody, or to the account that left, reaches no coach.
    if (!await _identified()) return PurchaseOutcome.notIdentified;
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
    } on PlatformException catch (e) {
      return _outcomeOf(e);
    }
  }
}
