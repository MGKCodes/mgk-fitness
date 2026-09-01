# 0029 — What a tier costs, and what it buys

**Status:** Accepted
**Extends:** [0014](0014-model-is-chosen-per-surface-and-per-tier.md), [0015](0015-spend-is-capped-over-three-windows.md)

## Context

Three tiers have existed in the schema since `core.entitlements` was written —
`product in ('free', 'paid', 'premium')` — and `entitlements.ts` has always
mapped them onto the model tiers `free`, `standard` and `sharp`. What none of it
had was a price, and `plan_gate_copy.dart` said so at length: *"the tiers are not
decided yet… inventing them would ship a commercial claim nobody has agreed."*

Two consequences followed from the gap, and the second was expensive.

**The gate copy could not say what a plan cost**, so it said a plan cost
something. That was the honest placeholder and it was never meant to ship.

**The spend ceilings were flat.** `limits.ts` shipped one set of numbers for
everybody: $0.20 daily, $0.50 weekly, $0.85 monthly, marked PROVISIONAL. Since
Run gives every runner a coach on the cheapest model
([ADR-0014](0014-model-is-chosen-per-surface-and-per-tier.md)), that meant **an
unpaying runner could cost $0.85 a month against no revenue at all**, and a
paying one could cost the same against £0.71. The ceiling did not know the
difference because there was nothing to tell it.

## Decision

**£1 a month for the coach. £3 a month for the sharper one. The free tier keeps
a taste of it, and each tier's spend ceiling is sized against its own revenue.**

| `product` | Model tier | Price | Ex-VAT | Net of Apple | ~USD |
|---|---|---|---|---|---|
| `free` | `free` | — | — | — | — |
| `paid` | `standard` | £1/mo | £0.833 | £0.71 | $0.85 |
| `premium` | `sharp` | £3/mo | £2.500 | £2.13 | $2.56 |

Net is after UK VAT at 20% (included in the App Store price, remitted by Apple)
and Apple's 15% Small Business Program rate. The USD column converts at a
deliberately pessimistic **1.20**, because these figures size *ceilings*:
understating revenue makes a cap safer, and OpenRouter bills in USD credits
while the subscription is priced in sterling.

### The ceilings

Carrying [ADR-0015](0015-spend-is-capped-over-three-windows.md)'s three windows
and its 24% / 60% / 100% shape, at roughly **three quarters of net revenue**:

| Tier | Daily | Weekly | Monthly | Requests/day |
|---|---|---|---|---|
| `free` | $0.025 | $0.06 | $0.10 | 40 |
| `standard` | $0.15 | $0.38 | $0.64 | 120 |
| `sharp` | $0.46 | $1.15 | $1.92 | 240 |

ADR-0015 requires the monthly ceiling to sit *under* revenue. How far under is a
policy choice, not a derivation, and three quarters is the answer: it leaves a
quarter for Supabase, MapTiler and margin **on the worst user the tier permits**,
and these are ceilings rather than forecasts. The average sits far below; what
this buys is that the runners who do reach the ceiling are still profitable
rather than merely survivable.

**Half was tried first and was too mean to be honest.** At the $0.002 a call the
test suite assumes, it refused a day of onboarding, a plan, forty chat turns and
the memories written after it — a heavy day, but not an abusive one. As it now
stands £1 buys about one such day and £3 buys several, which is a defensible
thing for the two tiers to mean. `limits_test.ts` pins that day's cost against
each tier, so the trade-off is an assertion somebody can read rather than a
number somebody chose.

**The free tier earns nothing, so every credit it spends is acquisition cost.**
A tenth of a dollar a month is enough to meet the coach and not enough to live
on it.

### Per-surface rate limits stay flat

They are blast-radius limits, not cost limits — `limits.ts` says so of each one.
How many times an hour somebody may rewrite their week is not a thing a
subscription should buy more of. Only the money ceilings and the all-surface
daily backstop scale with the tier.

### Configuration

Each ceiling gains a tier-suffixed secret —
`COACH_MONTHLY_SPEND_LIMIT_SHARP` and so on. **The legacy un-suffixed key is
honoured as a ceiling rather than a value**, so an old global can only ever
tighten. Letting it win outright would hand the free tier whatever number was
chosen when there was one config, which is the direction that costs money.

An unknown tier resolves to `free`, and `configFromEnv`'s tier argument defaults
to `free` — the same direction as `tierFor`'s fallback, for the same reason: a
bug must not be able to bill at the sharp rate.

## Consequences

**The gate can finally say what it costs**, and `plan_gate_copy.dart`'s PRICING
block is discharged. Its test flipped from asserting no figure is quoted to
asserting the right ones are, against consts that are now the single place the
price is written.

**These are still arithmetic against a price, not measurement of what a runner
costs.** The real numbers come from `coach_usage` after live traffic, and the
model behind `COACH_MODEL` is a server-side choice `limits.ts` knows nothing
about. What is no longer provisional is that the ceilings differ by tier and
that each sits under its own revenue.

**The exchange rate is now load-bearing.** A cap sized on a strong pound stops
sitting under revenue when sterling weakens. Re-check it if the rate moves far;
the arithmetic is in `limits.ts` beside the table.

**Apple's 15% assumes the Small Business Program.** Above $1M a year it becomes
30%, net revenue falls by about 18%, and every ceiling here is wrong in the
expensive direction. A good problem, but a real one.

**Nothing here decides what `sharp` actually is.** The user-facing framing is a
1/3, 2/3, 3/3 star coach rather than a model name
([ADR-0014](0014-model-is-chosen-per-surface-and-per-tier.md)), so the model
behind each tier can move as prices do without the tier meaning anything
different. Which models those are remains a `COACH_MODEL` decision.

**It does not build the purchase.** [ADR-0028](0028-revenuecat-is-the-purchase-path.md)
chose RevenueCat; the SDK, the webhook and the products in App Store Connect are
still unbuilt. This decides what those products will say.
