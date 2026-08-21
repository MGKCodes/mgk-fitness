// The coach proxy — the ONLY path from either app to the LLM provider.
//
//   app (user JWT)  ─▶  this function (auth + entitlement + limits + key)  ─▶  OpenRouter  ─▶  a model
//
// **One function, both apps.** The `coach` schema comment says the coach is
// app-agnostic and docs/architecture.md is written on it; this is where that is
// either true or a claim. Which app a request belongs to is read from the
// SURFACE, never from the body, so a caller cannot ask for the other app's
// entitlement to pay for its turn.
//
// The provider key never reaches the client: the repo is public, so a shipped
// key is everyone's key (ADR-0007). Two server-side secrets, set with
// `supabase secrets set`:
//
//     OPENROUTER_API_KEY   the OpenRouter key
//     COACH_MODEL          the model id, e.g. a cheap structured-output model
//                          (see the README — pick a current id from
//                           openrouter.ai/models?supported_parameters=structured_outputs)
//
// The provider is a server-side choice: swap models by changing COACH_MODEL, or
// swap providers by changing this one file. Both apps ship unchanged. Every
// surface returns JSON constrained to a schema; this function checks its SHAPE
// at the boundary, and Dart re-validates the VALUES before anything is used —
// "the model proposes, the validator disposes".
//
// ADR-0007 also makes this the place abuse and cost are controlled. Every
// request passes a per-user rate limit and a rolling spend cap BEFORE any token
// is spent — see limits.ts (the thresholds, pure and under test) and
// usage_store.ts (the durable counters). This file only wires them up.
//
// The prompts and schemas live in surfaces.ts, not here: this module calls
// `Deno.serve` at load, so anything defined in it could only be tested through
// a socket. surfaces.ts, limits.ts and the pure halves of the three stores are
// unit-tested.
//
// OpenRouter speaks the OpenAI chat-completions shape. Dependency-free (raw
// fetch) so the wire shape is explicit and the Deno edge build stays
// reproducible.

import {
  configFromEnv,
  decide,
  type Decision,
  isSurface,
  lookbackSeconds,
  type RecordedUsage,
  usageFromResponse,
  ZERO_USAGE,
} from "./limits.ts";
import {
  type App,
  type Body,
  modelFor,
  PROVIDER_ROUTING,
  SURFACES,
  type SurfaceSpec,
  type Tier,
} from "./surfaces.ts";
import { UsageStore } from "./usage_store.ts";
import { EntitlementStore, tierFor } from "./entitlements.ts";
import { LiftLog } from "./lift_log.ts";
import {
  CoachMemory,
  EMPTY_MEMORY,
  type Memory,
  shouldRegenerate,
  type StoredTurn,
} from "./coach_memory.ts";
import { Knowledge } from "./knowledge.ts";

const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";

/// How long the upstream call may take before it is abandoned.
///
/// **Deliberately shorter than the apps' own 90s deadline**, so a hung provider
/// comes back as this function's 502 — an error the client can name and count
/// against a rate budget — rather than as a client-side timeout with nothing
/// logged and no usage recorded. Without it, `fetch` here waits as long as the
/// provider holds the socket open, and both apps have screens that block the
/// back gesture until the call returns.
const UPSTREAM_TIMEOUT_MS = 75_000;

/**
 * OpenRouter's attribution headers. Cosmetic — they decide which name the
 * account's usage appears under in OpenRouter's own rankings and nothing else,
 * which is why the unsettled suite name is not a blocker here.
 */
const ATTRIBUTION: Record<App, { referer: string; title: string }> = {
  run: { referer: "https://runio.app", title: "Runio" },
  lift: { referer: "https://mgkcodes.com", title: "MGK Lift" },
};

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  // So a browser client (the Flutter web preview harness) can read Retry-After
  // off a 429 rather than only the copy in the body.
  "Access-Control-Expose-Headers": "Retry-After",
};

function json(
  body: unknown,
  status = 200,
  extraHeaders: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "content-type": "application/json", ...extraHeaders },
  });
}

// ---- limits -----------------------------------------------------------------

// A refusal the app can render: 429 with the scope that bound and how long
// until it clears. The spend cap is a 429 too, not a 402 — it is a rolling
// window that will clear on its own, so "come back later" is the honest
// semantics, and `error` distinguishes it from a rate limit.
function limited(decision: Decision & { allowed: false }): Response {
  return json(
    {
      error: decision.error,
      scope: decision.scope,
      retry_after_seconds: decision.retryAfterSeconds,
    },
    429,
    { "Retry-After": String(decision.retryAfterSeconds) },
  );
}

// ---- the provider call ------------------------------------------------------

/**
 * One model call, its usage, and what to call the attempt in the ledger.
 *
 * A discriminated result rather than a thrown error or a `Response`, because
 * this is called from two places that want opposite things from a failure: the
 * request path turns it into a status code, and the memory rewrite that follows
 * a reply swallows it. Both still have to ACCOUNT for it — a failed call spends
 * tokens or spends rate budget, and neither may be free.
 */
type ProviderOutcome =
  | { ok: true; parsed: Record<string, unknown>; usage: RecordedUsage }
  | {
    ok: false;
    status: number;
    error: string;
    usage: RecordedUsage;
    outcome: string;
  };

async function callProvider(opts: {
  apiKey: string;
  model: string;
  surface: SurfaceSpec;
  body: Body;
  attribution: { referer: string; title: string };
  fallbackCreditsPerMillionTokens: number;
}): Promise<ProviderOutcome> {
  const { surface, fallbackCreditsPerMillionTokens: rate } = opts;
  const estimate = (usage: unknown) =>
    usageFromResponse(usage, {
      creditsPerMillionTokens: rate,
      assumedTokensWhenUnknown: surface.maxTokens,
    });

  let res: Response;
  try {
    res = await fetch(OPENROUTER_URL, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "Authorization": `Bearer ${opts.apiKey}`,
        "HTTP-Referer": opts.attribution.referer,
        "X-Title": opts.attribution.title,
      },
      body: JSON.stringify({
        model: opts.model,
        max_tokens: surface.maxTokens,
        messages: surface.messages(opts.body),
        response_format: {
          type: "json_schema",
          json_schema: {
            name: surface.name,
            strict: true,
            schema: surface.schema,
          },
        },
        // Schema enforcement, the no-training rule, and fallback across
        // providers. Defined in surfaces.ts so a test can assert it — see
        // PROVIDER_ROUTING.
        provider: PROVIDER_ROUTING,
      }),
      // Aborting throws, which lands in the catch below and is already handled
      // as an unreachable upstream. A timeout and a refused connection are the
      // same thing from here: no answer, and the budget still spent.
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
    });
  } catch (e) {
    // A throw here spends nothing, but it must still cost rate budget —
    // otherwise a provider outage becomes a free retry loop.
    console.error("openrouter unreachable", String(e));
    return {
      ok: false,
      status: 502,
      error: "coach_upstream",
      usage: ZERO_USAGE,
      outcome: "unreachable",
    };
  }

  if (!res.ok) {
    // Capped: an upstream error message is a diagnostic, but it is also the one
    // place a provider might echo part of what we sent, and we do not put user
    // content in logs. It can also carry OUR billing details, which are not the
    // caller's business — which is why it is never forwarded to the client.
    console.error(
      "openrouter error",
      res.status,
      (await res.text()).slice(0, 300),
    );
    return {
      ok: false,
      status: 502,
      error: "coach_upstream",
      usage: ZERO_USAGE,
      outcome: "upstream_error",
    };
  }

  let payload: Record<string, unknown> & {
    usage?: unknown;
    error?: unknown;
    choices?: { finish_reason?: string; message?: { content?: unknown } }[];
  };
  try {
    payload = await res.json();
  } catch {
    // A 200 whose body is not JSON: tokens were almost certainly spent, so the
    // attempt is charged at the surface's budget rather than going free.
    console.error("openrouter non-json body", res.status);
    return {
      ok: false,
      status: 502,
      error: "coach_malformed",
      usage: estimate(null),
      outcome: "non_json",
    };
  }

  // OpenRouter reports `usage` (native token counts and the credits charged) on
  // every completion. That is what the cap is denominated in, so it stays
  // correct across model swaps without this function knowing a price list.
  const usage = estimate(payload?.usage);

  if (payload.error) {
    console.error("openrouter body error", JSON.stringify(payload.error));
    return {
      ok: false,
      status: 502,
      error: "coach_upstream",
      usage,
      outcome: "upstream_error",
    };
  }
  const choice = payload.choices?.[0];
  if (choice?.finish_reason === "content_filter") {
    return {
      ok: false,
      status: 422,
      error: "refused",
      usage,
      outcome: "refused",
    };
  }

  const text = choice?.message?.content;
  if (typeof text !== "string") {
    return {
      ok: false,
      status: 502,
      error: "coach_empty",
      usage,
      outcome: "empty",
    };
  }

  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(text);
  } catch {
    return {
      ok: false,
      status: 502,
      error: "coach_malformed",
      usage,
      outcome: "malformed",
    };
  }

  // Boundary validation: shape only. Dart re-validates the values.
  if (typeof parsed !== "object" || parsed === null || !surface.valid(parsed)) {
    return {
      ok: false,
      status: 502,
      error: "coach_malformed",
      usage,
      outcome: "malformed",
    };
  }

  return { ok: true, parsed, usage };
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  // 1. The caller must be a signed-in user. Supabase's auth endpoint validates
  //    the JWT for us; no user, no coach. We need the id as well as the yes/no,
  //    because every limit below is per user.
  const authHeader = req.headers.get("Authorization");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!authHeader || !supabaseUrl || !anonKey) {
    return json({ error: "unauthorized" }, 401);
  }
  const userRes = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: { Authorization: authHeader, apikey: anonKey },
  });
  if (!userRes.ok) return json({ error: "unauthorized" }, 401);
  const userId = (await userRes.json().catch(() => null))?.id;
  if (typeof userId !== "string" || !userId) {
    return json({ error: "unauthorized" }, 401);
  }

  // The base model is checked here, before the body is read, because a function
  // with no model configured is misconfigured for every request. WHICH model a
  // given surface uses cannot be settled until the surface and the tier are
  // known — see below.
  const apiKey = Deno.env.get("OPENROUTER_API_KEY");
  if (!apiKey || !Deno.env.get("COACH_MODEL")?.trim()) {
    return json({ error: "coach_not_configured" }, 503);
  }

  let body: Body;
  try {
    body = await req.json();
  } catch {
    return json({ error: "bad_request" }, 400);
  }

  const surfaceName = body.surface;
  if (!isSurface(surfaceName)) {
    return json({ error: "unsupported_surface" }, 400);
  }
  const surface = SURFACES[surfaceName];

  // A request that cannot produce a useful answer (a chat turn with no message,
  // a summary of no conversation) is refused here, before the limiter, because
  // it spends no tokens and blocking that traffic is the platform's job.
  if (surface.validRequest && !surface.validRequest(body)) {
    return json({ error: "bad_request" }, 400);
  }

  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!serviceKey) {
    console.error("coach: SUPABASE_SERVICE_ROLE_KEY missing");
    return json(
      { error: "coach_not_configured", reason: "limiter_unavailable" },
      503,
    );
  }

  // 2. What this caller has paid for, and therefore which model answers them.
  //
  //    Read from `core.entitlements` under service role, keyed on the surface's
  //    OWN app — never on anything the client sent. A client that could name
  //    its tier could bill the Sharp model on a free account, and one that
  //    could name its app could spend a Run subscription on a Lift turn.
  //
  //    `null` is "no coach at all", which Lift returns for an unentitled
  //    lifter: coaching is the paid half of that app. Run never returns it.
  const entitlements = new EntitlementStore(supabaseUrl, serviceKey);
  const tier = tierFor(
    surface.app,
    await entitlements.read(userId, surface.app),
  );
  if (tier === null) return json({ error: "not_entitled" }, 402);

  // The human-facing surfaces route to the tier's chat model when one is set.
  // With only COACH_MODEL configured, every surface on every tier runs on it.
  // `body.model` is the development escape hatch and is honoured ONLY when it
  // names something in COACH_MODEL_ALLOWLIST. With that secret unset — the
  // production state — the client's request is ignored entirely.
  const model = modelFor(surfaceName, (k) => Deno.env.get(k), tier, body.model);
  if (!model) return json({ error: "coach_not_configured" }, 503);

  // 3. ADR-0007's cost half: rate limit and spend cap, BEFORE any token is
  //    spent. The counters live in Postgres because Edge Function instances are
  //    ephemeral; the service-role key reaches them (the table is deliberately
  //    not user-writable, or a user could reset their own cap).
  const limits = configFromEnv((k) => Deno.env.get(k));
  const store = new UsageStore(supabaseUrl, serviceKey);
  const now = Date.now();
  const snapshot = await store.window(
    userId,
    now - lookbackSeconds(limits) * 1000,
  );

  // Fail CLOSED. Spending money we cannot account for is the exact failure
  // ADR-0007 exists to prevent, and the client degrades gracefully: plan
  // surfaces fall back to the deterministic builder, so a refused call costs a
  // provisional week, not a broken app. The two codes are distinguished so a
  // missing migration cannot be mistaken for a database wobble.
  if (snapshot.status === "not_installed") {
    return json(
      { error: "coach_not_configured", reason: "limiter_unavailable" },
      503,
    );
  }
  if (snapshot.status === "unavailable") {
    return json({ error: "coach_unavailable" }, 503);
  }

  const decision = decide(surfaceName, snapshot.rows, now, limits);
  if (!decision.allowed) {
    // Identifiers and counts only — never the request body.
    console.log(
      "coach limited",
      JSON.stringify({
        user: userId,
        surface: surfaceName,
        error: decision.error,
        scope: decision.scope,
      }),
    );
    return limited(decision);
  }

  // 4. Past the gate, so it is worth loading what the prompt needs.
  //
  //    Both of Lift's inputs are read HERE rather than sent by the client, and
  //    both are OVERWRITTEN rather than merged: whatever arrived under `brief`,
  //    `memory` or `history` is discarded.
  //
  //      * the training log — read as the caller, so RLS decides what the coach
  //        can see, and a log the client narrates is a log it can invent;
  //      * the memory and the transcript — the coach's own record of what was
  //        said, which is the thing item 2 exists to make durable. A client that
  //        supplied its own history could put words in the coach's mouth and
  //        then ask it to act on them.
  //
  //    Run's brief is genuinely the app's to write (it carries numbers computed
  //    client-side) and is left alone.
  const memoryStore = surface.app === "lift"
    ? new CoachMemory(supabaseUrl, anonKey, authHeader)
    : null;
  let memory: Memory = EMPTY_MEMORY;

  if (surfaceName === "lift_chat" && memoryStore) {
    // In parallel: the log and the memory are independent reads, and this is on
    // the path of every turn.
    const [brief, loaded] = await Promise.all([
      new LiftLog(supabaseUrl, anonKey).recent(authHeader),
      memoryStore.read("lift", userId),
    ]);
    memory = loaded;
    body.brief = brief;
    body.memory = memory.summary;
    body.history = memory.turns;
  }

  if (surfaceName === "lift_plan") {
    // Same overwrite rule as lift_chat, for the same reason: guidance is prompt
    // content, and prompt content a client supplies is prompt content a client
    // controls. The training log comes from the database as the caller, so a
    // plan is built from what somebody has actually lifted.
    //
    // The CATALOGUE is the one exception and stays client-supplied, because it
    // lives in the app and this function has no copy. Forging it gains nothing:
    // PlanShape checks every movement against the real catalogue app-side, so a
    // plan built from invented names fails before it is shown. Worth moving to
    // the same table as the knowledge eventually.
    const [brief, guidance] = await Promise.all([
      new LiftLog(supabaseUrl, anonKey).recent(authHeader),
      new Knowledge(supabaseUrl, anonKey, authHeader).forApp("lift"),
    ]);
    body.brief = brief;
    body.guidance = guidance;
    body.memory = (await memoryStore!.read("lift", userId)).summary;
  }

  // 5. Spend tokens, then record what they cost. `record` runs for every
  //    outcome, so a failing upstream cannot be retried for free.
  const accountFor = (usage: RecordedUsage, outcome: string) =>
    store.record(userId, surfaceName, usage, outcome);

  const attribution = ATTRIBUTION[surface.app];

  const result = await callProvider({
    apiKey,
    model,
    surface,
    body,
    attribution,
    fallbackCreditsPerMillionTokens: limits.fallbackCreditsPerMillionTokens,
  });

  // Records the call, then returns the response. Every exit goes through here
  // so that tokens spent are always tokens counted — including on a refusal or
  // a malformed reply, which cost exactly as much as a good one.
  const settle = async (
    response: Response,
    usage: RecordedUsage,
    outcome: string,
  ): Promise<Response> => {
    await accountFor(usage, outcome);
    console.log(
      "coach call",
      JSON.stringify({
        user: userId,
        surface: surfaceName,
        outcome,
        prompt_tokens: usage.promptTokens,
        completion_tokens: usage.completionTokens,
        cost_credits: usage.costCredits,
        cost_estimated: usage.costEstimated,
      }),
    );
    return response;
  };

  if (!result.ok) {
    return settle(
      json({ error: result.error }, result.status),
      result.usage,
      result.outcome,
    );
  }

  // The client maps the surface's own shape (intake -> {reply, extracted};
  // skeleton -> {weeks}; week -> {sessions}; chat -> {reply, intent};
  // summarise -> {summary}; lift_chat -> {reply}). `render` exists for the
  // surfaces whose prompt shape and app shape differ.
  const shaped = surface.render ? surface.render(result.parsed) : result.parsed;

  // 6. Remember it.
  //
  //    After the reply exists, and never allowed to fail the request: the
  //    lifter has already been answered, and throwing that away because a
  //    transcript row would not write is the worse outcome. The same trade the
  //    usage ledger makes.
  if (surfaceName === "lift_chat" && memoryStore) {
    const exchange: StoredTurn[] = [
      { role: "user", text: String(body.message ?? "").trim() },
      { role: "assistant", text: String(result.parsed.reply ?? "").trim() },
    ];
    await memoryStore.appendTurns("lift", userId, memory.total, exchange);

    const total = memory.total + exchange.length;
    if (shouldRegenerate(total, memory.turnsCovered)) {
      // Synchronously, and only about one turn in REGENERATE_AFTER. That turn
      // pays for a second short call, which is the honest cost of a memory that
      // is actually up to date. Moving it into the background needs the
      // platform's `waitUntil`, and is worth doing if that latency is ever felt
      // — it is not worth an untested code path today.
      //
      // The transcript handed over is the turns we already loaded plus this
      // exchange, which covers the drift precisely because MEMORY_TURNS is not
      // smaller than REGENERATE_AFTER. Break that and the memory would be
      // rewritten from less than it fell behind by.
      await regenerate({
        apiKey,
        userId,
        tier,
        previous: memory.summary,
        transcript: [...memory.turns, ...exchange],
        total,
        memoryStore,
        accountFor: (usage, outcome) =>
          store.record(userId, "lift_summarise", usage, outcome),
        fallbackCreditsPerMillionTokens: limits.fallbackCreditsPerMillionTokens,
      });
    }
  }

  return settle(json(shaped), result.usage, "ok");
});

/**
 * Rewrites the coach's memory from the conversation that has happened since.
 *
 * Never throws and never reports: it runs after a reply the lifter already has,
 * so every failure here degrades to "the memory is rewritten on a later turn"
 * rather than to an error they can see. It still ACCOUNTS for what it spends —
 * a call outside the ledger is a hole in the spend cap, and this one is not
 * triggered by anything the lifter did on purpose.
 *
 * It deliberately does NOT consult the rate limiter first. The gate has already
 * been passed for this turn, and the surface's own ceiling exists to catch the
 * pathological case rather than to bind here: at one rewrite per
 * REGENERATE_AFTER turns it cannot be reached by talking.
 */
async function regenerate(opts: {
  apiKey: string;
  userId: string;
  tier: Tier;
  previous: string;
  transcript: readonly StoredTurn[];
  total: number;
  memoryStore: CoachMemory;
  accountFor: (usage: RecordedUsage, outcome: string) => Promise<unknown>;
  fallbackCreditsPerMillionTokens: number;
}): Promise<void> {
  const surface = SURFACES.lift_summarise;
  const model = modelFor(
    "lift_summarise",
    (k) => Deno.env.get(k),
    opts.tier,
  );
  if (!model) return;

  const result = await callProvider({
    apiKey: opts.apiKey,
    model,
    surface,
    body: {
      previous: opts.previous,
      transcript: opts.transcript.map((t) => ({ role: t.role, text: t.text })),
    },
    attribution: ATTRIBUTION.lift,
    fallbackCreditsPerMillionTokens: opts.fallbackCreditsPerMillionTokens,
  });

  await opts.accountFor(
    result.usage,
    result.ok ? "ok" : result.outcome,
  );
  if (!result.ok) return;

  const summary = String(result.parsed.summary ?? "").trim();

  // `turns_covered` moves even when the memory comes back empty or unchanged.
  // It records how far the coach has READ, not how much it chose to keep — tie
  // it to the text and a lifter whose conversations are all small talk would
  // trigger a rewrite on every single turn thereafter.
  await opts.memoryStore.writeSummary(
    "lift",
    opts.userId,
    summary,
    opts.total,
    model,
  );
}
