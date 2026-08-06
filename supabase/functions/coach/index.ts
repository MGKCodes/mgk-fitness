// Runio coach proxy — the ONLY path from the app to the LLM provider.
//
//   app (user JWT)  ─▶  this function (auth + limits + provider key)  ─▶  OpenRouter  ─▶  a model
//
// The provider key never reaches the client: it is a public repo, so a shipped
// key is everyone's key (docs/decisions/0007-secrets-via-backend-proxy.md). Two
// server-side secrets, set with `supabase secrets set`:
//
//     OPENROUTER_API_KEY   the OpenRouter key
//     COACH_MODEL          the model id, e.g. a cheap structured-output model
//                          (see the README — pick a current id from
//                           openrouter.ai/models?supported_parameters=structured_outputs)
//
// The provider is a server-side choice (llm-and-secrets.md): swap models by
// changing COACH_MODEL, or swap providers by changing this one file. The app
// ships unchanged. Every surface returns JSON constrained to a schema; this
// function checks its SHAPE at the boundary, and Dart re-validates the VALUES
// (the plan validator, profile sanity) before anything is used — "the model
// proposes, the validator disposes".
//
// ADR-0007 also makes this the place abuse and cost are controlled. Every
// request passes a per-user rate limit and a rolling spend cap BEFORE any token
// is spent — see limits.ts (the thresholds, pure and under test) and
// usage_store.ts (the durable counters). This file only wires them up.
//
// The prompts and schemas live in surfaces.ts, not here: this module calls
// `Deno.serve` at load, so anything defined in it could only be tested through
// a socket. surfaces.ts is pure and unit-tested.
//
// OpenRouter speaks the OpenAI chat-completions shape. Dependency-free (raw
// fetch) so the wire shape is explicit and the Deno edge build stays reproducible.

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
  type Body,
  modelFor,
  PROVIDER_ROUTING,
  SURFACES,
  type Tier,
} from "./surfaces.ts";
import { UsageStore } from "./usage_store.ts";

const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";

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
  // given surface uses cannot be settled until the surface is known — see below.
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

  // Which tier this runner is on, and therefore which model answers them.
  //
  // Deliberately NOT read from the request body. A client that could name its
  // own tier could bill the Sharp model on a free account, so this must come
  // from something the runner cannot write: an entitlement row keyed to their
  // verified App Store transaction. That store does not exist yet, so this is
  // hard-coded to the cheapest tier — the safe direction, and the one that
  // makes adding the lookup a change of one line rather than a change of
  // policy. `tierFrom` is already here for when it is read from a query.
  const tier: Tier = "free";

  // `chat` and `summarise` reach the runner with no Dart validator in between,
  // so they route to the tier's chat model when one is set. With only
  // COACH_MODEL configured, every surface on every tier runs on it exactly as
  // before.
  // `body.model` is the development escape hatch and is honoured ONLY when it
  // names something in COACH_MODEL_ALLOWLIST. With that secret unset — the
  // production state — the client's request is ignored entirely.
  const model = modelFor(surfaceName, (k) => Deno.env.get(k), tier, body.model);
  if (!model) return json({ error: "coach_not_configured" }, 503);

  // A request that cannot produce a useful answer (a chat turn with no message,
  // a summary of no conversation) is refused here, before the limiter, because
  // it spends no tokens and blocking that traffic is the platform's job.
  if (surface.validRequest && !surface.validRequest(body)) {
    return json({ error: "bad_request" }, 400);
  }

  // 2. ADR-0007's cost half: rate limit and spend cap, BEFORE any token is
  //    spent. The counters live in Postgres because Edge Function instances are
  //    ephemeral; the service-role key reaches them (the table is deliberately
  //    not user-writable, or a user could reset their own cap).
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!serviceKey) {
    console.error("coach limiter: SUPABASE_SERVICE_ROLE_KEY missing");
    return json(
      { error: "coach_not_configured", reason: "limiter_unavailable" },
      503,
    );
  }

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

  // 3. Past the gate: spend tokens, then record what they cost. `record` runs
  //    for every outcome, so a failing upstream cannot be retried for free.
  const accountFor = (usage: RecordedUsage, outcome: string) =>
    store.record(userId, surfaceName, usage, outcome);

  let res: Response;
  try {
    res = await fetch(OPENROUTER_URL, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "Authorization": `Bearer ${apiKey}`,
        "HTTP-Referer": "https://runio.app",
        "X-Title": "Runio",
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
        // Only route to endpoints that actually enforce the JSON schema.
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
    // content in logs.
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
  // summarise -> {summary}). `render` exists for the surfaces whose prompt
  // shape and app shape differ.
  const shaped = surface.render ? surface.render(parsed) : parsed;
  return settle(json(shaped), "ok");
});
