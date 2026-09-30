import 'package:flutter/foundation.dart';

/// What the shop is called on [platform].
///
/// Run named the App Store on both platforms until a Play customer was told
/// their Apple ID would be charged (2026-09-11). Two names rather than one,
/// because a person has an Apple ID or a Google Play account, and the shop is
/// the App Store or Google Play.
///
/// **Here because both apps sell,** and each carried its own copy: a second
/// copy is a second chance to name the wrong store.
String storeName(TargetPlatform platform) =>
    platform == TargetPlatform.android ? 'Google Play' : 'the App Store';

/// What the person's account with that shop is called.
String storeAccountName(TargetPlatform platform) =>
    platform == TargetPlatform.android ? 'Google Play account' : 'Apple ID';

/// The auto-renew disclosure, in the words each store expects, for the
/// surface where money moves (guideline 3.1.2(a)).
///
/// Apple prescribes the facts and, in practice, the phrasing — "turned off" is
/// Apple's word, and the one Lift's terms use; Run said "switched off" until
/// the two were joined here. Play prescribes the facts. Both say the same four
/// things about the same subscription: that it renews, when it is charged, how
/// much notice cancelling needs, and where to do it.
String renewalWording(TargetPlatform platform) =>
    platform == TargetPlatform.android ? _googleRenewal : _appleRenewal;

const String _appleRenewal =
    'Subscriptions renew every month until cancelled. Payment is charged to '
    'your Apple ID at confirmation of purchase, and renews within 24 hours '
    'before the period ends unless auto-renew is turned off at least 24 hours '
    'before then. Manage or cancel it in your Apple ID settings.';

const String _googleRenewal =
    'Subscriptions renew every month until cancelled. Payment is charged to '
    'your Google Play account at confirmation of purchase, and renews within '
    '24 hours before the period ends unless auto-renew is turned off at least '
    '24 hours before then. Manage or cancel it in the Play Store under '
    'Payments and subscriptions.';
