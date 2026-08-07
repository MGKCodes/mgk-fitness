// The coach turn: the only thing in the suite that talks to a model.
//
// **This exists because the app is open source and the model key is not.** The
// key lives in this function's environment and never leaves the server. The
// client holds a user JWT and nothing else, so publishing the Flutter source
// gives nobody a way to spend somebody else's tokens.
//
// It also means the two rules that actually cost money — is this account
// entitled, and has it used its allowance — are enforced somewhere the lifter
// cannot edit. A client-side check is a suggestion.
//
// Deploy: supabase functions deploy coach
// Secrets: supabase secrets set ANTHROPIC_API_KEY=...

import { createClient } from 'jsr:@supabase/supabase-js@2';

const MODEL = 'claude-sonnet-4-5';
const MAX_TOKENS = 1024;

/// What each tier gets per rolling day. Enforced here rather than in the app.
const DAILY_TURNS: Record<string, number> = {
  paid: 40,
  premium: 200,
};

const SYSTEM = `You are the strength coach inside MGK Lift.

You are talking to somebody who lifts. Be direct, concrete and brief - two or
three sentences unless they asked for detail. No preamble, no "great question",
no bulleted lists of generic advice.

You have their recent training. Use the actual numbers when they are relevant
and say when you do not have enough of them to answer well. Never invent a lift
they did not do.

If they describe pain, say plainly that you are not a clinician and that
persistent or sharp pain is a physio's job, then help with what you can - what
to substitute, what to drop.`;

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return json({ error: 'method_not_allowed' }, 405);
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) return json({ error: 'unauthorised' }, 401);

  // Two clients, deliberately. The anon one carries the caller's JWT so RLS
  // applies to everything read on their behalf; the service one is used only
  // for the writes the client is not allowed to make (usage accounting).
  const asUser = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const asService = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const { data: userData } = await asUser.auth.getUser();
  const user = userData?.user;
  if (!user) return json({ error: 'unauthorised' }, 401);

  // Entitlement, server-side. `status` has five values and only 'active'
  // grants anything - the column comment says so, and treating 'grace' or
  // 'expired' as good enough is exactly the mistake it warns about.
  const { data: entitlement } = await asService
    .schema('core')
    .from('entitlements')
    .select('product, status')
    .eq('user_id', user.id)
    .eq('app', 'lift')
    .maybeSingle();

  const product = entitlement?.status === 'active' ? entitlement.product : 'free';
  const allowance = DAILY_TURNS[product];
  if (!allowance) return json({ error: 'not_entitled' }, 402);

  const { data: used } = await asService.rpc('usage_window', {
    p_user_id: user.id,
    p_hours: 24,
  });
  if (typeof used === 'number' && used >= allowance) {
    return json({ error: 'limit_reached', allowance }, 429);
  }

  const body = await req.json().catch(() => null);
  const message = typeof body?.message === 'string' ? body.message.trim() : '';
  if (!message) return json({ error: 'empty_message' }, 400);

  // Recent training, read as the user so RLS decides what they can see rather
  // than this function deciding. A coach that can read somebody else's log is
  // one RLS bypass away from being the worst bug in the product.
  const { data: workouts } = await asUser
    .schema('lift')
    .from('workouts')
    .select('name, started_at, duration_s, exercises(name, sets(reps, weight_kg, set_type, is_completed))')
    .is('deleted_at', null)
    .eq('is_template', false)
    .order('started_at', { ascending: false })
    .limit(10);

  const key = Deno.env.get('ANTHROPIC_API_KEY');
  if (!key) return json({ error: 'unavailable' }, 503);

  let reply: string;
  let usage = { input_tokens: 0, output_tokens: 0 };
  try {
    const res = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-api-key': key,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: MAX_TOKENS,
        system: SYSTEM,
        messages: [
          {
            role: 'user',
            content: `Recent training (most recent first):\n${summarise(workouts)}\n\n${message}`,
          },
        ],
      }),
    });

    if (!res.ok) {
      // Never forwarded to the client. An upstream error body can carry
      // account and billing details that are ours, not the lifter's.
      console.error('anthropic', res.status, await res.text());
      return json({ error: 'unavailable' }, 502);
    }

    const data = await res.json();
    reply = data?.content?.[0]?.text ?? '';
    usage = data?.usage ?? usage;
  } catch (e) {
    console.error('anthropic', e);
    return json({ error: 'unavailable' }, 502);
  }

  // Recorded after the call, and never allowed to fail the request: the lifter
  // has already had their answer, and losing an accounting row is cheaper than
  // charging them for a reply they did not get.
  try {
    await asService.rpc('record_usage', {
      p_user_id: user.id,
      p_surface: 'coach',
      p_outcome: 'ok',
      p_prompt_tokens: usage.input_tokens ?? 0,
      p_completion_tokens: usage.output_tokens ?? 0,
    });
  } catch (e) {
    console.error('record_usage', e);
  }

  return json({ reply, product });
});

/// Flattens the log into something small enough to send every turn.
///
/// Working sets only, and no warm-ups: the same definition of "counts" the app
/// uses, because a coach that reads a warm-up as a top set will prescribe from
/// it.
function summarise(workouts: unknown): string {
  const rows = Array.isArray(workouts) ? workouts : [];
  if (rows.length === 0) return '(no sessions logged yet)';

  return rows
    .map((w: Record<string, unknown>) => {
      const date = String(w.started_at ?? '').slice(0, 10);
      const exercises = Array.isArray(w.exercises) ? w.exercises : [];
      const lines = exercises
        .map((e: Record<string, unknown>) => {
          const sets = (Array.isArray(e.sets) ? e.sets : []).filter(
            (s: Record<string, unknown>) =>
              s.is_completed === true && s.set_type !== 'warmup',
          );
          if (sets.length === 0) return null;
          const detail = sets
            .map((s: Record<string, unknown>) => `${s.weight_kg}kg x${s.reps}`)
            .join(', ');
          return `  ${e.name}: ${detail}`;
        })
        .filter(Boolean);
      return `${date} ${w.name}\n${lines.join('\n')}`;
    })
    .join('\n');
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}
