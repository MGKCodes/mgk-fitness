# 0012 — Backup is consented, and restore only ever adds

**Status:** Accepted

## Context

Runio promised a backup it did not have. [ADR-0004](0004-offline-first-local-source-of-truth.md)
makes the on-device database the source of truth and Supabase "a backup and
cross-device store", and [ADR-0008](0008-shared-supabase-platform.md) put the
tables in a `runio` schema to hold it. Neither was true in practice:

- **Nothing pushed runs.** Plans, coach memory, profiles and settings each had a
  mirror. Runs had none, while History read *from* Supabase — so a recorded run
  was written to Drift, pushed nowhere, and never appeared in the log. Only
  seeded rows were ever visible, which is why nobody noticed.
- **Nothing pulled anything.** There was no Supabase → Drift path in the
  codebase at all. A reinstall left a runner with no plan and a coach that had
  forgotten them, which is the one loss that cannot be repaired: runs can be
  re-entered and a plan regenerated in a single call, but "runs before work,
  will not run in the dark, left calf tightens on faster sessions" took months
  of conversation to accumulate.
- **The schema was not exposed to the API.** Every `runio` read and write
  answered `PGRST106`. The coach limiter worked only because `usage_store.ts`
  had deliberately routed through `public` functions to avoid exactly this.

At the same time, what Runio stores is GPS traces, heart rates, injury notes and
the runner's own sentences about their body. Under UK GDPR that is
special-category data (Art. 9), and the lawful basis a consumer app has for
holding it is **explicit consent**.

## Decision

**Nothing leaves the device until the runner has said yes, and nothing pulled
back down may overwrite what the device already holds.**

Three parts.

### Consent is three-valued, and gates by wrapping

`BackupConsent` is `unknown | granted | declined`. "Not asked yet" is a real
state and behaves as a no. A boolean would have to default to something and both
defaults are wrong: `false` cannot be told apart from a considered refusal, and
`true` is consent nobody gave.

The gate is a **wrapper** — `ConsentedRunBackup`, `ConsentedPlanBackup`,
`ConsentedMemoryMirror` — built in `main.dart`, so nothing below ever holds an
ungated backup. Runs alone are pushed from four places (the recorder on stop,
the editor on add and on edit, the backfill), and the coach will add more when
it can log a run from conversation. A rule enforced by remembering to check
holds until someone adds the next caller, and the failure mode is not a bug: it
is special-category data leaving a phone whose owner declined to send it.

Consent is read on **every** call, so turning backup off applies to the run
being finished, not from the next launch. It is stored **locally only**: keeping
it on the server would mean writing a record about the runner to the place they
may be declining to send anything, and reading it back would need a network call
to find out whether a network call is allowed. It also gives the right behaviour
on new hardware — consent arrives unset, so nothing uploads and nothing restores
until they say yes on that device.

Deletion and pruning are **not** gated. They only ever remove rows, and someone
who has just withdrawn consent is exactly who needs them to work.

### Withdrawal erases

Stopping future uploads while years of traces and transcripts sit on a server is
a pause, not a withdrawal, and consent must be as easy to withdraw as to give.
`BackupEraser` deletes the runner's `runio` rows client-side, using their own
token: every table has `for all using (user_id = auth.uid())`, and DELETE is
granted to `authenticated` — including on `coach_turns`, where UPDATE is revoked
but DELETE was deliberately kept for this and for the right to erasure.

### Restore only ever adds

Every restore write is insert-or-ignore, so a row the phone already has always
wins. This is a deliberate choice of the *weaker* guarantee: a one-way pull
cannot resolve a conflict, and it cannot create one either.

Two narrower rules follow from not overruling the device that owns the truth:
the plan is pulled only onto a phone with **no** plan, and the coach's memory
only onto one that remembers **nothing**. A phone mid-conversation is not
missing its memory, and merging a server copy into a live transcript risks
interleaving turns by `seq` into an order neither side ever said.

## Obvious alternative

**Two-way sync with last-write-wins.** `updated_at` now exists on every mutable
`runio` row, stamped by a Postgres trigger rather than the client — a phone with
a wrong clock would otherwise write a row that merely *looks* newer. Nothing
reads it.

It was not built because Runio has one device per runner, so there is nothing
for it to resolve, and conflict resolution is where sync designs lose data. The
column is there because schema is cheap to change while the tables are empty and
expensive afterwards; when a second device appears, this becomes a code change
rather than a migration.

## Cost function

Consent-by-default-off means a runner who never answers keeps no backup, and the
guarantee reads as broken to them. That is why the question is asked once at
first launch rather than left in Settings to be found: consent that has to be
discovered is not really offered.

**Amended (ADR-0017).** "First launch" is now read as *first session*, not
*first frame*. A brand-new account has nothing on the server to restore, so the
question in front of the app was asking permission to store data that did not
exist yet, before the runner had seen Runio do anything — the second modal in
thirty seconds, and the one that could least be answered on the evidence
available. For an account created on this device the question is asked at the
end of the first flow instead: after the coach has built a plan, or after the
runner has declined to build one.

The guarantee this cost function protects is unchanged, and deliberately so.
The question is still unavoidable, still asked once, still inside the first
session, and still not something the runner has to go looking for. What moved
is only *which end of the first flow it sits at*. A runner signing back in on a
new device is unaffected: there the answer gates a restore that is about to
happen, so it is still asked before anything moves.

Insert-or-ignore means a genuinely stale local row is never corrected from the
server. Accepted, because the reverse — a pull quietly replacing an offline edit
with the older copy the server still holds — is the failure a runner would never
detect.

## Disconfirming condition

If runners start using Runio on two devices, or if a real case appears where the
server's copy is legitimately newer than the phone's, the insert-or-ignore rule
stops being right and `updated_at` starts being read.

If a regulator or a privacy review finds that consent obtained this way is not
specific enough for Art. 9 — for example because one switch covers both routes
and transcripts — the switch splits rather than the gate loosening.

**Amended, 2026-08-28 — asked once there is something to keep, not once there
is an account.**

The amendment above put the question at the end of the first flow, "after the
coach has built a plan, or after the runner has declined to build one". That
flow no longer exists in the shape it describes. An account is not the price of
using the app any more: it is asked for at the two moments it buys something —
a plan, and this. So the great majority of runners now reach their second week
with no account at all, and for them the previous rule asked the question at a
moment that never arrives.

The reasoning of the first amendment is what decides the new answer, because it
generalises further than it was written. Its objection was that the question was
being put *before the runner had seen the app do anything* — permission to store
data that did not exist yet. For somebody with no account that objection is
strictly stronger: not only is there nothing stored, there is nowhere to store
it, and a yes could only have been honoured by raising a sign-up at launch,
which is the intrusion removing the sign-in wall existed to end.

So the question follows the data rather than the flow:

| Runner | Asked | Why there |
|---|---|---|
| Signed in, opening the app | At launch, before the restore | The answer decides whether there **is** a restore |
| No account | After their **second** recorded run | The first is a trial; by the second there is a log they would mind losing |

One run is deliberately not enough. Somebody who has been to the end of the road
once to see whether the app works is still evaluating it, and a consent dialog
followed by a sign-up is how a tracker turns into a thing that wants something.

**Saying yes raises sign-up, and the dialog says so before it is tapped.** The
mirror writes rows attributed to a user, so the account is the mechanism the
answer needs rather than a second question — which is why this is one dialog and
not two. Abandoning that sign-up writes **nothing**: they did not decline, they
were interrupted, and the question is put again next time. Declining writes
`declined` and is never raised again, which is what the deliberate absence of a
"Not now" button is for.

The guarantee the cost function protects is unchanged. The question is still
unavoidable, still asked once, still not something the runner has to go looking
for. What moved again is only *when* — and it has moved to the first moment at
which the runner can answer it on the evidence.

## Consequences

- The `runio` schema **must stay exposed** in the project's API settings. It is
  a dashboard setting, not code, and nothing in the repo can assert it. Every
  `runio` read and write fails with `PGRST106` if it is removed.
- **Granting requires a session**, and the UI must enforce it rather than
  assume it. A backup switch with nobody signed in reads "On" over a mirror
  whose every push fails on a row-level policy — the switch and Home's prompt
  both raise sign-up before writing a grant.
- Every unbounded PostgREST read must page. See
  [0013](0013-page-every-postgrest-read.md).
- The privacy policy must name the restore path, not only the mirror: data moves
  in both directions and both are processing.
