# 0010 — Strength sessions are scheduled, not prescribed

**Status:** Accepted

## Context

A running plan of runs alone is incomplete. Strength work reduces injury risk
and is standard in any serious block, so a plan that never mentions it is
quietly telling the runner it does not matter.

But Runio is one half of a platform with Liftio (shared account, cross-readable
data — see [ADR-0008](0008-shared-supabase-platform.md)), and Liftio's entire
subject is resistance training: sets, reps, loads, progression, and a coach of
its own that reasons about them. If Runio also prescribed lifts, the same runner
would have two apps issuing two different opinions about Wednesday, with no
mechanism to reconcile them and no shared record of what was actually lifted.

The same question came up for **treadmill sessions**, which look superficially
similar — another thing a plan might name.

## Decision

**Runio schedules strength; it never says what is in one.**

`SessionKind.strength` carries a weekday and nothing else — no distance, no
duration, no exercises. On the plan it reads "Strength" and stops there. The
runner's lifting is Liftio's subject, and this is the seam between the two
products, drawn deliberately.

Consequences that follow from strength being a session but not a run:

- `SessionKind.isRun` excludes it, so it never enters weekly volume, can never
  be selected as the week's long run, and does not consume one of the runner's
  stated `daysPerWeek` running days. `strengthDaysPerWeek` is counted separately
  and defaults to **0** — a runner who never said they lift does not find a gym
  session in their plan.
- The validator refuses a strength session carrying a distance
  (`strength_distance`) rather than zeroing it. A model that put 8 km on a gym
  session has misunderstood the week, not made a typo, and per
  [ADR-0003](0003-llm-generates-validator-enforces.md) that is exactly what the
  validator exists to catch.
- The builder places strength on an available day the runner is *not* running
  where one exists, and never the day before the long run. When every available
  day is a running day it doubles up on the quality day rather than silently
  dropping what the runner asked for — stack hard with hard, keep easy days easy.

**There is no `treadmill` session kind, and there should not be.** A treadmill is
a *venue*, not a session: a 6 km easy run is the same session indoors or out,
at the same pace, with the same training effect. A plan that prescribed the
machine would be deciding something it has no basis to decide — the runner picks
where they run based on weather, daylight, and safety, none of which the plan
knows about. A short maintenance run is already expressible: it is
`SessionKind.recovery`, which exists and carries its own pace band.

## The obvious alternative

Model strength as a first-class prescription in Runio — sets, reps, a movement
list — so the runner never leaves the app.

Rejected because it makes Runio a worse lifting app than the one the same user
already has, and creates two sources of truth for one workout. The cost of the
split is a runner who wants a prescribed session has to open Liftio; the cost of
not splitting is two coaches disagreeing, permanently.

## Cost function

Judge this decision by whether runners with `strengthDaysPerWeek > 0` treat the
slot as real — that it is honoured rather than ignored as a blank row. If an
empty "Strength" line reads as unfinished rather than as deliberate delegation,
the answer is a deep link into Liftio for that day, **not** a prescription
written in Runio.

## Disconfirming condition

Reverse this if Liftio is discontinued or the shared-account assumption in
ADR-0008 stops holding. A strength slot that delegates to an app the runner does
not have is worse than no slot at all.
