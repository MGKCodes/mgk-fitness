# 0013 — Page every PostgREST read

**Status:** Accepted

## Context

PostgREST answers an unbounded `select()` with at most 1000 rows and says
nothing about it. No error, no header the client checks, no flag — just a
shorter list that looks complete.

This was found by restoring real data and **counting the result against the
server's own count**, rather than by checking that the restore "worked". A
seeded run holding 1081 trace points came back with exactly 1000. Across the
account, 1859 points restored as 1778. Every number looked plausible.

Two places it mattered, and one had already shipped:

- `SupabaseRestore` — a truncated trace draws as a route that simply stops.
- `SupabaseRunRepository.fetchRunDetail` — the existing read behind the run map,
  with the same unbounded select on `run_points`. Any long run had been drawing
  a partial route.

The worst case is `coach_turns`. Retention caps a transcript at **1000 turns**,
which is precisely the boundary: a runner at their limit would have lost the
oldest of their own conversation, with nothing anywhere to indicate it had gone.

## Decision

**Any read that can exceed a thousand rows pages explicitly**, via
`fetchAllPages` in `lib/src/core/supabase/paged_select.dart`. A page shorter
than the page size is the end; anything else is another request.

It takes a **closure** rather than a query object, because PostgREST builders
are single-use: `.range()` has to be applied to a freshly built query each time,
and reusing one returns the first page for ever.

## Obvious alternative

Raise the limit server-side (`db-max-rows`), or pass a large `.range()` once.

Rejected: both move the cliff rather than removing it, and leave the same silent
truncation waiting at the new number. A limit that fails loudly would be
tolerable; one that fails by returning plausible data is not.

## Cost function

Paging costs an extra round trip per thousand rows, which for a trace is one or
two. Accepted, because the alternative is data that is quietly wrong in a way no
test asserting "it worked" will ever catch.

## Disconfirming condition

If PostgREST ever signals truncation in a way the client library surfaces as an
error, the explicit paging can be replaced by trusting that signal.

## Consequences

- New Supabase reads are reviewed for this. An unbounded `.select()` on a table
  that can hold more than a thousand rows per runner is a defect, not a style
  preference.
- Tests that assert "some rows came back" do not catch it. The assertion has to
  be against a known count.
