# Data model

Stored in Supabase (Postgres) with a local Drift mirror. **Offline-first: record
to local SQLite, sync to Supabase when connected.** The server is a backup and
cross-device store, not the source of truth for a run in progress. Retrofitting
this is painful — do it from the first commit.

**Units: store metric everywhere. Convert at display only.**

## Tables

```
profiles          id, user_id, dob, weight_kg, unit_preference, created_at

runner_profiles   id, user_id, current_weekly_km, longest_run_km,
                  available_days[], time_trial_distance_m, time_trial_seconds,
                  injury_notes, updated_at

runs              id, user_id, started_at, duration_s, distance_m,
                  avg_pace_s_per_km, elevation_gain_m, avg_hr, max_hr,
                  cadence, calories_est, source (gps|healthkit|manual),
                  type (outdoor|treadmill), external_id, shoe_id,
                  rpe, notes, session_id (nullable)

run_points        run_id, seq, lat, lng, altitude_m, accuracy_m, timestamp

run_splits        run_id, seq, distance_m, duration_s, avg_hr

plans             id, user_id, goal_distance_m, goal_time_s, event_date,
                  start_date, weeks, status, created_at,
                  + runner profile snapshot: current_weekly_m,
                    longest_recent_m, days_per_week, available_weekdays[],
                    time_trial_distance_m, time_trial_seconds, injury_notes

plan_weeks        id, plan_id, user_id, week_number, phase, target_volume_m,
                  long_run_m, is_deload, generated_at

plan_sessions     id, plan_id, user_id, week_number, weekday, scheduled_date,
                  kind, target_distance_m, target_pace_s_per_km,
                  structure_json, rationale,
                  status (planned|completed|skipped), status_at,
                  provisional, run_id

shoes             id, user_id, name, distance_m, retired_at

check_ins         id, user_id, date, feeling, notes, created_at

coach_summaries   user_id (PK), summary, model, turns_covered, updated_at

coach_conversations
                  id, user_id, kind, started_at, last_turn_at

coach_turns       id, conversation_id, user_id, seq,
                  role (user|assistant), body, created_at
```

## The coach's memory

Tiered, in two layers with different lifetimes.

**`coach_summaries` is keyed on `user_id`, not on an id.** One row per runner, so
an upsert overwrites and no sequence of calls can accumulate summaries. That is
the "regenerated, never appended" rule expressed in the schema rather than
trusted to the client: each append would be a lossy re-encode of a re-encode,
and summaries that drift cannot be diffed. `model` and `updated_at` mean a bad
summary is traceable to what produced it, and that trace survives the
regeneration that fixes it.

**`coach_turns` is append-only, enforced by the database.** `update` is revoked
from `authenticated`, so nobody holding a user token can rewrite what a runner
said about their health after the fact. `delete` stays, because retention and
erasure both need it. Ordering is by `seq` rather than `created_at`, since two
turns can share a tick.

**Transcripts are pruned on write** — 180 days and 1000 turns per runner,
whichever bites first. Age alone does not bound a chatty week; a cap alone does
not bound how long a quiet runner's words are kept. Dropping old verbatim text
is safe precisely *because* the memory is tiered: the summary is the long-term
layer, the transcript is recall.

Transcripts contain health data — soreness, injuries, what a physio said. They
carry `user_id` so the deletion RPC's enumeration reaches them, and nothing in
this path may be logged.

### When each tier is written and read

The two tiers have deliberately different clocks, and the difference is what
makes the memory affordable.

| | Written | Read |
|---|---|---|
| `coach_turns` | every turn, as it happens | on launch (restore the dock) and on recall |
| `coach_summaries` | when a **conversation ends** | into every brief |

**A turn is stored before the model is called**, not after it answers. A
question asked in a tunnel is still a question the runner asked, and the
repository's contract is that the write completes on disk — so a force-quit
mid-sentence keeps it.

**The summary is rewritten only when the conversation ends** — when the dock is
closed, or the tab is disposed. Not per turn: the summarise surface is rate
limited to six an hour, so a rewrite per turn would spend the allowance in ten
minutes, and it would produce a copy of a copy besides (the surface is
regenerate-only for the same reason `coach_summaries` is keyed on `user_id`).
The rewrite is guarded on there being unsummarised turns, so closing a dock
nobody spoke into costs nothing.

**A failed rewrite is not a forgotten runner.** The summariser returns null when
it could not run — dead network, spent allowance — and null means *keep what you
have*, never *forget*. An empty string is a legitimate answer meaning "nothing
worth keeping" and is equally not a reason to discard a summary that already
exists. Either way the turns stay unsummarised, so the next close tries again.
None of this is ever surfaced: it is housekeeping the runner did not ask for.

**The summary is what is always loaded.** `CoachBrief` renders the typed state —
plan, recent runs, projections — from the database on every turn, and appends
the summary last, in the runner's own terms. The summary therefore holds only
what a schema cannot: shift work, a knee that complains on hills, a route they
will not run in the dark. Anything typed would be a second source of truth that
eventually disagrees with the first.

## Notes

- **`runs.source`** distinguishes a run recorded in Runio (`gps`), one synced
  from HealthKit (`healthkit`), and a hand-entered one (`manual`). Combined with
  `external_id` (the `HKWorkout` UUID / source bundle id) this drives
  [deduplication](run-recording.md#deduplication).
- **`runs.session_id`** links a completed run back to the planned session it
  fulfilled (nullable — not every run belongs to a plan).
- **`run_points`** is the raw trace. It can be large; keep it out of list
  queries and render history thumbnails from a pre-simplified path.
- **`plan_sessions.structure_json`** holds the workout structure (e.g. intervals)
  as validated JSON — never free-form model text used directly.
- A **treadmill/manual** run has no `run_points` and may have no `run_splits`.
  The plan and coaching layers must tolerate a session with no route and no
  splits.
- **`plans.start_date`** is the Monday of week 1. It is what maps a week *index*
  onto real calendar dates, so today's session stays correct as weeks pass —
  without it, a reloaded plan insists it is still week 1 forever.
- **`plans` snapshots the runner profile it was built for.** The validator checks
  a skeleton against a profile ([plan-generation.md](plan-generation.md)); if the
  profile were read live, editing it would retroactively invalidate a stored
  plan. `runner_profiles` remains the *current* profile; the snapshot is the one
  the plan was generated against.
- **`plans.status`** is `active | superseded | completed | abandoned`, with a
  partial unique index enforcing at most one `active` plan per user. Running the
  coach again **supersedes** the previous plan rather than deleting it — a plan
  is a record of what the runner committed to.
- **`plan_sessions` has one row per *training* day**; a rest day is the *absence*
  of a row. `(plan_id, week_number, weekday)` is unique, so regenerating or
  adapting a week updates it in place instead of duplicating sessions. Statuses
  the runner already set survive a rewrite.
- **`plan_sessions.target_pace_s_per_km`** is nullable and not written by the
  app: paces are derived deterministically in Dart from the time trial at
  display time. The column exists for a coach-authored override, not as a cache
  of a derived value.
- Sessions are generated **one week ahead**, so a `plan_weeks` row legitimately
  has no `plan_sessions` yet. "No sessions" and "a week of rest days" are
  different states and must not be conflated.

## Row Level Security

Every table is scoped by `user_id`. RLS policies must guarantee a user can only
read and write their own rows. This is a security-critical invariant — see
[SECURITY.md](../../SECURITY.md).

## Local mirror

The Drift schema mirrors these tables. Writes happen locally first; a sync layer
reconciles with Supabase. An in-progress run lives entirely in the local store
until it is finished and synced.

The **plan** follows the same rule and is already wired this way: `DriftPlanStore`
owns it and every read is local, so the Plan tab works with no network.
`SupabasePlanBackup` is a **push-only** mirror invoked *after* the local write
commits, and any failure is swallowed — a dead network must never cost the runner
a plan or a marked session.

Two differences from the Postgres shape, both deliberate:

- `plan_weeks` / `plan_sessions` use the composite keys `(plan_id, week_number)`
  and `(plan_id, week_number, weekday)` locally. Postgres needs a single-column
  primary key, so `id` there is composed from the same parts
  (`{plan}-w{week}-d{weekday}`) — deterministic, so a re-push updates the same
  row rather than duplicating it.
- `available_weekdays` is a Postgres `smallint[]` and a sorted comma-separated
  `TEXT` in SQLite, which has no array type.

**Not yet built:** pull/restore. The mirror is write-only, so signing in on a new
device does not yet recover a plan from Supabase.
