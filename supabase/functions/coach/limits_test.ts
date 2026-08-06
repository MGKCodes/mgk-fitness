// Unit tests for the coach limiter's decision logic.
//
// The point of keeping limits.ts pure is that every threshold and every window
// boundary can be asserted here without a database, a JWT, or a deployed
// function. Run from this directory:
//
//     deno test
//
// (Deno needs no permissions for these — there is no I/O in limits.ts.)

import { assert, assertAlmostEquals, assertEquals } from "jsr:@std/assert@1";

import {
  configFromEnv,
  decide,
  DEFAULT_LIMITS,
  isSurface,
  type LimitConfig,
  lookbackSeconds,
  type Surface,
  usageFromResponse,
  type UsageRow,
} from "./limits.ts";

const NOW = Date.parse("2026-07-26T12:00:00.000Z");
const MINUTE = 60_000;
const HOUR = 60 * MINUTE;

/// A tiny, explicit config so tests assert on numbers they can see rather than
/// on the shipped defaults (which are free to change).
const TEST_LIMITS: LimitConfig = {
  perSurface: {
    intake: { windowSeconds: 300, max: 3 },
    skeleton: { windowSeconds: 3600, max: 2 },
    week: { windowSeconds: 3600, max: 4 },
    adapt: { windowSeconds: 3600, max: 2 },
    chat: { windowSeconds: 300, max: 5 },
    summarise: { windowSeconds: 3600, max: 2 },
    log_run: { windowSeconds: 3600, max: 2 },
    edit_run: { windowSeconds: 3600, max: 2 },
    set_goal: { windowSeconds: 3600, max: 2 },
  },
  dailyRequests: { windowSeconds: 86_400, max: 10 },
  // One window in the fixture, so the existing single-cap assertions keep
  // testing exactly what they always did. Multi-window behaviour is asserted
  // separately below, against configs that declare more than one.
  spend: [{ windowSeconds: 86_400, credits: 1, scope: "daily_spend" }],
  fallbackCreditsPerMillionTokens: 2,
};

/// The ceiling for one named window, so a test names the window it means
/// rather than indexing into the array.
function credits(config: LimitConfig, scope: string): number | undefined {
  return config.spend.find((r) => r.scope === scope)?.credits;
}

/// `n` calls on `surface`, spaced `spacingMs` apart, the most recent
/// `offsetMs` before now.
function rows(
  surface: Surface,
  n: number,
  { offsetMs = 0, spacingMs = 1000, cost = 0 } = {},
): UsageRow[] {
  return Array.from({ length: n }, (_, i) => ({
    atMs: NOW - offsetMs - i * spacingMs,
    surface,
    costCredits: cost,
  }));
}

function denial(decision: ReturnType<typeof decide>) {
  assert(!decision.allowed, "expected the request to be refused");
  return decision;
}

// ---- surface guard ---------------------------------------------------------

Deno.test("isSurface accepts the wired surfaces and nothing else", () => {
  for (
    const s of ["intake", "skeleton", "week", "adapt", "chat", "summarise"]
  ) {
    assert(isSurface(s), `${s} should be a surface`);
  }
  for (
    const s of ["rationale", "checkin", "summarize", "", "INTAKE", null, 7, {}]
  ) {
    assert(!isSurface(s), `${JSON.stringify(s)} should not be a surface`);
  }
});

// ---- the happy path --------------------------------------------------------

Deno.test("a first-ever request is allowed", () => {
  assertEquals(decide("intake", [], NOW, TEST_LIMITS), { allowed: true });
});

Deno.test("usage below every ceiling is allowed", () => {
  const history = [
    ...rows("intake", 2, { offsetMs: MINUTE, cost: 0.01 }),
    ...rows("week", 3, { offsetMs: 10 * MINUTE, cost: 0.05 }),
  ];
  assertEquals(decide("intake", history, NOW, TEST_LIMITS), { allowed: true });
});

// ---- per-surface rate limiting ---------------------------------------------

Deno.test("a surface is limited at its own max, not a shared one", () => {
  // Two skeletons is skeleton's whole hourly allowance...
  const history = rows("skeleton", 2, { offsetMs: MINUTE });
  const refused = denial(decide("skeleton", history, NOW, TEST_LIMITS));
  assertEquals(refused.error, "rate_limited");
  assertEquals(refused.scope, "skeleton");

  // ...but it must not touch a cheap intake turn. This is the whole reason the
  // limits are per surface: one flat number either strangles plan generation or
  // leaves chat wide open.
  assertEquals(decide("intake", history, NOW, TEST_LIMITS), { allowed: true });
});

Deno.test("calls that have aged out of the window do not count", () => {
  // Three intake turns, but all older than the five-minute window.
  const history = rows("intake", 3, { offsetMs: 6 * MINUTE });
  assertEquals(decide("intake", history, NOW, TEST_LIMITS), { allowed: true });
});

Deno.test("the window slides — there is no boundary that doubles the allowance", () => {
  // Two turns just about to expire, one fresh: still three in the window.
  const history = [
    ...rows("intake", 2, { offsetMs: 299_000, spacingMs: 500 }),
    ...rows("intake", 1, { offsetMs: 0 }),
  ];
  assertEquals(
    denial(decide("intake", history, NOW, TEST_LIMITS)).error,
    "rate_limited",
  );

  // One second later the two oldest have left and the request fits.
  assertEquals(decide("intake", history, NOW + 2000, TEST_LIMITS), {
    allowed: true,
  });
});

Deno.test("retry_after is when the request would actually fit", () => {
  // Exactly at the limit: the oldest call must leave the window.
  const history = rows("intake", 3, { offsetMs: 60_000, spacingMs: 30_000 });
  const oldestAgeSeconds = 60 + 60; // third call is 120s old
  const refused = denial(decide("intake", history, NOW, TEST_LIMITS));
  assertEquals(refused.retryAfterSeconds, 300 - oldestAgeSeconds);
});

Deno.test("retry_after accounts for being several calls over the line", () => {
  // Five intake turns against a max of three: two must expire, so the wait is
  // until the third-oldest leaves — not the oldest.
  const history = rows("intake", 5, { offsetMs: 0, spacingMs: 10_000 });
  // Ages: 0s, 10s, 20s, 30s, 40s. Sorted oldest-first, index 5-3 = 2 is the 20s
  // one, which leaves the 300s window in 280s.
  const refused = denial(decide("intake", history, NOW, TEST_LIMITS));
  assertEquals(refused.retryAfterSeconds, 280);
});

Deno.test("retry_after is never zero or negative", () => {
  // A call right on the window edge would otherwise round to 0.
  const history = rows("intake", 3, { offsetMs: 299_999, spacingMs: 0 });
  const refused = denial(decide("intake", history, NOW, TEST_LIMITS));
  assert(refused.retryAfterSeconds >= 1, "retry must be at least a second");
});

Deno.test("a max of zero refuses without dividing by anything", () => {
  const config: LimitConfig = {
    ...TEST_LIMITS,
    perSurface: {
      ...TEST_LIMITS.perSurface,
      adapt: { windowSeconds: 3600, max: 0 },
    },
  };
  const refused = denial(decide("adapt", [], NOW, config));
  assertEquals(refused.error, "rate_limited");
  assertEquals(refused.retryAfterSeconds, 3600);
});

// ---- the daily request backstop --------------------------------------------

Deno.test("the daily ceiling catches a slow loop that dodges every window", () => {
  // Ten calls spread over the day: under every per-surface window, but the
  // whole daily allowance.
  const history = rows("week", 10, { offsetMs: HOUR, spacingMs: 2 * HOUR });
  const refused = denial(decide("intake", history, NOW, TEST_LIMITS));
  assertEquals(refused.error, "rate_limited");
  assertEquals(refused.scope, "daily_requests");
});

Deno.test("the daily ceiling counts every surface together", () => {
  const history = [
    ...rows("intake", 4, { offsetMs: 10 * HOUR, spacingMs: HOUR }),
    ...rows("week", 3, { offsetMs: 5 * HOUR, spacingMs: HOUR }),
    ...rows("adapt", 3, { offsetMs: 2 * HOUR, spacingMs: HOUR }),
  ];
  assertEquals(
    denial(decide("skeleton", history, NOW, TEST_LIMITS)).scope,
    "daily_requests",
  );
});

// ---- the spend cap ---------------------------------------------------------

Deno.test("spend under the cap is allowed", () => {
  const history = rows("week", 3, {
    offsetMs: HOUR,
    spacingMs: HOUR,
    cost: 0.3,
  });
  assertEquals(decide("week", history, NOW, TEST_LIMITS), { allowed: true });
});

Deno.test("reaching the spend cap refuses with its own error code", () => {
  const history = rows("week", 4, {
    offsetMs: HOUR,
    spacingMs: HOUR,
    cost: 0.25,
  });
  const refused = denial(decide("week", history, NOW, TEST_LIMITS));
  assertEquals(refused.error, "spend_cap_reached");
  assertEquals(refused.scope, "daily_spend");
});

Deno.test("the spend cap outranks a rate limit, so retry_after is honest", () => {
  // Both bind: three intake turns in five minutes AND the daily spend. Telling
  // the runner to come back in four minutes would be a lie, because the spend
  // cap still has hours to run.
  const history = rows("intake", 3, {
    offsetMs: MINUTE,
    spacingMs: 1000,
    cost: 0.5,
  });
  const refused = denial(decide("intake", history, NOW, TEST_LIMITS));
  assertEquals(refused.error, "spend_cap_reached");
  assert(
    refused.retryAfterSeconds > 20 * 3600,
    `expected the better part of a day, got ${refused.retryAfterSeconds}s`,
  );
});

Deno.test("spend clears when enough of the oldest cost ages out", () => {
  // 0.6 credits 23h ago, 0.6 credits an hour ago = 1.2, over the cap of 1.
  // Dropping the old one leaves 0.6, so the wait is until it turns 24h.
  const history: UsageRow[] = [
    { atMs: NOW - 23 * HOUR, surface: "week", costCredits: 0.6 },
    { atMs: NOW - 1 * HOUR, surface: "week", costCredits: 0.6 },
  ];
  const refused = denial(decide("week", history, NOW, TEST_LIMITS));
  assertEquals(refused.error, "spend_cap_reached");
  assertEquals(refused.retryAfterSeconds, 3600);
});

Deno.test("spend older than the rolling day does not count", () => {
  const history: UsageRow[] = [
    { atMs: NOW - 25 * HOUR, surface: "week", costCredits: 99 },
  ];
  assertEquals(decide("week", history, NOW, TEST_LIMITS), { allowed: true });
});

Deno.test("a cap of zero refuses everything for a full day", () => {
  const config: LimitConfig = {
    ...TEST_LIMITS,
    spend: [{ windowSeconds: 86_400, credits: 0, scope: "daily_spend" }],
  };
  const refused = denial(decide("week", [], NOW, config));
  assertEquals(refused.error, "spend_cap_reached");
  assertEquals(refused.retryAfterSeconds, 86_400);
});

Deno.test("a negative recorded cost cannot buy back budget", () => {
  const history: UsageRow[] = [
    { atMs: NOW - HOUR, surface: "week", costCredits: 1.5 },
    { atMs: NOW - MINUTE, surface: "week", costCredits: -5 },
  ];
  assertEquals(
    denial(decide("week", history, NOW, TEST_LIMITS)).error,
    "spend_cap_reached",
  );
});

// ---- config ----------------------------------------------------------------

Deno.test("lookback covers the longest window", () => {
  assertEquals(lookbackSeconds(TEST_LIMITS), 86_400);
  assert(
    lookbackSeconds(DEFAULT_LIMITS) >= 86_400,
    "must read back at least the spend period",
  );
});

Deno.test("env overrides are read", () => {
  const env: Record<string, string> = {
    COACH_DAILY_SPEND_LIMIT: "0.25",
    COACH_DAILY_REQUEST_LIMIT: "40",
    COACH_FALLBACK_CREDITS_PER_MTOK: "3.5",
  };
  const config = configFromEnv((k) => env[k]);
  assertEquals(credits(config, "daily_spend"), 0.25);
  assertEquals(config.dailyRequests.max, 40);
  assertEquals(config.fallbackCreditsPerMillionTokens, 3.5);
});

Deno.test("a junk env value keeps the default rather than becoming NaN", () => {
  // NaN is the dangerous direction: every comparison against it is false, so a
  // typo would silently allow unlimited spend.
  for (const junk of ["", "  ", "abc", "-1", "0", "NaN", "1e"]) {
    const config = configFromEnv((k) =>
      k === "COACH_DAILY_SPEND_LIMIT" ? junk : undefined
    );
    assertEquals(
      credits(config, "daily_spend"),
      credits(DEFAULT_LIMITS, "daily_spend"),
      `"${junk}" should have fallen back to the default`,
    );
  }
});

Deno.test("an unset environment yields the shipped defaults", () => {
  assertEquals(configFromEnv(() => undefined), DEFAULT_LIMITS);
});

// ---- usage accounting ------------------------------------------------------

const ACCOUNTING = {
  creditsPerMillionTokens: 2,
  assumedTokensWhenUnknown: 4096,
};

Deno.test("a reported cost is used verbatim and not estimated", () => {
  const usage = usageFromResponse({
    prompt_tokens: 1200,
    completion_tokens: 800,
    total_tokens: 2000,
    cost: 0.00123,
  }, ACCOUNTING);
  assertEquals(usage.promptTokens, 1200);
  assertEquals(usage.completionTokens, 800);
  assertEquals(usage.totalTokens, 2000);
  assertEquals(usage.costCredits, 0.00123);
  assertEquals(usage.costEstimated, false);
});

Deno.test("a zero reported cost is still a reported cost", () => {
  // A free-tier model really can cost nothing. Estimating over the top of that
  // would invent spend that was never charged.
  const usage = usageFromResponse(
    { prompt_tokens: 10, completion_tokens: 5, cost: 0 },
    ACCOUNTING,
  );
  assertEquals(usage.costCredits, 0);
  assertEquals(usage.costEstimated, false);
});

Deno.test("total_tokens is derived when the provider omits it", () => {
  const usage = usageFromResponse(
    { prompt_tokens: 100, completion_tokens: 50, cost: 0.1 },
    ACCOUNTING,
  );
  assertEquals(usage.totalTokens, 150);
});

Deno.test("a missing cost is estimated from tokens, never treated as free", () => {
  // Otherwise a provider that does not report cost is a hole straight through
  // the spend cap.
  const usage = usageFromResponse(
    { prompt_tokens: 400_000, completion_tokens: 100_000 },
    ACCOUNTING,
  );
  assertEquals(usage.totalTokens, 500_000);
  assertAlmostEquals(usage.costCredits, 1.0, 1e-9); // 0.5M * 2 credits/M
  assertEquals(usage.costEstimated, true);
});

Deno.test("no usage block at all charges the surface's whole token budget", () => {
  for (const absent of [undefined, null, {}, "nope", 42]) {
    const usage = usageFromResponse(absent, ACCOUNTING);
    assertEquals(usage.totalTokens, 0);
    assertAlmostEquals(usage.costCredits, (4096 / 1e6) * 2, 1e-12);
    assertEquals(usage.costEstimated, true);
  }
});

Deno.test("nonsense token counts do not poison the arithmetic", () => {
  const usage = usageFromResponse({
    prompt_tokens: "many",
    completion_tokens: -7,
    total_tokens: Number.NaN,
    cost: "free",
  }, ACCOUNTING);
  assertEquals(usage.promptTokens, 0);
  assertEquals(usage.completionTokens, 0);
  assertEquals(usage.totalTokens, 0);
  assert(Number.isFinite(usage.costCredits), "cost must stay a real number");
  assertEquals(usage.costEstimated, true);
});

Deno.test("a negative reported cost is floored at zero", () => {
  const usage = usageFromResponse(
    { prompt_tokens: 10, completion_tokens: 10, cost: -3 },
    ACCOUNTING,
  );
  assertEquals(usage.costCredits, 0);
});

// ---- the shipped defaults are sane ----------------------------------------

Deno.test("the shipped defaults permit a real onboarding conversation", () => {
  // Onboarding is four to five turns (INTAKE_INSTRUCTIONS), and a runner may
  // restart it. Six turns back to back must not be refused.
  let history: UsageRow[] = [];
  for (let i = 0; i < 6; i++) {
    const at = NOW + i * 15_000;
    assertEquals(
      decide("intake", history, at, DEFAULT_LIMITS),
      { allowed: true },
      `turn ${i + 1} should be allowed`,
    );
    history = [...history, {
      atMs: at,
      surface: "intake",
      costCredits: 0.0003,
    }];
  }
});

Deno.test("the shipped defaults permit a plan generation burst", () => {
  // One skeleton plus a first-time backfill of several weeks, each with the
  // validator's second attempt: PlanService retries twice before falling back.
  let history: UsageRow[] = [];
  const call = (surface: Surface, at: number) => {
    assertEquals(
      decide(surface, history, at, DEFAULT_LIMITS),
      { allowed: true },
      `${surface} at +${(at - NOW) / 1000}s should be allowed`,
    );
    history = [...history, { atMs: at, surface, costCredits: 0.002 }];
  };

  let t = NOW;
  for (let attempt = 0; attempt < 2; attempt++) call("skeleton", t += 5000);
  for (let week = 0; week < 6; week++) {
    for (let attempt = 0; attempt < 2; attempt++) call("week", t += 5000);
  }
});

Deno.test("the shipped defaults permit a real conversation", () => {
  // A runner typing every twenty-five seconds for five minutes. Chat is the
  // cheapest surface and the one they touch most, so the ceiling has to sit
  // above any human conversation pace or it becomes the product's speed limit.
  let history: UsageRow[] = [];
  for (let i = 0; i < 12; i++) {
    const at = NOW + i * 25_000;
    assertEquals(
      decide("chat", history, at, DEFAULT_LIMITS),
      { allowed: true },
      `message ${i + 1} should be allowed`,
    );
    history = [...history, { atMs: at, surface: "chat", costCredits: 0.0004 }];
  }
});

Deno.test("a client looping the chat surface is stopped without touching the plan", () => {
  const history = rows("chat", 15, { spacingMs: 1000 });
  const refused = denial(decide("chat", history, NOW, DEFAULT_LIMITS));
  assertEquals(refused.error, "rate_limited");
  assertEquals(refused.scope, "chat");
  // A runner who has talked their way to the chat ceiling can still have a week
  // generated. That is the whole reason the limits are per surface.
  assertEquals(decide("week", history, NOW, DEFAULT_LIMITS), { allowed: true });
});

Deno.test("summarising after every turn hits the wall, by design", () => {
  // The rolling memory is regenerated when a conversation ends, not per turn.
  // Per-turn summarising is a re-encode of a re-encode, which is the failure the
  // surface exists to avoid, and it is also the most expensive way to use it.
  // Six an hour covers six conversations plus a retry.
  const history = rows("summarise", 6, { spacingMs: 60_000 });
  const refused = denial(decide("summarise", history, NOW, DEFAULT_LIMITS));
  assertEquals(refused.error, "rate_limited");
  assertEquals(refused.scope, "summarise");
  // And it never costs the runner the conversation itself.
  assertEquals(decide("chat", history, NOW, DEFAULT_LIMITS), { allowed: true });
});

Deno.test("a heavy but honest day of coaching fits under the daily backstop", () => {
  // Onboarding, a plan, a talkative day, and the memories written after it. The
  // 120/day ceiling exists for a client bug, not for a keen runner.
  const day: [Surface, number, number][] = [
    // surface, calls, minutes between them
    ["intake", 6, 0.5],
    ["skeleton", 2, 1],
    ["week", 12, 5],
    ["chat", 40, 5],
    ["summarise", 6, 30],
    ["adapt", 4, 15],
  ];

  let history: UsageRow[] = [];
  let at = NOW;
  let calls = 0;
  for (const [surface, count, spacingMinutes] of day) {
    for (let i = 0; i < count; i++) {
      assertEquals(
        decide(surface, history, at, DEFAULT_LIMITS),
        { allowed: true },
        `${surface} call ${i + 1} should be allowed`,
      );
      history = [...history, { atMs: at, surface, costCredits: 0.002 }];
      at += spacingMinutes * MINUTE;
      calls++;
    }
  }

  assert(
    calls < DEFAULT_LIMITS.dailyRequests.max,
    `a real day is ${calls} calls; the backstop must sit above it`,
  );
  assert(at - NOW < 24 * HOUR, "the whole day must fall inside one window");
});

// ---- several spend windows at once ------------------------------------------
//
// The reason these exist: a daily cap alone silently authorises thirty times
// itself over a month, and a month is the unit a subscription is billed in.

const MULTI: LimitConfig = {
  ...TEST_LIMITS,
  spend: [
    { windowSeconds: 86_400, credits: 1, scope: "daily_spend" },
    { windowSeconds: 7 * 86_400, credits: 2, scope: "weekly_spend" },
    { windowSeconds: 30 * 86_400, credits: 3, scope: "monthly_spend" },
  ],
};

Deno.test("a month's worth of small days is stopped by the monthly ceiling", () => {
  // Twenty days at 0.2 each: never near the daily cap of 1, never near the
  // weekly cap of 2, comfortably past the monthly cap of 3. This is the case a
  // single daily cap cannot catch. (Deliberately clear of the cap rather than
  // exactly on it — summing 0.15 twenty times lands just under 3 in binary
  // floating point, which would test the arithmetic rather than the rule.)
  const history: UsageRow[] = Array.from({ length: 20 }, (_, i) => ({
    atMs: NOW - (i + 1) * 24 * HOUR,
    surface: "chat",
    costCredits: 0.2,
  }));
  const refused = denial(decide("chat", history, NOW, MULTI));
  assertEquals(refused.error, "spend_cap_reached");
  assertEquals(refused.scope, "monthly_spend");
});

Deno.test("the ceiling that clears last is the one reported", () => {
  // Breaches daily (1) and monthly (3) together. The daily window clears in
  // about a day; the monthly one holds for weeks, so reporting the daily
  // retry-after would send the runner back to a refusal.
  const history: UsageRow[] = [
    { atMs: NOW - 2 * HOUR, surface: "chat", costCredits: 1.2 },
    ...Array.from({ length: 10 }, (_, i) => ({
      atMs: NOW - (i + 2) * 24 * HOUR,
      surface: "chat",
      costCredits: 0.25,
    })),
  ];
  const refused = denial(decide("chat", history, NOW, MULTI));
  assertEquals(refused.scope, "monthly_spend");
  assert(
    refused.retryAfterSeconds > 86_400,
    `expected the monthly window, got ${refused.retryAfterSeconds}s`,
  );
});

Deno.test("spend outside every window does not count", () => {
  const history: UsageRow[] = [
    { atMs: NOW - 31 * 24 * HOUR, surface: "chat", costCredits: 99 },
  ];
  assertEquals(decide("chat", history, NOW, MULTI), { allowed: true });
});

Deno.test("lookback reaches the longest spend window, not just a day", () => {
  // If this ever regresses, the store reads too short a history and the long
  // ceilings silently stop binding. The SQL prune must outlive it too.
  assertEquals(lookbackSeconds(MULTI), 30 * 86_400);
  assert(lookbackSeconds(DEFAULT_LIMITS) >= 30 * 86_400);
});

Deno.test("each spend window has its own env override", () => {
  const env: Record<string, string> = {
    COACH_DAILY_SPEND_LIMIT: "0.1",
    COACH_WEEKLY_SPEND_LIMIT: "0.4",
    COACH_MONTHLY_SPEND_LIMIT: "1.2",
  };
  const config = configFromEnv((k) => env[k]);
  assertEquals(credits(config, "daily_spend"), 0.1);
  assertEquals(credits(config, "weekly_spend"), 0.4);
  assertEquals(credits(config, "monthly_spend"), 1.2);
});

Deno.test("the shipped defaults are ordered day <= week <= month", () => {
  // Not arithmetic for its own sake: a monthly ceiling below the daily one
  // would make the daily ceiling unreachable and the config a lie.
  const by = (s: string) => credits(DEFAULT_LIMITS, s) ?? 0;
  assert(by("daily_spend") <= by("weekly_spend"), "day must not exceed week");
  assert(
    by("weekly_spend") <= by("monthly_spend"),
    "week must not exceed month",
  );
});
