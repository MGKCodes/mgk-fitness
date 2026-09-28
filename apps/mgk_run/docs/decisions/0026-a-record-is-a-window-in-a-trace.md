# 0026 — A record is a window in a trace

**Status:** Accepted

## Context

Profile kept two records: the longest run, and the best average pace over a run.
Neither is a thing runners say to each other. What they say is "my 5K is 24:10"
— a time at one of four standard distances, 5K, 10K, half, marathon.

Adding those looks like an afternoon's work, and there is an obvious cheap
implementation: find the runs whose distance is near 10 km and take the fastest
of their times. It is wrong, and it is wrong in the shape this codebase has a
standing rule about — **a plausible wrong number is worse than no number**,
because nothing about it looks wrong.

The 23 Aug test run is the example. It covered **10.18 km in 58:28**. Treating
that as a 10K personal best reports 58:28. The runner's actual 10K — the fastest
continuous 10,000 m inside that run — was about **57:25**. So the cheap version
understates a runner's own record by a minute, silently, and the error grows
with every metre past the mark: a 21.5 km training run reported as a half
marathon is a wildly slow half marathon, and there is nothing on the screen to
say why.

Runners already know what the right answer is, because every other product
computes it this way. A best effort is a **window**, not a summary.

The second question is where it is computed. A window over a trace means walking
every point of a run — thousands of rows. Doing that when Profile opens would
mean loading every point of every run in the log on every visit to a tab, over a
log that grows forever. That is the read [ADR-0023](0023-the-log-is-read-from-the-phone.md)
took off the network; this takes the same class of read off the critical path.

## Decision

**A personal best is the fastest continuous stretch of a standard distance
inside a run, computed from the trace when the run finishes and stored.**

- **The window slides over the trace**, and it is measured by the same rules the
  run's own distance is: fixes worse than 20 m are dropped, hops under a metre
  are jitter, and a gap in the trace is not bridged. A record measured by a
  different rule than the distance would reach 10 km somewhere the run says it
  did not.
- **A window never spans a gap.** The straight line across a hole is a line
  nobody ran, and bridging it would credit the runner with the tunnel — which
  would be the fastest kilometre of any run they ever did.
- **Both edges are interpolated.** Fixes land every second or two, so snapping a
  window to whole points is tens of metres out at each end, which at 10 km is a
  real number of seconds in a direction that flatters or robs at random.
- **A run with no trace contributes nothing.** Hand-entered, imported from
  Health, a treadmill: there is no interior to search, and the whole-run time is
  **not** substituted. Two kinds of evidence in one records table is how a
  records table stops meaning anything — nothing reading it back could tell
  which number was which.
- **A run shorter than the distance contributes nothing**, which needs no
  argument.
- **Computed at `stop()`, stored in `run_best_efforts`**, beside the splits and
  the elevation figures that already come out of that same single walk over the
  persisted trace. Four numbers per run at the very most, and none at all for
  the majority.
- **The four distances are stored exactly** — 5,000, 10,000, 21,097.5 and
  42,195 m. A marathon is not 42 km, and searching for 42 km would find a window
  195 m short and report a time nobody ran. The *names* are display: `raceName`
  says "Half marathon", which is both shorter and more accurate than "21 km" or
  "13 mi".

**Schema 9 backfills, and schema 8 deliberately did not.** The difference is the
evidence. Schema 8 refused to invent a step count for an old run because there
was nothing on the phone that could produce one, so a backfill would have been
the app making up a number it was about to display as measured. That argument
does not reach this table: `run_points` already holds every fix of every run,
and the migration runs exactly the window the recorder would have run at the
finish line. The answer is not an estimate of the record, it *is* the record —
and leaving it out would mean a runner with a year of recorded running opening
Records to four dashes, over a database that could answer all four.

The backfill runs **inside the migration** rather than off the critical path,
because its cost is bounded by construction: it only ever meets a database that
predates schema 9, which is one built during this app's pre-release life. Every
run recorded afterwards has its records written when it finishes, so no future
log reaches that code however long it grows. Exactly-once is what a schema
version *is*; the alternative was a backfill fired from the composition root
that needed a new column purely to remember whether it had already run.

## Consequences

**A runner who logs their races by hand sees dashes.** Somebody who types in
their marathon has a marathon in their log and nothing beside "Marathon". This
is correct and it is not self-evident, so the records card says so in one line
whenever the log holds a run long enough to have set a record that set none.
It is the only case where the table can look wrong to a runner who knows exactly
what they ran, and it is worth a sentence rather than a support question.

The alternative — falling back to the whole-run time for untraced runs only —
was considered and refused. It would fix the one case a runner notices by
breaking the one they cannot: a hand-typed 42.4 km run would set a "marathon
record" 205 m long, and it would sit in the same column as a real one.

**Records are local-only.** `run_best_efforts` has no counterpart in the `run`
Postgres schema, and `SupabaseRunBackup` enumerates its columns explicitly, so
the mirror does not carry it — the same position `elevation_max_m` and
`runs.steps` are in ([ADR-0024](0024-elevation-is-barometric-or-absent.md)), and
for the same reason: the schema lives in `supabase/` at the repo root and is not
this app's to change.

This is the cheapest of the three gaps to live with, because a record is a pure
function of the trace and **the trace is mirrored**. Everything needed to
recompute them survives a restore, and `AppDatabase.backfillBestEfforts()` is
already that walk. Nothing calls it after a restore today, so a runner who
changes phone rebuilds their records from new runs only.

**Correcting a run's distance does not move its records.** `updateRunDetails`
cannot reach this table, exactly as it cannot reach the splits
([ADR-0016](0016-a-run-is-editable-its-trace-is-not.md)). A GPS run edited down
to 4 km keeps whatever its trace holds, including a 5 km record, because a
record is read off the evidence and not off the runner's account of it. The
backfill follows the same rule and never uses `distanceM` to rule a run out.

**Nothing here is shown on a single run's summary yet.** The efforts are carried
on `RunSummary` and read by `runDetail`, so a finished run knows what records it
set; the finish screen does not mention them. "You just set a 10K PB" is the
obvious next thing and it is a separate decision about tone, not about
measurement.

**The records section is the third thing on Profile, and it grew.** Four rows in
one card rather than four more stat cards, on the grounds that a PB table is how
runners already read these and four cards would push the year grid off the fold
to say the same thing at three times the height.
