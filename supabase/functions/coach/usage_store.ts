// The durable half of the coach limiter: where a user's recent model calls are
// read from and written to.
//
// Edge Function instances are ephemeral and there may be many of them, so the
// counters cannot live in memory — they live in Postgres, in
// `runio.coach_usage`. The table is service-role only: a user must not be able
// to delete their own usage rows and reset their own cap, so it has RLS on with
// no policies, its grants revoked, and it is reached through two SECURITY
// DEFINER functions in `public` (the only schema PostgREST exposes by default —
// so installing this needs no project-level API config change). The exact DDL
// is in README.md under "Counter storage".
//
// This module holds no thresholds and makes no decisions; limits.ts does that,
// purely and under test. Everything impure is here, behind an injectable
// `fetch` so the failure mapping is testable too.

import type { RecordedUsage, UsageRow } from "./limits.ts";

/**
 * `ok` — we have a trustworthy snapshot.
 * `not_installed` — the counter storage is absent or unreachable by us (the
 *   SQL has not been applied, or the service key is wrong). A deploy-order
 *   mistake, not a user problem.
 * `unavailable` — a transient failure: timeout, network, 5xx.
 */
export type StoreStatus = "ok" | "not_installed" | "unavailable";

export interface WindowResult {
  status: StoreStatus;
  rows: UsageRow[];
}

const READ_TIMEOUT_MS = 3000;
const WRITE_TIMEOUT_MS = 3000;

/**
 * Postgres / PostgREST codes that mean "this is not set up", as opposed to
 * "the database is having a moment".
 */
const NOT_INSTALLED_CODES = new Set([
  "PGRST202", // function not found in the schema cache
  "PGRST205", // table not found in the schema cache
  "PGRST302", // JWT / role could not be resolved
  "42883", // undefined_function
  "42P01", // undefined_table
  "42501", // insufficient_privilege
  "3F000", // invalid_schema_name
]);

/**
 * Maps a PostgREST failure onto a store status. Pure, so it is unit-tested.
 *
 * 404 is a schema-cache miss (nothing there to call). 401/403 means our
 * service credential is wrong — also a setup problem, and one that would
 * otherwise masquerade as a database outage forever. Everything else is
 * treated as transient.
 */
export function classifyFailure(
  httpStatus: number,
  body: unknown,
): "not_installed" | "unavailable" {
  const code = (typeof body === "object" && body !== null)
    ? (body as Record<string, unknown>).code
    : undefined;
  if (typeof code === "string" && NOT_INSTALLED_CODES.has(code)) {
    return "not_installed";
  }
  if (httpStatus === 404 || httpStatus === 401 || httpStatus === 403) {
    return "not_installed";
  }
  return "unavailable";
}

/**
 * Parses the rows the window RPC returns, dropping anything malformed rather
 * than trusting it into the arithmetic.
 */
export function parseWindowRows(payload: unknown): UsageRow[] {
  if (!Array.isArray(payload)) return [];
  const rows: UsageRow[] = [];
  for (const raw of payload) {
    if (typeof raw !== "object" || raw === null) continue;
    const r = raw as Record<string, unknown>;
    const atMs = Date.parse(String(r.at ?? ""));
    if (!Number.isFinite(atMs)) continue;
    const cost = Number(r.cost_credits);
    rows.push({
      atMs,
      surface: typeof r.surface === "string" ? r.surface : "",
      costCredits: Number.isFinite(cost) ? cost : 0,
    });
  }
  return rows;
}

export type FetchLike = (
  input: string,
  init?: RequestInit,
) => Promise<Response>;

export class UsageStore {
  constructor(
    private readonly baseUrl: string,
    private readonly serviceKey: string,
    private readonly fetchFn: FetchLike = fetch,
  ) {}

  /**
   * A user's calls since `sinceMs`. Returns a status rather than throwing: the
   * caller decides what a missing limiter means, and it always fails closed.
   */
  async window(userId: string, sinceMs: number): Promise<WindowResult> {
    try {
      const res = await this.rpc("usage_window", {
        p_user: userId,
        p_since: new Date(sinceMs).toISOString(),
      }, READ_TIMEOUT_MS);

      if (!res.ok) {
        const body = await safeJson(res);
        const status = classifyFailure(res.status, body);
        console.error("coach limiter read failed", res.status, status);
        return { status, rows: [] };
      }
      return { status: "ok", rows: parseWindowRows(await safeJson(res)) };
    } catch (e) {
      console.error("coach limiter read error", String(e));
      return { status: "unavailable", rows: [] };
    }
  }

  /**
   * Records one attempt. Never throws and never fails the caller's request:
   * the model has already answered, and discarding a good response because an
   * accounting row would not write is the worse outcome. A dropped row is
   * logged and shows up as slightly under-counted spend.
   */
  async record(
    userId: string,
    surface: string,
    usage: RecordedUsage,
    outcome: string,
  ): Promise<StoreStatus> {
    try {
      const res = await this.rpc("record_usage", {
        p_user: userId,
        p_surface: surface,
        p_prompt_tokens: usage.promptTokens,
        p_completion_tokens: usage.completionTokens,
        p_total_tokens: usage.totalTokens,
        p_cost_credits: usage.costCredits,
        p_cost_estimated: usage.costEstimated,
        p_outcome: outcome,
      }, WRITE_TIMEOUT_MS);

      if (!res.ok) {
        const status = classifyFailure(res.status, await safeJson(res));
        console.error("coach usage write failed", res.status, status);
        return status;
      }
      return "ok";
    } catch (e) {
      console.error("coach usage write error", String(e));
      return "unavailable";
    }
  }

  private rpc(
    fn: string,
    args: Record<string, unknown>,
    timeoutMs: number,
  ): Promise<Response> {
    return this.fetchFn(`${this.baseUrl}/rest/v1/rpc/${fn}`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        // Both routines live in the `coach` schema. Without this PostgREST
        // resolves the name against the FIRST exposed schema and 404s, which
        // `classifyFailure` reads as "limiter missing" — and the limiter fails
        // closed, so every coach request would 503.
        "Content-Profile": "coach",
        "apikey": this.serviceKey,
        "Authorization": `Bearer ${this.serviceKey}`,
      },
      body: JSON.stringify(args),
      signal: AbortSignal.timeout(timeoutMs),
    });
  }
}

async function safeJson(res: Response): Promise<unknown> {
  try {
    return await res.json();
  } catch {
    return null;
  }
}
