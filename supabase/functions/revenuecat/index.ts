// The RevenueCat webhook — the ONLY thing that writes `core.entitlements`.
//
//   App Store  ─▶  RevenueCat  ─▶  this function  ─▶  core.entitlements
//                                                     (service_role)
//
// ADR-0028 chose RevenueCat and named this function before it existed; the
// migration that created the table named it earlier still ("an Edge Function
// that has already validated the receipt with Apple or Google"). This is it.
//
// ## Why the client is not in this diagram
//
// The table grants `select` to `authenticated` and nothing else, because the
// repo is public and a write path that exists is a write path somebody uses. A
// purchase is a claim until a store confirms it, and the only party here that
// has heard from the store is RevenueCat. So the app performs a purchase and
// learns nothing from it; this function is what makes it true.
//
// ## Contract
//
// POST, RevenueCat's event envelope. The shared secret arrives in the
// `Authorization` header, set on the webhook in the RevenueCat dashboard.
//
// **Always 200 on a well-formed request, even when nothing is written.** A
// webhook that answers 4xx to an event it has chosen to ignore gets retried
// until RevenueCat gives up and alerts, which turns "we do not handle
// TRANSFER yet" into an outage page. The reason is in the body instead, and in
// the log. 401 is the exception: a bad secret should be loud.
//
// Environment:
//
//     SUPABASE_URL
//     SUPABASE_SERVICE_ROLE_KEY      writes the row; never leaves this function
//     REVENUECAT_WEBHOOK_SECRET      the Authorization value to expect
//     REVENUECAT_PRODUCTS            {"<product id>": {"app","product"}, ...}
//     REVENUECAT_ACCEPT_SANDBOX      "true" to honour sandbox purchases
//
// Dependency-free (raw fetch), matching `coach/index.ts` and
// `delete-account/index.ts`.

import {
  decide,
  type EntitlementWrite,
  productMap,
  supersedes,
} from "./entitlement_event.ts";

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "content-type": "application/json" },
  });
}

/**
 * Constant-time-ish comparison of the shared secret.
 *
 * Length is compared first and then every byte regardless of mismatch, so the
 * time taken does not narrow the search. Overkill for a webhook secret and
 * cheap enough not to argue about.
 */
function secretMatches(given: string | null, expected: string): boolean {
  if (given === null || given.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < expected.length; i++) {
    diff |= given.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  return diff === 0;
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const secret = Deno.env.get("REVENUECAT_WEBHOOK_SECRET");

  // A missing secret is 503, never "allow": an unconfigured deploy that
  // accepted anonymous writes to the entitlement table would be the worst
  // possible failure of this function.
  if (!supabaseUrl || !serviceKey || !secret) {
    return json({ error: "not_configured" }, 503);
  }
  if (!secretMatches(req.headers.get("Authorization"), secret)) {
    return json({ error: "unauthorized" }, 401);
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json({ error: "bad_request" }, 400);
  }

  const decision = decide(
    body,
    productMap(Deno.env.get("REVENUECAT_PRODUCTS")),
    { acceptSandbox: Deno.env.get("REVENUECAT_ACCEPT_SANDBOX") === "true" },
  );

  if ("ignore" in decision) {
    // Logged so an unmapped product id or a new event type is findable, and
    // 200 so it is not retried forever. Neither the body nor the user id is
    // logged: this is the money path, not a debugging surface.
    console.log(
      `revenuecat: ignored (${decision.ignore}${
        decision.detail === undefined ? "" : `: ${decision.detail}`
      })`,
    );
    return json({ ok: true, ignored: decision.ignore });
  }

  const row = decision.write;
  const rest = `${supabaseUrl}/rest/v1/entitlements`;
  const headers = {
    apikey: serviceKey,
    Authorization: `Bearer ${serviceKey}`,
    "content-type": "application/json",
    // The table is in `core`, and without this PostgREST resolves the name in
    // the first exposed schema and 404s — the same trap `delete-account`
    // documents, and the one that made a whole log disappear once.
    "Content-Profile": "core",
    "Accept-Profile": "core",
  };

  // 1. What we already hold, so a late delivery cannot revert a newer state.
  //    Read rather than relying on an upsert condition: PostgREST cannot
  //    express "only if newer" on a conflict, and doing it in SQL would mean a
  //    function whose logic lives away from the mapping that produced the row.
  let storedMs: number | null | undefined;
  try {
    const res = await fetch(
      `${rest}?select=event_ms&user_id=eq.${row.user_id}&app=eq.${row.app}`,
      { headers },
    );
    if (!res.ok) return json({ error: "read_failed" }, 502);
    const rows = await res.json().catch(() => []);
    storedMs = Array.isArray(rows) && rows.length > 0
      ? (rows[0] as { event_ms?: number | null }).event_ms
      : null;
  } catch {
    return json({ error: "read_failed" }, 502);
  }

  if (!supersedes(row.event_ms, storedMs)) {
    console.log("revenuecat: ignored (stale)");
    return json({ ok: true, ignored: "stale" });
  }

  // 2. Upsert on the primary key. `resolution=merge-duplicates` is the upsert;
  //    without it a second event for the same runner is a unique violation.
  try {
    const res = await fetch(rest, {
      method: "POST",
      headers: { ...headers, Prefer: "resolution=merge-duplicates" },
      body: JSON.stringify(writeBody(row)),
    });
    if (!res.ok) {
      // Never echo PostgREST's message: it can carry schema detail, and this
      // response goes to a third party's retry logic.
      console.error(`revenuecat: write failed ${res.status}`);
      return json({ error: "write_failed" }, 502);
    }
  } catch {
    return json({ error: "write_failed" }, 502);
  }

  return json({ ok: true, status: row.status });
});

/** The row, with `updated_at` left to the table's own trigger. */
function writeBody(row: EntitlementWrite): Record<string, unknown> {
  return {
    user_id: row.user_id,
    app: row.app,
    product: row.product,
    status: row.status,
    platform: row.platform,
    expires_at: row.expires_at,
    source_txn_id: row.source_txn_id,
    event_ms: row.event_ms,
  };
}
