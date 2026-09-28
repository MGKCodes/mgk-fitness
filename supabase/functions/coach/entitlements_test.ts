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

const paid: Entitlement = {
  product: "paid",
  status: "active",
  expires_at: null,
};

// ---- the policy -------------------------------------------------------------

Deno.test("an active purchase maps onto its tier", () => {
  // `free` is a row that bought nothing, so it grants nothing on either app.
  assertEquals(
    tierFor("run", { product: "free", status: "active", expires_at: null }),
    null,
  );
  assertEquals(tierFor("run", paid), "standard");
  assertEquals(
    tierFor("run", { product: "premium", status: "active", expires_at: null }),
    "sharp",
  );
  assertEquals(tierFor("lift", paid), "standard");
  assertEquals(
    tierFor("lift", { product: "premium", status: "active", expires_at: null }),
    "sharp",
  );
});

Deno.test("only `active` grants anything", () => {
  // The column comment says so, and `grace` is the tempting mistake: it reads
  // like "still fine" and means "the store has not been paid".
  for (const status of ["expired", "grace", "refunded", "revoked", "ACTIVE"]) {
    assertEquals(
      tierFor("run", { product: "premium", status, expires_at: null }),
      null,
      `${status} must not grant the premium tier`,
    );
    assertEquals(
      tierFor("lift", { product: "premium", status, expires_at: null }),
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
      tierFor("run", { product, status: "active", expires_at: null }),
      null,
      `${JSON.stringify(product)} must not be promoted`,
    );
  }
});

Deno.test("no entitlement means no coach, on either app", () => {
  // Run used to return "free" here, which was a hard-coded placeholder that
  // survived into policy rather than a decision (ADR-0030). Every surface this
  // proxy exposes is the coach, and the coach is what a subscription buys, so
  // both apps refuse. A FAILED read arrives as null too, which means the
  // failure mode is "no coach" rather than "a free one" — the safe direction
  // now that it costs money on both sides.
  assertEquals(tierFor("lift", null), null);
  assertEquals(tierFor("run", null), null);
  assertEquals(
    tierFor("lift", { product: "free", status: "active", expires_at: null }),
    null,
  );
  assertEquals(
    tierFor("run", { product: "free", status: "active", expires_at: null }),
    null,
  );
});

Deno.test("a paid row still grants, so the gate is not simply shut", () => {
  // The counter-test to the one above: refusing everybody would pass every
  // assertion about refusal and ship an app nobody can use.
  assertEquals(tierFor("run", paid), "standard");
  assertEquals(
    tierFor("run", { product: "premium", status: "active", expires_at: null }),
    "sharp",
  );
  assertEquals(tierFor("lift", paid), "standard");
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
  // Neither app may be granted a coach because the check could not be made, and
  // neither request may die on the attempt: a 500 or a dead socket resolves to
  // null, and null now refuses on both sides. Before ADR-0030 this was the one
  // place the asymmetry bit hardest — a failed read handed Run a free coach.
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
    assertEquals(tierFor("run", b), null);
  });
});

// ---- the lapse --------------------------------------------------------------
//
// The webhook ends a subscription only when an EXPIRATION event says so. These
// are about the event that never comes, and about not over-correcting for it.

const HOUR = 60 * 60 * 1000;
const NOW = Date.parse("2026-09-28T12:00:00Z");

/** An `active` row whose paid period ends `hours` after NOW, or before it. */
function endingIn(hours: number, product = "paid"): Entitlement {
  return {
    product,
    status: "active",
    expires_at: new Date(NOW + hours * HOUR).toISOString(),
  };
}

Deno.test("an active row inside its paid period grants", () => {
  assertEquals(tierFor("run", endingIn(24 * 30), NOW), "standard");
  assertEquals(tierFor("run", endingIn(1, "premium"), NOW), "sharp");
  assertEquals(tierFor("lift", endingIn(1), NOW), "standard");
});

Deno.test("less than a day past the expiry still grants", () => {
  // A renewal in flight. RevenueCat retries a failed delivery for hours, and a
  // renewal can land just after the period it extends has ended; until it does
  // the row carries the old expiry. Refusing on the boundary would lock out a
  // subscriber whose money is on its way.
  assertEquals(tierFor("run", endingIn(-1), NOW), "standard");
  assertEquals(tierFor("run", endingIn(-23), NOW), "standard");
  assertEquals(tierFor("lift", endingIn(-23), NOW), "standard");
});

Deno.test("an active row more than a day past its expiry is refused", () => {
  // The defect. CANCELLATION leaves the row active and only EXPIRATION ends it,
  // so a lost EXPIRATION meant a paid coach for ever. The margin is exclusive:
  // a day to the millisecond is over.
  assertEquals(tierFor("run", endingIn(-24), NOW), null);
  assertEquals(tierFor("run", endingIn(-25), NOW), null);
  assertEquals(tierFor("run", endingIn(-25, "premium"), NOW), null);
  assertEquals(tierFor("lift", endingIn(-25), NOW), null);
});

Deno.test("the lapsed test subscription is refused", () => {
  // The row as it was found on 2026-09-28: still `active`, expired 2026-09-11
  // 15:39 UTC, and not written since a minute after that.
  const found: Entitlement = {
    product: "paid",
    status: "active",
    expires_at: "2026-09-11T15:39:32+00:00",
  };
  assertEquals(tierFor("run", found, NOW), null);

  // The margin's whole cost, on the same row: served until a day after it
  // lapsed, and not a minute past that.
  assertEquals(
    tierFor("run", found, Date.parse("2026-09-12T15:00:00Z")),
    "standard",
  );
  assertEquals(tierFor("run", found, Date.parse("2026-09-12T15:40:00Z")), null);
});

Deno.test("no expiry still grants, because a hand-granted row has none", () => {
  // The App Review demo account and the TestFlight sheet's grant are inserted
  // with no expires_at. Reading null as lapsed would lock the reviewer out of
  // the paid half, which is a rejection rather than a saving.
  assertEquals(tierFor("run", paid, NOW), "standard");
  assertEquals(tierFor("lift", paid, NOW), "standard");
  assertEquals(
    tierFor(
      "run",
      { product: "premium", status: "active", expires_at: null },
      NOW,
    ),
    "sharp",
  );
});

Deno.test("an expiry cannot make any other status grant", () => {
  // The rule only takes away. `grace` with a month left on it is still the
  // store not having been paid.
  for (const status of ["expired", "grace", "refunded", "revoked"]) {
    assertEquals(
      tierFor("run", { ...endingIn(24 * 30), status }, NOW),
      null,
      `${status} must not grant, whatever its expiry says`,
    );
  }
});

Deno.test("an unreadable expiry is a malformed row, not a missing one", () => {
  // Reading it as "no end date" would grant for ever on a value nobody can
  // check, which is the defect again by a different road.
  for (
    const expires_at of [
      "",
      "soon",
      "2026-13-45T00:00:00Z",
      1789141172000,
      true,
      {},
    ]
  ) {
    assertEquals(
      parseEntitlement([{ product: "paid", status: "active", expires_at }]),
      null,
      `${JSON.stringify(expires_at)} must not parse`,
    );
  }

  // Absent and null are both "no end date", which is an answer.
  assertEquals(parseEntitlement([{ product: "paid", status: "active" }]), paid);
  assertEquals(
    parseEntitlement([{ product: "paid", status: "active", expires_at: null }]),
    paid,
  );

  // A real one arrives as PostgREST wrote it, microseconds and all.
  const row = {
    product: "paid",
    status: "active",
    expires_at: "2026-09-11T15:39:32.123456+00:00",
  };
  assertEquals(parseEntitlement([row]), row);

  // And the policy refuses one that never went through the parser: NaN fails
  // the comparison that grants, rather than passing the one that refuses.
  assertEquals(
    tierFor("run", { product: "paid", status: "active", expires_at: "soon" }),
    null,
  );
});

Deno.test("the read fetches the expiry, or there is nothing to enforce", () => {
  // A select that dropped expires_at would parse every row as "no end date"
  // and grant for ever: property 4 undone without a line of it changing.
  let seen = "";
  const lapsed = {
    product: "paid",
    status: "active",
    expires_at: "2026-09-11T15:39:32+00:00",
  };
  const store = new EntitlementStore("https://db", "service-key", (url) => {
    seen = String(url);
    return Promise.resolve(
      new Response(JSON.stringify([lapsed]), { status: 200 }),
    );
  });

  return store.read("user-1", "run").then((row) => {
    const select = new URL(seen).searchParams.get("select")?.split(",") ?? [];
    assert(select.includes("expires_at"), seen);
    assertEquals(row, lapsed);
    assertEquals(tierFor("run", row, NOW), null);
  });
});
