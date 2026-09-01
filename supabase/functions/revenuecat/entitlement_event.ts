// What a RevenueCat webhook event means for `core.entitlements`.
//
// DELIBERATELY PURE, for the same reason `limits.ts` is: this is the money
// gate, and every mapping in it can be got wrong in a way that either gives
// somebody a coach they did not buy or takes one they did. None of that should
// need a deployed function or a live store to assert. The impure half — the
// shared-secret check, the read, the write — is `index.ts`.
//
// PRIVACY: an event carries a store transaction and a product id. Nothing here
// keeps a receipt body, and nothing here logs one.

/** The apps `core.entitlements.app` allows. */
export type App = "lift" | "run";

/** The tiers `core.entitlements.product` allows. Not the model tiers. */
export type Product = "free" | "paid" | "premium";

/** The states `core.entitlements.status` allows. */
export type Status = "active" | "expired" | "grace" | "refunded" | "revoked";

/** What one product id sells. Configured, never hard-coded — see `productMap`. */
export interface ProductSale {
  app: App;
  product: Product;
}

/** The row a webhook wants written. */
export interface EntitlementWrite {
  user_id: string;
  app: App;
  product: Product;
  status: Status;
  platform: "apple" | "google" | null;
  expires_at: string | null;
  source_txn_id: string | null;
  event_ms: number;
}

/** Why an event produced no write. Reported, never thrown. */
export type IgnoredReason =
  | "not_an_event"
  | "no_event_timestamp"
  | "unknown_app_user_id"
  | "unmapped_product"
  | "unhandled_type"
  | "sandbox";

export type Decision =
  | { write: EntitlementWrite }
  | { ignore: IgnoredReason };

/**
 * How each event type moves the row.
 *
 * **Unknown types are ignored rather than guessed.** RevenueCat adds event
 * types, and the cost of guessing wrong is asymmetric: inventing an `active`
 * from an unrecognised name gives away a subscription, and inventing an
 * `expired` takes one from somebody who paid. Ignoring leaves the row as it is,
 * which is the state the store last confirmed, and the function still answers
 * 200 so RevenueCat does not retry forever.
 *
 * `CANCELLATION` is the one worth reading twice. It does **not** mean access
 * ends — it means auto-renew was switched off, and the runner keeps what they
 * paid for until it runs out. `EXPIRATION` is the event that ends access, and
 * treating cancellation as the end would take away time somebody has bought.
 */
const STATUS_BY_TYPE: Record<string, Status> = {
  INITIAL_PURCHASE: "active",
  RENEWAL: "active",
  PRODUCT_CHANGE: "active",
  UNCANCELLATION: "active",
  NON_RENEWING_PURCHASE: "active",
  SUBSCRIPTION_EXTENDED: "active",
  // Auto-renew off, access intact until it lapses.
  CANCELLATION: "active",
  EXPIRATION: "expired",
  SUBSCRIPTION_PAUSED: "expired",
  // The store is chasing a payment. Access continues, and `grace` is why the
  // column has five values rather than a boolean — the Edge Function's
  // entitlement check treats anything but `active` as no entitlement, so a
  // billing retry deliberately reads as "not paid" while it resolves.
  BILLING_ISSUE: "grace",
  REFUND: "refunded",
  TRANSFER: "revoked",
};

function str(value: unknown): string | null {
  return typeof value === "string" && value.trim() !== "" ? value : null;
}

/** A Supabase user id, which is what ADR-0028 makes the RevenueCat app user id. */
function uuid(value: unknown): string | null {
  const s = str(value);
  if (s === null) return null;
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
      .test(s)
    ? s
    : null;
}

/**
 * Parses `REVENUECAT_PRODUCTS`: a JSON object of product id to `{app, product}`.
 *
 * Configuration rather than code because the App Store product ids are not
 * decided yet, and because a price change that adds a SKU should not need a
 * deploy. A malformed or missing value yields an empty map, which makes every
 * event `unmapped_product` — visible and harmless, rather than a crash loop or,
 * worse, a default that grants something.
 */
export function productMap(raw: string | undefined): Map<string, ProductSale> {
  const out = new Map<string, ProductSale>();
  if (!raw) return out;
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return out;
  }
  if (parsed === null || typeof parsed !== "object") return out;
  for (const [id, value] of Object.entries(parsed as Record<string, unknown>)) {
    const v = value as { app?: unknown; product?: unknown };
    const app = str(v?.app);
    const product = str(v?.product);
    if (app !== "lift" && app !== "run") continue;
    if (product !== "free" && product !== "paid" && product !== "premium") {
      continue;
    }
    out.set(id, { app, product });
  }
  return out;
}

/**
 * The event, as a row to write or a reason not to.
 *
 * `acceptSandbox` exists because a sandbox purchase is a real event from a fake
 * payment. Accepting them in production would let anybody with a sandbox tester
 * account grant themselves a coach; refusing them in development would make the
 * whole thing untestable before release. So it is a decision the caller makes
 * from configuration, not a thing this file assumes.
 */
export function decide(
  body: unknown,
  products: Map<string, ProductSale>,
  { acceptSandbox = false }: { acceptSandbox?: boolean } = {},
): Decision {
  const event = (body as { event?: unknown } | null)?.event;
  if (event === null || typeof event !== "object") {
    return { ignore: "not_an_event" };
  }
  const e = event as Record<string, unknown>;

  const eventMs = typeof e.event_timestamp_ms === "number" &&
      Number.isFinite(e.event_timestamp_ms)
    ? e.event_timestamp_ms
    : null;
  // Without one there is no watermark, so a replay could not be told from a new
  // event and ordering would be whatever arrived last.
  if (eventMs === null) return { ignore: "no_event_timestamp" };

  const userId = uuid(e.app_user_id);
  if (userId === null) return { ignore: "unknown_app_user_id" };

  if (e.environment === "SANDBOX" && !acceptSandbox) {
    return { ignore: "sandbox" };
  }

  const productId = str(e.product_id);
  const sale = productId === null ? undefined : products.get(productId);
  if (sale === undefined) return { ignore: "unmapped_product" };

  const type = str(e.type);
  const status = type === null ? undefined : STATUS_BY_TYPE[type];
  if (status === undefined) return { ignore: "unhandled_type" };

  const expiresMs = typeof e.expiration_at_ms === "number" &&
      Number.isFinite(e.expiration_at_ms)
    ? e.expiration_at_ms
    : null;

  return {
    write: {
      user_id: userId,
      app: sale.app,
      product: sale.product,
      status,
      platform: platformOf(e.store),
      expires_at: expiresMs === null
        ? null
        : new Date(expiresMs).toISOString(),
      source_txn_id: str(e.transaction_id) ?? str(e.original_transaction_id),
      event_ms: eventMs,
    },
  };
}

/**
 * `core.entitlements.platform` allows apple, google or null.
 *
 * An unrecognised store is null rather than a guess: the column is provenance
 * for support and reconciliation, and a wrong value there sends somebody
 * looking in the wrong console.
 */
function platformOf(store: unknown): "apple" | "google" | null {
  switch (str(store)) {
    case "APP_STORE":
    case "MAC_APP_STORE":
      return "apple";
    case "PLAY_STORE":
      return "google";
    default:
      return null;
  }
}

/**
 * Whether an event should overwrite what is already stored.
 *
 * The whole out-of-order story, and it is one comparison. A stored NULL loses
 * to everything, so a row inserted by hand — the TestFlight sheet does exactly
 * that — is replaced by the first real event rather than blocking it forever.
 *
 * Equal timestamps do not write. That is what makes a replay a no-op, and
 * RevenueCat retries deliveries.
 */
export function supersedes(
  incomingMs: number,
  storedMs: number | null | undefined,
): boolean {
  if (storedMs === null || storedMs === undefined) return true;
  return incomingMs > storedMs;
}
