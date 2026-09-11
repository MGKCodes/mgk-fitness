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
/// two columns, read once; one answer for what to draw, one for what to say.
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
  ended,
}

/// A tier and its standing, which are independent: a premium subscriber whose
/// card just failed is `premiumCoach` + [SubscriptionStanding.billingRetry],
/// and flattening that to "free" would lose the only fact worth telling them.
class CoachSubscription {
  const CoachSubscription({required this.tier, required this.standing});

  /// Nobody signed in, no row, or a read that failed. Same direction as
  /// everything else on the client side: the absence of proof is not a tier.
  static const CoachSubscription none = CoachSubscription(
    tier: CoachTier.none,
    standing: SubscriptionStanding.none,
  );

  final CoachTier tier;
  final SubscriptionStanding standing;

  /// Whether the coach's reading is drawn — the same answer [CoachAccess]
  /// gives, derived here so the two cannot drift apart.
  ///
  /// **Only [SubscriptionStanding.active] grants.** `grace` reads like "still
  /// fine" and means "the store has not been paid", and the server refuses it,
  /// so drawing an unlocked coach here would produce a 402 the moment it was
  /// opened — a worse experience than the locked door plus an honest sentence.
  bool get isSubscribed =>
      standing == SubscriptionStanding.active && tier != CoachTier.none;

  /// Reads the two columns of `core.entitlements` that decide anything.
  ///
  /// Unknown values resolve downwards — an unrecognised product is
  /// [CoachTier.none] rather than the dearest tier, and an unrecognised status
  /// is [SubscriptionStanding.ended] rather than active. Same direction as
  /// `tierFor` and `accessFrom`, for the same reason: a typo or a SKU from a
  /// future version of the receipt validator must not be able to unlock
  /// anything it did not buy.
  static CoachSubscription fromRow(Map<String, dynamic>? row) {
    if (row == null) return none;
    final tier = switch (row['product']) {
      'paid' => CoachTier.coach,
      'premium' => CoachTier.premiumCoach,
      _ => CoachTier.none,
    };
    if (tier == CoachTier.none) return none;
    final standing = switch (row['status']) {
      'active' => SubscriptionStanding.active,
      'grace' => SubscriptionStanding.billingRetry,
      _ => SubscriptionStanding.ended,
    };
    return CoachSubscription(tier: tier, standing: standing);
  }

  @override
  bool operator ==(Object other) =>
      other is CoachSubscription &&
      other.tier == tier &&
      other.standing == standing;

  @override
  int get hashCode => Object.hash(tier, standing);

  @override
  String toString() => 'CoachSubscription(${tier.name}, ${standing.name})';
}
