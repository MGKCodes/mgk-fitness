# 0030 — The coach is the paid half, on both apps

**Status:** Accepted
**Amends:** [0014](0014-model-is-chosen-per-surface-and-per-tier.md), [0017](0017-the-coach-is-the-entry-point.md), [0029](0029-what-a-tier-costs-and-buys.md)

## Context

Run served the coach to everybody. `tierFor` returned `"free"` for an
unentitled Run caller and `null` only for Lift, and the comment beside it
described this as a product choice: *"Run gives everyone a coach on the cheapest
model."*

**It was not a choice. It was a placeholder that outlived its excuse.** The
commit that unified the two apps behind one proxy (`a3980c4`) says what
happened in its own words — it gave Run *"the real tier lookup its code had been
hard-coding to `free`"*. There was no entitlement system, so the code hard-coded
the cheapest tier; when the real lookup arrived, the hard-coded value was
preserved as behaviour and then rationalised as intent. `tierFor`'s doc even
says so plainly, one paragraph below the claim: *"the existing behaviour of both
apps, preserved exactly… Run has never had an entitlement row to read."*

Three things made it untenable rather than merely untidy.

**It contradicted the app's own copy.** `plan_gate_copy.dart` has told runners a
plan needs a subscription since onboarding split in two
([ADR-0019](0019-onboarding-is-two-moments.md)), and `_Locked` on the last-run
card says *"Upgrade to see this stat"*. The app said the coach was paid while
the server gave it away.

**Every surface the proxy exposes is the coach.** `intake`, `skeleton`, `week`
and `adapt` are a plan; `chat`, `log_run`, `edit_run` and `set_goal` are a
conversation and the intents inside one; `summarise` is the memory written after
one. There is no non-coach use of the model, so "the coach is paid" and "model
calls are paid" are the same sentence.

**It was the only unbounded cost in the system.** A free runner spent real
credits against no revenue, and until [ADR-0029](0029-what-a-tier-costs-and-buys.md)
they spent them under the same ceiling as a paying one.

## Decision

**`tierFor` refuses an unentitled caller on both apps.** `free` is a row that
bought nothing, so it grants nothing; a missing row, an inactive status and a
failed read all resolve the same way, on either app.

Three things follow, and none of them is optional — flipping the server alone
would have made a working paywall look like broken software.

**A refusal reaches the UI as a door.** `CoachNotEntitledException` is distinct
from every other coach failure, and deliberately not a `CoachLimitException`:
that one means "come back later" and this one never clears on its own. Before
it, a 402 fell through to *"The coach hit a problem. Please try again."* — a
sentence that is untrue, invites a retry guaranteed to fail, and describes a
fault where the truth is a price.

**Nothing swallows it into a fallback.** `PlanService._safe` and
`AdaptationService` both caught everything and returned null, which means
"the model failed, use the deterministic path". An unentitled runner would have
been handed a free fallback plan — the exact thing the subscription is for —
while being told nothing. Both now rethrow.

**The app draws the door before somebody walks into it.**
`SupabaseEntitlements` reads `core.entitlements` and `HomeShell` resolves the
tier on launch, so the coach mark opens a sheet naming the price rather than a
conversation that then fails. The table is client-readable for exactly this:
`select` to `authenticated` under a row-level policy and no other grant at all,
so a client can see what it bought and cannot write what it did not.

**The client is still not the gate.** It decides what is *drawn*; the Edge
Function decides what is *allowed*. Every client-side failure path resolves to
`free`, which is safe only because a stale "locked" is corrected by the server
letting the request through — whereas a stale "unlocked" would produce a 402 at
the moment somebody tapped.

**There is no buy button yet, and deliberately not a fake one.**
[ADR-0028](0028-revenuecat-is-the-purchase-path.md) chose RevenueCat and none of
it is built, so the sheet states the price and stops. A button that cannot take
money fails at the moment somebody has decided to pay.

## Consequences

**The free tier is now the tracker, and the tracker is whole.** Recording, the
log, splits, records, elevation, the year view and the runner's entire history
cost nothing and are not degraded. What is behind the subscription is the
coach's *reading* of them, which is what
[ADR-0019](0019-onboarding-is-two-moments.md) already said the subscription
bought.

**[ADR-0017](0017-the-coach-is-the-entry-point.md) needs reading differently**,
and is amended rather than replaced. The coach is still the entry point to
*coaching*; it is no longer the entry point to the app. That job moved to the
scripted intro when onboarding split ([ADR-0019](0019-onboarding-is-two-moments.md)),
which is also why this change costs nothing at first launch: `intro_script.dart`
is a script precisely because the model cannot run before there is a session.

**[ADR-0029](0029-what-a-tier-costs-and-buys.md)'s free ceiling is now
unreachable.** It is left in `limits.ts` rather than deleted: the tier still
exists, `configFromEnv` still defaults to it, and a ceiling that can never bind
is cheaper than a `null` somebody has to handle. It is now a second line of
defence rather than a budget.

**Development does not need the free grant.** Two mechanisms already exist — the
entitlement insert in
[testflight-1.0.0-test-sheet.md](../testflight-1.0.0-test-sheet.md), and
`COACH_MODEL_ALLOWLIST` with `body.model` for the model itself.

**A runner who has paid and has no network sees a locked coach.** The read
fails to `free`, so the mark shows the gate. Acceptable, and the direction to
fail in: the alternative caches an entitlement on the device, which is a value a
client can write.

**This is a behaviour change to a shipped TestFlight build.** Build 11 served
the coach to anyone with an account. Anyone testing after this needs a row.
