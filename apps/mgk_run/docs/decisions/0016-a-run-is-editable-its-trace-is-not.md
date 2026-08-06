# 0016 — A run is editable; its trace is not

**Status:** Accepted

## Context

Runio could only record runs it watched happen. There was no way to add a
treadmill session, a race the phone sat out, or a run from before the app — and
no way to correct one it had got wrong. `RunSummary.type` already allowed
`outdoor | treadmill | manual`, so the data model had anticipated it; nothing in
the app could produce one.

That makes the log the device's record rather than the runner's, which is the
wrong way round. It also blocks the coach: "I did 5k in 26 minutes this morning"
is a thing a runner says to a coach, and the app had nowhere to put it.

Allowing edits raises the obvious question. If a runner can change the distance
of a GPS-recorded run, what happened to the run that was recorded?

## Decision

**A run's summary is the runner's account and may be corrected. Its trace is
evidence and may not.**

`AppDatabase.updateRunDetails` cannot reach `run_points` or `run_splits`. Not by
convention — the method has no path to them. `source` is absent from it too, so
provenance is not editable and a GPS run can never be laundered into a
hand-typed one or the reverse.

The consequence is deliberate: correcting the distance of a recorded run leaves
its trace saying something else. When the two disagree the runner wins for
training purposes, and the evidence stays intact underneath.

**The validator comes before the form.** `RunDraft` is pure and testable, and it
exists because it has two callers of very different trustworthiness: a person
typing into a field, who can see what they typed, and the coach proposing a run
from a sentence. The second is the model proposing, so Dart has to dispose
([ADR-0003](0003-llm-generates-validator-enforces.md)) — and the rules had to
exist *before* the conversational path did, or that path would have shipped
unguarded. It is the path where a wrong number does most damage: nobody typed
it, so nobody has reason to check it.

Its bounds are **loose on purpose**. It catches a misplaced decimal, a misheard
unit and an invented number. It does not catch slow running: a validator that
refuses a twelve-minute mile has decided what counts as a run, which is not its
job.

`RunEditor` refuses an invalid draft rather than repairing it. A silent fix would
make the confirmation a runner tapped a description of something other than what
got written.

## Obvious alternative

Make a tracked run immutable in full, and let the runner delete and re-add it.

Rejected: it loses the trace to fix a typo in the distance, which is a worse
outcome than the inconsistency it avoids. The map of where they actually ran is
the part that cannot be re-entered.

## Cost function

A recorded run whose summary has been edited is internally inconsistent, and
nothing marks it as edited — there is no provenance column for "corrected", only
for `source`. Accepted for now, because the alternative is a schema change on
both sides for a distinction that has not yet been needed. If a runner ever has
to answer "did I change this?", it becomes a column.

## Disconfirming condition

If runs are ever used as evidence for something outside the app — a race
verification, a challenge, anything where a third party trusts the number —
editable summaries stop being acceptable and the edited flag becomes mandatory.

## Consequences

- The coach's `log_run` and `edit_run` intents validate against `RunDraft`. It
  was built first for exactly that.
- Each further thing the coach may change needs **its own** validator. `RunDraft`
  covers runs and nothing else. That is not scope creep; it is the price of
  [ADR-0003](0003-llm-generates-validator-enforces.md) applied to a wider
  surface, and it is what keeps "nearly everything editable" from becoming
  "nearly everything corruptible".
