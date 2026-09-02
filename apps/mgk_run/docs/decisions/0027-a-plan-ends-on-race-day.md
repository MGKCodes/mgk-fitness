# 0027 — A plan ends on race day, and the runner says how

**Status:** Accepted

## Context

A training plan is aimed at something. Sixteen weeks of a marathon block exist
because there is a marathon on a Sunday in April, and every number in the plan
— the ramp, the peak, the taper — is derived by counting backwards from that
date ([ADR-0011](0011-a-plan-has-a-shape.md) is where the counting-backwards
became conditional rather than universal).

**The app had nothing for the day it arrived at.** Race day was the last row of
the last week: a Sunday with a distance on it, drawn by the same card and in the
same words as the Tuesday before. There was no result, no time, no
acknowledgement that the block had concluded, and nothing that said the plan was
over.

Three things were missing, and they are separable:

**Nothing marked the day.** `HomeTodayTile` rendered a prescription and an
effort cue. A runner opening the app on the morning of their first marathon got
"42 km · comfortably hard", which is both true and the wrong sentence.

**Nothing recorded the result.** The app knew the distance the runner had
entered for and knew, from its own log, that they had run something that day. It
put the two together nowhere. A runner's own marathon time — the number they
will still know in ten years — existed in the app only as an ordinary run in an
ordinary list.

**Nothing ended the plan.** `Plans.status` has documented
`active | superseded | completed | abandoned` since the table was written.
Grepping the app finds two of those four: `savePlan` writes `superseded` on
whatever was active, and the column defaults to `active`. **Nothing has ever
written `completed` or `abandoned`.** A finished block therefore stayed the
runner's active plan indefinitely — until they built another one, at which point
sixteen weeks of training ended by being quietly demoted by an unrelated action.

The downstream costs of the third one are the expensive ones, because they are
invisible. `CoachBrief` kept briefing against a marathon that had already
happened, complete with a countdown that went negative. `PlanRecord.outcome`
inferred "raced" from `eventDate.isBefore(endedAt)`, which is a statement about
whether the plan survived until the date and *not* about whether the runner
started. And a plan with no successor had no `endedAt` at all, so a runner who
ran their marathon and has not started anything since had a plan indistinguishable
from the one they are on.

## Decision

**A block ends at its race. The runner says what happened, and if they never do,
the app closes the plan from the log.**

Three answers, in the order the questions arrive.

### 1. The result is read from the log and confirmed by the runner

A run recorded on the event date **is** the result. Nothing is typed. That is
[ADR-0017](0017-the-coach-is-the-entry-point.md) applied to the biggest day in
the plan: completion is observed rather than asserted, and a runner who tracked
their own marathon should not have to enter it a second time.

The time is **editable before it is confirmed**, and that is the substance of
this clause rather than a convenience. In a chip-timed race the watch starts in
the pen and stops at the barrier; the certificate says something else. The gap
is routinely a minute and occasionally much more. **Neither number is wrong**,
and treating the disagreement as an error would be the app being confidently
incorrect about the one figure the runner cares most about. So both are kept:
the confirmed time is the result, and what the phone made of it is shown beside
it, labelled as the phone's.

The **race distance is the goal distance, never the trace's.** A marathon whose
watch read 42.61 km is a marathon; the extra 400 m is weaving, missed tangents
and the walk to the barrier. Reporting the trace as the distance would give
every runner a slightly different marathon and make the pace figure meaningless.

Read-with-an-override, rather than either pure alternative:

- **Read only** cannot express a chip time, cannot serve a runner who raced on a
  watch, and would let a later edit to the run silently rewrite their marathon.
- **Entered only** asks a runner who has just run 42 km to type a number the app
  is already holding, which is the sort of thing that makes an app feel like
  paperwork.

### 2. The confirmed result is stored, not re-derived

Two nullable columns on `plans`, schema 10: `finished_at` and `race_time_s`.

This is a **deliberate exception** to the standing rule in this codebase that a
derived fact should not be stored twice — the rule `plan_history.dart` states
about `supersededAt` and `best_effort.dart` states about records. It is an
exception for a specific reason: a race result is not a derivation, it is
something the runner **agreed to**. `RunEditor` refuses to silently repair an
invalid draft on the grounds that it would make the confirmation a description
of something other than what got written; the same argument applies here, in the
other direction. If the number is re-derived, then correcting the run's distance
([ADR-0016](0016-a-run-is-editable-its-trace-is-not.md) explicitly permits it)
or deleting the run a year later changes what their marathon was.

There is no `race_distance_m` column and no `race_run_id` column. The distance
is the plan's goal by definition, and the run is findable by date; storing
either would be the duplication this exception does not extend to.

### 3. The plan ends when the runner closes it, and by itself if they never do

Race day passing leaves the plan **active and asking**. Home's Today card is
replaced by "How did the marathon go?" with two answers — a time, or "I did not
race in the end" — and it keeps asking for **fourteen days**. That window is the
runner's; nothing is written without them.

After it, `overdueClosureFor` closes the plan from the log: `completed` if a run
exists on the day, `abandoned` if not.

**The runner who never races is the case this clause exists for, and it is
common.** They tear a calf in week eleven. The event is cancelled. The entry
never happened. What they do next is not tap a button; it is stop opening the
app. Without an automatic close their block stays `active` forever — the coach
briefs against a race that happened last spring, and Profile never lists it among
the things they have trained for. The automatic close can be wrong (a runner
whose phone stayed in the hotel raced and is recorded as not having), and that is
the direction the error has to fall: the alternative is the app asserting a race
nothing evidences.

`abandoned` is the wire value because it is the word the column has carried
since it was written. **No screen says it.** Injury, cancellation and a change of
mind are ordinary; `PlanOutcome.didNotRace` renders as no mark at all on Profile,
for the reason `_OutcomeMark` already gave about not turning somebody's own
history into a scoreboard.

### And a moment, assembled from what exists

Confirming pushes `PlanFinishScreen`: the result laid out the way
`RunSummaryScreen` lays out a finished run, the `BlockArc` `PlanBlockScreen`
already draws — for once at the end of its own progression rather than partway
along — the weeks, runs and distance inside the plan's own window, and one line
from the coach.

**The coach's line is derived in Dart**, like `RunNote` and `CoachNote` and for
the same reason (CLAUDE.md rule 2). This is the moment in the product where a
model would be most tempted to embellish and least checkable: sixteen weeks and
a number the runner will quote for years. What the model *does* get is the
conversation — the screen hands it an opener carrying the result, and
`CoachBrief` now carries the race, so a runner who taps "Talk it through" is
talking to a coach that already knows what they ran. No new coach mechanism.

**It is shown to a runner who did not race, too.** They trained for eleven weeks
and then could not start, and a screen that went quiet on them would be the app
agreeing that only the race counted.

## Only a block has any of this

`shapeOf` is asked **once**, in `raceOutlookFor`, and answers null for a horizon,
a rhythm and a log. `TodayView.race` is null on the overwhelming majority of days
for everybody and on every day of a rhythm runner's life, and `HomeTodayTile`
draws it or does not — so no widget learns that shapes exist, which is the
constraint ADR-0011 says erodes first.

A horizon plan whose arc runs out is **not** closed by this. It has no date to
have arrived at, so there is nothing to ask about and no evidence to close from;
a horizon that has run out of weeks is a separate problem about what a plan does
when it reaches its end without an end, and inventing an answer here would be
worse than leaving it.

## Consequences

**The plan disappears from the Plan tab when it closes**, which is correct and
is not self-evident, so the finish screen says so in a line. It is listed under
"Before this" on Profile from that moment, with its time on the row.

**The result does not reach Supabase.** `finished_at` and `race_time_s` have no
counterpart in the `run` Postgres schema, and `plan_backup_rows.dart` enumerates
columns explicitly — it also writes `status` as a literal `'active'`, and
`pushPlan` demotes every other row to `'superseded'`, so a block that finished
with a race locally reads as merely replaced on the server. This is the position
`runs.steps` and `elevation_max_m` are already in
([ADR-0024](0024-elevation-is-barometric-or-absent.md)): the schema lives in
`supabase/` at the repo root and is not this app's to change, and reaching across
that boundary for two columns is worse than documenting the gap at the seam,
which `plan_backup_rows.dart` now does.

It is, though, the **most expensive** of the three gaps rather than the cheapest.
A record is a pure function of a mirrored trace and can be recomputed; a step
count was never on the phone to begin with. A race result is a fact the runner
confirmed and nothing can rebuild it, so a restored phone gets the plan and its
arc back and loses how the block ended. When the `run` schema next moves, these
are the columns to add.

**Schema 10 does not backfill, unlike schema 9.** The difference is again the
evidence, and the line falls on schema 8's side this time. Schema 9 could
recompute a record because `run_points` held every fix of every run, so the
backfill produced the record rather than an estimate of it. Nothing on the phone
can say whether a runner with an old block on disk actually ran that race — a
run on the day is suggestive, and no run at all means nothing, since the phone
may have stayed in the hotel. Writing `completed` on that basis would file a
result on the runner's behalf for a race the app did not see, and it would then
appear in their history as a race they ran and in the coach's brief as a block
they saw through. Old plans keep their status; `overdueClosureFor` reaches any
whose race is long past on the next open, from the log, which is the same
evidence a runner would have been shown before confirming.

**A runner who drops to a shorter distance on the day is not modelled.** They
entered a marathon and ran the half; the app records a marathon plan closed with
a half marathon time, which is wrong in a way nothing on screen explains. It is
rare enough to leave, and the coach can hear about it in a sentence. If it stops
being rare, the fix is a distance on the result rather than a special case.

**`PlanOutcome` grew a fifth value.** `didNotRace` is kept apart from
`leftEarly` (they stayed on the plan to the date, which is a different runner)
and from `ended` (which means there was nothing to arrive at). Both older values
keep their inference for plans that predate this, so a history stored before
schema 10 reads exactly as it always did.

## Cost function

Judge this by whether a runner who has just finished a marathon feels the app
noticed. The counter-signal is a plan that is still counting down to a race that
happened — if `active` blocks with past event dates show up, the automatic close
is not running where it needs to.

The second signal is quieter and worth watching for: `if (race.phase == ...)`
appearing outside `home_today_tile.dart`. One card is the design; a second
surface branching on the phase means the outlook has become a shape system of
its own, which is the ADR-0011 failure with a different noun.

## Disconfirming condition

Reverse the stored result if a race result ever has to be verifiable — if a time
in this app is used as evidence by anything outside it. A confirmed number the
runner typed is exactly the wrong shape for that, and the honest version would
read from the trace and mark hand-entered results as such, which is
[ADR-0016](0016-a-run-is-editable-its-trace-is-not.md)'s disconfirming condition
arriving here as well.
