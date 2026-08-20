/**
 * Pushes the knowledge files into `coach.knowledge`.
 *
 *     deno task knowledge:sync                 # local stack
 *     SUPABASE_URL=... SUPABASE_SERVICE_KEY=... deno task knowledge:sync
 *
 * ## Why a script and not a migration
 *
 * A migration would version the content, which sounds right and is not: every
 * wording fix would become a schema change, and correcting a claim would need a
 * database deploy in lockstep with whatever else is unmigrated. The point of
 * putting knowledge in a table was to decouple it from release cadences, and a
 * migration per edit puts it straight back on one.
 *
 * Git still versions it — the FILES are the record, and this only carries them.
 *
 * ## Why it deletes
 *
 * A row whose file is gone has been deliberately removed, and leaving it behind
 * means the coach keeps citing advice nobody can find the source of. That is the
 * failure mode this whole arrangement exists to prevent, so the sync is a
 * mirror rather than an upsert.
 */

const DIRS = ["claims", "guidance"] as const;

interface Doc {
  id: string;
  app: string;
  kind: string;
  title: string;
  body: string;
  confidence: string | null;
  sources: string[];
  last_checked: string | null;
  depends_on: string[];
}

/**
 * Front matter, parsed narrowly on purpose.
 *
 * Scalars, and lists written as `- item` lines. Not YAML: a full parser is a
 * dependency and a surface area, and everything here is a string, a date or a
 * list of strings. If a file needs more than that, the file is doing too much.
 */
export function parse(text: string, path: string): Doc {
  const m = /^---\r?\n([\s\S]*?)\r?\n---\r?\n([\s\S]*)$/.exec(text);
  if (!m) throw new Error(`${path}: no front matter`);

  const meta: Record<string, string | string[]> = {};
  let key: string | null = null;

  for (const raw of m[1].split(/\r?\n/)) {
    const line = raw.trimEnd();
    if (!line.trim()) continue;

    const listItem = /^\s+-\s+(.*)$/.exec(line);
    if (listItem && key) {
      const cur = meta[key];
      if (Array.isArray(cur)) cur.push(listItem[1].trim());
      else meta[key] = [listItem[1].trim()];
      continue;
    }

    const pair = /^([a-z_]+):\s*(.*)$/.exec(line);
    if (!pair) continue;
    key = pair[1];
    const value = pair[2].trim();
    // `sources:` with nothing after it opens a list; `sources: []` is an empty
    // one. Both have to mean "no scalar here" or the next `- ` line is lost.
    meta[key] = value === "" || value === "[]" ? [] : value;
  }

  const str = (k: string): string => {
    const v = meta[k];
    if (typeof v !== "string" || v === "") {
      throw new Error(`${path}: missing ${k}`);
    }
    return v;
  };
  const list = (k: string): string[] => {
    const v = meta[k];
    return Array.isArray(v) ? v : v ? [v] : [];
  };

  const kind = str("kind");
  if (kind !== "claim" && kind !== "guidance") {
    throw new Error(`${path}: kind must be claim or guidance, got ${kind}`);
  }
  const app = str("app");
  if (!["all", "lift", "run"].includes(app)) {
    throw new Error(`${path}: app must be all, lift or run, got ${app}`);
  }

  const lastChecked = typeof meta.last_checked === "string"
    ? meta.last_checked
    : null;
  // A claim with no date is the thing this table exists to make impossible.
  if (kind === "claim" && !lastChecked) {
    throw new Error(`${path}: a claim needs last_checked`);
  }
  if (kind === "claim" && list("sources").length === 0) {
    throw new Error(`${path}: a claim needs at least one source`);
  }

  return {
    id: str("id"),
    app,
    kind,
    title: str("title"),
    body: m[2].trim(),
    confidence: typeof meta.confidence === "string" ? meta.confidence : null,
    sources: list("sources"),
    last_checked: lastChecked,
    depends_on: list("depends_on"),
  };
}

async function read(): Promise<Doc[]> {
  const here = new URL(".", import.meta.url).pathname.replace(/^\/([A-Z]:)/, "$1");
  const out: Doc[] = [];
  const seen = new Set<string>();

  for (const dir of DIRS) {
    for await (const entry of Deno.readDir(`${here}${dir}`)) {
      if (!entry.isFile || !entry.name.endsWith(".md")) continue;
      const path = `${dir}/${entry.name}`;
      const doc = parse(await Deno.readTextFile(`${here}${path}`), path);
      const key = `${doc.id}:${doc.app}`;
      if (seen.has(key)) throw new Error(`${path}: duplicate id ${key}`);
      seen.add(key);
      out.push(doc);
    }
  }
  return out;
}

if (import.meta.main) {
  const url = Deno.env.get("SUPABASE_URL") ?? "http://127.0.0.1:54321";
  const key = Deno.env.get("SUPABASE_SERVICE_KEY") ??
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU";

  const docs = await read();
  console.log(`${docs.length} documents`);

  const headers = {
    apikey: key,
    Authorization: `Bearer ${key}`,
    "Content-Type": "application/json",
    "Accept-Profile": "coach",
    "Content-Profile": "coach",
  };

  // Mirror: everything, then insert. One statement each, so a failed run leaves
  // the table empty rather than half-updated -- which is loud, and a coach with
  // no knowledge is better than one with half of it and no way to tell.
  const wipe = await fetch(`${url}/rest/v1/knowledge?id=neq.__none__`, {
    method: "DELETE",
    headers,
  });
  if (!wipe.ok) {
    console.error(`delete failed ${wipe.status}: ${await wipe.text()}`);
    Deno.exit(1);
  }

  const put = await fetch(`${url}/rest/v1/knowledge`, {
    method: "POST",
    headers: { ...headers, Prefer: "return=minimal" },
    body: JSON.stringify(docs),
  });
  if (!put.ok) {
    console.error(`insert failed ${put.status}: ${await put.text()}`);
    Deno.exit(1);
  }

  for (const d of docs) {
    console.log(`  ${d.app.padEnd(4)} ${d.kind.padEnd(8)} ${d.id}`);
  }
  console.log("synced");
}
