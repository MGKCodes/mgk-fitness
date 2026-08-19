# Coach evals

Ten scenarios, nine rules, run against the **deployed** `coach` function by a
dedicated account. Answers the one question the unit tests cannot: not "does it
answer" but "is the answer allowed".

    deno task eval            # run, print a table, write a dated record
    deno task eval --only=joint-pain

## Why this exists separately from the tests

`limits_test.ts`, `entitlements_test.ts` and the 33 pgTAP tests assert exact
outcomes over fixed inputs, so they are free, instant and either green or a bug.
None of them can tell you the coach told somebody to put 140 kg on a bar they
have never pressed 90 on, because that reply is a well-formed 200 OK.

## It is a measurement, never a gate

A judged rule can mark a good answer down, perhaps one run in twenty. That is
fine for a number you watch and fatal for something that blocks a release: a
check that goes red for no reason is ignored within a fortnight, and an ignored
check is worse than none because it looks like coverage.

So: **read the trend, not the run.** 27/30 this week and 22/30 after a prompt
change is the signal. One red on one scenario is a thing to go and read.

The `CHECKED` rules in `rules.ts` are different — they are arithmetic and cannot
be flaky. Those are safe to gate on, and anything that can be moved from
`JUDGED` to `CHECKED` should be.

## Cost

`COACH_MODEL` is $0.25/$1.50 per million tokens. A scenario is two calls — the
coach and the judge — at roughly 4k in / 300 out and 1.5k in / 150 out, so about
**$0.002 a scenario** and around **5p a full run**. Running it daily for a year
costs less than a month of the Supabase project.

Cost is not the reason to run it rarely. Flakiness is the reason not to gate on
it. Those are different things, and conflating them is how this ends up running
once and never again.

## Isolation: an account, not a surface

Evals go through `lift_chat`, exactly as a lifter does. A separate `lift_eval`
surface was considered and rejected — it would exercise a different prompt,
different `maxTokens` and a different schema, so a green run would say nothing
about what users hit.

Isolation comes from the **account** instead, which is enough because
`limits.ts` is per-user with per-surface thresholds:

- the eval account has its own rate-limit window, so a run cannot throttle a
  real lifter, and a real lifter cannot make a run fail
- it has its own rolling spend cap
- `coach.usage` carries `user_id`, so eval spend is separable from real spend
  with one query and no new plumbing

The account needs the Lift entitlement, because the coach is the paid half and a
`402` would otherwise be the only thing this ever measured.

## The log is part of the scenario

The coach reads the training log under the caller's own JWT. An eval that does
not control that log is measuring the account's history rather than the coach,
and the result drifts every time somebody uses the account. The runner therefore
seeds `lift.workouts` / `lift.exercises` / `lift.sets` from the scenario's `log`
and clears it afterwards.

**Clearing between scenarios matters more than it looks.** `coach.summaries` is
regenerated from the transcript, so a memory formed during `joint-pain` is still
there for `empty-log` and quietly makes the empty-log scenario not empty.

## Reading a record

Records are written to `records/<date>.md`, dated and committed, for the same
reason the screenshot folders are: the value is in the comparison, and a result
nobody kept is a result nobody learned from.

A red tells you which rule and why, never which wording. If you find yourself
arguing with a judged red, that is usually a sign the rule is phrased as a taste
rather than a boundary — fix the rule, not the reply.
