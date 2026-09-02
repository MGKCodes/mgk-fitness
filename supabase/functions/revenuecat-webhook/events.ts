// Turning a RevenueCat event into a row of `core.entitlements`.
//
// Pure, and separate from `index.ts` for the reason the coach function splits
// the same way: this is the part with the judgement in it, and judgement is
// worth testing without an HTTP server or a database.

/// The `product` values `core.entitlements` allows.
export type Tier = "free" | "paid" | "premium";

/// The `status` values it allows. `active` is the only one that grants anything.
export type Status = "active" | "expired" | "grace" | "refunded" | "revoked";

export interface RevenueCatEvent {
  type?: string;
  id?: string;
  app_user_id?: string;
  original_app_user_id?: string;
  product_id?: string;
  expiration_at_ms?: number | null;
  store?: string;
  environment?: string;
  cancel_reason?: string | null;
  expiration_reason?: string | null;
  event_timestamp_ms?: number;
}

export interface EntitlementWrite {
  product: Tier;
  status: Status;
  expires_at: string | null;
  platform: "apple" | "google" | null;
  source_txn_id: string;
}

/// The products this app sells, and what each grants.
///
/// **Anything not listed becomes `paid`, and that is the point rather than a
/// fallback.** Liftio sold £1.99/mo and £19.99/yr under this same bundle id and
/// those subscriptions are still live, so 2.0.0 will receive renewal events for
/// product ids it has never heard of. Refusing them would tell a paying customer
/// of four years that they have no subscription; granting `paid` gives them the
/// coach, which is what they have always been paying for.
///
/// It is deliberately not a list of Liftio's ids. We do not have them to hand,
/// and a list we cannot verify would fail exactly where it matters — on the id
/// somebody forgot. Defaulting the unknown case correctly needs no list.
const PRODUCT_TIERS: Record<string, Tier> = {
  "lift.coach.monthly": "paid",
  "lift.premium_coach.monthly": "premium",
};

export function tierFor(productId?: string): Tier {
  if (!productId) return "paid";
  return PRODUCT_TIERS[productId] ?? "paid";
}

/// What the event means for access, or `null` for events that must not write.
///
/// ## Cancellation does not cancel access
///
/// The single most important line here. In RevenueCat, `CANCELLATION` means
/// **auto-renew was switched off**, not that the subscription ended — the person
/// has paid for the current period and keeps it until `EXPIRATION` arrives at
/// the end of it. Treating cancellation as revocation would take away time
/// somebody has already been charged for, on the day they decided not to renew,
/// which is both wrong and the most annoying possible moment to be wrong.
///
/// The exception is a refund. RevenueCat reports those as a cancellation with
/// `cancel_reason: CUSTOMER_SUPPORT`, and money returned is access ended.
export function statusFor(event: RevenueCatEvent): Status | null {
  switch (event.type) {
    case "INITIAL_PURCHASE":
    case "RENEWAL":
    case "UNCANCELLATION":
    case "PRODUCT_CHANGE":
    case "SUBSCRIPTION_EXTENDED":
    case "NON_RENEWING_PURCHASE":
    case "TEMPORARY_ENTITLEMENT_GRANT":
    case "REFUND_REVERSED":
    case "TRANSFER":
      return "active";

    case "CANCELLATION":
      return event.cancel_reason === "CUSTOMER_SUPPORT" ? "refunded" : "active";

    case "EXPIRATION":
      // A refund can also arrive as an expiration, and the two are worth
      // distinguishing in the row: `expired` is a subscription that ran out,
      // `refunded` is one that was given back.
      return event.expiration_reason === "CUSTOMER_SUPPORT"
        ? "refunded"
        : "expired";

    case "BILLING_ISSUE":
      // The store is retrying a failed payment. Access continues by the store's
      // own intent, and `core.entitlements` records the state rather than the
      // decision — the client is what currently declines to grant on `grace`,
      // and that is the place to revisit it.
      return "grace";

    case "SUBSCRIPTION_PAUSED":
      return "expired";

    // TEST fires from the RevenueCat dashboard and carries no real customer.
    // Anything unrecognised is a new event type this function predates; both
    // must leave the row alone rather than guess at it.
    default:
      return null;
  }
}

export function platformFor(store?: string): "apple" | "google" | null {
  switch (store) {
    case "APP_STORE":
    case "MAC_APP_STORE":
      return "apple";
    case "PLAY_STORE":
      return "google";
    default:
      // Stripe, Amazon, promotional. The column is nullable and a wrong value
      // would fail the CHECK and lose the whole write.
      return null;
  }
}

/// Provenance, and the one place the environment is recorded.
///
/// `core.entitlements` has no environment column, so it goes here. That matters
/// because **sandbox events are honoured** (see [entitlementFrom]) and somebody
/// reconciling against the store later needs to know which rows came from a test
/// purchase without having to guess from the timestamps.
///
/// The `rc:` prefix distinguishes these from the `manual:` rows
/// `core.grant_entitlement()` writes.
export function provenance(event: RevenueCatEvent): string {
  const env = (event.environment ?? "UNKNOWN").toLowerCase();
  const store = (event.store ?? "unknown").toLowerCase();
  return `rc:${env}:${store}:${event.id ?? "no-id"}`;
}

/// The row to write, or `null` if this event must not write one.
///
/// ## Sandbox events are honoured, deliberately
///
/// It is tempting to ignore `environment: "SANDBOX"` so test purchases cannot
/// grant real access. That would fail App Store review: **the reviewer's
/// purchase is a sandbox purchase**, and an app where the reviewer pays and
/// receives nothing is rejected under 2.1. The environment is recorded in
/// [provenance] instead, so the rows are auditable rather than invisible.
export function entitlementFrom(
  event: RevenueCatEvent,
): EntitlementWrite | null {
  const status = statusFor(event);
  if (status === null) return null;
  if (!event.app_user_id) return null;

  return {
    product: tierFor(event.product_id),
    status,
    expires_at: event.expiration_at_ms
      ? new Date(event.expiration_at_ms).toISOString()
      : null,
    platform: platformFor(event.store),
    source_txn_id: provenance(event),
  };
}

/// Whether an incoming event should be allowed to overwrite what is stored.
///
/// RevenueCat retries, and retries can arrive out of order — an `EXPIRATION`
/// delivered after the `RENEWAL` that followed it would otherwise revoke a live
/// subscription. Comparing expiry dates is the cheap guard: an event whose
/// entitlement ends **before** the one already recorded is stale news about a
/// period that has already been superseded.
///
/// Deliberately permissive when either side has no expiry. A missing expiry is a
/// lifetime or non-renewing purchase, and refusing those would drop real writes
/// to defend against a rarer problem than the one it causes.
export function supersedes(
  incoming: EntitlementWrite,
  stored: { expires_at?: string | null } | null,
): boolean {
  if (!stored?.expires_at || !incoming.expires_at) return true;
  return (
    new Date(incoming.expires_at).getTime() >=
      new Date(stored.expires_at).getTime()
  );
}
