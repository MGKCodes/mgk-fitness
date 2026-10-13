# 0049 — A race is a run, with or without a plan

**Status:** Accepted. Supersedes the "only a block has any of this" section of
[ADR-0027](0027-a-plan-ends-on-race-day.md) and moves where its result is kept;
the rest of 0027 stands.

## Context

On Sunday 11 October 2026 the app's own author ran the Royal Parks Half with Run
recording. The finish was an ordinary run summary: 21.69 km in large, "Furthest
you've been", a records card reading "Fastest 5K, 10K and Half marathon yet ·
25:16" (the 25:16 was the 5K), and twenty-two split rows each ending in a dash.
The chip said 2:00:30; the phone said 2:00:47. Nothing on the screen knew a
race had happened.

ADR-0027 already had most of what was missing: a sheet that takes a chip time
and keeps the phone's beside it, and a finish screen for the block. **It was
unreachable**, because 0027 attaches a race to a plan with a date, and the
runner had no plan in the app. That is not an edge case. A runner who uses Run
to record and trains to their own schedule, or follows a plan from somewhere
else, is a normal runner, and every one of them got nothing on race day.

Even with a plan, the result was reachable only from a card on Home the day
after, and it was stored on the phone's copy of the plan and never mirrored, so
a new phone lost it. 0027 called that the most expensive of its gaps.

## Decision

**A race is something a run is.** The run row carries it: the course distance,
the official time when the runner gave one, and an optional name
(`runs.race_distance_m`, `race_time_s`, `race_name`; schema 13 on the phone,
`20261013120000_run_race_on_the_run.sql` in Postgres). Null distance is a
training run.

### How a run becomes a race

1. **After the run, by the runner.** A run within 96–108% of 5K, 10K, half or
   marathon on the phone's reckoning gets a quiet "Was this a race?" card under
   its figures. Any other outdoor run has "Mark as a race" at the foot. The
   sheet starts on the nearest distance with the phone's time in the wheels.
   A time left as the phone had it is **not** stored as official: that would
   claim a chip time the app never saw.
2. **On a plan's race day, by the app.** The run finished on a block plan's race
   date, if it is the longest of the day and at least half the race distance,
   is marked with the plan's distance and no official time. The half-distance
   floor is new: 0027 matches by day alone because the runner confirms the
   match, and an automatic mark has nobody confirming, so a 3 km shakeout
   recorded before the race existed in the log would otherwise be filed as the
   marathon.
3. **Before the run (not yet built).** A Race option on the start screen, so the
   live screen can show distance left and a projected finish. Phase two.

### The plan closes from the run, too

Saving the race sheet on the active plan's race-day run closes the plan as
raced with that time. That is the runner answering Home's "How did it go?"
from the screen they are already on, and asking again the next morning would be
the app not listening. Home's card still works, and now opens on a time already
given on the run (`raceResultFor` treats it as entered), and on confirming it
writes the time onto the run and opens the race's own screen rather than the
plan's. `PlanFinishScreen` remains for a race the phone did not record.

Clearing a race never reopens a plan.

### What a race screen shows

The same screen, drawn differently, in the order a runner asks the questions:

- the **time** in large (official, else the phone's), with the race and the pace
  over the **course** distance;
- a line saying which time it is, and what the phone had over what distance;
- **where it stands** among their races at the distance (first; fastest, by how
  much; or what the best is). First looks backwards and stays true; fastest is
  a claim about now, like `RunNote`'s records;
- the 5K and 10K records inside it, but **not** the race distance's own best
  effort, which inside an over-read trace is shorter than the course and would
  be a second, wrong, half marathon time;
- **how it was run**: the two halves' paces and a pace per 5K section
  (`raceBreakdownFor`), with one derived coach line naming a fade, a negative
  split or an even race, and the biggest drop between sections;
- **the training**: when a block plan was aimed at that day, the runs,
  distance, longest run and weekly distance inside the plan's window. **Hidden
  without a plan**, at the runner's request: a guessed window ("your last twelve
  weeks") would report a block nobody committed to;
- the run's remaining figures, notes, and the splits, folded.

### Sections are proportional, and paces only

The phone reads long in a race everywhere, not at the end (590 m over the
half, mostly in the crowd at the start). Cutting the trace at the phone's own
5 km puts the "5K" 140 m early. So checkpoints are placed at the same fraction
of the phone's distance as of the course, read off the stored splits. Against
that Sunday's chip timing, every section's pace came out within five seconds a
kilometre; checkpoint times were up to about twenty seconds early. The screen
therefore shows **paces per section, never checkpoint times**: a pace is what
the method can support. Outside 90–115% of the course the recording is not the
race (a watch left running on the walk home) and no breakdown is drawn.

### Splits fold, on every run

More than five splits fold to a one-line chart of every kilometre, the fastest
and slowest whole kilometre, and "Show all N splits". The heart-rate column is
drawn only when some split has a heart rate. The records card lists each record
with its own time.

## Consequences

**The result reaches Supabase.** Unlike 0027's plan columns, these are mirrored
and restored, so the official time survives a new phone. Order matters: the
Postgres columns must be live before a build that sends them ships, or every
run upsert fails (`pushRun` enumerates columns; this happened with
`elevation_max_m` and `steps`).

**The plan's own copy of the result is now a second copy.** `plans.race_time_s`
is still written when a plan closes, and is what Profile's plan history reads.
Correcting the official time on the run after the plan has closed does not
update it. Rare, and the run is the copy that is mirrored; if Profile is ever
moved to read the run instead, the plan column can go.

**Profile's records still fold best efforts, not races.** A half marathon PB on
Profile is the fastest 21.0975 km stretch of any trace, which for a race run is
shorter than the course and quicker than the official time. Showing race
results there is the obvious next step and is not done here.

**`RunSummaryScreen` branches on whether the run is a race.** That is the one
branch, it is on a property of the run rather than on a plan's shape, and every
race piece takes plain values (`race_parts.dart`), so no widget learns what a
block is (ADR-0011).

## Cost function

Judge this by whether a runner finishing a race with Run recording, plan or no
plan, sees a screen that knows it was a race within one tap, and whether the
time they quote matches the one the app shows after they add it.

## Disconfirming condition

If runners mark training runs as races to get the race screen (a parkrun every
Saturday would be a fair case), the race screen is doing a job the training
screen should; reconsider what the training screen shows rather than tightening
what counts as a race. If proportional sections are ever more than ten seconds
a kilometre from the chip on a real race, stop drawing them and show halves
only.
