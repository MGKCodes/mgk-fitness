# 0041 — Premium is a better model and a bigger allowance; which model is configuration

**Status:** Accepted. Supersedes
[ADR-0038](0038-premium-buys-more-coaching-not-a-different-model.md).

## Context

ADR-0038, written on 2026-09-29, made Premium "the same coach with three times
the coaching" because no tier chat model was configured in production, so the
store's old line — *"A better model behind every plan and answer."* — was false.
It fixed the copy to match the configuration.

The owner's intent for Premium was always the other way round: a better model,
with more room to use it. The coach goes through OpenRouter precisely so the
model can change without a store submission. So the right fix is to make the
configuration match the intent, and to describe the intent in the store rather
than a model name or a number that a configuration change would falsify.

## Decision

- **Premium is a better AI model for coach replies, with a bigger monthly
  allowance.** The store description is *"A better AI model and a bigger
  allowance."* (41 characters) on both stores; Play's benefits say the same in
  two lines. Nothing in the listing, the paywall or the review notes names a
  model or a message count.
- **The model is configuration:** `COACH_CHAT_MODEL_SHARP` on the coach
  function, read by `modelFor` for the human-facing surfaces (`chat`,
  `summarise`). Set on 2026-09-30 to `google/gemini-3.8-flash`, against
  `COACH_MODEL`'s Flash-Lite for Coach. Verified the same day by a live Premium
  chat call whose charged cost (0.00251625 credits for 1,910 + 289 tokens)
  matches 3.8 Flash's price and not Flash-Lite's (0.00091).
- **Plans are not tier-routed** ([ADR-0014](0014-model-is-chosen-per-surface-and-per-tier.md)):
  every plan is written by `COACH_MODEL` and checked by the same validator, so
  nothing may say Premium's *plans* are better.

## What keeps the description true

"Better" is a claim about configuration, so it is only as true as the secret.
Whoever changes a model checks two things:

1. `COACH_CHAT_MODEL_SHARP` is a stronger model than whatever Coach replies with
   (`COACH_CHAT_MODEL_STANDARD`, else `COACH_CHAT_MODEL`, else `COACH_MODEL`).
2. It routes under `data_collection: "deny"`, and, if OpenRouter's account-wide
   Zero Data Retention is on, it has a ZDR endpoint — otherwise every Premium
   reply fails.

"A bigger allowance" is `TIER_SPEND` and `TIER_DAILY_REQUESTS` in
`supabase/functions/coach/limits.ts` (three times Coach's monthly spend, twice
its daily requests) and holds whatever the model.

## The alternatives

**A frontier model for Premium** (e.g. Claude Sonnet 5, about eight times
Flash-Lite's price). The strongest answers, but at Premium's allowance a
subscriber would get *fewer* replies a month than Coach gives — about 120
against 320 — which is not what "a bigger allowance" should feel like. Chosen
against for launch; a configuration change away if usage says otherwise.

**Naming the model in the listing.** Ties a store field to a vendor, and every
model change becomes a store edit — the exact coupling OpenRouter was chosen to
avoid.

## The disconfirming condition

Premium subscribers reaching their allowance more often than Coach subscribers
reach theirs. Then the Premium model is too expensive for its allowance: pick a
cheaper strong model or raise `TIER_SPEND.sharp`, and this ADR's numbers go
with it.
