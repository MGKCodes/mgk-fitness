# 0044 — Race week is a week of its own, and race day is on the plan

**Status:** Accepted, 2026-10-01.

## Context

Found on a phone ten days before a race. The Plan tab showed a 7 km run on the
Sunday the race was on, and nothing in that week said "race".

[ADR-0027](0027-a-plan-ends-on-race-day.md) made race day the event
rather than a training day, and it said so about one screen: what Home draws on
the morning. Three things were left as they were.

- **The plan's own screens never drew race day.** The week list, the calendar
  and the week's own screen drew whatever the stored week held for that date:
  a rest row at best.
- **A stored week is never regenerated.** A race week written before race day
  was kept clear went on holding its run on the day, for good.
- **A new race week was an ordinary week with one day blocked out.** It kept
  its quality session, and its long run moved to the last free day, which for a
  Sunday race is the Saturday. A runner was asked for a threshold run and a
  long run, and then to race.

## Decision

- **Race day is drawn as the race on every screen that draws a week.**
  "Race day", the race's name, its distance, and a time to expect. Derived from
  the profile when the week is read and never stored, so a plan built by any
  earlier build is covered when it is opened. The row is the race whatever the
  week holds for that day.
- **The time is the runner's time trial carried to the race distance by
  Riegel's formula**, rounded to the minute and said as "about". No time trial,
  no time: the row shows the name and the distance.
- **Race week is built by a rule, not proposed.** `buildRaceWeek`: easy runs
  only, each shorter than the one before, the day before off, and one fewer
  running day than usual because the race is one of them. The model is never
  asked for it. Every other week is a shape a model may improve on; this one
  has a right answer that does not depend on the runner.
- **Its distance is the taper week's, less the long run.** The race replaces
  the long run, so the week holds what the slot held outside it
  (`SkeletonWeek.beforeRaceMeters`). The week's line reads "Race week · 14 km
  before the race".
- **A race week already on disk is repaired when it is read**, if it has a
  session on race day or a long run in it. A week that has not started is
  rebuilt whole. One that is under way keeps the days already gone, exactly as
  they were, and takes the rule's week from today on.
- **The runner can still adjust it.** The validator knows race week when it is
  given a calendar: it measures the week against the smaller distance, does not
  ask for a long run, and refuses two things: a session on race day and a long
  run. A short run the day before, asked for, is allowed and stays.

## Why the repair and the validator refuse the same two things

The rule that builds race week is stricter than the test that decides whether a
stored one needs repairing. It rests the day before and keeps everything easy;
the test only looks for a run on race day or a long run.

That gap is deliberate. If the repair were as strict as the builder, a runner
who asked the coach for a shake-out on the Saturday would get it, approve it,
and find it gone the next time the week was read. The repair may only undo what
the validator would have refused.

## What it costs

- **The plan arc's number for the last week is no longer what the week runs.**
  The skeleton still says the taper week's full distance; the week itself is
  that less the long run. Stored skeletons are not rewritten. The week's own
  line states the smaller figure.
- **A parameter nothing sends.** `PlanClient.proposeWeek` keeps `raceWeekday`
  because the deployed coach function reads it and builds already on phones
  send it. Nothing in this build does.
- **The prediction is one result through one formula.** It ignores the course,
  the weather and sixteen weeks of training since the time trial. It will be
  slow for a runner who has improved. "About", and the words "on your time
  trial" on the week's screen, are the honest limit of what it knows.

## What it does not do

It does not tell the model, when the runner adjusts race week, that it is race
week. The validator refuses a long run and the runner is told why, but a model
that knew would not propose one. The adjust prompt lives in the coach function
and that is a deploy; recorded in [after-1.0.0.md](../after-1.0.0.md).

It does not handle a race in the first days of a week well: a Monday or Tuesday
race leaves an empty race week, and the taper is whatever the week before held.

## Disconfirming condition

A runner on the sitting, or after launch, whose race week reads as too little:
the last run two days out, three short runs in a week that used to hold five.
The shape is conventional but the distances come from arithmetic on the taper
slot, not from anyone's coaching. If it reads wrong, the weights in
`buildRaceWeek` are the thing to change, not the rule that race week is built
by one.
