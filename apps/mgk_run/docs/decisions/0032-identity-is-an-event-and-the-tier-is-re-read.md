# 0032 — Identity is an event, and the tier is re-read on resume

**Status:** Accepted
**Amends:** [0030](0030-the-coach-is-the-paid-half.md), [0012](0012-backup-is-consented-restore-only-adds.md) in part

## Context

Three defects on the build 13 field sheet looked like three problems:

- **A4** — the "restored your runs" message arrived over and over.
- **E1** — the backup consent prompt appeared repeatedly.
- **D14** — the coach opened from Profile on a free account.

They were one problem with two halves.

**The auth stream said that something happened, not who.** `authChanges()` was
`Stream<void>`, type-erased on the reasoning that a listener only needs to know
*that* state moved and can re-read `isSignedIn` itself. True of routing, which
was all it had when it was written. False the moment a restore was hung off it:
`onAuthStateChange` also emits `tokenRefreshed`, periodically and on every
resume, so the restore ran on a timer. A listener cannot filter what the stream
declined to tell it.

**And state was resolved once at launch.** `_access` came from `initState` and
was otherwise re-read only after an auth event or a purchase. Nothing re-read it
when the app came back.

D14 is the one worth stating carefully, because **the door was never broken**.
Every entry point already routed through `_askCoach`, which checks the tier, and
a test had pinned that since 2026-09-04. The tier it checked was stale: the test
sheet's own running order grants an entitlement row, works D1 to D13, deletes
the row, and then tries D14 — without relaunching, because nothing on the sheet
says to. That is also what a lapsed, refunded or revoked subscription looks like
to anyone who leaves the app open.

## Decision

**The stream carries an `AuthChange`** — `signedIn`, `signedOut`, `userUpdated`
— and drops everything that is not an identity change, `tokenRefreshed` above
all. De-duplication stays at the listener, keyed on the **user id** rather than
on the event: two different people signing in must both restore, and the same
person arriving twice must not.

**The tier is re-read on resume**, through the path that respects a pinned tier.
Its staleness bound is one resume rather than one launch.

**The restore is single-flight, bounded, and reports what it added.**

- Single-flight as a future rather than a flag: `_doRestoreThenLoad` has four
  exit paths, and a second caller should *join* the pull already running.
- A 20s per-step deadline, matching `AuthRepository.timeout`. It had none, and
  it is awaited on the launch path.
- It counts rows **inserted**, not rows fetched. Writes are insert-or-ignore, so
  the number handed in says nothing about the number that landed — a runner with
  21 runs on the server was told "restored 21 runs" on every launch, having
  restored nothing since the first. The count moves into `AppDatabase`, which is
  the only thing that knows.

**The local read comes first.** Everything Profile and the log draw comes from
`_allRuns`, which only `_refreshHome` fills — and it ran last, behind a modal
dialog and an unbounded network call. A runner with three years of running on
the device watched a blank page until the server answered, and indefinitely if
it never did.

## Two things this deliberately does not do

**No time-based throttle on the resume read.** It was written and removed. The
only thing a window buys is a saved round trip on one indexed row, against the
risk of drawing access the server has withdrawn — and staleness is the defect
being fixed. Single-flight instead, so a burst of resumes coalesces into one
read rather than stacking.

**The log is not refreshed on resume.** `_refreshHome` offers backup, so doing
that would put the consent dialog on screen every time the app came back.

## Consequences

- E1's real cause was neither of the above and is fixed alongside: backing out
  of the sign-up cleared the in-session flag without writing anything, so every
  later `_refreshHome` raised the dialog again — and that runs after a finished
  run, after an edit, after a unit change. The store staying unwritten is what
  keeps the question open for next launch (ADR-0012, *"they did not decline,
  they were interrupted"*); re-asking thirty seconds later is badgering.
- ADR-0012's restore is amended in part: it reports insertions, has a deadline,
  and no longer gates the first local paint.
- Two Plan-tab doors that never went through `_askCoach` are closed. Building a
  plan and adjusting a week are model calls — `skeleton`, `week` and `adapt` are
  the coach as much as `chat` is — and both were gated on having an *account*.
- **The order of the account and the price is a decision.** Naming the price
  first sounds fairer and dead-ends: `PurchaseScreen` refuses a signed-out buyer
  with *"Sign in first"* and offers no way to do it, because the webhook keys the
  row on a Supabase id and will not write one to an `RCAnonymousID:`. So the
  account comes first (ADR-0019), and the price follows immediately (ADR-0030),
  both behind one method on the shell rather than as two halves a caller could
  reassemble wrongly.

## The disconfirming condition

A runner reporting the coach still working after cancelling, or a restore
message appearing more than once for one sign-in. And the log must never wait on
the network again: `profile_paints_before_the_network_test.dart` pins it against
a restore that never completes.
