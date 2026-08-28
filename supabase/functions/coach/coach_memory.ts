// What the coach remembers between visits.
//
// Two tiers with opposite lifecycles, which is the whole design:
//
//   * `coach.summaries` — a few sentences of prose, sent on EVERY turn,
//     regenerated from scratch and replaced. Bounded, so month six costs the
//     same as week one.
//   * `coach.turns` — the verbatim transcript, append-only, of which only the
//     last few are sent. Unbounded, and never all loaded.
//
// Sending the whole history instead would work for a fortnight and then not.
// Appending to the summary instead would make every version a re-encode of a
// re-encode, drifting with nothing to say which copy was right.
//
// **Read and written AS THE CALLER**, like the training log and for the same
// reason: RLS is the boundary, so a bug here cannot read somebody else's
// memory. The turns are append-only at the grant layer too — `authenticated`
// holds INSERT and DELETE on `coach.turns` but not UPDATE — so nothing in this
// file can rewrite what was said, only add to it.
//
// PRIVACY: everything through here is somebody's own words about their body.
// Nothing in this file logs a turn, a summary, or any part of either. The error
// paths log a status code and nothing else, deliberately.

import type { App } from "./surfaces.ts";

/** How many stored turns are replayed into the prompt. */
export const MEMORY_TURNS = 20;

/**
 * How far the memory may fall behind the transcript before it is rewritten.
 *
 * Not every turn: regenerating on each one is a re-encode loop, it is the most
 * expensive way to run a coach, and it is the failure the two-tier design
 * exists to avoid. Not on a timer either — a memory should move when the
 * conversation moves, not when the clock does.
 */
export const REGENERATE_AFTER = 20;

const READ_TIMEOUT_MS = 3000;
const WRITE_TIMEOUT_MS = 3000;

export interface StoredTurn {
  role: "user" | "assistant";
  text: string;
}

export interface Memory {
  /** The rolling prose memory, or "" when there is none yet. */
  summary: string;
  /** How many turns that summary was written from. */
  turnsCovered: number;
  /** The last [MEMORY_TURNS] turns, oldest first. */
  turns: StoredTurn[];
  /** How many turns exist in total. Also where the next `seq` comes from. */
  total: number;
}

export const EMPTY_MEMORY: Memory = {
  summary: "",
  turnsCovered: 0,
  turns: [],
  total: 0,
};

/**
 * Has the memory fallen far enough behind to be worth rewriting?
 *
 * `>=` rather than `>`, and guarded against a `turnsCovered` ahead of the
 * count: a memory covering turns that no longer exist is a pruned transcript,
 * not a reason to skip regeneration forever.
 */
export function shouldRegenerate(total: number, turnsCovered: number): boolean {
  return total - Math.max(0, Math.min(turnsCovered, total)) >= REGENERATE_AFTER;
}

/**
 * Reads the total row count out of a PostgREST `Content-Range`.
 *
 * The header is `0-19/137`, or `* / 0` for an empty table, or absent when the
 * caller did not ask for a count. Anything unparseable answers `null` so the
 * caller can fall back to what it actually received rather than trusting a
 * zero it invented — a wrong total here would be handed straight to `seq`,
 * where it collides with a turn that already exists.
 */
export function totalFromContentRange(header: string | null): number | null {
  if (!header) return null;
  const slash = header.lastIndexOf("/");
  if (slash < 0) return null;
  const total = Number(header.slice(slash + 1).trim());
  return Number.isInteger(total) && total >= 0 ? total : null;
}

/** Parses the turns PostgREST returns, newest first, into oldest-first. */
export function parseTurns(payload: unknown): StoredTurn[] {
  const rows = Array.isArray(payload) ? payload : [];
  const turns: StoredTurn[] = [];
  for (const raw of rows) {
    if (typeof raw !== "object" || raw === null) continue;
    const r = raw as Record<string, unknown>;
    const text = typeof r.body === "string" ? r.body.trim() : "";
    if (!text) continue;
    // A turn whose speaker is unknown is dropped rather than attributed. Put it
    // on the wrong side and the coach reads its own words as the lifter's.
    if (r.role !== "user" && r.role !== "assistant") continue;
    turns.push({ role: r.role, text });
  }
  return turns.reverse();
}

export class CoachMemory {
  constructor(
    private readonly baseUrl: string,
    private readonly anonKey: string,
    private readonly authHeader: string,
    private readonly fetchFn: typeof fetch = fetch,
  ) {}

  /**
   * The memory as it stands: the summary, the recent turns, and how many turns
   * there are in total.
   *
   * A failed read answers [EMPTY_MEMORY] rather than throwing. The coach can
   * still hold a useful conversation with no memory — it just holds it as a
   * stranger — and refusing the turn would trade a slightly worse answer for no
   * answer at all. The `total` of 0 that comes with it is the one part that
   * matters: [appendTurns] will not write against a count it did not read.
   */
  async read(app: App, conversation: string): Promise<Memory> {
    const [summary, transcript] = await Promise.all([
      this.readSummary(app),
      this.readTurns(conversation),
    ]);
    return { ...summary, ...transcript };
  }

  private async readSummary(
    app: App,
  ): Promise<{ summary: string; turnsCovered: number }> {
    try {
      const res = await this.get(
        `/rest/v1/summaries?select=summary,turns_covered&app=eq.${app}&limit=1`,
        "coach",
      );
      if (!res.ok) {
        console.error("coach memory summary read failed", res.status);
        return { summary: "", turnsCovered: 0 };
      }
      const rows = await res.json().catch(() => null);
      const row = Array.isArray(rows) ? rows[0] : null;
      if (typeof row !== "object" || row === null) {
        return { summary: "", turnsCovered: 0 };
      }
      const r = row as Record<string, unknown>;
      return {
        summary: typeof r.summary === "string" ? r.summary.trim() : "",
        turnsCovered: typeof r.turns_covered === "number" ? r.turns_covered : 0,
      };
    } catch (e) {
      console.error("coach memory summary read error", String(e));
      return { summary: "", turnsCovered: 0 };
    }
  }

  /**
   * The last [MEMORY_TURNS] turns AND the total count, in one request.
   *
   * `Prefer: count=exact` puts the total in `Content-Range`, which is what
   * makes this one round trip instead of two — and the total is needed on every
   * turn anyway, both to number the next one and to decide whether the memory
   * has fallen behind.
   */
  private async readTurns(
    conversation: string,
  ): Promise<{ turns: StoredTurn[]; total: number }> {
    try {
      const id = encodeURIComponent(conversation);
      const res = await this.get(
        `/rest/v1/turns?select=role,body&conversation_id=eq.${id}` +
          `&order=seq.desc&limit=${MEMORY_TURNS}`,
        "coach",
        { Prefer: "count=exact" },
      );
      if (!res.ok) {
        console.error("coach memory turns read failed", res.status);
        return { turns: [], total: 0 };
      }
      const turns = parseTurns(await res.json().catch(() => null));
      const counted = totalFromContentRange(res.headers.get("Content-Range"));
      // Falling back to what arrived rather than to 0: a bogus total becomes a
      // `seq` that collides with a turn already stored.
      return { turns, total: counted ?? turns.length };
    } catch (e) {
      console.error("coach memory turns read error", String(e));
      return { turns: [], total: 0 };
    }
  }

  /**
   * Appends the exchange, both sides, numbered from `after`.
   *
   * Never fails the caller's request. The lifter has already had their answer,
   * and losing a transcript row is cheaper than throwing away a good reply —
   * the same trade the usage ledger makes. A `seq` collision (two devices
   * talking at once) lands here as a rejected insert, which is correct: the
   * turn that got there first keeps the number.
   */
  async appendTurns(
    app: App,
    userId: string,
    id: string,
    after: number,
    exchange: readonly StoredTurn[],
  ): Promise<void> {
    if (exchange.length === 0) return;
    const at = new Date().toISOString();

    try {
      // The conversation first: `coach.turns.conversation_id` is a NOT NULL FK,
      // so a turn with no parent is a rejected insert. `started_at` is left out
      // of the payload deliberately — PostgREST updates only the columns it is
      // given, so an existing conversation keeps the moment it actually began
      // while `last_turn_at` moves forward.
      const parent = await this.write("/rest/v1/conversations", "coach", {
        id,
        user_id: userId,
        app,
        kind: "coach",
        last_turn_at: at,
      }, "resolution=merge-duplicates");
      if (!parent.ok) {
        console.error("coach memory conversation write failed", parent.status);
        return;
      }

      const rows = exchange.map((turn, i) => ({
        id: `${id}:${after + i + 1}`,
        conversation_id: id,
        user_id: userId,
        seq: after + i + 1,
        role: turn.role,
        body: turn.text,
        created_at: at,
      }));
      // ON CONFLICT DO NOTHING, not a merging upsert: UPDATE on `coach.turns`
      // is revoked from `authenticated`, so a merge would be rejected outright.
      // Re-sending an identical turn is correctly a no-op.
      const res = await this.write(
        "/rest/v1/turns",
        "coach",
        rows,
        "resolution=ignore-duplicates",
      );
      if (!res.ok) console.error("coach memory turn write failed", res.status);
    } catch (e) {
      console.error("coach memory turn write error", String(e));
    }
  }

  /**
   * Replaces the memory. Never appends — see the file header.
   *
   * `turns_covered` is written with it and not separately: the pair is what
   * makes "has this fallen behind" answerable, and a summary whose coverage
   * count is stale would either regenerate forever or never again.
   */
  async writeSummary(
    app: App,
    userId: string,
    summary: string,
    turnsCovered: number,
    model: string | null,
  ): Promise<void> {
    try {
      const res = await this.write("/rest/v1/summaries", "coach", {
        user_id: userId,
        app,
        summary,
        model,
        turns_covered: Math.max(0, turnsCovered),
        updated_at: new Date().toISOString(),
      }, "resolution=merge-duplicates");
      if (!res.ok) {
        console.error("coach memory summary write failed", res.status);
      }
    } catch (e) {
      console.error("coach memory summary write error", String(e));
    }
  }

  private get(
    path: string,
    profile: string,
    extra: Record<string, string> = {},
  ): Promise<Response> {
    return this.fetchFn(`${this.baseUrl}${path}`, {
      headers: {
        "Accept-Profile": profile,
        "apikey": this.anonKey,
        "Authorization": this.authHeader,
        ...extra,
      },
      signal: AbortSignal.timeout(READ_TIMEOUT_MS),
    });
  }

  private write(
    path: string,
    profile: string,
    body: unknown,
    resolution: string,
  ): Promise<Response> {
    return this.fetchFn(`${this.baseUrl}${path}`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        // Writes need Content-Profile, not Accept-Profile. Getting this wrong
        // resolves the table against the first exposed schema and 404s.
        "Content-Profile": profile,
        "apikey": this.anonKey,
        "Authorization": this.authHeader,
        "Prefer": `${resolution},return=minimal`,
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(WRITE_TIMEOUT_MS),
    });
  }
}
