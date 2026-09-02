// Unit tests for the webhook's event mapping.
//
// Every one of these is about somebody's access being wrong in a direction that
// costs them or costs us. The mapping is small; what is worth asserting is that
// each way it can be wrong is a way somebody notices.
//
//     deno test

import { assertEquals } from "jsr:@std/assert@1";

import {
  entitlementFrom,
  platformFor,
  provenance,
  type RevenueCatEvent,
  statusFor,
  supersedes,
  tierFor,
} from "./events.ts";

const event = (over: Partial<RevenueCatEvent> = {}): RevenueCatEvent => ({
  type: "INITIAL_PURCHASE",
  id: "evt_1",
  app_user_id: "user-1",
  product_id: "lift.coach.monthly",
  store: "APP_STORE",
  environment: "PRODUCTION",
  ...over,
});

// ---- tiers ------------------------------------------------------------------

Deno.test("the two products this app sells map to their tiers", () => {
  assertEquals(tierFor("lift.coach.monthly"), "paid");
  assertEquals(tierFor("lift.premium_coach.monthly"), "premium");
});

Deno.test("an unknown product grants paid, for Liftio's subscribers", () => {
  // The legacy case, and the reason there is no list of old product ids here.
  // Liftio sold under this same bundle id and those subscriptions are live, so
  // renewals arrive for products 2.0.0 has never heard of. Refusing them would
  // tell a four-year customer they have no subscription.
  assertEquals(tierFor("liftio.pro.monthly"), "paid");
  assertEquals(tierFor("liftio.pro.annual"), "paid");
  assertEquals(tierFor(undefined), "paid");
});

// ---- statuses ---------------------------------------------------------------

Deno.test("cancelling does not end access", () => {
  // The most important line in the file. CANCELLATION means auto-renew was
  // switched off; the period is paid for and runs to its end. Revoking here
  // would take away time somebody has been charged for, on the day they chose
  // not to renew.
  assertEquals(statusFor(event({ type: "CANCELLATION" })), "active");
  assertEquals(
    statusFor(event({ type: "CANCELLATION", cancel_reason: "UNSUBSCRIBE" })),
    "active",
  );
});

Deno.test("a refund does end access, however it arrives", () => {
  assertEquals(
    statusFor(
      event({ type: "CANCELLATION", cancel_reason: "CUSTOMER_SUPPORT" }),
    ),
    "refunded",
  );
  assertEquals(
    statusFor(
      event({ type: "EXPIRATION", expiration_reason: "CUSTOMER_SUPPORT" }),
    ),
    "refunded",
  );
});

Deno.test("running out is expired, and distinguishable from a refund", () => {
  assertEquals(statusFor(event({ type: "EXPIRATION" })), "expired");
  assertEquals(
    statusFor(event({ type: "EXPIRATION", expiration_reason: "UNSUBSCRIBE" })),
    "expired",
  );
});

Deno.test("a failed payment is grace, not gone", () => {
  assertEquals(statusFor(event({ type: "BILLING_ISSUE" })), "grace");
});

Deno.test("everything that grants, grants", () => {
  for (
    const type of [
      "INITIAL_PURCHASE",
      "RENEWAL",
      "UNCANCELLATION",
      "PRODUCT_CHANGE",
      "SUBSCRIPTION_EXTENDED",
      "NON_RENEWING_PURCHASE",
      "REFUND_REVERSED",
      "TRANSFER",
    ]
  ) {
    assertEquals(statusFor(event({ type })), "active", type);
  }
});

Deno.test("test pings and unknown types write nothing", () => {
  // A dashboard TEST carries no real customer, and an unrecognised type is one
  // this function predates. Both must leave the row alone rather than guess.
  assertEquals(statusFor(event({ type: "TEST" })), null);
  assertEquals(statusFor(event({ type: "SOMETHING_NEW_IN_2027" })), null);
  assertEquals(entitlementFrom(event({ type: "TEST" })), null);
});

Deno.test("an event with no customer writes nothing", () => {
  assertEquals(entitlementFrom(event({ app_user_id: undefined })), null);
});

// ---- the row ----------------------------------------------------------------

Deno.test("platform comes from the store, and is null when it is neither", () => {
  assertEquals(platformFor("APP_STORE"), "apple");
  assertEquals(platformFor("PLAY_STORE"), "google");
  // The column has a CHECK, and a wrong value loses the whole write rather than
  // one field.
  assertEquals(platformFor("STRIPE"), null);
  assertEquals(platformFor(undefined), null);
});

Deno.test("sandbox purchases are honoured, and recorded as sandbox", () => {
  // Ignoring them would fail review: the App Store reviewer's purchase IS a
  // sandbox purchase, and an app where the reviewer pays and gets nothing is
  // rejected. So it writes, and the environment lives in the provenance.
  const row = entitlementFrom(event({ environment: "SANDBOX" }));
  assertEquals(row?.status, "active");
  assertEquals(row?.source_txn_id, "rc:sandbox:app_store:evt_1");
});

Deno.test("provenance says this was the store, not a support grant", () => {
  // core.grant_entitlement() writes `manual:`. Reconciling against the store
  // later depends on being able to tell the two apart.
  assertEquals(provenance(event()), "rc:production:app_store:evt_1");
});

Deno.test("expiry is carried across as an instant", () => {
  const row = entitlementFrom(event({ expiration_at_ms: 1767225600000 }));
  assertEquals(row?.expires_at, "2026-01-01T00:00:00.000Z");
});

// ---- ordering ---------------------------------------------------------------

Deno.test("a late expiration cannot revoke a renewal that followed it", () => {
  // RevenueCat retries, and retries arrive out of order. Without this an
  // EXPIRATION delivered after the RENEWAL that superseded it would end a live
  // subscription.
  const stale = entitlementFrom(
    event({ type: "EXPIRATION", expiration_at_ms: 1000 }),
  )!;
  assertEquals(
    supersedes(stale, { expires_at: "1970-01-01T00:00:02.000Z" }),
    false,
  );
});

Deno.test("the newer event wins, and equal timestamps still write", () => {
  const fresh = entitlementFrom(event({ expiration_at_ms: 5000 }))!;
  assertEquals(
    supersedes(fresh, { expires_at: "1970-01-01T00:00:02.000Z" }),
    true,
  );
  assertEquals(
    supersedes(fresh, { expires_at: "1970-01-01T00:00:05.000Z" }),
    true,
  );
});

Deno.test("a missing expiry on either side writes rather than blocks", () => {
  // Lifetime and non-renewing purchases have no expiry. Refusing those would
  // drop real writes to defend against a rarer problem than it causes.
  const noExpiry = entitlementFrom(event())!;
  assertEquals(
    supersedes(noExpiry, { expires_at: "2030-01-01T00:00:00.000Z" }),
    true,
  );
  assertEquals(supersedes(noExpiry, null), true);
});
