# 0023 — The log is read from the phone

**Status:** Accepted

## Context

On 23 August 2026 Runio recorded its first real run: 10.18 km in 58:28, with
Strava alongside as a control. The recorder worked. The screen held up for an
hour. The next morning Profile said **No runs yet**.

The run was not lost. It was in the on-device database, finalised, with its
whole trace. It was invisible because of one line:

```dart
historySource: SupabaseRunRepository().fetchRuns,   // main.dart:177
```

**History was read from the backup.** So a run existed, as far as the app was
concerned, only if it had been successfully mirrored — and mirroring is optional
by design and silently failable by implementation. That gave four independent
ways for a complete, correct run to appear nowhere, and **not one of them told
anybody**:

| Trigger | What happens | What the runner sees |
|---|---|---|
| Backup consent off | `ConsentedRunBackup.pushRun` returns false | "No runs yet" |
| Offline / RLS / auth error at finish | `_backup`'s `catch (_)` swallows it | "No runs yet" |
| `backfill()` throws at launch | `unawaited`, no handler, unhandled async error | "No runs yet" |
| The read itself fails | `_refreshHome` catches and shows an empty log | "No runs yet" |

The fourth is the one that settles what happened on 23 August, and it is worth
recording because of what it says about the shape of the mistake rather than
about the typo. `fetchRuns` asked for `.schema('runSchema')` — a schema that
does not exist, left behind by the rename that moved this repo into the
monorepo. PostgREST answers `PGRST106`. So the log had been failing on **every**
launch for **every** runner since that rename, regardless of consent, signal or
anything else, and nothing anywhere said so. A read path that had been dead for
weeks looked exactly like a runner who had not been running.

That is the tell. A source of truth that is never read is a source of truth
nobody can check, and a read path that is only exercised in production fails
where nobody is watching.

### It contradicts ADR-0004

[ADR-0004](0004-offline-first-local-source-of-truth.md) makes the on-device
database the source of truth. It is written on every fix and finalised on stop.
It was complete, correct, and read by nothing. "Offline-first" described the
write path and nothing else — the app could record a run in a tunnel and then
needed a network to admit it had happened.

### It breaks the consent bargain in ADR-0012, and this is the strongest reason

[ADR-0012](0012-backup-is-consented-restore-only-adds.md) says backup is
consented: Runio holds GPS traces, heart rates, injury notes and the runner's
own sentences about their body, which under UK GDPR is special-category data
(Art. 9), and the lawful basis is explicit consent. The whole architecture of
that ADR — three-valued consent, gating by wrapper, withdrawal that erases —
exists to make declining a real, usable answer.

As built, declining meant **your own runs were invisible to you on your own
phone**.

That is not a bug in the consent flow. It is the consent being void. Consent has
to be freely given, and it is not freely given when refusing costs you the app's
central function: the switch was not "may we keep a copy?", it was "may we keep
a copy, or would you rather not see your runs?". A toggle that silently doubles
as *show me my runs* is not a privacy control; it is a price. And the runner
could not even have discovered the trade — nothing in the switch's wording, or
anywhere else, connected backup to whether the log worked, because nobody had
noticed the connection existed.

It also fails the narrower test the same ADR sets itself. `ConsentedRunBackup`
is documented as making the unsafe object unreachable so no call path can skip
the check. It did that perfectly. What it could not do is stop the *rest of the
app* from depending on the push having happened.

## Decision

**The log is read from the on-device database. Supabase is a mirror and only a
mirror.**

`historySource` is `DriftRunRepository(db).fetchRuns` — a single local query,
newest first, over runs with a non-null `endedAt`. No network is on the
path between a finished run and the log that shows it. `SupabaseRunRepository`
is deleted rather than demoted: it was the read path, it was broken, and leaving
a second way to answer "what are my runs?" is how the two answers drift apart.

Two supporting changes, because the read path was only the largest of the ways a
run could go quiet.

### A failed push is recorded, not merely survived

Every push is best-effort by contract — the run has committed locally, so a
failure costs a backup and never a run — and that stays true. What changes is
that "cannot fail the caller" stops meaning "cannot be observed by anybody".
`ReportedRunBackup` wraps the real backup and writes down what each push did;
Settings reads it and says so beside the switch that promised the backup.

A **wrapper**, for the reason ADR-0012 gives about the consent gate at greater
length: runs are pushed from the recorder on stop, the editor on add, the editor
on edit and the backfill on launch, and the coach will add more. It sits
*inside* the consent gate, so a push consent refused is never reported as a
failure — the switch working as asked is not an incident.

It is deliberately quiet. There is nothing for a runner to do about a failed
upload except be online at some point, which the next launch's backfill handles,
and a toast over a finished run would be the app apologising for something that
cost them nothing. It is discoverable, not loud.

### `backfill()` is no longer fired into the void

`unawaited(widget.runEditor?.backfill() ?? …)` with no error handler turns a
throwing backfill into an unhandled async error: nobody catches it, nothing
records it, and a runner is simply never backed up. It keeps its handler now,
and `RunEditor.backfill` documents that it never throws so a caller can rely on
it.

## Obvious alternative

**Keep reading Supabase and surface the push failures** — a retry queue, an
error state on the log, a banner when the mirror is behind.

Rejected, and the reason is the point of this ADR. It keeps the contradiction
and merely narrates it: the phone would still be asking a server what its own
runs were, and the answer would still be wrong whenever the network was. Worse,
it cannot touch the consent problem at all. A runner who declined has no rows on
the server to read, so the most honest possible error state still shows them an
empty log — and the app would now be explaining, at length, why it will not show
them their own run.

A softer version — read local, fall back to Supabase when local is empty — is
worse than either. It puts a network call on the log's path for the exact case
where a runner is most likely to be new and offline, and it needs a rule about
which copy wins, which is the conflict resolution
[ADR-0012](0012-backup-is-consented-restore-only-adds.md) deliberately does not
have. `SupabaseRestore` already covers the case it is reaching for: a reinstall
pulls the runs down into Drift at launch, before the log is loaded, and then the
local read is complete by construction.

## Cost function

**The log stops being an accidental end-to-end test of the backup.** It was one,
and that is the only reason "runs are mirrored" was ever visibly true. Now
nothing on screen changes whether or not a push lands, so a mirror could rot
without a single symptom. That is precisely what `ReportedRunBackup` is paying
for, and it is a weaker signal than the old one: it reports the last attempt, not
whether everything on the phone is safely elsewhere.

**A run that exists only in the backup is invisible until it is pulled down.**
On a reinstall, or on new hardware, the log is empty until `SupabaseRestore`
finishes — and it is gated on consent, which on a new device arrives unset, so
the true order is ask, restore, then read. `HomeShell` already restores before
loading for exactly this reason; that ordering is now load-bearing rather than
cosmetic.

## Disconfirming condition

If Runio is ever genuinely used on two devices, "the phone is the log" stops
being complete: the phone would hold a subset and the read would have to become
local-first-then-merge, along with the insert-only restore rule ADR-0012 sets.
That is the same trigger as ADR-0012's, and both should be reopened together.

If a run ever legitimately originates somewhere other than this device — a
watch, an import, a Health workout written by another app — the same thing
applies, and the answer is still to bring it into Drift rather than to read it
from wherever it landed.

## Consequences

- **`SupabaseRunRepository` is gone**, and with it `fetchRunDetail`, which was
  never called by anything. `run_mappers.dart` is left with no caller in `lib/`
  and should follow, together with the two doc comments in
  `coaching/data/` that cite it as a pattern.
- **The log filters on `endedAt`**, which the old read never had to. A null
  `endedAt` is the recorder's marker for a run in progress or interrupted, and
  such a row carries a zero distance until `finalizeRun` writes the real one.
  Supabase never showed those because nothing pushed a run until it stopped;
  reading locally, the filter is explicit or a runner mid-run sees a 0.00 km run
  at the top of their own history.
- **A run opened from the log still has no trace.** It never did — the Supabase
  read returned summaries and `fetchRunDetail` was dead code — so `RunSummaryScreen`
  draws no route for a logged run. That is now a local query away rather than a
  network round trip, and it belongs with the run-completed screen in Phase 1 of
  the 1.0.0 plan.
- **Splits are still never written locally.** The recorder computes them live
  and stores none, so `run_splits` is populated only by a restore. Local reads
  make that gap visible; it was previously hidden behind a mirror that had
  nothing to mirror.
- The privacy position improves rather than merely holding: declining backup now
  costs a runner exactly what the switch says it costs — a copy elsewhere — and
  nothing else.
