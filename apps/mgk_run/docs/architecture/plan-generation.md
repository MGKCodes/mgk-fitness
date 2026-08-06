# Plan generation

**The LLM generates. A deterministic validator enforces structure.**

Precision does not matter — a threshold pace off by a few seconds per km is
irrelevant to outcomes. **Structure matters**, and long-horizon LLM generation
degrades structurally in ways that aren't visible on inspection: the taper
quietly disappears, two hard sessions land back to back in week 9, volume jumps
35% out of a deload. An 80-session block cannot be eyeballed.

The validator is small — target ~150 lines — and is the safety net that makes
model swaps and prompt changes safe.

## Two-stage generation

### Stage 1 — Skeleton (generated once, at plan creation)

Phases (base / build / peak / taper), weekly volume targets, deload placement,
taper placement, long-run progression. This is the arc. It is shown to the user
in full so they can see what they've committed to.

### Stage 2 — Sessions (generated one week ahead)

Seven sessions for the coming week, constrained by that week's slot in the
skeleton and informed by what actually happened: completions, misses, RPE trend,
resting HR / HRV if available.

This gets both properties: the arc is visible and structurally sound, the detail
is responsive to reality.

### Persistence

The skeleton is stored once, at creation. Sessions are stored **per week, when
that week is first needed** — so "this week has no sessions yet" is a normal
state, distinct from "this week is all rest days". A rest day is the *absence* of
a session row.

A validated skeleton is **validated again before it is written** and refused if
it fails: nothing the validator would reject reaches disk, so a plan reloaded
next launch is exactly as sound as the day it was generated. There is regression
coverage for the round trip itself — save, reload, re-validate — because a lossy
round trip (a dropped deload, a truncated volume) would corrupt a block
invisibly.

Weeks are *not* re-validated on read. Validation gates what gets written; a later
tuning of `PlanRules` must not lock a runner out of a plan that was sound under
the rules it was built with.

## Validator invariants

Applied to the skeleton once, and to each generated week against its slot:

- Weekly volume increase ≤ ~10% (excepting returns from deload).
- Deload every 3–4 weeks, volume ~70% of the preceding week.
- Taper present in the final block: volume down, intensity retained.
- Never two hard sessions on consecutive days.
- Long run within a sane fraction of weekly volume, with an absolute ceiling.
- Week 1 volume close to the user's stated current volume.
- Sessions only on days the user said they're available.
- Session count matches stated days per week — **running** days; strength does
  not consume one (see [ADR-0010](../decisions/0010-strength-sessions-not-prescribed.md)).
- A strength session carries no distance, and no more of them than the runner
  asked for.

**On failure:** regenerate with the violated constraints fed back explicitly.
**Two failures:** fill the week from the skeleton — volume target, long run,
phase — with easy runs and one workout, flagged as *provisional*, and
regenerate when possible.

### The shape of a filled week

The fallback does **not** divide the remaining distance equally between the
non-long days. That produced four identical runs and a long one, which is a
number divided by four rather than a training week. Instead each day takes a
declared share of the remainder: one quality session, a short recovery run
after it, the medium-long aerobic run mid-week, and something gentler the day
before the long run.

Where the arithmetic cannot support the shape — with only two non-long days the
remainder is ~65% of the week against a long run that is 35% of it, so a shaped
share can overtake it — the shape is blended toward equal shares by the smallest
amount that keeps every session under the long run. Weeks with room keep their
shape untouched; the long run stays the week's longest session in all cases,
because the validator checks it and the plan arc shows its number.

## Pace derivation (deterministic, in Dart — not the LLM)

One input — a recent race or time trial — produces everything.

- **Riegel:** `T₂ = T₁ × (D₂/D₁)^1.06` for equivalent race times and goal
  prediction.
- Zones as a percentage of threshold pace: easy ~75–80%, marathon ~88%,
  threshold 100%, interval ~105–110%.

**Do not reproduce VDOT tables from Daniels' *Running Formula* or any published
plan schedule — they are copyrighted.** Read for principles (Daniels,
Pfitzinger), implement from formulae. Principles are not copyrightable; their
tables and specific schedules are. This matters because the repo is public. See
[ADR-0003](../decisions/0003-llm-generates-validator-enforces.md).

## Where the LLM is allowed to act

1. **Intake parsing** — conversation → structured profile.
2. **Skeleton and session generation** — subject to the validator.
3. **Adaptation** — natural language ("worked till 2am, can't run Tuesday") →
   structured diff → validator → approval UI → apply.
4. **Rationale and continuity** — why this session exists, how the week went,
   what's next.

**The model proposes, the validator disposes.** Every model output is a
structured proposal passing through the same validation as user input. The model
never writes a number directly into a plan.

## Test strategy

Generate across a matrix of input combinations
(`distance × goal × current volume × days available × block length`) and assert
**every invariant** holds. This is the regression suite for prompt and model
changes — the thing that lets you swap models without fear.
