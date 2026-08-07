# The database

One Supabase project serves every app in the suite. This document explains the
shape it has, and — because the reasoning is more useful than the diagram — what
it used to be and why that stopped working.

## The shape

```
core.    profiles · user_settings · entitlements
         progress_photos · announcements · activities
coach.   conversations · turns · summaries · usage
lift.    workouts · exercises · sets · ai_summary_requests
run.     runs · run_points · run_splits
         plans · plan_weeks · plan_sessions · runner_profiles
```

One schema per domain. An app reads what it owns, plus `core`. Adding `eat`
means adding a schema — not touching Lift or Run.

Three ideas do the work.

### 1. The coach belongs to nobody

Nothing about conversations, memory, or usage metering is running-specific. It
lived under `runio` only because running is where it was built first.

Promoting it out means one coach subsystem, one rate limiter, three apps — and
it means most of Lift's AI feature is already written before Lift starts.

### 2. `core.activities` is the load-bearing table

One row per training event regardless of which app produced it: what, when, how
long, how hard, and a reference to the detail row.

```sql
core.activities (
  user_id, app, kind, occurred_at,
  duration_s, distance_m, effort_rpe, title,
  run_id      → run.runs(id)      on delete cascade,
  workout_id  → lift.workouts(id) on delete cascade
)
```

It makes "Lift shows your runs" a single query against a table Lift already
reads, gives the coach one cross-domain read instead of one per app, and makes
adding a third app cost nothing in the first two.

**It is maintained by triggers, never by clients.** The detail tables stay the
source of truth; this is a derived index over them. Two consequences worth the
constraint:

- Run needed **no code changes at all** to start populating the feed. It keeps
  writing `run.runs` and the rest follows.
- A derived table that clients also write will drift. This one can't — there is
  no client write path. RLS grants `SELECT` and nothing else.

It also means Lift cannot forge a run, which matters when the source is public.

**Typed references, not a polymorphic pair.** `run_id` and `workout_id` are real
foreign keys with real cascades rather than a `(ref_table, ref_id)` text pair.
Deleting a run deletes its activity for free, and a dangling reference is
impossible. The cost is that adding `eat` needs a column and a check-constraint
change — an explicit migration rather than a silent convention. That's the trade
worth making.

### 3. Entitlements are client-read-only

```sql
core.entitlements (user_id, app, product, status, platform, expires_at)
primary key (user_id, app)
```

Not a single `is_pro` flag: pricing is per-app, so a row per app means a future
bundle is two rows rather than a migration.

There is **no INSERT, UPDATE or DELETE policy on this table, and no such grant
to `authenticated`.** Only `service_role` writes it, from an Edge Function that
has already validated the receipt with Apple or Google.

That absence is the security control. With public source, anyone can read
exactly how entitlements are granted — so if a client write path exists,
someone will use it.

## Security model

**RLS is the boundary, not secrecy.** The Supabase URL and anon key are meant to
be public; they ship in every binary already. What protects data is that every
table has row-level security enabled and every policy is scoped to
`auth.uid()`.

Never in this repo: the `service_role` key, LLM provider keys, webhook secrets.
Those live in Edge Function environment variables.

Some specifics that are easy to get wrong:

- **Policies name `authenticated`, not `public`.** A policy `TO public` includes
  `anon` and is held out only because `auth.uid()` is null there — security by
  arithmetic rather than by intent.
- **Predicates read `(select auth.uid())`, not `auth.uid()`.** Postgres hoists
  the subquery into an InitPlan and evaluates it once per statement instead of
  once per row. On `run.run_points` — a row per GPS sample — that is the
  difference between a scan and a crawl.
- **`coach.usage` has RLS on and no policy at all.** It is the rate limiter's
  ledger, reachable only through `SECURITY DEFINER` functions under
  `service_role`. A client that can write it can lift its own spend cap.
- **`coach.turns` is append-only.** `authenticated` holds INSERT and DELETE but
  not UPDATE, so a transcript cannot be rewritten after the fact. DELETE stays
  because the client prunes to a rolling window.

The real open-source risk here is not leaked keys — it's abuse economics. Public
repo plus open signup means anyone can burn LLM credits through a legitimate
account, so rate limits are enforced server-side, platform-wide, and never in
the client.

These invariants are not documentation. They are
[`supabase/tests/coach_contract.sql`](../supabase/tests/coach_contract.sql), run
by `supabase test db` against the real catalog.

## Account deletion

`core.delete_account(user, app)`.

```
delete_account(user)          erase everything, everywhere, and the login
delete_account(user, 'run')   erase run.*; keep the login if lift.* holds data
```

The sweep **enumerates tables by their `user_id` column** rather than a
hard-coded list, so a table added later is covered by construction. Give every
new user-owned table a `user_id` or it silently escapes erasure — a GDPR problem
that no application test would catch.

One known gap, stated rather than hidden: coach data is erased only when the
last app goes. That was because `coach.conversations` had no `app` column, so
there was no honest way to erase "the running half" of a conversation.

**The column now exists** (`20260807130000_coach_memory_per_app.sql`, which also
re-keys `coach.summaries` on `(user_id, app)` so two apps cannot overwrite each
other's memory). Scoping the sweep to it is the outstanding half, and it is the
last thing standing between this and honest per-app erasure.

### The bug this replaced

Worth recording, because it is the kind that hides in plain sight.

Both apps shipped their own `delete-account` Edge Function against the same
project under the **same slug**, so whichever deployed last was the one running
— for both. Liftio's won. It called `auth.admin.deleteUser` unconditionally, and
every user-owned table in both schemas cascades from `auth.users`. So a *Run*
user tapping "delete account" erased their *Lift* data.

Deploying the other app's version instead would have been worse: it never
touched a Lift table, so a Lift user would have got a `200` with nothing
deleted, and been told their account was gone. A silent failure to honour an
erasure request is harder to notice than an over-deletion.

Neither was right, because "what should this erase?" has no answer until you
know who is asking. Now the caller says, and the answer no longer depends on
which binary happened to deploy last.

## Migrations

This repo is the source of truth. It was not always — and the way that broke is
instructive.

Two apps pushed into **one** migration ledger. Neither repo's files could
rebuild the result: two migrations had been applied by hand and never recorded,
four recorded migrations existed in no repo at all, and two more carried
different versions in the repo than in the ledger — so a `db push` would have
silently re-run them.

The fix was to stop trusting the files and read the database: the baseline was
introspected from the live catalog and verified with `supabase db diff`
reporting no differences. The old ledger entries are listed in the baseline's
header, and the ledger now holds exactly the migrations in this directory.

The lesson generalises. A schema is only version-controlled if you can rebuild
it from the repo and prove the result matches. Until you have run that check,
you have a directory of SQL files and a hope.

```sh
supabase db reset                    # rebuild locally from migrations alone
supabase db diff --linked            # must report no differences
supabase test db                     # invariants hold
```

## Out-of-band configuration

Two things live outside SQL and will bite you:

1. **Exposed schemas.** PostgREST only serves schemas listed in the dashboard
   (Settings → API). `core`, `coach`, `lift` and `run` must all be there or
   every client gets a 404.
2. **Clients must name the schema.** supabase-js and supabase-flutter default to
   `public`, which is now empty. Reads are
   `.schema('lift').from('workouts')`, and RPC calls need a `Content-Profile`
   header.
