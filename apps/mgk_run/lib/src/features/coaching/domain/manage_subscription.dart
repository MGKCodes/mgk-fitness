/// Where a subscription is managed and cancelled.
///
/// **Both stores want the way out inside the app.** Google Play's subscriptions
/// policy asks for a link to its Subscription Center (or cancellation in the
/// app), and Apple's account-deletion guidance asks for the way to manage the
/// subscription to be offered alongside. The account screen said "cancel it in
/// Google Play" and linked to nothing.
library;

import 'package:flutter/foundation.dart';

import 'coach_subscription.dart';

/// This app's id on Google Play, which the Subscription Center is opened for.
const String kPlayPackage = 'com.mgkcodes.fitness.run';

/// Apple's page listing the subscriptions on an Apple ID.
const String kAppleSubscriptionsUrl =
    'https://apps.apple.com/account/subscriptions';

/// The Play subscription each tier is sold as.
///
/// `play-setup.md` keeps the Play subscription ids the same as the App Store
/// product ids, and the webhook has logged `run.coach.monthly:monthly` from a
/// Play purchase -- the subscription id, then the base plan. The Subscription
/// Center wants the first half.
const Map<CoachTier, String> _playSubscriptionIds = <CoachTier, String>{
  CoachTier.coach: 'run.coach.monthly',
  CoachTier.premiumCoach: 'run.coach.premium.monthly',
};

/// The store that bills [subscription]: the one its row names, or this
/// phone's own when the row does not say.
BillingStore billingStoreFor(
  CoachSubscription subscription,
  TargetPlatform device,
) =>
    subscription.store ??
    (device == TargetPlatform.android
        ? BillingStore.googlePlay
        : BillingStore.appStore);

/// Whether there is a subscription to manage: one that is live, failing, or
/// over. Over still counts -- the store's page is where a lapsed runner
/// resubscribes, or checks they are no longer being charged.
bool hasSubscriptionToManage(CoachSubscription subscription) =>
    subscription.standing != SubscriptionStanding.none;

/// The page for managing a subscription billed by [store].
///
/// Google Play opens this app's own entry in the Subscription Center when it
/// is told which subscription ([tier]); without one it opens the list.
Uri manageSubscriptionUri(
  BillingStore store, {
  CoachTier tier = CoachTier.none,
}) => switch (store) {
  BillingStore.appStore => Uri.parse(kAppleSubscriptionsUrl),
  BillingStore.googlePlay => Uri.https(
    'play.google.com',
    '/store/account/subscriptions',
    <String, String>{
      'package': kPlayPackage,
      if (_playSubscriptionIds[tier] case final String sku) 'sku': sku,
    },
  ),
};
