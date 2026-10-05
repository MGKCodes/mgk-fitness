/// Where a Lift subscription is managed and cancelled (5 October 2026).
///
/// **Both stores want the way out inside the app.** Google Play's
/// subscriptions policy asks for a link to its Subscription Center, and
/// Apple's account-deletion guidance asks for the way to manage a
/// subscription to be offered where deleting is. Lift 2.0.0 sells
/// subscriptions and had neither; Run has had both since build 26
/// (`manage_subscription.dart` there).
///
/// **The store of this phone, which is not always the store that bills.**
/// Run reads which store sold the subscription from its entitlement row; Lift's
/// row does not carry it yet, so somebody who subscribed on an iPhone and
/// opens this on an Android phone is sent to Google Play, where they will not
/// find it. Rare enough to ship, and named here so it is not forgotten.
library;

import 'package:flutter/foundation.dart';

/// Lift's id on both stores. It ships as Liftio's, and always will: changing
/// it makes a new app with no users (`core/brand.dart`).
const String kPlayPackage = 'com.mgkcodes.liftio';

/// Apple's page listing the subscriptions on an Apple ID.
const String kAppleSubscriptionsUrl =
    'https://apps.apple.com/account/subscriptions';

/// The page for managing a subscription bought on [platform]'s store.
/// Google Play opens Lift's own entry in its Subscription Center.
Uri manageSubscriptionUri(TargetPlatform platform) =>
    platform == TargetPlatform.android
    ? Uri.https(
        'play.google.com',
        '/store/account/subscriptions',
        <String, String>{'package': kPlayPackage},
      )
    : Uri.parse(kAppleSubscriptionsUrl);
