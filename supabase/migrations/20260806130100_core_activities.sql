-- core.activities — one row per training event, whatever produced it.
--
-- This is the piece the suite is built on. "Lift shows you your runs" becomes a
-- single query against a table Lift already reads, the coach gets one
-- cross-domain read instead of one per app, and adding `eat` later costs a
-- migration here and nothing at all in Lift or Run.
--
-- ## Written by triggers, never by clients
--
-- The detail tables stay the source of truth; this is a derived index over
-- them, maintained by triggers on `run.runs` and `lift.workouts`. Two reasons:
--
--   1. Runio moves into the monorepo genuinely unchanged. It keeps writing
--      `run.runs` and the feed populates itself.
--   2. A derived table that clients also write drifts. Here it cannot — there
--      is no client write path at all (RLS grants SELECT only).
--
-- It also means Lift cannot forge a run, which matters in a public repo.
--
-- ## Typed references, not a polymorphic pair
--
-- `run_id` and `workout_id` are real foreign keys with real cascades, rather
-- than a `(ref_table, ref_id)` text pair. Deleting a run deletes its activity
-- for free, and a dangling reference is impossible. The cost is that adding
-- `eat` needs a column and a check-constraint change — an explicit migration
-- rather than a silent convention, which is the trade worth making.


create table core.activities (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,

  -- The producing app. Consumers branch on this.
  app text not null check (app in ('lift', 'run')),
  -- The app's own type string, scoped to that app: 'outdoor'/'treadmill' for a
  -- run, 'workout' for a lift session. Deliberately not a shared taxonomy —
  -- inventing one before `eat` exists would be guessing.
  kind text not null,

  occurred_at timestamptz not null,
  duration_s  integer check (duration_s is null or duration_s >= 0),
  distance_m  real    check (distance_m is null or distance_m >= 0),
  effort_rpe  smallint check (effort_rpe is null or effort_rpe between 1 and 10),
  title       text,

  run_id     text references run.runs(id)     on delete cascade,
  workout_id text references lift.workouts(id) on delete cascade,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint activities_exactly_one_ref check (
    (run_id is not null)::int + (workout_id is not null)::int = 1
  ),
  constraint activities_ref_matches_app check (
    case app
      when 'run'  then run_id is not null
      when 'lift' then workout_id is not null
      else false
    end
  )
);

comment on table core.activities is
  'One row per training event across every app. Derived from the detail tables and maintained by trigger — never written by a client.';
comment on column core.activities.kind is
  'App-scoped type string, not a shared taxonomy. Branch on `app` first.';

-- NULLs do not conflict in a unique index, so these enforce "at most one
-- activity per detail row" while leaving the other column free.
create unique index activities_run_id_key     on core.activities (run_id);
create unique index activities_workout_id_key on core.activities (workout_id);
create index activities_user_occurred_idx     on core.activities (user_id, occurred_at desc);

alter table core.activities enable row level security;

-- Read-only to the client, by construction. The triggers below are SECURITY
-- DEFINER, so they write regardless of this policy.
create policy own_activities_read on core.activities
  for select to authenticated using ((select auth.uid()) = user_id);

grant select on core.activities to authenticated;
grant all    on core.activities to service_role;


-- ---------------------------------------------------------------------------
-- Sync from run.runs
-- ---------------------------------------------------------------------------

create function core.sync_activity_from_run()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  insert into core.activities
    (user_id, app, kind, occurred_at, duration_s, distance_m, effort_rpe, run_id)
  values
    (new.user_id, 'run', new.type, new.started_at,
     nullif(new.duration_s, 0), nullif(new.distance_m, 0), new.rpe, new.id)
  on conflict (run_id) do update
    set user_id     = excluded.user_id,
        kind        = excluded.kind,
        occurred_at = excluded.occurred_at,
        duration_s  = excluded.duration_s,
        distance_m  = excluded.distance_m,
        effort_rpe  = excluded.effort_rpe,
        updated_at  = now();
  return new;
end;
$$;

create trigger sync_activity
  after insert or update on run.runs
  for each row execute function core.sync_activity_from_run();


-- ---------------------------------------------------------------------------
-- Sync from lift.workouts
--
-- Three kinds of row must NOT reach the feed, and all three exist in the data
-- today: templates (47 of 84 rows — they carry `date = 0`, since a template
-- has no date), soft-deleted workouts (41 rows), and anything with a
-- non-positive date. A workout can also become ineligible after the fact by
-- being soft-deleted, so the trigger removes as well as adds.
--
-- `date` is epoch MILLISECONDS. Reading it as seconds puts every workout in
-- the year 58561 — verified against the live data, not assumed.
-- ---------------------------------------------------------------------------

create function core.sync_activity_from_workout()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if new.is_template <> 0 or new.deleted_at is not null or new.date <= 0 then
    delete from core.activities where workout_id = new.id;
    return new;
  end if;

  insert into core.activities
    (user_id, app, kind, occurred_at, duration_s, title, workout_id)
  values
    (new.user_id, 'lift', 'workout', to_timestamp(new.date / 1000.0),
     nullif(new.duration, 0), nullif(new.name, ''), new.id)
  on conflict (workout_id) do update
    set user_id     = excluded.user_id,
        kind        = excluded.kind,
        occurred_at = excluded.occurred_at,
        duration_s  = excluded.duration_s,
        title       = excluded.title,
        updated_at  = now();
  return new;
end;
$$;

create trigger sync_activity
  after insert or update on lift.workouts
  for each row execute function core.sync_activity_from_workout();


-- ---------------------------------------------------------------------------
-- Backfill
--
-- Expected at the time of writing: 10 runs + 33 workouts = 43 activities.
-- ---------------------------------------------------------------------------

insert into core.activities
  (user_id, app, kind, occurred_at, duration_s, distance_m, effort_rpe, run_id)
select r.user_id, 'run', r.type, r.started_at,
       nullif(r.duration_s, 0), nullif(r.distance_m, 0), r.rpe, r.id
from run.runs r
on conflict (run_id) do nothing;

insert into core.activities
  (user_id, app, kind, occurred_at, duration_s, title, workout_id)
select w.user_id, 'lift', 'workout', to_timestamp(w.date / 1000.0),
       nullif(w.duration, 0), nullif(w.name, ''), w.id
from lift.workouts w
where w.is_template = 0
  and w.deleted_at is null
  and w.date > 0
on conflict (workout_id) do nothing;
