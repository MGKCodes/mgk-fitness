// Unit tests for the limiter's storage seam.
//
// No database: `fetch` is injected, so the thing under test is the mapping from
// a PostgREST reply onto a store status — which is what decides whether a
// missing migration reads as "not set up" or as "the database is down". Run
// from this directory:
//
//     deno test

import { assertEquals } from "jsr:@std/assert@1";

import {
  classifyFailure,
  type FetchLike,
  parseWindowRows,
  UsageStore,
} from "./usage_store.ts";
import { ZERO_USAGE } from "./limits.ts";

const URL_BASE = "https://example.supabase.co";
const KEY = "service-role-key";

function respond(status: number, body: unknown): FetchLike {
  return () =>
    Promise.resolve(
      new Response(JSON.stringify(body), {
        status,
        headers: { "content-type": "application/json" },
      }),
    );
}

// ---- failure classification ------------------------------------------------

Deno.test("a missing table or function reads as not_installed", () => {
  // The case that matters: the SQL has not been applied yet.
  assertEquals(classifyFailure(404, { code: "PGRST202" }), "not_installed");
  assertEquals(classifyFailure(404, { code: "PGRST205" }), "not_installed");
  assertEquals(classifyFailure(400, { code: "42P01" }), "not_installed");
  assertEquals(classifyFailure(400, { code: "42883" }), "not_installed");
  assertEquals(classifyFailure(400, { code: "3F000" }), "not_installed");
});

Deno.test("a permissions problem reads as not_installed, not an outage", () => {
  // A wrong service key would otherwise masquerade as a database outage for
  // ever, and it is a setup mistake with the same fix: check the deploy.
  assertEquals(classifyFailure(401, null), "not_installed");
  assertEquals(classifyFailure(403, null), "not_installed");
  assertEquals(classifyFailure(400, { code: "42501" }), "not_installed");
});

Deno.test("a server-side wobble reads as unavailable", () => {
  assertEquals(classifyFailure(500, null), "unavailable");
  assertEquals(classifyFailure(502, null), "unavailable");
  assertEquals(classifyFailure(503, { code: "57014" }), "unavailable");
  assertEquals(classifyFailure(429, null), "unavailable");
  assertEquals(classifyFailure(400, { code: "22P02" }), "unavailable");
  assertEquals(classifyFailure(400, "not even json"), "unavailable");
});

// ---- row parsing -----------------------------------------------------------

Deno.test("window rows are parsed into timestamps, surfaces and costs", () => {
  const rows = parseWindowRows([
    { at: "2026-07-26T11:00:00Z", surface: "week", cost_credits: 0.004 },
    { at: "2026-07-26T11:30:00Z", surface: "intake", cost_credits: "0.001" },
  ]);
  assertEquals(rows.length, 2);
  assertEquals(rows[0].atMs, Date.parse("2026-07-26T11:00:00Z"));
  assertEquals(rows[0].surface, "week");
  assertEquals(rows[0].costCredits, 0.004);
  // PostgREST renders numeric as a string; it must still count as spend.
  assertEquals(rows[1].costCredits, 0.001);
});

Deno.test("malformed rows are dropped rather than trusted into the maths", () => {
  const rows = parseWindowRows([
    null,
    "nope",
    {},
    { at: "not a date", surface: "week", cost_credits: 1 },
    { at: "2026-07-26T11:00:00Z", surface: "week", cost_credits: "oops" },
  ]);
  assertEquals(rows.length, 1);
  assertEquals(rows[0].costCredits, 0); // unreadable cost counts as zero
});

Deno.test("a non-array payload yields no rows", () => {
  for (const junk of [null, undefined, {}, "[]", 5]) {
    assertEquals(parseWindowRows(junk), []);
  }
});

Deno.test("the timestamp shapes Postgres actually emits all parse", () => {
  // Load-bearing: the window RPC returns jsonb, and `to_jsonb(timestamptz)`
  // renders an offset rather than a Z. If this stopped parsing, every row would
  // be silently dropped and the limiter would see every user as brand new.
  const shapes = [
    "2026-07-26T11:00:00+00:00", // jsonb_build_object on a timestamptz
    "2026-07-26T11:00:00.123456+00:00", // with microseconds
    "2026-07-26T11:00:00Z", // if the column is ever handed back as a Z
  ];
  for (const at of shapes) {
    const rows = parseWindowRows([{ at, surface: "week", cost_credits: 4e-5 }]);
    assertEquals(rows.length, 1, `${at} should parse`);
    assertEquals(
      rows[0].atMs,
      Date.parse("2026-07-26T11:00:00Z") + (
        at.includes(".123456") ? 123 : 0
      ),
    );
    assertEquals(rows[0].costCredits, 4e-5);
  }
});

// ---- the store -------------------------------------------------------------

Deno.test("a good read returns ok and its rows", async () => {
  const store = new UsageStore(
    URL_BASE,
    KEY,
    respond(200, [
      { at: "2026-07-26T11:00:00Z", surface: "week", cost_credits: 0.01 },
    ]),
  );
  const result = await store.window(
    "user-1",
    Date.parse("2026-07-25T12:00:00Z"),
  );
  assertEquals(result.status, "ok");
  assertEquals(result.rows.length, 1);
});

Deno.test("the read calls the window RPC with the service key", async () => {
  let seenUrl = "";
  let seenInit: RequestInit | undefined;
  const store = new UsageStore(URL_BASE, KEY, (url, init) => {
    seenUrl = url;
    seenInit = init;
    return Promise.resolve(new Response("[]", { status: 200 }));
  });

  await store.window("user-1", Date.parse("2026-07-25T12:00:00Z"));

  assertEquals(seenUrl, `${URL_BASE}/rest/v1/rpc/usage_window`);
  const headers = seenInit?.headers as Record<string, string>;
  assertEquals(headers.apikey, KEY);
  assertEquals(headers.Authorization, `Bearer ${KEY}`);
  // The schema is load-bearing: without it the limiter 404s and fails closed.
  assertEquals(headers["Content-Profile"], "coach");
  assertEquals(JSON.parse(String(seenInit?.body)), {
    p_user: "user-1",
    p_since: "2026-07-25T12:00:00.000Z",
  });
});

Deno.test("a missing RPC surfaces as not_installed with no rows", async () => {
  const store = new UsageStore(
    URL_BASE,
    KEY,
    respond(404, { code: "PGRST202", message: "Could not find the function" }),
  );
  const result = await store.window("user-1", 0);
  assertEquals(result.status, "not_installed");
  assertEquals(result.rows, []);
});

Deno.test("a thrown fetch surfaces as unavailable, not as an empty snapshot", async () => {
  // Load-bearing: an empty snapshot with an ok status would look like a brand
  // new user and let the request through unmetered.
  const store = new UsageStore(URL_BASE, KEY, () => {
    throw new Error("timed out");
  });
  const result = await store.window("user-1", 0);
  assertEquals(result.status, "unavailable");
  assertEquals(result.rows, []);
});

Deno.test("an unreadable body does not turn a failure into a success", async () => {
  const store = new UsageStore(
    URL_BASE,
    KEY,
    () =>
      Promise.resolve(new Response("<html>gateway</html>", { status: 502 })),
  );
  assertEquals((await store.window("user-1", 0)).status, "unavailable");
});

Deno.test("record posts token counts and cost, and never a payload", async () => {
  let body: Record<string, unknown> = {};
  let url = "";
  const store = new UsageStore(URL_BASE, KEY, (u, init) => {
    url = u;
    body = JSON.parse(String(init?.body));
    return Promise.resolve(new Response("null", { status: 200 }));
  });

  const status = await store.record("user-1", "week", {
    promptTokens: 1500,
    completionTokens: 700,
    totalTokens: 2200,
    costCredits: 0.0009,
    costEstimated: false,
  }, "ok");

  assertEquals(status, "ok");
  assertEquals(url, `${URL_BASE}/rest/v1/rpc/record_usage`);
  assertEquals(body, {
    p_user: "user-1",
    p_surface: "week",
    p_prompt_tokens: 1500,
    p_completion_tokens: 700,
    p_total_tokens: 2200,
    p_cost_credits: 0.0009,
    p_cost_estimated: false,
    p_outcome: "ok",
  });
  // The whole point: there is no field here that could carry a prompt, a
  // session, or a health value.
  assertEquals(Object.keys(body).length, 8);
});

Deno.test("a failed write is reported, never thrown at the caller", async () => {
  // The model has already answered. Losing an accounting row is better than
  // throwing away a good response.
  const store = new UsageStore(URL_BASE, KEY, () => {
    throw new Error("connection reset");
  });
  assertEquals(
    await store.record("user-1", "intake", ZERO_USAGE, "ok"),
    "unavailable",
  );
});
