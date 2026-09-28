# 0014 — The model is chosen per surface, and per tier

**Status:** Accepted
**Extends:** [0007](0007-secrets-via-backend-proxy.md)

## Context

[ADR-0007](0007-secrets-via-backend-proxy.md) made the model a server-side
choice: one `COACH_MODEL` secret, swappable without shipping an app. That was
right and remains right. It was also too coarse, for two reasons that only
became visible once the six surfaces existed.

**Four surfaces are graded; two are not.** `intake`, `skeleton`, `week` and
`adapt` are checked by a Dart validator afterwards
([ADR-0003](0003-llm-generates-validator-enforces.md)), so a cheap model's
mistake is a caught error — the plan validator rejects it and the deterministic
builder takes over. `chat` and `summarise` have no such net: whatever the model
says is what the runner reads. `summarise` is the worse of the two, because its
output is persisted and reloaded into every later prompt, so an error compounds
rather than passing.

**Those two are also the cheapest.** `chat` allows 1024 output tokens and
`summarise` 512 — the smallest budgets of the six. The expensive one is
`skeleton` at 4096, and it is validated. So the surfaces where quality matters
most are the cheapest to improve, and the surface that costs most is the one
already protected.

The same line turns out to separate the data. Only `chat` receives the
`CoachBrief`, and only `summarise` receives a transcript; the planning surfaces
get volume, days and dates. So the validated/unvalidated boundary and the
carries-health-prose boundary are **the same boundary**.

## Decision

**`COACH_MODEL` runs the validated planning surfaces. `COACH_CHAT_MODEL` runs
`chat` and `summarise`, and may vary by tier.**

Resolution falls back at every step — tier model → `COACH_CHAT_MODEL` →
`COACH_MODEL` — so with only `COACH_MODEL` set, every surface behaves exactly as
it did before. `humanFacing` is declared on the surface itself rather than as a
second list in `index.ts`, so the two cannot drift.

**A client never names a model.** It says at most which tier it believes it is
on, and the id is resolved entirely from server-side configuration. `tierFrom`
collapses anything unrecognised — absent, misspelled, wrong type, hostile — to
the *cheapest* tier. The fallback direction is the property that matters: a bug
must not be able to bill at the dearest rate.

Tier is **not** read from the request body. It has to come from something the
runner cannot write — an entitlement keyed to a verified App Store transaction —
so until that store exists it is pinned to `free`.

### The development escape hatch

`COACH_MODEL_ALLOWLIST` lets a client name a model **by membership in a list the
server published**. It exists because comparing models is the one job this design
makes slow: every id is server-side configuration, so each experiment is a
dashboard edit and a wait, and in practice you compare two models instead of ten.

Unset means off, which is production. An id is used only if it appears verbatim,
so a client can pick a published model but never invent one. **Delete the secret
before launch**, and never put a paid tier's model on the list.

## Obvious alternative

One model for everything, and buy quality by making it better for all six.

Rejected on cost: `skeleton` is the largest budget and gains nothing from a
better model, because the validator already decides whether its output is
acceptable. Paying more for the surface that is checked, in order to improve the
surfaces that are not, is the wrong way round.

## Cost function

Measured against a live deployment: a full onboarding is about $0.0035, a chat
turn about $0.0003 at 937 prompt / 58 completion tokens, and the cheap model
passed the plan validator **first attempt** on both `skeleton` and `week`. So
the planning surfaces genuinely do not need a better model, and the split buys
quality exactly where it is unguarded.

The accepted cost is more configuration: up to five secrets rather than one, and
a resolution order somebody has to hold in their head. Mitigated by every step
falling back, so a missing secret degrades rather than fails.

## Disconfirming condition

If the cheap model starts failing the plan validator often enough that runners
routinely get provisional weeks, the planning surfaces need a better model and
the split stops paying for itself.

If a single model ever becomes cheap enough that the dearest tier's price is
irrelevant, the tier machinery is dead weight and should go.

**Amended, 2026-09-01 — there is no free tier to route.**
[ADR-0030](0030-the-coach-is-the-paid-half.md) refuses an unentitled caller on
both apps, so `tierFor` never returns `"free"` and no request is ever served on
the free tier's model. The tier itself is kept: `PRODUCT_TIERS` still maps it,
`configFromEnv` still defaults to it, and both are the cheapest-not-dearest
fallback this record asks for. It is now a floor nothing stands on rather than a
tier anybody is served from.

Everything else here is unchanged. The model is still chosen per surface and per
tier, still server-side, and an unknown product still resolves to the cheapest
thing rather than the dearest.

## Consequences

- The privacy policy must name the providers that may process health data.
  `chat` and `summarise` carry Art. 9 data, so swapping *those* to a provider
  the policy does not name is a policy change, not a configuration change. The
  planning surfaces carry no health prose and are freer to move.
- `runio.coach_summaries.model` exists to record which model wrote a summary and
  is currently always null — the app does not pass it. With two models in play
  that gap matters more than it did with one.
