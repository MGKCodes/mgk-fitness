import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../settings/presentation/phone_scope.dart';
import '../data/purchase_client.dart';
import '../domain/coach_subscription.dart';
import '../domain/manage_subscription.dart';

/// Opens a URL outside the app. Injected by tests, which have no browser.
typedef UrlOpener = Future<bool> Function(Uri uri);

/// The real [UrlOpener]. A launcher that throws -- no browser, no handler --
/// is a page that did not open, not an error.
Future<bool> openExternally(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Object {
    return false;
  }
}

/// Takes the runner to where [subscription] is managed and cancelled.
///
/// **The store that bills them, not the store this phone runs.** An App Store
/// subscription on an iPhone goes through the purchase client first, so the
/// store's own management page for it opens; anywhere else, and whenever that
/// cannot open anything, the store's page is opened directly. A Google Play
/// subscription opens this app's entry in Play's Subscription Center.
///
/// [purchases] falls back to the one in [PhoneScope]; [open] to the browser.
Future<void> openManageSubscription(
  BuildContext context,
  CoachSubscription subscription, {
  PurchaseClient? purchases,
  UrlOpener? open,
  TargetPlatform? platform,
}) async {
  final device = platform ?? defaultTargetPlatform;
  final store = billingStoreFor(subscription, device);
  final client = purchases ?? PhoneScope.maybeOf(context)?.purchases;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (store == BillingStore.appStore &&
      device == TargetPlatform.iOS &&
      client != null &&
      await client.showManageSubscriptions()) {
    return;
  }
  final uri = manageSubscriptionUri(store, tier: subscription.tier);
  if (await (open ?? openExternally)(uri)) return;
  // Says where it is when nothing will open it, as the support row does: a
  // dead link to the way out of a subscription is worse than a long one.
  messenger?.showSnackBar(
    SnackBar(content: Text('Could not open ${store.label}. It is at $uri')),
  );
}
