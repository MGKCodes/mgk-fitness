// The lifting log, read for the coach and flattened into something small enough
// to send on every turn.
//
// **Read as the CALLER, never as service role.** The whole point of the two
// clients in index.ts is that RLS — not this file — decides which sessions the
// coach can see. A coach that can read somebody else's log is one bypass away
// from being the worst bug in the product, and reading under the user's own JWT
// makes that bypass impossible rather than merely unlikely.
//
// It is also why the client cannot send its own brief for `lift_chat`, the way
// Run's app does. Run's brief carries numbers the app computes and the database
// does not hold, so the client is its source. Lift's is the log, and a log the
// client narrates is a log the client can invent.
//
// Split like usage_store.ts: the read is impure and behind an injectable
// `fetch`, the rendering is pure and unit-tested.
//
// PRIVACY: this file does not log. What passes through it is somebody's
// training history.

/** How many sessions the coach is given. */
export const RECENT_WORKOUTS = 10;

const READ_TIMEOUT_MS = 3000;

/**
 * PostgREST embeds `exercises` and their `sets` in one round trip.
 *
 * `set_type` comes from `20260807120000_lift_sync_columns.sql`. Until that
 * migration is applied the select is a 400 and the coach sees an empty log —
 * which reads exactly like a lifter who has logged nothing, so it is worth
 * knowing rather than debugging.
 */
const SELECT =
  "name,started_at,exercises(name,sets(reps,weight_kg,set_type,is_completed))";

export class LiftLog {
  constructor(
    private readonly baseUrl: string,
    private readonly anonKey: string,
    private readonly fetchFn: typeof fetch = fetch,
  ) {}

  /**
   * The caller's recent sessions, newest first, already rendered.
   *
   * A failed read returns an empty string rather than throwing: the coach can
   * still answer, and `liftChatMessages` says plainly that there is nothing
   * logged. Refusing the turn because the log would not load would be a worse
   * trade than answering without it.
   */
  async recent(authHeader: string): Promise<string> {
    try {
      const url = `${this.baseUrl}/rest/v1/workouts?select=${SELECT}` +
        `&deleted_at=is.null&is_template=eq.false` +
        `&order=started_at.desc&limit=${RECENT_WORKOUTS}`;
      const res = await this.fetchFn(url, {
        headers: {
          // `lift` is not the first exposed schema, so PostgREST needs telling.
          "Accept-Profile": "lift",
          "apikey": this.anonKey,
          "Authorization": authHeader,
        },
        signal: AbortSignal.timeout(READ_TIMEOUT_MS),
      });
      if (!res.ok) {
        console.error("coach lift log read failed", res.status);
        return "";
      }
      return renderLiftLog(await res.json().catch(() => null));
    } catch (e) {
      console.error("coach lift log read error", String(e));
      return "";
    }
  }
}

/**
 * Flattens the log into prose.
 *
 * **Working sets only, and no warm-ups** — the same definition of "counts" the
 * app uses, because a coach that reads a warm-up as a top set will prescribe
 * from it.
 *
 * A session whose sets are all warm-ups or all unticked is dropped entirely
 * rather than listed with nothing under it. An empty heading is not a fact
 * about someone's training; it is a session they opened and abandoned, and a
 * model handed a row of them will find a pattern in it.
 */
export function renderLiftLog(payload: unknown): string {
  const rows = Array.isArray(payload) ? payload : [];

  const sessions: string[] = [];
  for (const raw of rows) {
    if (typeof raw !== "object" || raw === null) continue;
    const w = raw as Record<string, unknown>;

    const lines: string[] = [];
    for (const e of asArray(w.exercises)) {
      const sets = asArray(e.sets).filter((s) =>
        s.is_completed === true && s.set_type !== "warmup"
      );
      if (sets.length === 0) continue;
      lines.push(
        `  ${str(e.name) || "(unnamed)"}: ${sets.map(set).join(", ")}`,
      );
    }
    if (lines.length === 0) continue;

    const date = str(w.started_at).slice(0, 10);
    sessions.push(`${date} ${str(w.name)}`.trim() + `\n${lines.join("\n")}`);
  }

  return sessions.join("\n");
}

/**
 * One set. A zero weight is rendered as "bodyweight" rather than "0kg" —
 * `lift.sets.weight_kg` defaults to 0 and that is what a chin-up is stored as,
 * so "0kg x8" would read to a model as a loaded lift the lifter failed to load.
 */
function set(s: Record<string, unknown>): string {
  const reps = num(s.reps);
  const weight = num(s.weight_kg);
  return weight > 0 ? `${weight}kg x${reps}` : `bodyweight x${reps}`;
}

function asArray(value: unknown): Record<string, unknown>[] {
  return Array.isArray(value)
    ? value.filter((v): v is Record<string, unknown> =>
      typeof v === "object" && v !== null
    )
    : [];
}

function str(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function num(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}
