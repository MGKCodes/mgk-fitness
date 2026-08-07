// Unit tests for the entitlement policy.
//
// Every one of these is about a DIRECTION of failure. The policy is small
// enough to read in a minute; what is worth asserting is that each way it can
// be wrong costs nothing rather than costing money.
//
//     deno test

import { assert, assertEquals } from "jsr:@std/assert@1";

import {
  type Entitlement,
  EntitlementStore,
  parseEntitlement,
  tierFor,
} from "./entitlements.ts";

const paid: Entitlement = { product: "paid", status: "active" };

// ---- the policy -------------------------------------------------------------

Deno.test("an active purchase maps onto its tier", () => {
  assertEquals(tierFor("run", { product: "free", status: "active" }), "free");
  assertEquals(tierFor("run", paid), "standard");
  assertEquals(
    tierFor("run", { product: "premium", status: "active" }),
    "sharp",
  );
  assertEquals(tierFor("lift", paid), "standard");
  assertEquals(
    tierFor("lift", { product: "premium", status: "active" }),
    "sharp",
  );
});

Deno.test("only `active` grants anything", () => {
  // The column comment says so, and `grace` is the tempting mistake: it reads
  // like "still fine" and means "the store has not been paid".
  for (const status of ["expired", "grace", "refunded", "revoked", "ACTIVE"]) {
    assertEquals(
      tierFor("run", { product: "premium", status }),
      "free",
      `${status} must not grant the premium tier`,
    );
    assertEquals(
      tierFor("lift", { product: "premium", status }),
      null,
      `${status} must not grant a Lift coach`,
    );
  }
});

Deno.test("an unknown product is the cheapest tier, never the dearest", () => {
  // A typo, a new SKU, or a row from a future receipt validator. The failure
  // that matters is the one that bills at the Sharp model's rate.
  for (const product of ["", "pro", "PREMIUM", "lifetime", "premium "]) {
    assertEquals(
      tierFor("run", { product, status: "active" }),
      "free",
      `${JSON.stringify(product)} must not be promoted`,
    );
  }
});

Deno.test("no entitlement means no Lift coach, and a free Run coach", () => {
  // Both halves preserve what each app did before the two were unified: Lift
  // sells coaching, Run gives everyone the cheapest model. It also means a
  // FAILED read (which arrives as null) fails closed on the app that charges.
  assertEquals(tierFor("lift", null), null);
  assertEquals(tierFor("run", null), "free");
  assertEquals(tierFor("lift", { product: "free", status: "active" }), null);
});

// ---- reading the row --------------------------------------------------------

Deno.test("a well-formed row is read, anything else is no entitlement", () => {
  assertEquals(parseEntitlement([paid]), paid);
  assertEquals(parseEntitlement(paid), paid);

  // Granting on a shape rather than on a purchase is the failure here.
  assertEquals(parseEntitlement([]), null);
  assertEquals(parseEntitlement(null), null);
  assertEquals(parseEntitlement("active"), null);
  assertEquals(parseEntitlement([{ product: "paid" }]), null);
  assertEquals(parseEntitlement([{ status: "active" }]), null);
  assertEquals(parseEntitlement([{ product: 1, status: "active" }]), null);
});

Deno.test("the read names the core schema and filters to one app", () => {
  // Without Accept-Profile the read resolves against the first exposed schema
  // and 404s, which would make every Lift caller look unentitled.
  let seen: { url: string; headers: Headers } | null = null;
  const store = new EntitlementStore(
    "https://db",
    "service-key",
    (url, init) => {
      seen = { url: String(url), headers: new Headers(init?.headers) };
      return Promise.resolve(
        new Response(JSON.stringify([paid]), { status: 200 }),
      );
    },
  );

  return store.read("user-1", "lift").then((row) => {
    assertEquals(row, paid);
    const call = seen!;
    assertEquals(call.headers.get("Accept-Profile"), "core");
    assertEquals(call.headers.get("Authorization"), "Bearer service-key");
    assert(call.url.includes("user_id=eq.user-1"), call.url);
    assert(call.url.includes("app=eq.lift"), call.url);
    assert(call.url.includes("select=product,status"), call.url);
  });
});

Deno.test("a failed read is no entitlement, not a thrown request", () => {
  // A Run request must not die on a table Run does not use, and a Lift request
  // must not be granted because the check could not be made.
  const failing = new EntitlementStore(
    "https://db",
    "service-key",
    () => Promise.resolve(new Response("nope", { status: 500 })),
  );
  const throwing = new EntitlementStore(
    "https://db",
    "service-key",
    () => Promise.reject(new Error("socket")),
  );

  return Promise.all([
    failing.read("user-1", "lift"),
    throwing.read("user-1", "run"),
  ]).then(([a, b]) => {
    assertEquals(a, null);
    assertEquals(b, null);
    assertEquals(tierFor("lift", a), null);
    assertEquals(tierFor("run", b), "free");
  });
});
