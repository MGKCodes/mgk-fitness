// Unit tests for the webhook's decision logic.
//
// The point of keeping `entitlement_event.ts` pure is that every mapping on the
// money path can be asserted without a deployed function, a live store, or a
// database. Run from this directory:
//
//     deno test

import { assert, assertEquals } from "jsr:@std/assert@1";

import {
  decide,
  productMap,
  type ProductSale,
  supersedes,
} from "./entitlement_event.ts";

const USER = "3f1a2b4c-5d6e-4f70-8a91-b2c3d4e5f607";

const PRODUCTS = productMap(JSON.stringify({
  "run.coach.monthly": { app: "run", product: "paid" },
  "run.coach.premium.monthly": { app: "run", product: "premium" },
  "lift.coach.monthly": { app: "lift", product: "paid" },
}));

function event(over: Record<string, unknown> = {}): unknown {
  return {
    event: {
      type: "INITIAL_PURCHASE",
      app_user_id: USER,
      product_id: "run.coach.monthly",
      store: "APP_STORE",
      environment: "PRODUCTION",
      event_timestamp_ms: 1_700_000_000_000,
      expiration_at_ms: 1_702_592_000_000,
      transaction_id: "txn-1",
      ...over,
    },
  };
}

function written(over: Record<string, unknown> = {}) {
  const d = decide(event(over), PRODUCTS);
  assert("write" in d, `expected a write, got ${JSON.stringify(d)}`);
  return d.write;
}

function ignored(over: Record<string, unknown> = {}) {
  const d = decide(event(over), PRODUCTS);
  assert("ignore" in d, `expected an ignore, got ${JSON.stringify(d)}`);
  return d.ignore;
}

// ---- what an event becomes --------------------------------------------------

Deno.test("a purchase becomes an active row for the product's own app", () => {
  const row = written();
  assertEquals(row.user_id, USER);
  assertEquals(row.app, "run");
  assertEquals(row.product, "paid");
  assertEquals(row.status, "active");
  assertEquals(row.platform, "apple");
  assertEquals(row.source_txn_id, "txn-1");
  assertEquals(row.event_ms, 1_700_000_000_000);
  assertEquals(row.expires_at, new Date(1_702_592_000_000).toISOString());

  assertEquals(
    written({ product_id: "run.coach.premium.monthly" }).product,
    "premium",
  );
  assertEquals(written({ product_id: "lift.coach.monthly" }).app, "lift");
});

Deno.test("cancellation does not end access; expiration does", () => {
  // The mistake worth a test rather than a comment. CANCELLATION means
  // auto-renew was switched off, and the runner keeps what they paid for until
  // it runs out. Treating it as the end takes away time somebody bought.
  assertEquals(written({ type: "CANCELLATION" }).status, "active");
  assertEquals(written({ type: "EXPIRATION" }).status, "expired");
});

Deno.test("a billing issue is grace, which grants nothing", () => {
  // `grace` reads like "still fine" and means "the store has not been paid".
  // The coach's own entitlement check treats everything but `active` as no
  // entitlement, so this deliberately locks while the retry resolves.
  assertEquals(written({ type: "BILLING_ISSUE" }).status, "grace");
});

Deno.test("every status the table allows can be reached, and no other", () => {
  const allowed = ["active", "expired", "grace", "refunded", "revoked"];
  const reached = new Set<string>();
  // Events as RevenueCat actually sends them. This list once reached
  // `refunded` through a `REFUND` type that does not exist, which is how a
  // refunded subscriber kept the coach without any test noticing.
  for (
    const over of [
      { type: "INITIAL_PURCHASE" },
      { type: "RENEWAL" },
      { type: "PRODUCT_CHANGE" },
      { type: "UNCANCELLATION" },
      { type: "NON_RENEWING_PURCHASE" },
      { type: "SUBSCRIPTION_EXTENDED" },
      { type: "CANCELLATION", cancel_reason: "UNSUBSCRIBE" },
      { type: "CANCELLATION", cancel_reason: "CUSTOMER_SUPPORT" },
      { type: "EXPIRATION", expiration_reason: "UNSUBSCRIBE" },
      { type: "BILLING_ISSUE" },
      { type: "REFUND_REVERSED" },
      { type: "TRANSFER" },
    ]
  ) {
    const status = written(over).status;
    assert(
      allowed.includes(status),
      `${JSON.stringify(over)} produced ${status}`,
    );
    reached.add(status);
  }
  // A check constraint violation would be a 502 at 3am rather than a test.
  assertEquals([...reached].sort(), [...allowed].sort());
});

Deno.test("a refund is a cancellation with a reason, and it ends access", () => {
  // RevenueCat has no REFUND type: "Customer received a refund from Apple
  // support…" arrives as CANCELLATION with cancel_reason CUSTOMER_SUPPORT.
  // Every other cancellation keeps access until it lapses; this one does not,
  // because the money went back.
  assertEquals(
    written({ type: "CANCELLATION", cancel_reason: "CUSTOMER_SUPPORT" }).status,
    "refunded",
  );
  for (
    const reason of [
      "UNSUBSCRIBE",
      "BILLING_ERROR",
      "PRICE_INCREASE",
      "UNKNOWN",
    ]
  ) {
    assertEquals(
      written({ type: "CANCELLATION", cancel_reason: reason }).status,
      "active",
      `a ${reason} cancellation should keep access until it lapses`,
    );
  }
  assertEquals(
    written({ type: "EXPIRATION", expiration_reason: "CUSTOMER_SUPPORT" })
      .status,
    "refunded",
  );
});

Deno.test("a reversed refund gives access back", () => {
  assertEquals(written({ type: "REFUND_REVERSED" }).status, "active");
});

Deno.test("there is no REFUND event type to trust", () => {
  // If RevenueCat ever sent one it would be new, and new types are ignored
  // rather than guessed — the same rule as every other unknown.
  assertEquals(ignored({ type: "REFUND" }), "unhandled_type");
});

// ---- what is refused, and in which direction --------------------------------

Deno.test("an unknown event type is ignored, never guessed", () => {
  // RevenueCat adds types. Inventing `active` from an unrecognised name gives
  // away a subscription; inventing `expired` takes one from somebody who paid.
  assertEquals(ignored({ type: "SOMETHING_NEW" }), "unhandled_type");
  assertEquals(ignored({ type: "" }), "unhandled_type");
  assertEquals(ignored({ type: 7 }), "unhandled_type");
});

Deno.test("an unmapped product grants nothing", () => {
  // The failure that matters: a product id nobody configured must not fall back
  // to a tier. It falls back to no write at all.
  assertEquals(
    ignored({ product_id: "run.coach.lifetime" }),
    "unmapped_product",
  );
  assertEquals(ignored({ product_id: null }), "unmapped_product");
});

Deno.test("the app user id must be a Supabase user id", () => {
  // ADR-0028 makes them the same value. Anything else is a misconfigured
  // RevenueCat app, and writing it would create a row keyed to nobody.
  for (const id of ["", "anonymous", "RCAnonymousID:abc123", USER + "x", 42]) {
    assertEquals(
      ignored({ app_user_id: id }),
      "unknown_app_user_id",
      `${JSON.stringify(id)} must not be written`,
    );
  }
});

Deno.test("a sandbox purchase is refused unless configured otherwise", () => {
  // A sandbox event is a real event from a fake payment, refused by default.
  // Production turns this on deliberately (ADR-0037): App Review buys in the
  // sandbox, and only invited testers and Apple can make such a purchase.
  assertEquals(ignored({ environment: "SANDBOX" }), "sandbox");

  const d = decide(
    event({ environment: "SANDBOX" }),
    PRODUCTS,
    { acceptSandbox: true },
  );
  assert("write" in d, "sandbox must be usable when explicitly enabled");
});

Deno.test("an event with no timestamp is ignored", () => {
  // Without one there is no watermark, so a replay could not be told from a new
  // event and ordering would be whatever arrived last.
  assertEquals(
    ignored({ event_timestamp_ms: undefined }),
    "no_event_timestamp",
  );
  assertEquals(
    ignored({ event_timestamp_ms: "1700000000000" }),
    "no_event_timestamp",
  );
});

Deno.test("a body that is not an event is ignored, not thrown", () => {
  for (const body of [null, {}, { event: null }, { event: "x" }, 5, "hello"]) {
    const d = decide(body, PRODUCTS);
    assert("ignore" in d, `${JSON.stringify(body)} should be ignored`);
  }
});

Deno.test("an unrecognised store is null rather than a guess", () => {
  // The column is provenance for support. A wrong value sends somebody to the
  // wrong console.
  assertEquals(written({ store: "PLAY_STORE" }).platform, "google");
  assertEquals(written({ store: "STRIPE" }).platform, null);
  assertEquals(written({ store: undefined }).platform, null);
});

Deno.test("a missing expiry is null, not an epoch", () => {
  // new Date(undefined) is Invalid Date, and its ISO string throws. A
  // lifetime purchase has no expiry and must not become 1970.
  assertEquals(written({ expiration_at_ms: undefined }).expires_at, null);
  assertEquals(written({ expiration_at_ms: null }).expires_at, null);
});

Deno.test("the transaction id falls back to the original", () => {
  assertEquals(
    written({ transaction_id: undefined, original_transaction_id: "orig-9" })
      .source_txn_id,
    "orig-9",
  );
  assertEquals(
    written({ transaction_id: undefined, original_transaction_id: undefined })
      .source_txn_id,
    null,
  );
});

// ---- configuration ----------------------------------------------------------

Deno.test("a malformed product map grants nothing rather than crashing", () => {
  for (const raw of [undefined, "", "not json", "[]", "null", '"x"']) {
    assertEquals(productMap(raw).size, 0, `${JSON.stringify(raw)}`);
  }
  // Entries that are not a valid (app, product) pair are dropped individually,
  // so one typo does not take the whole map down with it.
  const partial = productMap(JSON.stringify({
    good: { app: "run", product: "paid" },
    wrongApp: { app: "swim", product: "paid" },
    wrongTier: { app: "run", product: "gold" },
    empty: {},
  }));
  assertEquals(partial.size, 1);
  assertEquals(
    partial.get("good"),
    { app: "run", product: "paid" } as ProductSale,
  );
});

// ---- ordering ---------------------------------------------------------------

Deno.test("a newer event wins, an equal or older one does not", () => {
  assert(supersedes(2000, 1000), "newer must win");
  assert(
    !supersedes(1000, 2000),
    "a late delivery must not revert a newer state",
  );
  // Equal is the replay case, and RevenueCat retries deliveries.
  assert(!supersedes(1000, 1000), "a replay must be a no-op");
});

Deno.test("a row with no watermark loses to any real event", () => {
  // The TestFlight sheet inserts an entitlement by hand. That row must not
  // block the first real webhook forever.
  assert(supersedes(1, null));
  assert(supersedes(1, undefined));
});

Deno.test("an unmapped product says which one, because a typo looks like a test", () => {
  // The reason alone cannot separate a dummy id in a RevenueCat test event from
  // a mistyped one in REVENUECAT_PRODUCTS, and the second is silent on a real
  // purchase. The id is the only field carried out, and it is a catalogue
  // identifier rather than anything about a person.
  const decision = decide(event({ product_id: "run.coach.montly" }), PRODUCTS);
  assertEquals("ignore" in decision && decision.ignore, "unmapped_product");
  assertEquals(
    "ignore" in decision ? decision.detail : undefined,
    "run.coach.montly",
  );
});

Deno.test("a scheduled pause keeps what was paid for; the expiry ends it", () => {
  // RevenueCat sends SUBSCRIPTION_PAUSED when the pause is scheduled, which is
  // before the paid period ends. It must not end access.
  assertEquals(ignored({ type: "SUBSCRIPTION_PAUSED" }), "unhandled_type");
  const d = decide(
    event({ type: "EXPIRATION", expiration_reason: "SUBSCRIPTION_PAUSED" }),
    PRODUCTS,
  );
  assert("write" in d);
  assertEquals(d.write.status, "expired");
});
