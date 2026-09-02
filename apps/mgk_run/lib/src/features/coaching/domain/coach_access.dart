/// Whether the runner has paid for coaching.
///
/// **The subscription buys a coach, not a plan.** That distinction is
/// [ADR-0019](../../../../docs/decisions/0019-onboarding-is-two-moments.md)'s
/// and it decides what this gates: recording, logging, pace, distance and the
/// runner's own history are the free product and stay whole. What costs money
/// is the coach's *reading* of them — the comparison between what was asked for
/// and what was done.
///
/// **It defaults to [free] and every unknown answer resolves to [free].**
/// That direction is the property that matters, and it is the same one
/// [ADR-0014](../../../../docs/decisions/0014-model-is-chosen-per-surface-and-per-tier.md)
/// states for the server's own tier parsing: a bug must not be able to bill at
/// the dearest rate, and — the client-side half — a bug must not hand out what
/// somebody has not bought. A client asserting an entitlement is a claim, not a
/// fact, so nothing here is load-bearing for anything but what is *drawn*.
///
/// Nothing sets [subscribed] yet. Payment needs a verified App Store
/// transaction (ADR-0014) and that is unbuilt, so every runner is on [free]
/// today and the paid surfaces exist to be designed against rather than sold.
/// This is deliberately not read from a stored flag: a value a client can write
/// is a value a client can forge, and the moment there is money involved the
/// answer has to come from a receipt.
enum CoachAccess {
  /// Records, logs, and shows the runner their own numbers.
  free,

  /// Adds the coach's reading of them.
  subscribed;

  bool get isSubscribed => this == CoachAccess.subscribed;
}
