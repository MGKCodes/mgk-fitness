// RevenueCat → `core.entitlements`.
//
//   the stores  ─▶  RevenueCat  ─▶  this function  ─▶  core.entitlements
//
// The one thing that writes that table, apart from `core.grant_entitlement()`
// for support. The table has no INSERT, UPDATE or DELETE policy and no such
// grant to `authenticated`, so a client cannot write its own access no matter
// what the app is persuaded to believe — this runs under `service_role` and is
// the whole of the path in.
//
// ## Contract
//
// POST, RevenueCat's standard body: `{ "api_version": "1.0", "event": { ... } }`.
// Authenticated by a shared secret RevenueCat sends in `Authorization`, set to
// the same value in the dashboard and in `REVENUECAT_WEBHOOK_SECRET`.
//
// ## Status codes are a retry policy, not decoration
//
// RevenueCat retries anything that is not 2xx, so the codes here decide whether
// a problem heals itself or repeats forever:
//
//     401  bad or missing secret        — do not retry, it will not get better
//     400  body is not an event         — do not retry
//     200  handled, or deliberately ignored (TEST pings, unknown event types,
//          anonymous customers) — nothing to retry
//     500  the database did not accept the write — RETRY, please
//
// The 200-for-ignored case is the one worth stating: returning an error for an
// event we have chosen not to act on would have RevenueCat redelivering it until
// it gave up, and the log would fill with a decision rather than a fault.
//
// ## Environment
//
//     SUPABASE_URL                 injected
//     SUPABASE_SERVICE_ROLE_KEY    injected
//     REVENUECAT_WEBHOOK_SECRET    NEW — set this before pointing RevenueCat here
//
// Raw fetch against PostgREST, matching `coach/index.ts` and most of
// `delete-account`: the endpoints are documented and stable, and the wire shape
// being explicit is worth more here than a dependency.

import { entitlementFrom, type RevenueCatEvent, supersedes } from "./events.ts";

/// This function serves Lift. `core.entitlements` is keyed `(user_id, app)`
/// because pricing is per app and never cross-app — a Run subscription must not
/// unlock the coach here — so a second app gets its own RevenueCat project and
/// its own copy of this, rather than a branch inside it.
const APP = "lift";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const WEBHOOK_SECRET = Deno.env.get("REVENUECAT_WEBHOOK_SECRET") ?? "";

/// Compared without short-circuiting on the first differing byte.
///
/// A plain `===` on a secret leaks its length and, in principle, its content to
/// anybody who can measure the response. This costs nothing and removes the
/// argument.
function secretMatches(presented: string): boolean {
  if (WEBHOOK_SECRET.length === 0) return false;
  if (presented.length !== WEBHOOK_SECRET.length) return false;
  let diff = 0;
  for (let i = 0; i < presented.length; i++) {
    diff |= presented.charCodeAt(i) ^ WEBHOOK_SECRET.charCodeAt(i);
  }
  return diff === 0;
}

/// RevenueCat's `app_user_id` is whatever the client called `logIn` with, and
/// this app calls it with the Supabase user id so the two systems agree on who
/// somebody is without a mapping table.
///
/// Anybody who has not signed in carries an `$RCAnonymousID:...` instead. That
/// is not an error and must not retry: there is no account to attach the
/// purchase to yet, and RevenueCat will send a `TRANSFER` when there is.
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function ok(body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

async function currentRow(
  userId: string,
): Promise<{ expires_at?: string | null } | null> {
  const url = `${SUPABASE_URL}/rest/v1/entitlements` +
    `?select=expires_at&user_id=eq.${userId}&app=eq.${APP}`;
  const response = await fetch(url, {
    headers: {
      apikey: SERVICE_ROLE,
      authorization: `Bearer ${SERVICE_ROLE}`,
      "accept-profile": "core",
    },
  });
  if (!response.ok) return null;
  const rows = await response.json() as Array<{ expires_at?: string | null }>;
  return rows[0] ?? null;
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method !== "POST") {
    return new Response("method not allowed", { status: 405 });
  }

  // Bearer-prefixed or bare: the dashboard field is free text and it is not
  // worth a failed integration to insist on one shape.
  const presented = (request.headers.get("authorization") ?? "")
    .replace(/^Bearer\s+/i, "");
  if (!secretMatches(presented)) {
    return new Response("unauthorized", { status: 401 });
  }

  let event: RevenueCatEvent;
  try {
    const body = await request.json() as { event?: RevenueCatEvent };
    if (!body?.event) throw new Error("no event");
    event = body.event;
  } catch {
    return new Response("bad request", { status: 400 });
  }

  const write = entitlementFrom(event);
  if (write === null) {
    return ok({ ignored: true, type: event.type ?? null });
  }

  const userId = event.app_user_id ?? "";
  if (!UUID.test(userId)) {
    // Anonymous, or an id from before the app identified customers properly.
    // Nothing to attach it to, and nothing that retrying would fix.
    return ok({ ignored: true, reason: "not a signed-in customer" });
  }

  if (!supersedes(write, await currentRow(userId))) {
    // An out-of-order retry about a period that has already been superseded.
    return ok({ ignored: true, reason: "stale event" });
  }

  const response = await fetch(`${SUPABASE_URL}/rest/v1/entitlements`, {
    method: "POST",
    headers: {
      apikey: SERVICE_ROLE,
      authorization: `Bearer ${SERVICE_ROLE}`,
      "content-type": "application/json",
      "content-profile": "core",
      // The table's primary key is (user_id, app), so this is an upsert on the
      // row that already exists rather than a second row per renewal.
      prefer: "resolution=merge-duplicates,return=minimal",
    },
    body: JSON.stringify({ user_id: userId, app: APP, ...write }),
  });

  if (!response.ok) {
    // The one case that SHOULD retry. Returning 200 here would silently drop a
    // purchase, and the person would have paid and received nothing with no
    // record of why.
    console.error(
      `entitlement write failed ${response.status}: ${await response.text()}`,
    );
    return new Response("write failed", { status: 500 });
  }

  return ok({ applied: true, product: write.product, status: write.status });
});
