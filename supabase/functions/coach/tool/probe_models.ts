// Checks each model on each coach surface before production is switched to it.
//
// From supabase/functions/coach:
//
//     deno run --allow-env --allow-read tool/probe_models.ts \
//       anthropic/claude-haiku-5.5 anthropic/claude-sonnet-5.5
//
// prints the plan and calls nothing. Add `--yes` (and `--allow-net=openrouter.ai`)
// to make the calls. `--only=chat,lift_chat` narrows the surfaces.
//
// **What it answers.** Not "is the coaching good" — supabase/evals is for that
// — but the mechanical questions a model switch can fail on before a word of
// coaching is read: does the model route at all under PROVIDER_ROUTING (no
// provider that trains, schema enforced), does it fit its answer inside each
// surface's `max_tokens` once thinking is counted, does the JSON parse and
// pass the shape check production applies, and is the cost the spend cap will
// record the cost that was actually billed. A model that fails any of those in
// production fails as a 502 a person sees; here it fails as a line of text.
//
// **The request is production's, not a copy of it.** Bodies are built by
// `providerRequest` with the surface's own message builder and schema,
// PROVIDER_ROUTING, and `reasoningFor` reading COACH_REASONING from THIS
// shell's environment — so set it here the way it will be set as a secret.
// Lift's log and plan are rendered by lift_log.ts, as index.ts renders them.
// What differs is the input: SAMPLE bodies below, invented, never anybody's
// data. The function's caller is a signed-in person and this has no person,
// so it talks to OpenRouter directly with the key the function would use.
//
// The key is read from the file named by OPENROUTER_KEY_FILE, by default
// ~/.mgk-fitness/openrouter.key (beside the store keys), and only with
// `--yes`. It is never printed, nor any part of it.

import {
  DEFAULT_LIMITS,
  isSurface,
  type Surface,
  SURFACE_NAMES,
  usageFromResponse,
} from "../limits.ts";
import {
  type Body,
  providerRequest,
  type Reasoning,
  reasoningFor,
  SURFACES,
} from "../surfaces.ts";
import { renderLiftLog, renderLiftPlan } from "../lift_log.ts";

const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";

/// The same ceiling index.ts gives a real call.
const UPSTREAM_TIMEOUT_MS = 75_000;

/// USD per million tokens, from openrouter.ai/api/v1/models on 2026-10-09.
/// Under BYOK this is what Anthropic bills our key; OpenRouter's fee is on top.
/// A model not listed is still probed, and left out of the worst case.
const PRICES: Record<string, { input: number; output: number }> = {
  "anthropic/claude-haiku-5.5": { input: 0.10, output: 0.50 },
  "anthropic/claude-sonnet-5.5": { input: 2, output: 10 },
};

// ---- sample requests --------------------------------------------------------
//
// One per surface, shaped like what reaches `callProvider` in production: the
// client's body for Run's surfaces, and for Lift's the body after index.ts has
// overwritten it with what it reads as the caller. Typed against `Surface`, so
// a surface added without a sample does not compile.

const DAY_MS = 86_400_000;
const isoDaysFromNow = (days: number) =>
  new Date(Date.now() + days * DAY_MS).toISOString();

const RUN_PROFILE = {
  goal_distance_meters: 21097,
  event_date: isoDaysFromNow(12 * 7).slice(0, 10),
  shape: "block",
  current_weekly_meters: 30000,
  longest_recent_meters: 12000,
  days_per_week: 4,
  available_weekdays: [2, 4, 6, 7],
  strength_days_per_week: 0,
  injury_notes: "Left knee aches on long downhills.",
};

const RUN_SLOT = {
  index: 1,
  phase: "base",
  volume_meters: 32000,
  long_run_meters: 12000,
  is_deload: false,
};

const RUN_WEEK = {
  sessions: [
    { weekday: 2, kind: "easy", distance_meters: 7000 },
    { weekday: 4, kind: "threshold", distance_meters: 8000 },
    { weekday: 6, kind: "easy", distance_meters: 5000 },
    { weekday: 7, kind: "long", distance_meters: 12000 },
  ],
};

const RUN_BRIEF =
  `They are in week 4 of 12 of a 21.1 km block, 55 days out from the
event. This is a build week of about 34 km.

Their last run was yesterday: 8 km at 5:31 /km.`;

const working = (weight_kg: number, reps: number) => ({
  reps,
  weight_kg,
  set_type: "working",
  is_completed: true,
});

const LIFT_LOG = renderLiftLog([
  {
    name: "Upper",
    started_at: isoDaysFromNow(-2),
    exercises: [
      {
        name: "Barbell Bench Press",
        sets: [working(85, 6), working(85, 6), working(85, 5)],
      },
      { name: "Barbell Row", sets: [working(70, 8), working(70, 8)] },
    ],
  },
  {
    name: "Lower",
    started_at: isoDaysFromNow(-4),
    exercises: [
      {
        name: "Barbell Back Squat",
        sets: [working(110, 5), working(110, 5)],
      },
      { name: "Romanian Deadlift", sets: [working(90, 8)] },
    ],
  },
  {
    name: "Upper",
    started_at: isoDaysFromNow(-6),
    exercises: [
      { name: "Barbell Bench Press", sets: [working(85, 6), working(85, 6)] },
      { name: "Pull-up", sets: [working(0, 8), working(0, 7)] },
    ],
  },
]);

const LIFT_PLAN = renderLiftPlan([{
  split: "Upper/Lower",
  available_weekdays: [1, 2, 4, 5],
  day_order: ["Upper", "Lower", "Upper", "Lower"],
  goal: "get stronger on the big lifts",
  equipment: "a full commercial gym",
  injury_notes: "left shoulder twinges on overhead work",
}]);

const LIFT_MEMORY =
  "Trains after work, usually four evenings a week. Says their left shoulder " +
  "twinges on overhead pressing and they would rather avoid it. Prefers " +
  "barbell work to machines.";

const CATALOGUE = [
  "Barbell Bench Press",
  "Incline Dumbbell Press",
  "Barbell Row",
  "Seated Cable Row",
  "Pull-up",
  "Lat Pulldown",
  "Barbell Back Squat",
  "Leg Press",
  "Romanian Deadlift",
  "Conventional Deadlift",
  "Walking Lunge",
  "Leg Curl",
  "Standing Calf Raise",
  "Dumbbell Lateral Raise",
  "Face Pull",
  "Barbell Curl",
  "Cable Triceps Pushdown",
].join("\n");

const SAMPLES: Record<Surface, Body> = {
  intake: {
    slots: { goal_distance_meters: 21097, days_per_week: 4 },
    missing: ["event_date", "current_weekly_meters", "available_weekdays"],
    history: [
      { role: "assistant", text: "What are you training for?" },
      { role: "user", text: "A half marathon. I can run four days a week." },
      { role: "assistant", text: "Good. When is the race?" },
      { role: "user", text: "Early March, it's my first one." },
    ],
  },
  skeleton: { profile: RUN_PROFILE },
  week: { slot: RUN_SLOT, profile: RUN_PROFILE },
  adapt: {
    request: "I'm away on Thursday this week, can we move that session?",
    week: RUN_WEEK,
    slot: RUN_SLOT,
    profile: RUN_PROFILE,
  },
  chat: {
    brief: RUN_BRIEF,
    history: [
      { role: "user", text: "how did last week look" },
      { role: "coach", text: "Solid. You hit every session." },
    ],
    message: "can we move Thursday to Friday, I am away",
  },
  summarise: {
    previous: "Works shifts, so mornings vary. Nervous about the hills.",
    transcript: [
      { role: "user", text: "my knee was sore after the long run downhill" },
      { role: "coach", text: "Ease off the descents this week." },
      { role: "user", text: "ok. also I hate the treadmill, never again" },
    ],
  },
  edit_run: { request: "Actually yesterday's run was 6k, not 5." },
  set_goal: { request: "I've entered a 10k at the end of next month." },
  log_run: {
    request:
      "Did 5k in 26 minutes this morning, felt easy, about a 4 out of 10.",
  },
  lift_chat: {
    message: "why has my bench stalled?",
    brief: LIFT_LOG,
    plan: LIFT_PLAN,
    memory: LIFT_MEMORY,
    history: [
      { role: "user", text: "squats felt heavy on Tuesday" },
      { role: "assistant", text: "Sleep and food first. How was the week?" },
    ],
  },
  lift_swap: {
    message: "The bench is taken, what can I do instead?",
    session: {
      exercises: [
        {
          name: "Barbell Bench Press",
          sets: [
            { is_completed: true },
            { is_completed: false },
            { is_completed: false },
          ],
        },
        {
          name: "Barbell Row",
          sets: [{ is_completed: false }, { is_completed: false }],
        },
      ],
    },
  },
  lift_plan: {
    profile: {
      goal: "get stronger on the big lifts",
      weeks: null,
      days_per_week: 4,
      available_weekdays: [1, 2, 4, 5],
      equipment: "a full commercial gym",
      injury_notes: "left shoulder twinges on overhead work",
    },
    weekdays: [1, 2, 4, 5],
    catalogue: CATALOGUE,
    brief: LIFT_LOG,
    memory: LIFT_MEMORY,
    // `guidance` is read from coach.knowledge in production. Left out: the
    // probe reads no database, and absent is a state the prompt handles.
  },
  lift_intake: {
    slots: { days_per_week: 4 },
    declined: [],
    history: [
      { role: "coach", text: "How many days a week can you train?" },
      {
        role: "user",
        text: "Four, Monday, Tuesday, Thursday and Friday, at a full gym.",
      },
    ],
  },
  lift_summarise: {
    previous: LIFT_MEMORY,
    transcript: [
      { role: "user", text: "can we drop overhead press for good" },
      { role: "assistant", text: "Yes. Landmine press instead." },
      { role: "user", text: "and I've moved gyms, no barbells on Fridays" },
    ],
  },
};

// ---- arguments --------------------------------------------------------------

function usage(): never {
  console.error(
    "usage: deno run --allow-env --allow-read [--allow-net=openrouter.ai] \\\n" +
      "         tool/probe_models.ts <model id>... [--only=surface,...] [--yes]",
  );
  Deno.exit(2);
}

const models: string[] = [];
let yes = false;
let only: Surface[] | null = null;
for (const arg of Deno.args) {
  if (arg === "--yes") yes = true;
  else if (arg.startsWith("--only=")) {
    const names = arg.slice("--only=".length).split(",").map((s) => s.trim())
      .filter(Boolean);
    const unknown = names.filter((n) => !isSurface(n));
    if (unknown.length) {
      console.error(`unknown surface: ${unknown.join(", ")}`);
      usage();
    }
    only = names as Surface[];
  } else if (arg.startsWith("-")) usage();
  else models.push(arg);
}
if (!models.length) usage();

const surfaces: readonly Surface[] = only ?? SURFACE_NAMES;

// A sample production would refuse is a bug in this file, not a finding about
// a model, so it stops here rather than spending a call on a 400.
for (const name of surfaces) {
  const spec = SURFACES[name];
  if (spec.validRequest && !spec.validRequest(SAMPLES[name])) {
    throw new Error(`the ${name} sample fails its own validRequest`);
  }
}

const get = (k: string) => Deno.env.get(k);
const home = Deno.env.get("USERPROFILE") ?? Deno.env.get("HOME") ?? ".";
const sep = Deno.build.os === "windows" ? "\\" : "/";
const keyFile = Deno.env.get("OPENROUTER_KEY_FILE")?.trim() ||
  [home, ".mgk-fitness", "openrouter.key"].join(sep);

// ---- the plan ---------------------------------------------------------------

const usd = (n: number) => `$${n.toFixed(n < 0.01 ? 6 : 4)}`;
const pad = (s: string, n: number) => s.padEnd(n);

function describe(reasoning: Reasoning | undefined): string {
  return reasoning ? `effort=${reasoning.effort}` : "(not sent)";
}

/// A rough upper bound on input tokens: one per three characters of messages
/// and schema, where English runs nearer four. Only the worst case uses it.
function inputEstimate(name: Surface): number {
  const spec = SURFACES[name];
  const chars = JSON.stringify(spec.messages(SAMPLES[name])).length +
    JSON.stringify(spec.schema).length;
  return Math.ceil(chars / 3);
}

function worstCase(model: string, name: Surface): number | null {
  const price = PRICES[model];
  if (!price) return null;
  return (inputEstimate(name) * price.input +
    SURFACES[name].maxTokens * price.output) / 1_000_000;
}

console.log(
  yes
    ? "coach model probe: calling OpenRouter\n"
    : "coach model probe: dry run, nothing is called\n",
);
let keyState = "missing, needed for --yes";
try {
  if ((await Deno.stat(keyFile)).isFile) keyState = "present";
} catch {
  // Missing, or no read permission. Either way it cannot be used.
}
console.log(`key file   ${keyFile} (${keyState})`);
console.log(
  `reasoning  COACH_REASONING=${get("COACH_REASONING")?.trim() || "(unset)"}\n`,
);

console.log(`${pad("model", 32)}${pad("reasoning", 18)}price in / out per M`);
for (const model of models) {
  const price = PRICES[model];
  console.log(
    pad(model, 32) + pad(describe(reasoningFor(model, get)), 18) +
      (price
        ? `$${price.input.toFixed(2)} / $${price.output.toFixed(2)}`
        : "unknown, left out of the worst case"),
  );
}

console.log(
  `\n${pad("surface", 16)}${pad("max_tokens", 12)}${pad("~input", 9)}` +
    "worst case per model",
);
let worstTotal = 0;
for (const name of surfaces) {
  const costs = models.map((m) => worstCase(m, name));
  for (const c of costs) worstTotal += c ?? 0;
  console.log(
    pad(name, 16) + pad(String(SURFACES[name].maxTokens), 12) +
      pad(`~${inputEstimate(name)}`, 9) +
      costs.map((c) => pad(c === null ? "?" : usd(c), 11)).join("").trimEnd(),
  );
}
const calls = surfaces.length * models.length;
console.log(
  `\n${surfaces.length} surfaces x ${models.length} models = ${calls} calls. ` +
    `Worst case ${usd(worstTotal)}: every input as estimated, every answer ` +
    `at its full max_tokens.`,
);

if (!yes) {
  console.log("Run again with --yes (and --allow-net=openrouter.ai) to call.");
  Deno.exit(0);
}

// ---- the calls --------------------------------------------------------------

let key: string;
try {
  key = (await Deno.readTextFile(keyFile)).trim();
} catch (e) {
  console.error(
    `cannot read the key file ${keyFile}: ${(e as Error).name}`,
  );
  Deno.exit(1);
}
if (!key) {
  console.error(`the key file ${keyFile} is empty`);
  Deno.exit(1);
}

/// An error body, capped, and with the key taken out in case anything ever
/// echoes a header back. The input here is the samples above, so unlike the
/// function's own logs there is no user content to keep out.
function excerpt(text: string): string {
  const clean = text.replaceAll(key, "[key]").replace(/\s+/g, " ").trim();
  return clean.length > 300 ? `${clean.slice(0, 300)}…` : clean;
}

type Payload = {
  provider?: unknown;
  error?: unknown;
  usage?: {
    prompt_tokens?: unknown;
    completion_tokens?: unknown;
    completion_tokens_details?: { reasoning_tokens?: unknown };
    cost?: unknown;
    is_byok?: unknown;
    cost_details?: { upstream_inference_cost?: unknown };
  };
  choices?: { finish_reason?: unknown; message?: { content?: unknown } }[];
};

const show = (v: unknown) => v === undefined || v === null ? "-" : String(v);

let passed = 0;
let truncated = 0;
let billed = 0;
let upstreamTotal = 0;
let recordedTotal = 0;
const started = performance.now();

console.log("");
for (const model of models) {
  const reasoning = reasoningFor(model, get);
  for (const name of surfaces) {
    const spec = SURFACES[name];
    const label = `${pad(model, 30)}${pad(name, 16)}`;
    const t0 = performance.now();

    let res: Response;
    try {
      res = await fetch(OPENROUTER_URL, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "Authorization": `Bearer ${key}`,
          "HTTP-Referer": "https://mgkfitness.mgkcodes.com",
          // Its own title, so the probe's calls are told apart from real
          // coaching in OpenRouter's activity view.
          "X-Title": "MGKFitness: coach probe",
        },
        body: JSON.stringify(providerRequest({
          model,
          surface: spec,
          body: structuredClone(SAMPLES[name]),
          reasoning,
        })),
        signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
      });
    } catch (e) {
      console.log(`${label}unreachable (${(e as Error).name})`);
      continue;
    }
    const seconds = ((performance.now() - t0) / 1000).toFixed(1);

    const text = await res.text().catch(() => "");
    if (!res.ok) {
      console.log(`${label}${res.status}  ${seconds}s  ${excerpt(text)}`);
      continue;
    }

    let payload: Payload;
    try {
      payload = JSON.parse(text);
    } catch {
      console.log(`${label}${res.status}  ${seconds}s  non-JSON body`);
      continue;
    }
    if (payload.error) {
      console.log(
        `${label}${res.status}  ${seconds}s  error ` +
          excerpt(JSON.stringify(payload.error)),
      );
      continue;
    }

    const choice = payload.choices?.[0];
    const finish = show(choice?.finish_reason);
    if (finish === "length") truncated++;

    // What production does with the answer: parse it, then the shape check
    // that decides between a 200 and a 502 coach_malformed.
    let json = "no";
    let keys = "-";
    let valid = "no";
    const content = choice?.message?.content;
    if (typeof content === "string") {
      try {
        const parsed = JSON.parse(content);
        json = "yes";
        if (typeof parsed === "object" && parsed !== null) {
          const required =
            (spec.schema as { required?: readonly string[] }).required ?? [];
          const missing = required.filter((k) => !(k in parsed));
          keys = missing.length ? `missing:${missing.join(",")}` : "ok";
          if (spec.valid(parsed)) {
            valid = "yes";
            passed++;
          }
        }
      } catch {
        // Stays "no": this is the 502 a person would see.
      }
    }

    const u = payload.usage ?? {};
    // What the spend cap would write down for this call.
    const recorded = usageFromResponse(payload.usage, {
      creditsPerMillionTokens: DEFAULT_LIMITS.fallbackCreditsPerMillionTokens,
      assumedTokensWhenUnknown: spec.maxTokens,
    });
    const upstream = u.cost_details?.upstream_inference_cost;
    if (typeof u.cost === "number") billed += u.cost;
    if (typeof upstream === "number") upstreamTotal += upstream;
    recordedTotal += recorded.costCredits;

    console.log(
      `${label}${res.status} ${pad(show(payload.provider), 12)}` +
        `${pad(finish, 8)}json=${json} keys=${keys} valid=${valid}  ` +
        `in=${show(u.prompt_tokens)} out=${show(u.completion_tokens)} ` +
        `think=${show(u.completion_tokens_details?.reasoning_tokens)}  ` +
        `cost=${show(u.cost)} upstream=${show(upstream)} ` +
        `byok=${show(u.is_byok)} recorded=${recorded.costCredits.toFixed(6)}${
          recorded.costEstimated ? "(est)" : ""
        }  ${seconds}s`,
    );
  }
}

const total = ((performance.now() - started) / 1000).toFixed(1);
console.log(
  `\n${passed} of ${calls} calls passed the shape check, ${truncated} ` +
    `stopped at max_tokens. cost=${billed.toFixed(6)} ` +
    `upstream=${upstreamTotal.toFixed(6)} recorded=${
      recordedTotal.toFixed(6)
    }  ${total}s`,
);
if (passed < calls) Deno.exitCode = 1;
