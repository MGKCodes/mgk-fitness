// Who is allowed to spend, and on which model.
//
// `core.entitlements` holds one row per (user, app) — the tier they bought and
// what the store currently says about it. This module turns that row into the
// two answers the proxy needs before it calls anything: may this request happen
// at all, and which model answers it.
//
// Split the same way as the limiter: the POLICY is pure and unit-tested
// (`tierFor`), the read is behind an injectable `fetch` so its failure mapping
// is testable too. The two halves fail in opposite directions and both are
// deliberate, so neither belongs in a handler where it would be read as
// plumbing.
//
// PRIVACY: an entitlement row carries a tier, a store status and a transaction
// id. This module reads two columns of it and keeps neither.

import type { App, Tier } from "./surfaces.ts";

/** The two columns of `core.entitlements` that decide anything. */
export interface Entitlement {
  product: string;
  status: string;
}

/**
 * What the coach may do for this caller: a tier, or a refusal.
 *
 * `null` is "no coach at all", which is not the same as the free tier. The
 * coach is the paid half of both apps, so a user with nothing bought gets
 * `null` and a 402 on either. Run got `"free"` here until ADR-0030 — see the
 * note inside `tierFor`.
 */
export type Access = Tier | null;

/**
 * `product` is the tier the store sold. The names differ because the database
 * describes what was bought and the router describes what it costs to serve —
 * mapping them here rather than renaming either keeps `core.entitlements`
 * readable by a person looking at a receipt.
 */
const PRODUCT_TIERS: Record<string, Tier> = {
  free: "free",
  paid: "standard",
  premium: "sharp",
};

/**
 * Whether the coach may serve this caller, and on which tier.
 *
 * Three properties, each written against a specific way this goes wrong:
 *
 * 1. **Only `active` grants anything.** `core.entitlements.status` has five
 *    values and the column comment says to treat every other one as no
 *    entitlement. `grace` is the tempting mistake: it reads like "still fine"
 *    and means "the store has not been paid".
 * 2. **An unknown product is the cheapest tier, never the dearest.** A typo, a
 *    new SKU, or a row written by a future version of the receipt validator
 *    must not be able to bill at the Sharp model's rate. Same fallback
 *    direction as `tierFrom`.
 * 3. **A missing row is `null` on both apps.** A failed entitlement READ
 *    arrives here as `null` too, so the failure mode is "no coach" rather than
 *    "a free one" — the safe direction now that the coach costs money on both
 *    sides. Run got `free` here until ADR-0030; the note in the body says why
 *    that was never a decision.
 */
export function tierFor(app: App, entitlement: Entitlement | null): Access {
  const active = entitlement?.status === "active";
  const tier = active ? PRODUCT_TIERS[entitlement.product] ?? "free" : "free";

  // **Both apps refuse an unentitled caller.** The coach is the paid half of
  // each, and every surface this proxy exposes is the coach: a plan, a
  // conversation, the intents inside one, and the memory written after it.
  //
  // Run used to return `"free"` here. That was never a decision — a3980c4 gave
  // Run "the real tier lookup its code had been hard-coding to `free`", and the
  // hard-coded placeholder was preserved rather than chosen. The comment above
  // it then described the leftover as a product choice, which is how a
  // placeholder becomes a policy nobody agreed. It also contradicted the app's
  // own gate copy, which has told runners a plan needs a subscription the whole
  // time. See ADR-0030.
  if (tier === "free") return null;
  return tier;
}

/**
 * Reads a user's entitlement for one app.
 *
 * Under `service_role`, not as the caller. The row is client-READABLE, so the
 * caller's own JWT would work — but the read would then be subject to a session
 * the client controls, and this is the money gate. Service role reads exactly
 * one row of exactly two columns.
 */
export class EntitlementStore {
  constructor(
    private readonly baseUrl: string,
    private readonly serviceKey: string,
    private readonly fetchFn: typeof fetch = fetch,
  ) {}

  /**
   * Returns the row, or `null` for "no entitlement" — which is also what a
   * failed read returns, because there is no honest way to distinguish "they
   * have not bought it" from "we could not tell" in a way the caller could act
   * on, and `tierFor` already treats absence as the safe direction.
   *
   * The failure is logged rather than thrown so that a Run request is not
   * killed by a table Run does not use.
   */
  async read(userId: string, app: App): Promise<Entitlement | null> {
    try {
      const url = `${this.baseUrl}/rest/v1/entitlements` +
        `?select=product,status&user_id=eq.${encodeURIComponent(userId)}` +
        `&app=eq.${encodeURIComponent(app)}&limit=1`;
      const res = await this.fetchFn(url, {
        headers: {
          // `core` is not the first exposed schema, so PostgREST needs telling.
          // Without this the read 404s and every Lift caller looks unentitled.
          "Accept-Profile": "core",
          "apikey": this.serviceKey,
          "Authorization": `Bearer ${this.serviceKey}`,
        },
        signal: AbortSignal.timeout(READ_TIMEOUT_MS),
      });
      if (!res.ok) {
        console.error("coach entitlement read failed", res.status);
        return null;
      }
      return parseEntitlement(await res.json().catch(() => null));
    } catch (e) {
      console.error("coach entitlement read error", String(e));
      return null;
    }
  }
}

const READ_TIMEOUT_MS = 3000;

/**
 * Reads the one row PostgREST returns, dropping anything malformed rather than
 * trusting it into the decision. A row missing either column is not an
 * entitlement — treating it as one would grant on a shape, not on a purchase.
 */
export function parseEntitlement(payload: unknown): Entitlement | null {
  const row = Array.isArray(payload) ? payload[0] : payload;
  if (typeof row !== "object" || row === null) return null;
  const r = row as Record<string, unknown>;
  if (typeof r.product !== "string" || typeof r.status !== "string") {
    return null;
  }
  return { product: r.product, status: r.status };
}
