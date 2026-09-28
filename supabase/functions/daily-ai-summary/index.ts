// Supabase Edge Function: daily-ai-summary
//
// ⚠️ THIS BELONGS TO THE LIVE LIFTIO APP. IT IS NOT RUN'S, AND IT IS NOT
// apps/mgk_lift's. DO NOT DELETE IT.
//
// Its caller is the **React Native Liftio** currently shipping on the App
// Store, which lives in a different repository. Nothing in THIS repository
// calls it — and that is the trap, because the obvious conclusion from a
// repo-wide grep is that it is dead code costing money, which it is not.
// Deleting it breaks the summary on every phone running the shipped build.
//
// It was mistaken for orphaned on 2026-09-10 during a gating audit, on exactly
// that evidence: all four `functions.invoke` calls across both Flutter apps
// name `coach` or `delete-account`. The grep was right and the conclusion was
// wrong. Hence this banner.
//
// ## Which function does what
//
//   coach              — both Flutter apps (apps/mgk_run, apps/mgk_lift).
//                        Entitlement-gated: `tierFor` refuses an unpaid caller
//                        with a 402 before a token is spent (ADR-0030).
//   daily-ai-summary   — THIS ONE. Legacy Liftio (React Native) only.
//   delete-account     — the whole suite, app-aware.
//   revenuecat         — the store webhook; the only writer of core.entitlements.
//
// The Flutter rewrite does not use this function at all. Its coach prose goes
// through `coach`, on the `lift_summarise` surface, and is gated there. When
// the App Store build of Liftio is finally superseded by apps/mgk_lift, THIS
// FUNCTION BECOMES DELETABLE — and that is the moment to do it, not before.
// See the decision *Liftio is replaced, not relaunched*.
//
// ## Known gap, deliberately recorded rather than fixed here
//
// There is **no entitlement check** on this function: it authenticates a JWT
// and spends a model call, where `coach` reads `core.entitlements` first. Any
// signed-in account can therefore reach Haiku through it, once per day, capped
// by the limits below rather than by what anybody bought. Whether that is a
// defect depends on whether the summary was a paid feature in the shipped
// Liftio and whether its gate was only client-side — a question this repository
// cannot answer, because the client is not in it. It is bounded by the daily
// per-user limit and the global circuit breaker, which is why it is written
// down here instead of being changed in a hurry.
//
// ## What it does
//
// Generates a short editorial training observation using Claude Haiku 4.5.
// Exactly 3 short sentences, observational tone, no motivational language.
// The client sends pre-aggregated stats; the LLM never sees personal data.
//
// Security:
//  - JWT verified at the gateway (verify_jwt: true) and inside the function
//  - Rate limited: 1 LLM call per user per day (ai_summary_requests table)
//  - On rate-limit hit, returns the previously-generated summary so a user
//    who wiped their local cache can still display it
//  - Global circuit breaker: DAILY_GLOBAL_LIMIT env var
//  - Payload validated and size-capped (2 KB)
//  - Anthropic API key stored as edge function secret, never in app binary

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const SYSTEM_PROMPT = `You are a training log analyst. You receive pre-aggregated workout statistics and produce a short editorial observation that reads like the app quietly noticing things about the user's training.

Rules:
- Write exactly 3 short sentences. No fewer, no more. No motivational closer sentence.
- Total output: under 240 characters. HARD limit, not a suggestion. Count your characters before returning.
- Do not use the person's name. The app will prepend the name.
- Do not mention AI, machine learning, algorithms, bots, or that you are an assistant.
- Do not use exclamation marks.
- Do not use motivational language. No "great job", no "keep going", no "you've got this", no encouragement, no congratulations, no warm closers, no "paying off", no "clearly".
- Tone is calm, factual, observational throughout. The app is noticing — not cheerleading.
- Do not give workout recommendations, advice, or suggestions.
- State what happened — patterns, changes, consistency, specific numbers.
- Sentence 1: A brief factual opener about current training status or context.
- Sentence 2: A frequency or consistency observation, ideally with a specific number compared to a baseline.
- Sentence 3: A specific data point — a trending exercise with weight change, a volume figure, or a streak. End here — do not append a closing comment.
- Use the weightUnit value to determine unit label (kg or lbs). All weight values in the data are in kg; if weightUnit is "lbs", convert (multiply by 2.2) and round to the nearest whole number.
- Vary sentence openers. Do not start every sentence with "Your" or "You've been".`;

const json = (body: Record<string, unknown>, status: number) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  // ── Auth ────────────────────────────────────────────────────────────────
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return json({ error: 'Unauthorized' }, 401);

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_ANON_KEY') ?? '',
  );

  const { data: { user }, error: userError } = await supabase.auth.getUser(
    authHeader.replace('Bearer ', '')
  );
  if (userError || !user) return json({ error: 'Unauthorized' }, 401);

  // ── Payload validation ──────────────────────────────────────────────────
  const rawBody = await req.text();
  if (rawBody.length > 2048) return json({ error: 'Payload too large' }, 413);

  let payload: Record<string, unknown>;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return json({ error: 'Invalid JSON' }, 400);
  }

  if (!payload.today || !payload.recentWindow || !payload.baselineWindow) {
    return json({ error: 'Missing required fields' }, 400);
  }

  // ── Rate limit + circuit breaker ────────────────────────────────────────
  // `ai_summary_requests` moved from `public` to `lift` in the 2026-08-06
  // restructure. Pinning the schema here keeps the three `.from()` calls below
  // unchanged; without it they resolve against `public`, which is now empty,
  // and every request fails the rate-limit read.
  const supabaseAdmin = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    { auth: { persistSession: false }, db: { schema: 'lift' } }
  );

  const todayKey = new Date().toISOString().slice(0, 10);

  // Per-user rate limit — if a row exists for today, return its stored
  // summary instead of rejecting. This lets users who wipe their local
  // cache (reinstall, sign out + in) still see their daily summary.
  const { data: existing } = await supabaseAdmin
    .from('ai_summary_requests')
    .select('summary')
    .eq('user_id', user.id)
    .eq('date_key', todayKey)
    .limit(1);

  if (existing && existing.length > 0) {
    const cached = existing[0]?.summary;
    if (cached) {
      // 200 with the cached summary — client treats this as success.
      return json({ summary: cached, cached: true }, 200);
    }
    // Row exists but no summary text (legacy row from before the schema
    // change). Fall through and re-generate — we'll UPDATE the row on success.
  }

  // Global circuit breaker
  const globalLimit = parseInt(Deno.env.get('DAILY_GLOBAL_LIMIT') ?? '2000', 10);
  const { count } = await supabaseAdmin
    .from('ai_summary_requests')
    .select('*', { count: 'exact', head: true })
    .eq('date_key', todayKey);

  if ((count ?? 0) >= globalLimit) {
    return json({ error: 'Service temporarily unavailable' }, 503);
  }

  // ── LLM call ────────────────────────────────────────────────────────────
  const anthropicKey = Deno.env.get('ANTHROPIC_API_KEY');
  if (!anthropicKey) return json({ error: 'LLM not configured' }, 503);

  let llmResponse: Response;
  try {
    llmResponse = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': anthropicKey,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: 200,
        temperature: 0.3,
        system: SYSTEM_PROMPT,
        messages: [
          { role: 'user', content: JSON.stringify(payload) },
        ],
      }),
    });
  } catch {
    return json({ error: 'LLM request failed' }, 502);
  }

  if (!llmResponse.ok) {
    return json({ error: 'LLM error' }, 502);
  }

  const llmData = await llmResponse.json();
  const summary = llmData?.content?.[0]?.text?.trim();
  if (!summary) return json({ error: 'Empty LLM response' }, 502);

  // ── Record rate limit row + store the summary text ──────────────────────
  // Upsert so a legacy row with NULL summary gets filled in on regenerate.
  await supabaseAdmin.from('ai_summary_requests').upsert(
    {
      user_id: user.id,
      date_key: todayKey,
      summary,
    },
    { onConflict: 'user_id,date_key' },
  );

  return json({ summary }, 200);
});
