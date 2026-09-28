// Per-user rate limiting and spend capping for the coach proxy — the "abuse and
// cost are controlled at the proxy" half of ADR-0007.
//
// This module is DELIBERATELY PURE: no Deno APIs, no fetch, no database. It
// takes a snapshot of a user's recent model calls and answers one question —
// may this request spend tokens? That makes every threshold and every window
// boundary unit-testable without a platform (see limits_test.ts). The impure
// half (reading and writing the snapshot) lives in usage_store.ts.
//
// PRIVACY: a usage row carries a timestamp, a surface name, token counts and a
// cost. It never carries a prompt, a response, or any training or health value.
// Usage accounting is exactly where a request body gets logged by accident, so
// the type below has nowhere to put one.

// Type-only, and therefore erased: this file still has no runtime dependency on
// anything. `surfaces.ts` already imports `Surface` from here, so the pair
// referencing each other's types is existing shape rather than new coupling.
import type { Tier } from "./surfaces.ts";

/**
 * The prompt surfaces the proxy exposes. Each is priced differently, so each
 * is limited differently.
 *
 * The list spans BOTH apps. One coach function serves Lift and Run (the `coach`
 * schema comment says so, and docs/architecture.md is written on it), so a
 * surface name carries which app it belongs to — `lift_chat` is Lift's, the
 * unprefixed ones are Run's, for the historical reason that they were written
 * before there was a second app to disambiguate from. Which app a surface
 * serves is declared in `surfaces.ts` and is what the entitlement check is
 * keyed on; the client never says.
 */
export type Surface =
  | "intake"
  | "skeleton"
  | "week"
  | "adapt"
  | "chat"
  | "summarise"
  | "log_run"
  | "edit_run"
  | "set_goal"
  | "lift_chat"
  | "lift_summarise"
  | "lift_intake"
  | "lift_plan"
  | "lift_swap";

export const SURFACE_NAMES: readonly Surface[] = [
  "intake",
  "skeleton",
  "week",
  "adapt",
  "chat",
  "summarise",
  "log_run",
  "edit_run",
  "set_goal",
  "lift_chat",
  "lift_summarise",
  "lift_intake",
  "lift_plan",
  "lift_swap",
];

export function isSurface(value: unknown): value is Surface {
  return typeof value === "string" &&
    (SURFACE_NAMES as readonly string[]).includes(value);
}

/**
 * "At most `max` requests in any `windowSeconds` window." The window slides —
 * it is evaluated against the actual call timestamps, not a calendar bucket,
 * so there is no boundary at which a user gets 2x their allowance.
 */
export interface RateRule {
  windowSeconds: number;
  max: number;
}

/**
 * A money ceiling over one rolling window.
 *
 * There is more than one because the windows answer different questions. A
 * daily ceiling bounds a runaway loop; a monthly one bounds the bill. They are
 * not substitutes: a $0.20 daily cap silently authorises $6 a month, which is
 * the number that actually arrives on an invoice. Whatever a subscription
 * charges is a MONTHLY figure, so the monthly window is the one that has to sit
 * under it, and the shorter windows exist to stop a single bad day spending the
 * whole month's allowance in an hour.
 */
export interface SpendRule {
  windowSeconds: number;
  credits: number;
  /** Named in the refusal so the UI can say which ceiling bound. */
  scope: string;
}


const DAY_SECONDS = 86_400;
const WEEK_SECONDS = DAY_SECONDS * 7;
/** 30 days. A rolling month, not a calendar one — there is no reset day. */
const MONTH_SECONDS = DAY_SECONDS * 30;

/**
 * The money ceilings, per tier. **This is where the price list meets the code**
 * — see [ADR-0029](../../../apps/mgk_run/docs/decisions/0029-what-a-tier-costs-and-buys.md).
 *
 * ## Where the numbers come from
 *
 * A tier's monthly ceiling has to sit under what that tier actually earns, or
 * one runner reaching it consumes the margin of several others (ADR-0015's
 * whole argument). Net of UK VAT at 20% and Apple's 15% Small Business rate:
 *
 * | Tier      | Price   | Ex-VAT  | Net of Apple | ~USD  |
 * |-----------|---------|---------|--------------|-------|
 * | `free`    | —       | —       | —            | —     |
 * | `standard`| £1/mo   | £0.833  | £0.71        | $0.85 |
 * | `sharp`   | £3/mo   | £2.500  | £2.13        | $2.56 |
 *
 * The USD column converts at a deliberately pessimistic 1.20, because these are
 * ceilings: understating revenue makes the cap safer, and OpenRouter bills in
 * USD credits while the subscription is priced in sterling. **Re-check it if
 * the rate moves far** — a cap sized on a strong pound is a cap that stops
 * sitting under revenue when it weakens.
 *
 * Each paid ceiling is set at roughly **three quarters** of its tier's net
 * revenue. ADR-0015's rule is that the monthly ceiling sits *under* revenue;
 * this picks how far under, and the answer is a policy choice rather than a
 * derivation. Three quarters leaves a quarter for Supabase, MapTiler and margin
 * on the worst user the tier permits, and it is a CEILING rather than a
 * forecast — the average is far below it, so what this buys is that the runners
 * who do reach it are still profitable rather than merely survivable.
 *
 * Half was tried first and was too mean to be honest: at $0.002 a call it
 * refused a day of onboarding, a plan and forty chat turns, which is a heavy
 * day but not an abusive one. `limits_test.ts` pins that day's cost against
 * each tier, so the trade-off is an assertion somebody can read rather than a
 * number somebody chose. As it stands £1 buys about one such day and £3 buys
 * three, which is a defensible thing for the two tiers to mean.
 *
 * **`free` earns nothing, so every credit is acquisition cost.** It gets a
 * tenth of a dollar a month — enough to meet the coach, not enough to live on
 * it. Before this existed the free tier shared the standard ceiling, so an
 * unpaying Run user could cost $0.85 a month against no revenue at all.
 *
 * The 24% / 60% / 100% shape across the three windows is carried over from the
 * flat config, and is ADR-0015's: the daily ceiling bounds a runaway loop, the
 * monthly one bounds the bill, the weekly sits between so a bad few days cannot
 * quietly become a bad month.
 *
 * **Still provisional.** These are arithmetic against a price, not measurement
 * of what a runner costs — that comes from `coach_usage` after live traffic,
 * and the model behind COACH_MODEL is a server-side choice this file knows
 * nothing about. What is no longer provisional is that they differ by tier and
 * that each sits under its own revenue.
 */
const TIER_SPEND: Record<Tier, SpendRule[]> = {
  free: [
    { windowSeconds: DAY_SECONDS, credits: 0.025, scope: "daily_spend" },
    { windowSeconds: WEEK_SECONDS, credits: 0.06, scope: "weekly_spend" },
    { windowSeconds: MONTH_SECONDS, credits: 0.1, scope: "monthly_spend" },
  ],
  standard: [
    { windowSeconds: DAY_SECONDS, credits: 0.15, scope: "daily_spend" },
    { windowSeconds: WEEK_SECONDS, credits: 0.38, scope: "weekly_spend" },
    { windowSeconds: MONTH_SECONDS, credits: 0.64, scope: "monthly_spend" },
  ],
  sharp: [
    { windowSeconds: DAY_SECONDS, credits: 0.46, scope: "daily_spend" },
    { windowSeconds: WEEK_SECONDS, credits: 1.15, scope: "weekly_spend" },
    { windowSeconds: MONTH_SECONDS, credits: 1.92, scope: "monthly_spend" },
  ],
};

/**
 * The all-surface request backstop, per tier.
 *
 * Unlike `perSurface`, this one scales with the tier: it is the "client looping
 * slowly" guard, and a premium subscriber legitimately makes more calls. The
 * per-surface rules stay flat on purpose — they are blast-radius limits, and
 * how many times an hour somebody may rewrite their week is not something a
 * subscription should buy more of.
 */
const TIER_DAILY_REQUESTS: Record<Tier, number> = {
  free: 40,
  standard: 120,
  sharp: 240,
};

export interface LimitConfig {
  /** One rule per surface, sized to that surface's real call profile. */
  perSurface: Record<Surface, RateRule>;
  /**
   * A backstop across all surfaces, for a client that loops slowly enough to
   * stay under every individual window.
   */
  dailyRequests: RateRule;
  /**
   * The money ceilings, evaluated together. Every rule must pass; the one that
   * clears LAST is the one reported, so `retryAfterSeconds` is never optimistic.
   */
  spend: SpendRule[];
  /**
   * Used only when the provider does not report a cost, so that an unreported
   * generation still moves the user toward the cap instead of being free.
   */
  fallbackCreditsPerMillionTokens: number;
}

/**
 * Sized from the real call profile (docs/architecture/plan-generation.md):
 *
 * - `intake` is one cheap chat turn. Onboarding is four to six turns, and a
 *   runner may restart it. Generous, short window: it must feel instant.
 * - `week` is one call per week of the block, generated a week ahead, with up
 *   to two validator-driven attempts. 12/h covers backfilling several weeks
 *   at once plus retries.
 * - `skeleton` is generated once per training block (every 8 to 20 weeks) with
 *   up to two attempts. It is the most expensive single call, so it gets the
 *   tightest allowance — enough to re-plan a few times while onboarding.
 * - `adapt` is a runner typing a request. A handful a week is real use.
 * - `chat` is the cheapest call and the most frequent: a runner talking. 15 in
 *   five minutes is a message every twenty seconds sustained, which is faster
 *   than anyone converses, so it never binds in real use. What actually bounds
 *   a long conversation is the spend cap, because the prompt carries the brief
 *   and the history and grows with the exchange.
 * - `summarise` is not a runner action at all: the app condenses a conversation
 *   when one ends. Six an hour covers six conversations plus a retry, and it is
 *   deliberately too low to summarise after every turn — that would be a
 *   re-encode loop, and it is the design this surface exists to avoid.
 * - `log_run` follows a chat turn in which the runner said what they ran, so it
 *   is bounded by how often anyone reports a run: a handful a week.
 *
 * These are per-surface on purpose: a flat limit either strangles plan
 * generation or leaves chat wide open.
 */
export const DEFAULT_LIMITS: LimitConfig = {
  perSurface: {
    intake: { windowSeconds: 300, max: 12 },
    skeleton: { windowSeconds: 3600, max: 6 },
    week: { windowSeconds: 3600, max: 12 },
    adapt: { windowSeconds: 3600, max: 10 },
    chat: { windowSeconds: 300, max: 15 },
    summarise: { windowSeconds: 3600, max: 6 },
    // A runner telling the coach what they ran. Bounded like `adapt`: a
    // handful a week is real use, and the cap is generous enough that
    // correcting a mis-heard run twice in a row never binds.
    log_run: { windowSeconds: 3600, max: 10 },
    // Correcting a run the coach mis-heard, or that the runner got wrong.
    // Bounded like log_run: it follows a chat turn, so it is limited by
    // how often anyone talks about a run rather than by cost.
    edit_run: { windowSeconds: 3600, max: 10 },
    // Changing what the plan is aimed at. Tighter than the rest on purpose:
    // this is not a cost limit, it is a blast-radius limit. Every accepted one
    // supersedes a block, and a runner who has legitimately changed their mind
    // four times in an hour has not changed their mind, something is looping.
    set_goal: { windowSeconds: 3600, max: 4 },
    // A lifter talking. Sized like `chat` for the same reason: a message every
    // twenty seconds sustained is faster than anyone converses, so the rate
    // never binds in real use and the spend cap is what actually bounds a long
    // conversation. Its own window rather than a shared one, because a lifter
    // who also runs would otherwise spend one allowance on two coaches.
    lift_chat: { windowSeconds: 300, max: 15 },
    // Not a lifter action: the coach rewrites its own memory when the
    // transcript has run ahead of it, roughly once every REGENERATE_AFTER
    // turns. Six an hour is far more headroom than that needs, and it is
    // deliberately too low to rewrite the memory after every turn — that is a
    // re-encode loop, and it is the design the two-tier memory exists to avoid.
    lift_summarise: { windowSeconds: 3600, max: 6 },
    // Onboarding, four to six turns, and a lifter may restart it. Generous and
    // short like Run's `intake`: it must feel instant.
    // Building a plan is a deliberate act, not something anybody does in a
    // loop. Six an hour covers a first attempt, two validator retries and
    // somebody changing their mind twice.
    lift_plan: { windowSeconds: 3600, max: 6 },
    lift_intake: { windowSeconds: 300, max: 12 },
    // The block's arc, laid out once per block (every 8 to 16 weeks) with up to
    // two validator-driven attempts. The tightest allowance of the three —
    // enough to re-plan a few times while onboarding, and no more.
    // One call per week of the block, generated a week ahead, up to two
    // attempts. 12/h covers backfilling several weeks at once plus retries.
    // A lifter standing in front of a machine somebody else is on. An hour
    // window rather than five minutes because that is the shape of the use:
    // two or three swaps spread across a session, not a burst. Twelve covers a
    // whole session's worth plus retries, and is low enough that a client bug
    // cannot loop on it.
    lift_swap: { windowSeconds: 3600, max: 12 },
    // Changing the week ahead. Tighter than the rest on purpose, and not for
    // cost: this is a blast-radius limit. Every accepted change edits a block
    // somebody is working through, and a lifter who has legitimately
    // rearranged their week six times in an hour has not rearranged it,
    // something is looping.
  },
  dailyRequests: { windowSeconds: DAY_SECONDS, max: TIER_DAILY_REQUESTS.standard },
  spend: TIER_SPEND.standard,
  fallbackCreditsPerMillionTokens: 1.0,
};

/** Which secret tunes which spend window, and the per-tier form of each. */
const SPEND_ENV_KEYS: Record<string, string> = {
  daily_spend: "COACH_DAILY_SPEND_LIMIT",
  weekly_spend: "COACH_WEEKLY_SPEND_LIMIT",
  monthly_spend: "COACH_MONTHLY_SPEND_LIMIT",
};

/**
 * Reads the tunable ceilings from the environment. Everything is optional;
 * a missing, unparseable or negative value keeps the default rather than
 * becoming 0 (which would deny every request) or NaN (which would allow
 * every request — the dangerous direction).
 */
export function configFromEnv(
  get: (key: string) => string | undefined,
  tier: Tier = "free",
): LimitConfig {
  const shipped = TIER_SPEND[tier] ?? TIER_SPEND.free;
  return {
    ...DEFAULT_LIMITS,
    dailyRequests: {
      ...DEFAULT_LIMITS.dailyRequests,
      max: positiveNumber(
        get(`COACH_DAILY_REQUEST_LIMIT_${tier.toUpperCase()}`) ??
          get("COACH_DAILY_REQUEST_LIMIT"),
        TIER_DAILY_REQUESTS[tier] ?? TIER_DAILY_REQUESTS.free,
      ),
    },
    spend: shipped.map((rule) => {
      const key = SPEND_ENV_KEYS[rule.scope];
      // Tier-specific secret wins; the shipped tier default is the fallback.
      const resolved = positiveNumber(
        get(`${key}_${tier.toUpperCase()}`),
        rule.credits,
      );
      // The legacy un-suffixed secret predates tiers and may still be set. It
      // is honoured as a CEILING rather than a value, so an old global can only
      // ever tighten. Letting it win outright would hand the free tier whatever
      // number was chosen when there was only one, which is the direction that
      // costs money.
      const legacy = get(key);
      if (legacy === undefined) return { ...rule, credits: resolved };
      const capped = positiveNumber(legacy, resolved);
      return { ...rule, credits: Math.min(resolved, capped) };
    }),
    fallbackCreditsPerMillionTokens: positiveNumber(
      get("COACH_FALLBACK_CREDITS_PER_MTOK"),
      DEFAULT_LIMITS.fallbackCreditsPerMillionTokens,
    ),
  };
}

function positiveNumber(raw: string | undefined, fallback: number): number {
  if (raw === undefined) return fallback;
  const n = Number(raw.trim());
  if (!Number.isFinite(n) || n <= 0) return fallback;
  return n;
}

/**
 * One previously recorded model call. Timestamps, a surface, and a cost —
 * nothing else exists here to leak.
 */
export interface UsageRow {
  atMs: number;
  surface: string;
  costCredits: number;
}

/**
 * How far back the store must read for `decide` to be able to answer. Always
 * at least the spend period, since that is the longest-lived counter.
 */
export function lookbackSeconds(config: LimitConfig): number {
  const windows = [
    config.dailyRequests.windowSeconds,
    ...SURFACE_NAMES.map((s) => config.perSurface[s].windowSeconds),
    ...config.spend.map((r) => r.windowSeconds),
    DAY_SECONDS,
  ];
  return Math.max(...windows);
}

export type DenialCode = "rate_limited" | "spend_cap_reached";

/**
 * A refusal the app can render. `scope` names which ceiling bound, so the UI
 * can be specific ("too many plan changes" vs "daily coaching budget").
 */
export interface Denial {
  error: DenialCode;
  scope: string;
  retryAfterSeconds: number;
}

export type Decision = { allowed: true } | ({ allowed: false } & Denial);

const ALLOWED: Decision = { allowed: true };

/**
 * May this request spend model tokens?
 *
 * Checks the hardest ceiling first so the reported `retryAfterSeconds` is the
 * time until the request would *actually* succeed: clearing a five-minute
 * chat window is pointless if the daily spend cap still binds for hours.
 */
export function decide(
  surface: Surface,
  rows: readonly UsageRow[],
  nowMs: number,
  config: LimitConfig,
): Decision {
  const spend = spendDenial(rows, nowMs, config);
  if (spend) return { allowed: false, ...spend };

  const daily = rateDenial(
    rows,
    nowMs,
    config.dailyRequests,
    "daily_requests",
    null,
  );
  if (daily) return { allowed: false, ...daily };

  const perSurface = rateDenial(
    rows,
    nowMs,
    config.perSurface[surface],
    surface,
    surface,
  );
  if (perSurface) return { allowed: false, ...perSurface };

  return ALLOWED;
}

/**
 * Count the calls inside the window; if the allowance is used up, work out
 * when enough of them will have aged out for this request to fit.
 */
function rateDenial(
  rows: readonly UsageRow[],
  nowMs: number,
  rule: RateRule,
  scope: string,
  onlySurface: string | null,
): Denial | null {
  const windowMs = rule.windowSeconds * 1000;
  const inWindow = rows
    .filter((r) =>
      r.atMs > nowMs - windowMs && (onlySurface === null ||
        r.surface === onlySurface)
    )
    .sort((a, b) => a.atMs - b.atMs);

  if (inWindow.length < rule.max) return null;
  if (rule.max <= 0) {
    return {
      error: "rate_limited",
      scope,
      retryAfterSeconds: rule.windowSeconds,
    };
  }

  // We are `inWindow.length - max + 1` calls over the line, so the request
  // fits once the row at that index (0-based, oldest first) leaves the window.
  const blocker = inWindow[inWindow.length - rule.max];
  return {
    error: "rate_limited",
    scope,
    retryAfterSeconds: secondsUntil(blocker.atMs + windowMs, nowMs),
  };
}

/**
 * The money ceilings. Every window must pass.
 *
 * When more than one is breached the one that clears LAST is reported, because
 * that is when the request would actually succeed — telling a runner to come
 * back in an hour for a daily cap, while the monthly cap still binds for a
 * fortnight, would be a lie the UI then repeats.
 */
function spendDenial(
  rows: readonly UsageRow[],
  nowMs: number,
  config: LimitConfig,
): Denial | null {
  let binding: Denial | null = null;
  for (const rule of config.spend) {
    const denial = spendDenialFor(rows, nowMs, rule);
    if (
      denial &&
      (!binding || denial.retryAfterSeconds > binding.retryAfterSeconds)
    ) {
      binding = denial;
    }
  }
  return binding;
}

/**
 * One ceiling. Clears when enough of the oldest cost has aged out of the window
 * to leave room under the cap.
 */
function spendDenialFor(
  rows: readonly UsageRow[],
  nowMs: number,
  rule: SpendRule,
): Denial | null {
  const windowMs = rule.windowSeconds * 1000;
  const inWindow = rows
    .filter((r) => r.atMs > nowMs - windowMs)
    .sort((a, b) => a.atMs - b.atMs);

  let spent = inWindow.reduce((sum, r) => sum + Math.max(0, r.costCredits), 0);
  if (spent < rule.credits) return null;

  const scope = rule.scope;
  if (rule.credits <= 0) {
    return {
      error: "spend_cap_reached",
      scope,
      retryAfterSeconds: rule.windowSeconds,
    };
  }

  for (const row of inWindow) {
    spent -= Math.max(0, row.costCredits);
    if (spent < rule.credits) {
      return {
        error: "spend_cap_reached",
        scope,
        retryAfterSeconds: secondsUntil(row.atMs + windowMs, nowMs),
      };
    }
  }
  // Dropping every row must get under any positive cap, so this is unreachable
  // in practice; answer with the full window rather than a bogus 0.
  return {
    error: "spend_cap_reached",
    scope,
    retryAfterSeconds: rule.windowSeconds,
  };
}

function secondsUntil(whenMs: number, nowMs: number): number {
  return Math.max(1, Math.ceil((whenMs - nowMs) / 1000));
}

// ---- usage accounting ------------------------------------------------------

/** What we record about one model call. Token counts and money, no content. */
export interface RecordedUsage {
  promptTokens: number;
  completionTokens: number;
  totalTokens: number;
  costCredits: number;
  /**
   * True when the provider did not report a cost and we derived one. Recorded
   * so a spend figure is never silently mistaken for a billed amount.
   */
  costEstimated: boolean;
}

export const ZERO_USAGE: RecordedUsage = {
  promptTokens: 0,
  completionTokens: 0,
  totalTokens: 0,
  costCredits: 0,
  costEstimated: false,
};

/**
 * Reads the provider's usage block.
 *
 * OpenRouter includes `usage` on every chat-completion response, with native
 * token counts and `cost` — the credits actually charged to the account. That
 * is what we bill against: it is a real figure from the gateway, so the cap
 * stays correct across model and provider swaps without this file ever
 * knowing a price list (ADR-0007 keeps the model a server-side choice).
 *
 * If `cost` is absent we do not treat the call as free — that would be a hole
 * in the cap. We estimate from tokens, and if even tokens are missing we
 * assume the surface spent its whole `max_tokens` budget. Both cases are
 * flagged `costEstimated`.
 */
export function usageFromResponse(
  usage: unknown,
  opts: {
    creditsPerMillionTokens: number;
    assumedTokensWhenUnknown: number;
  },
): RecordedUsage {
  const u = (typeof usage === "object" && usage !== null)
    ? usage as Record<string, unknown>
    : {};

  const promptTokens = count(u.prompt_tokens);
  const completionTokens = count(u.completion_tokens);
  const reportedTotal = count(u.total_tokens);
  const totalTokens = reportedTotal > 0
    ? reportedTotal
    : promptTokens + completionTokens;

  const reportedCost = u.cost;
  if (typeof reportedCost === "number" && Number.isFinite(reportedCost)) {
    return {
      promptTokens,
      completionTokens,
      totalTokens,
      costCredits: Math.max(0, reportedCost),
      costEstimated: false,
    };
  }

  const billableTokens = totalTokens > 0
    ? totalTokens
    : Math.max(0, opts.assumedTokensWhenUnknown);
  const rate = Math.max(0, opts.creditsPerMillionTokens);
  return {
    promptTokens,
    completionTokens,
    totalTokens,
    costCredits: (billableTokens / 1_000_000) * rate,
    costEstimated: true,
  };
}

function count(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) && value > 0
    ? Math.round(value)
    : 0;
}
