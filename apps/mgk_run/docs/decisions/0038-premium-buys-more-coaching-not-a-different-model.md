# 0038 — Premium buys more coaching, not a different model

**Status:** Accepted. Amends the Premium half of
[ADR-0029](0029-what-a-tier-costs-and-buys.md) for 1.0.0.

## Context

Premium Coach (£2.99) is sold on both stores with the description *"A better
model behind every plan and answer."* (app-store-listing.md, store-setup.md), and
the paywall shows that line verbatim.

Neither half is true in production, found 2026-09-29:

- **Plans:** every planning surface runs on `COACH_MODEL` for every tier, by
  design ([ADR-0014](0014-model-is-chosen-per-surface-and-per-tier.md); `modelFor` in
  `supabase/functions/coach/surfaces.ts`). "Every plan" could never have been
  true.
- **Answers:** the human-facing surfaces take a tier model from
  `COACH_CHAT_MODEL_SHARP` / `_STANDARD`, falling back to `COACH_CHAT_MODEL`,
  then `COACH_MODEL`. None of the three chat secrets is set in production, so a
  £2.99 subscriber and a £0.99 one talk to the same model.

What *does* differ, once the coach function carries c708e3e, is how much
coaching each tier may use:

| | Coach (`standard`) | Premium (`sharp`) |
|---|---|---|
| Monthly spend ceiling | 0.64 credits | 1.92 credits (3×) |
| Weekly | 0.38 | 1.15 |
| Daily | 0.15 | 0.46 |
| Requests per day, all surfaces | 120 | 240 |

## Decision

**For 1.0.0, Premium Coach is the same coach with three times the monthly
allowance.** The store description changes to say exactly that
(*"Three times the coaching each month."*, 37 characters), on both stores, and
nothing in the listing or the paywall claims a different model.

No tier chat model is configured. Choosing one is a model-choice decision, and
this project decides those by bake-off against its own validator, not by picking
a name the night before submission.

## The alternatives

**Configure `COACH_CHAT_MODEL_SHARP` now and keep the description** (reworded to
answers only). Makes the claim true tonight, at the price of an unmeasured model
choice with its own cost, latency and `data_collection: "deny"` routing to check.
The right end state; the wrong way to reach it.

**Pull Premium from 1.0.0.** Honest and simple, but it throws away a tier that
has a real, enforced difference and was already configured in both stores.

## Cost function

A Premium subscriber buys headroom they may never reach. The allowance is real
and enforced server-side, but most runners will not hit Coach's ceiling, so the
tier is weaker than its old description implied. That is the price of the
description being true.

## Consequences

- The coach function must be deployed from a commit carrying c708e3e before
  review; without it (as on 2026-09-29, when production ran an older copy) the
  two tiers are identical in every respect and Premium cannot be sold honestly.
- The Play subscription benefit text changes with the App Store description.

## The disconfirming condition

Premium subscribers who never approach the Coach ceiling cancelling at the first
renewal. Then the tier needs the sharper model, chosen by bake-off, or it should
go.
