# The plan model: standing, not blocked

Written before the cutover rather than after it, because the block model is
threaded through eighteen files and three tables and the second attempt at this
would be much more expensive than the first.

**Nothing is live.** No account has an active plan, the app is unreleased, and
`lift.plans` holds no rows anybody is standing in the middle of. So this is a
replacement, not a migration — no converts, no compatibility shim, no double
model. That window closes the day it ships.

---

## 1. The decision

`Plan` carries `start_date`, `weeks`, an arc of `plan_weeks` and a `completed`
status. That shape came from Runio and it is right there: a marathon plan ends
on race day, the taper only means anything relative to it, and "completed" is a
real event with a date.

Lifting has no race day. "Get stronger" does not finish, and a twelve-week block
leaves two bad answers on week thirteen — expire it and make somebody re-answer
an intake to carry on doing what they were already doing, or quietly extend it
and admit the twelve was decorative.

**A plan is a standing arrangement**: a split, the days it runs on, and what
fills each slot. Today's session is derived from it on the day.

A plan still ends when somebody replaces it — *"I don't like this split"* is a
first-class action and needs a visible door. What it no longer does is expire on
its own, and those two are different things.

## 2. What that changes about the data

The plan stops being a list of sessions and becomes the rule that produces them.

| Today | After |
|---|---|
| `lift.plans` — goal, start_date, **weeks**, status, days, weekdays, equipment, injuries | `lift.plans` — goal, **split**, weekdays, started_at, status, equipment, injuries |
| `lift.plan_weeks` — week_number, phase (base/build/peak/**deload**) | **gone** |
| `lift.plan_sessions` — a row per session for the whole block | `lift.plan_slots` — a row per movement, about two dozen, that outlive every session |

```sql
create table lift.plan_slots (
  id       text primary key,
  plan_id  text not null references lift.plans(id) on delete cascade,
  user_id  uuid not null references auth.users(id) on delete cascade,

  -- Which day of the split: 'Upper', 'Push', 'Full body A'.
  day        text     not null,
  sort_order smallint not null,

  -- The role is the plan; the movement is this month's answer to it.
  role     text not null,
  movement text not null,
  is_main  boolean not null default false,

  -- Enough to say "not moved in six sessions" without reading the whole log.
  sessions_at_same_top smallint not null default 0,
  last_top_kg          numeric,
  last_top_reps        smallint
);
```

`weeks`, `week_number`, `phase` and `scheduled_date` all go. Anything derived
from a start date is derived from the weekday instead, which is what makes a
missed fortnight cost nothing: Thursday is still Upper.

### Rows that outlive sessions

Worth saying because it is the practical payoff. `plan_sessions` had to be
written up front for the whole block, rewritten whenever anything changed, and
thrown away at the end. `plan_slots` is written once and edited only when a
movement is swapped.

## 3. What survives, and it is more than it looks

**`PlanValidator` keeps its most important job.** Its second responsibility —
*"the coach prescribes an intensity; the kilograms come from this lifter's own
logged sets, or they do not come at all"* — is about a session, not a block, and
a standing plan still produces sessions. Keep the load computation whole. Drop
only the week-shaped checks.

**`SwapSheet` already is the swap feature**, and its rule holds: the coach
proposes, nothing changes until a tap. It gains a second entry point from the
plan and an equipment framing.

**`PlanIntake` is unchanged.** The questions were never the problem — see
`intake_flow.dart`. It loses `weeks` and gains nothing.

**`session_from_plan.dart`** keeps doing exactly what it does, reading from
slots rather than from a stored session row.

## 4. What goes, and what replaces it

**`plan_adaptation.dart` / `AdaptSheet` — adapting a week — no longer has a
subject.** There is no week to adapt. What that feature was actually for is
still real, and it becomes the post-session loop: the coach reads what happened,
the lifter says how it felt, and the answer changes the next session's target.
That is the same intent with a shorter feedback cycle and no regeneration.

**Deloads stop being scheduled.** `phase = 'deload'` assumed week four of a
block, which does not exist here. Fatigue is real and still needs managing, so
the trigger moves to the same place every other trigger moved: the data.
Consecutive sessions reporting harder-than-usual, or a main lift going backwards
rather than merely flat, is a deload signal. A calendar week is not.

This is the same principle already applied twice — the load rule became a schema
property rather than a prompt instruction, and rotation became a stall count
rather than an interval.

## 5. What the research actually supports

Two things were designed on instinct and only one survived contact.

**Frequency.** Volume-equated, training frequency has close to no independent
effect on hypertrophy; its benefit is that it lets more weekly volume fit, and
twice-weekly beats once-weekly mostly in untrained lifters. The useful target is
roughly 12–20 hard sets per muscle per week. So the split is a scheduling
wrapper — which is exactly why `TrainingSplit.forDays` can be arithmetic and
must not be a model's opinion.

**Rotation.** The instinct that movements should keep changing so nothing goes
stale is *not* supported for growth: varying exercises and repeating them
produce similar hypertrophy and strength. Worse, progressive overload — which
does drive both — is impossible on a movement you keep replacing, because there
is no previous number to beat. Variation helps against detrimental adaptation
and works best planned rather than reactive.

Hence: main lifts never rotate, accessories become eligible at six sessions
without improvement, and a stalled **main** lift is deliberately not a swap
prompt. That is a programming problem — load, fatigue, sleep — and changing the
movement hides it.

Sources are in [coach-profile.md](coach-profile.md) and the meta-analyses it
cites.

## 6. Order of operations

The order matters because the middle steps are the ones that cannot be checked
without a database.

1. **Domain first, with tests.** `StandingPlan`, `MovementSlot`,
   `TrainingSplit` exist and are tested. Extend `PlanValidator`: keep the load
   computation, delete the week checks, add the standing rules (a day exists in
   the split, no day is empty, main lifts are present).
2. **Delete the block domain** — `PlanWeek`, `PlanStatus.completed`,
   `plan_adaptation.dart`, and the tests that only exist to cover them.
3. **The migration**, rehearsed locally before it goes near the linked project.
   `lift.plan_weeks` dropped, `lift.plan_sessions` dropped, `lift.plan_slots`
   created, `lift.plans` altered. Update `core.delete_account`'s enumeration —
   it sweeps app schemas by `user_id` column so a new table is covered by
   construction, but confirm rather than assume.
4. **The Edge Function surfaces.** `lift_skeleton` and `lift_adapt` emit
   block-shaped JSON against schemas in `surfaces.ts`. They need to emit slots.
   This is the step that has to be deployed in step with the app.
5. **The UI last** — `PlanSurface` gives way to `StandingPlanSurface`,
   `AdaptSheet` to the post-session review.

## 7. Open

- **Where the post-session review lives.** It is a coach conversation, so the
  sheet is the obvious home — but it fires on finishing a session rather than on
  tapping the mark, which is the first thing that opens the coach without being
  asked to.
- **Whether "Pick a different split" can override the arithmetic.** If it can,
  `forDays` stops being a guarantee and becomes a default. That may well be
  right — it is somebody's training — but it should be a decision rather than a
  side effect.
- **What `status` still means.** `draft` and `active` survive; `completed` has
  nothing to mark. `superseded` is what replacing a plan produces, and is worth
  keeping so the history of what somebody has run is not lost.
