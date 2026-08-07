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
} from "./surfaces.ts";
import { UsageStore } from "./usage_store.ts";
import { EntitlementStore, tierFor } from "./entitlements.ts";
import { LiftLog } from "./lift_log.ts";

const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";

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
  //    Lift's brief is the training log, read AS THE CALLER so RLS decides what
  //    the coach can see, and OVERWRITTEN rather than merged: whatever a client
  //    sent under `brief` is discarded, because a log the client narrates is a
  //    log the client can invent. Run's brief is genuinely the app's to write
  //    (it carries numbers computed client-side) and is left alone.
  if (surfaceName === "lift_chat") {
    body.brief = await new LiftLog(supabaseUrl, anonKey).recent(authHeader);
  }

  // 5. Spend tokens, then record what they cost. `record` runs for every
  //    outcome, so a failing upstream cannot be retried for free.
  const accountFor = (usage: RecordedUsage, outcome: string) =>
    store.record(userId, surfaceName, usage, outcome);

  const attribution = ATTRIBUTION[surface.app];

  let res: Response;
  try {
    res = await fetch(OPENROUTER_URL, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "Authorization": `Bearer ${apiKey}`,
        "HTTP-Referer": attribution.referer,
        "X-Title": attribution.title,
      },
      body: JSON.stringify({
        model,
        max_tokens: surface.maxTokens,
        messages: surface.messages(body),
        response_format: {
          type: "json_schema",
          json_schema: {
            name: surface.name,
            strict: true,
            schema: surface.schema,
          },
        },
        // Schema enforcement and the no-training rule. Defined in surfaces.ts
        // so a test can assert it — see PROVIDER_ROUTING.
        provider: PROVIDER_ROUTING,
      }),
    });
  } catch (e) {
    // A throw here spends nothing, but it must still cost rate budget —
    // otherwise a provider outage becomes a free retry loop.
    console.error("openrouter unreachable", String(e));
    await accountFor(ZERO_USAGE, "unreachable");
    return json({ error: "coach_upstream" }, 502);
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
    // No usage to read, but the attempt still consumes rate budget so a broken
    // upstream cannot be hammered for free.
    await accountFor(ZERO_USAGE, "upstream_error");
    return json({ error: "coach_upstream" }, 502);
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
    await accountFor(
      usageFromResponse(null, {
        creditsPerMillionTokens: limits.fallbackCreditsPerMillionTokens,
        assumedTokensWhenUnknown: surface.maxTokens,
      }),
      "non_json",
    );
    return json({ error: "coach_malformed" }, 502);
  }

  // OpenRouter reports `usage` (native token counts and the credits charged) on
  // every completion. That is what the cap is denominated in, so it stays
  // correct across model swaps without this function knowing a price list.
  const usage = usageFromResponse(payload?.usage, {
    creditsPerMillionTokens: limits.fallbackCreditsPerMillionTokens,
    assumedTokensWhenUnknown: surface.maxTokens,
  });

  // Records the call, then returns the response. Every exit below goes through
  // here so that tokens spent are always tokens counted — including on a
  // refusal or a malformed reply, which cost exactly as much as a good one.
  const settle = async (
    response: Response,
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

  if (payload.error) {
    console.error("openrouter body error", JSON.stringify(payload.error));
    return settle(json({ error: "coach_upstream" }, 502), "upstream_error");
  }
  const choice = payload.choices?.[0];
  if (choice?.finish_reason === "content_filter") {
    return settle(json({ error: "refused" }, 422), "refused");
  }

  const text = choice?.message?.content;
  if (typeof text !== "string") {
    return settle(json({ error: "coach_empty" }, 502), "empty");
  }

  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(text);
  } catch {
    return settle(json({ error: "coach_malformed" }, 502), "malformed");
  }

  // Boundary validation: shape only. Dart re-validates the values.
  if (typeof parsed !== "object" || parsed === null || !surface.valid(parsed)) {
    return settle(json({ error: "coach_malformed" }, 502), "malformed");
  }

  // The client maps the surface's own shape (intake -> {reply, extracted};
  // skeleton -> {weeks}; week -> {sessions}; chat -> {reply, intent};
  // summarise -> {summary}; lift_chat -> {reply}). `render` exists for the
  // surfaces whose prompt shape and app shape differ.
  const shaped = surface.render ? surface.render(parsed) : parsed;
  return settle(json(shaped), "ok");
});
