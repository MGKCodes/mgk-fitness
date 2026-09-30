/// Where a runner stands with the coach subscription, in enough detail to
/// **say it out loud**.
///
/// [CoachAccess] is a boolean because a locked door needs nothing more: either
/// the coach's reading is drawn or it is not. That is the right shape for a
/// gate and the wrong shape for a sentence. "You are on the free app" and
/// "your card was declined and Google is retrying" both draw the same locked
/// door, and telling somebody the first when the second is true is how a
/// paying subscriber concludes the app has eaten their money.
///
/// So this exists beside [CoachAccess] rather than replacing it. Same row, same
/// three columns, read once; one answer for what to draw, one for what to say.
///
/// **It is still not the gate.** `tierFor` in `supabase/functions/coach`
/// decides what may actually be spent, under `service_role`, and a client
/// asserting a tier is a claim rather than a fact. Nothing here unlocks
/// anything — it only ever prints.
library;

/// Which subscription, by the name the runner bought it under.
///
/// The names are the *product's*, not the database's. `core.entitlements`
/// stores `paid` and `premium` because that column describes a receipt;
/// somebody reading a settings screen bought "Coach" or "Premium Coach", which
/// is what the paywall called it and what the store charged them for.
enum CoachTier {
  /// Nothing bought. Recording, history and pace are still whole — that is the
  /// free app rather than a trial (ADR-0030).
  none,

  /// `paid` in the entitlement row.
  coach,

  /// `premium` in the entitlement row.
  premiumCoach;

  /// What to call it on screen.
  String get label => switch (this) {
    CoachTier.none => 'Free',
    CoachTier.coach => 'Coach',
    CoachTier.premiumCoach => 'Premium Coach',
  };
}

/// What the store currently says about the money.
///
/// `core.entitlements.status` has five values and this collapses them to the
/// three a runner can act on. The collapse is deliberate: `refunded` and
/// `revoked` differ enormously to us and not at all to the person reading —
/// both mean "it is over and you are not being charged".
enum SubscriptionStanding {
  /// No row. Never subscribed, or subscribed and long since cleaned up.
  none,

  /// Paid and current.
  active,

  /// `grace` — the store is chasing a payment that did not go through.
  ///
  /// **The one standing worth having a name for.** It is the only state where
  /// somebody believes they are paying and the app disagrees, and the only one
  /// where there is something they can do about it.
  billingRetry,

  /// `expired`, `refunded` or `revoked`. Over, and not being charged.
  ///
  /// Also `active` more than a day past its expiry, which is what an `expired`
  /// row looks like when the event that would have said so never arrived. See
  /// [CoachSubscription.fromRow].
  ended,
}

/// Which store takes the money, as `core.entitlements.platform` records it.
///
/// **Not the phone's store.** A runner who subscribed on an iPhone and signs in
/// on Android is billed by Apple, and was being told to cancel in Google Play:
/// Settings named the store from `defaultTargetPlatform`, which answers where
/// the app is running, not who is charging.
enum BillingStore {
  appStore,
  googlePlay;

  /// What to call it in a sentence.
  String get label => switch (this) {
    BillingStore.appStore => 'the App Store',
    BillingStore.googlePlay => 'Google Play',
  };

  /// [label] where it opens a sentence: "The App Store is retrying it".
  ///
  /// A second getter rather than a capital in [label], which is right in the
  /// middle of a sentence and is used there far more often. Account's
  /// payment-failed line began "the App Store is retrying it" (screen board
  /// T8).
  String get sentenceLabel =>
      '${label.substring(0, 1).toUpperCase()}${label.substring(1)}';
}

/// A tier and its standing, which are independent: a premium subscriber whose
/// card just failed is `premiumCoach` + [SubscriptionStanding.billingRetry],
/// and flattening that to "free" would lose the only fact worth telling them.
class CoachSubscription {
  const CoachSubscription({
    required this.tier,
    required this.standing,
    this.store,
  });

  /// Nobody signed in, no row, or a read that failed. Same direction as
  /// everything else on the client side: the absence of proof is not a tier.
  static const CoachSubscription none = CoachSubscription(
    tier: CoachTier.none,
    standing: SubscriptionStanding.none,
  );

  final CoachTier tier;
  final SubscriptionStanding standing;

  /// The store that bills it, or null when the row does not say -- a
  /// hand-granted row, or one written before the column was filled. Callers
  /// fall back to this phone's store, which is right for nearly everybody.
  final BillingStore? store;

  /// Whether the coach's reading is drawn — the same answer [CoachAccess]
  /// gives, derived here so the two cannot drift apart.
  ///
  /// **Only [SubscriptionStanding.active] grants.** `grace` reads like "still
  /// fine" and means "the store has not been paid", and the server refuses it,
  /// so drawing an unlocked coach here would produce a 402 the moment it was
  /// opened — a worse experience than the locked door plus an honest sentence.
  bool get isSubscribed =>
      standing == SubscriptionStanding.active && tier != CoachTier.none;

  /// How long past `expires_at` an `active` row still reads as active: a day,
  /// the same margin as `LAPSE_GRACE_MS` beside `tierFor`.
  ///
  /// Mirrored rather than chosen here, because the two disagreeing is the
  /// failure in either direction. Shorter, and a runner whose renewal is still
  /// in flight is shown a locked coach the server would have served. Longer,
  /// and a lapsed one is shown an open coach that 402s the moment it is used.
  /// Why a day — RevenueCat's retries, and a renewal landing just after the
  /// period ends — is the server's reasoning, and is written there.
  static const Duration lapseGrace = Duration(hours: 24);

  /// Reads the three columns of `core.entitlements` that decide anything.
  ///
  /// Unknown values resolve downwards — an unrecognised product is
  /// [CoachTier.none] rather than the dearest tier, and an unrecognised status
  /// is [SubscriptionStanding.ended] rather than active. Same direction as
  /// `tierFor` and `accessFrom`, for the same reason: a typo or a SKU from a
  /// future version of the receipt validator must not be able to unlock
  /// anything it did not buy.
  ///
  /// **An `active` row more than [lapseGrace] past `expires_at` is
  /// [SubscriptionStanding.ended]** — the same branch as `expired`, because it
  /// is an expired row whose `EXPIRATION` event never arrived. Nothing else
  /// ends one: the webhook leaves a cancelled subscription `active` until that
  /// event comes, and a Google test subscription sat `active` seventeen days
  /// past its expiry waiting for it. This mirrors property 4 of `tierFor`,
  /// which refuses the same row, so the app stops drawing a coach the server
  /// will not serve. A null expiry means no end date, which is what every
  /// hand-granted row carries, and stays active. An expiry that cannot be read
  /// is ended rather than trusted, as an unrecognised status is; the server
  /// refuses that row outright.
  ///
  /// [now] is the instant the expiry is judged against. The caller's clock,
  /// not this function's, so a test can stand either side of the margin.
  static CoachSubscription fromRow(
    Map<String, dynamic>? row, {
    required DateTime now,
  }) {
    if (row == null) return none;
    final tier = switch (row['product']) {
      'paid' => CoachTier.coach,
      'premium' => CoachTier.premiumCoach,
      _ => CoachTier.none,
    };
    if (tier == CoachTier.none) return none;
    final standing = switch (row['status']) {
      'active' when _stillCurrent(row['expires_at'], now) =>
        SubscriptionStanding.active,
      'grace' => SubscriptionStanding.billingRetry,
      _ => SubscriptionStanding.ended,
    };
    return CoachSubscription(
      tier: tier,
      standing: standing,
      store: switch (row['platform']) {
        'apple' => BillingStore.appStore,
        'google' => BillingStore.googlePlay,
        _ => null,
      },
    );
  }

  /// No end date, or one less than [lapseGrace] gone.
  ///
  /// Written as the condition that keeps a row active, so anything it cannot
  /// read — a number, a typo, a string [DateTime.tryParse] refuses — falls
  /// through to ended instead of being waved on.
  static bool _stillCurrent(Object? expiresAt, DateTime now) {
    if (expiresAt == null) return true;
    final end = expiresAt is String ? DateTime.tryParse(expiresAt) : null;
    return end != null && end.add(lapseGrace).isAfter(now);
  }

  @override
  bool operator ==(Object other) =>
      other is CoachSubscription &&
      other.tier == tier &&
      other.standing == standing &&
      other.store == store;

  @override
  int get hashCode => Object.hash(tier, standing, store);

  @override
  String toString() => 'CoachSubscription(${tier.name}, ${standing.name})';
}
