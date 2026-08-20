# Training claims this app is built on

**The claims now live in `supabase/knowledge/`, one file each, and are synced
into `coach.knowledge` so they can be corrected without shipping an app.** This
file is the explainer; the files are the source and the table is the delivery.

    supabase/knowledge/claims/     research, with sources and a date
    supabase/knowledge/guidance/   coaching prose, checked against the product
    deno task sync                 push them to the database

## Why the table, and why the repo is still the source

Guidance shapes what the coach tells somebody to do, and it goes out of date. In
Dart it ships on the app's cadence and needs a store review to correct. In the
Edge Function's source it needs a function deploy, which is faster but still
couples a wording fix to whatever else is unreleased.

In a table it changes when somebody changes it. But advice that shapes
somebody's training should be reviewable and diffable, so it is authored as
files, reviewed as a diff, and pushed with a script. Git is the record; the
table is how it gets there.

## What every claim carries

What it rests on, how confident that is, when it was last checked, **what in the
code depends on it**, and what breaks if it turns out to be wrong.

That last one is why this exists. A claim went stale inside a fortnight of being
used: `TrainingSplit` and `PlanShape` were both written citing "twice a week
beats once a week", which is a real 2016 finding that a later review by the same
group substantially walked back. The code did not say where the claim came from,
so nothing pointed at what to re-check. The sync refuses a claim with no date
and no source, so that cannot recur.

**Re-check anything older than a year.** Training science moves slowly, but it
moves. A dated claim can be audited; an undated one is folklore.

## The claims, at a glance

| | claim | confidence |
|---|---|---|
| c1 | weekly volume drives hypertrophy, ~12-20 sets | high direction, moderate numbers |
| c2 | frequency, volume-equated, does little | moderate-high — **supersedes** the 2016 result |
| c3 | one session is a poor delivery vehicle | moderate — reasoning, not a result |
| c4 | variation does not beat consistency | moderate |
| c5 | progressive overload is necessary | high |

`c3` is the weakest thing the app enforces and the first to revisit: it is
stricter than `c2` justifies on its own, and it is what rejects a bro split.

## Not a research claim: how a week is shaped

**`TrainingSplit.forDays` is arithmetic, not evidence.** Five training days does
not divide into a three-day Push/Pull/Legs rotation: pinned to fixed weekdays it
comes out P, P, L, P, P and trains legs once that week. That follows from the
model, not from a study, and an earlier commit message that attributed it to
"the evidence" was wrong.

**A known modelling limit.** A plan here is a fixed set of weekdays, so a
*rolling* cycle — PPL repeating every third session regardless of what day it
lands on, which is how plenty of people run it — cannot be expressed at all.
Anybody training five days a week on a rolling PPL is served an upper/lower
instead. That is a real limitation rather than a considered position, and it is
worth revisiting before anybody calls the planner finished.
