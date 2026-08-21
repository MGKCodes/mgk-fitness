/**
 * What the coach knows, read at request time.
 *
 * The rows are authored as files under `supabase/knowledge/` and synced into
 * `coach.knowledge`, so correcting a claim is a file edit and a sync rather
 * than a function deploy. Reading it here rather than taking it from the
 * request body is the same rule Lift's other inputs follow: the training log
 * and the memory are read as the caller and OVERWRITE whatever the client
 * sent, because prompt content a client supplies is prompt content a client
 * controls.
 *
 * **Absent is a normal state.** An empty table, a failed read or a timeout all
 * produce an empty string, and every surface that uses this treats guidance as
 * optional. The rules that are actually enforced live in the instructions and
 * in the app's validator; this makes the coach better informed, not correct.
 */

const READ_TIMEOUT_MS = 4000;

/** How much guidance may reach a prompt. Enough for a handful of documents, and
 *  a ceiling so a runaway table cannot push the real context out of the
 *  window. */
export const MAX_GUIDANCE_CHARS = 8000;

export interface KnowledgeRow {
  id: string;
  kind: string;
  title: string;
  body: string;
}

/** Rows to the block that goes in a system prompt. */
export function renderGuidance(
  rows: readonly KnowledgeRow[],
  limit: number = MAX_GUIDANCE_CHARS,
): string {
  const out: string[] = [];
  let used = 0;
  for (const r of rows) {
    const title = typeof r.title === "string" ? r.title.trim() : "";
    const body = typeof r.body === "string" ? r.body.trim() : "";
    if (!title || !body) continue;
    const block = `## ${title}\n${body}`;
    // Whole documents or nothing. Half a claim is worse than none of it: the
    // qualifications are usually in the second half, and the confident part is
    // usually the first.
    if (used + block.length > limit) break;
    out.push(block);
    used += block.length + 2;
  }
  return out.join("\n\n");
}

export class Knowledge {
  constructor(
    private readonly baseUrl: string,
    private readonly anonKey: string,
    private readonly authHeader: string,
    private readonly fetchFn: typeof fetch = fetch,
  ) {}

  /**
   * Guidance and claims for one app, shared rows included.
   *
   * `guidance` first, then `claim`: guidance is what to DO and is written for
   * this purpose, where a claim is the evidence behind it and matters more to
   * whoever maintains the guidance than to the coach mid-answer. If the limit
   * bites, losing the citations is better than losing the instructions.
   */
  async forApp(app: string): Promise<string> {
    try {
      const res = await this.fetchFn(
        `${this.baseUrl}/rest/v1/knowledge` +
          `?select=id,kind,title,body&app=in.(all,${encodeURIComponent(app)})` +
          `&order=kind.asc,id.asc`,
        {
          headers: {
            "Accept-Profile": "coach",
            "apikey": this.anonKey,
            "Authorization": this.authHeader,
          },
          signal: AbortSignal.timeout(READ_TIMEOUT_MS),
        },
      );
      if (!res.ok) {
        console.error("coach knowledge read failed", res.status);
        return "";
      }
      const rows = await res.json().catch(() => null);
      return renderGuidance(Array.isArray(rows) ? rows : []);
    } catch (e) {
      // Never fatal. A coach with no house guidance still answers; a coach that
      // refuses to answer because a reference table was slow does not.
      console.error("coach knowledge read error", String(e));
      return "";
    }
  }
}
