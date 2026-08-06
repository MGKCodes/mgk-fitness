-- Restructure: one schema per domain, replacing the public/runio split.
--
--   core.   what belongs to the person and the platform
--   coach.  the AI coach — app-agnostic, promoted out of `runio`
--   lift.   lifting
--   run.    running
--
-- Liftio sprawled into `public`; Runio namespaced itself correctly. That
-- asymmetry — not the Flutter rewrite — is the real migration job, and this is
-- it. `ALTER TABLE ... SET SCHEMA` preserves rows, primary keys, indexes,
-- constraints, triggers and policies, so no data moves and nothing is exported.
--
-- ## The one-way door
--
-- The moment these tables move, the live Liftio build on the App Store breaks:
-- it queries `public` through PostgREST, and `public` will be empty. That is
-- accepted deliberately — there are two users and both are known.
--
-- ## Two things this migration CANNOT do
--
-- 1. PostgREST's exposed-schema list is project configuration, not SQL. After
--    this runs, `core`, `coach`, `lift` and `run` must be added in the
--    dashboard (Settings → API → Exposed schemas) or EVERY client gets 404,
--    Runio included. Do it in the same window as the push.
-- 2. Clients must name the schema. supabase-js/-flutter default to `public`,
--    so `.from('workouts')` becomes `.schema('lift').from('workouts')`, and
--    Runio's `.schema('runio')` calls become `.schema('run')` /
--    `.schema('coach')`.
--
-- ## Not created here, deliberately
--
-- `eat` — an empty schema with no tables and no grants proves nothing. What
-- proves the pattern is that adding it later costs one migration and zero
-- changes to Lift or Run. `lift.lifter_profiles` likewise waits for the Lift
-- rewrite that needs it; the shape is `run.runner_profiles`, generalised.


-- ---------------------------------------------------------------------------
-- 1. Schemas
-- ---------------------------------------------------------------------------

create schema if not exists core;
create schema if not exists coach;
create schema if not exists lift;
create schema if not exists run;

comment on schema core is 'The person and the platform: identity, settings, entitlements, and the cross-app activity feed. Owned by no single app.';
comment on schema coach is 'The AI coach. App-agnostic by design — one conversation store, one rate limiter, every app.';
comment on schema lift is 'Lifting.';
comment on schema run is 'Running.';


-- ---------------------------------------------------------------------------
-- 2. Move the tables
--
-- `progress_photos` and `announcements` were misfiled: they belong to the
-- person and to the platform, not to lifting.
-- ---------------------------------------------------------------------------

alter table public.profiles          set schema core;
alter table public.user_settings     set schema core;
alter table public.progress_photos   set schema core;
alter table public.announcements     set schema core;

alter table public.workouts             set schema lift;
alter table public.exercises            set schema lift;
alter table public.sets                 set schema lift;
-- Liftio's daily AI summary predates the coach and is not part of it. It stays
-- app-local until the Lift rewrite replaces it with a coach surface.
alter table public.ai_summary_requests  set schema lift;

alter table runio.runs           set schema run;
alter table runio.run_points     set schema run;
alter table runio.run_splits     set schema run;
alter table runio.runner_profiles set schema run;
alter table runio.plans          set schema run;
alter table runio.plan_weeks     set schema run;
alter table runio.plan_sessions  set schema run;

alter table runio.coach_conversations set schema coach;
alter table runio.coach_turns         set schema coach;
alter table runio.coach_summaries     set schema coach;
alter table runio.coach_usage         set schema coach;

-- The `coach_` prefix was carrying the namespace. The schema does that now.
alter table coach.coach_conversations rename to conversations;
alter table coach.coach_turns         rename to turns;
alter table coach.coach_summaries     rename to summaries;
alter table coach.coach_usage         rename to usage;


-- ---------------------------------------------------------------------------
-- 3. Functions
--
-- `touch_updated_at` is shared by run.* and coach.* triggers, so it becomes a
-- core utility. Existing triggers bind to it by OID and keep working.
-- ---------------------------------------------------------------------------

alter function runio.touch_updated_at() set schema core;

-- These two are LANGUAGE sql with an empty search_path, so their bodies name
-- `runio.coach_usage` literally and are re-parsed at call time — moving the
-- table would break them. They have to be rewritten, not relocated.
drop function if exists public.runio_coach_record_usage(uuid, text, integer, integer, integer, numeric, boolean, text);
drop function if exists public.runio_coach_usage_window(uuid, timestamptz);

create function coach.record_usage(
  p_user uuid, p_surface text, p_prompt_tokens integer, p_completion_tokens integer,
  p_total_tokens integer, p_cost_credits numeric, p_cost_estimated boolean, p_outcome text
) returns void
language sql
security definer
set search_path to ''
as $$
  insert into coach.usage (
    user_id, surface, outcome, prompt_tokens, completion_tokens,
    total_tokens, cost_credits, cost_estimated
  ) values (
    p_user,
    p_surface,
    coalesce(p_outcome, 'ok'),
    greatest(coalesce(p_prompt_tokens, 0), 0),
    greatest(coalesce(p_completion_tokens, 0), 0),
    greatest(coalesce(p_total_tokens, 0), 0),
    greatest(coalesce(p_cost_credits, 0), 0),
    coalesce(p_cost_estimated, false)
  );

  delete from coach.usage
   where user_id = p_user
     and created_at < now() - interval '31 days';
$$;

create function coach.usage_window(p_user uuid, p_since timestamptz)
returns jsonb
language sql
stable
security definer
set search_path to ''
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object('at', u.created_at, 'surface', u.surface, 'cost_credits', u.cost_credits)
      order by u.created_at
    ),
    '[]'::jsonb
  )
  from coach.usage u
  where u.user_id = p_user
    and u.created_at >= p_since;
$$;

comment on function coach.record_usage(uuid, text, integer, integer, integer, numeric, boolean, text) is
  'Records one model call against a user''s rate limit and spend cap, and prunes past 31 days. service_role only — a client that can write this can lift its own cap.';

-- Signup still has to produce a profile row; it now lands in core.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  insert into core.profiles (id, email)
  values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end;
$$;

-- Rebuilt against the new schemas in the account-deletion migration that
-- follows this one. Left in place it would be worse than absent: it enumerates
-- `runio` (now gone, so it would find nothing to erase) and probes
-- `public.workouts` through to_regclass (now null, so it would conclude the
-- account holds no Liftio data and report the login as safe to delete).
drop function if exists public.runio_delete_account(uuid, boolean);


-- ---------------------------------------------------------------------------
-- 4. Keep the RLS safety net pointed at the right schemas
--
-- `ensure_rls` auto-enables RLS on new tables, but only watched `public` —
-- which is now empty. Without this the net would silently cover nothing.
-- ---------------------------------------------------------------------------

create or replace function public.rls_auto_enable()
returns event_trigger
language plpgsql
security definer
set search_path to 'pg_catalog'
as $$
declare
  cmd record;
begin
  for cmd in
    select *
    from pg_event_trigger_ddl_commands()
    where command_tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      and object_type in ('table', 'partitioned table')
  loop
    if cmd.schema_name in ('public', 'core', 'coach', 'lift', 'run', 'eat') then
      begin
        execute format('alter table if exists %s enable row level security', cmd.object_identity);
        raise log 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      exception
        when others then
          raise log 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      end;
    else
      raise log 'rls_auto_enable: skip % (schema % not enforced)', cmd.object_identity, cmd.schema_name;
    end if;
  end loop;
end;
$$;


-- ---------------------------------------------------------------------------
-- 5. Row-level security, rewritten
--
-- Policies survive the move, so these are dropped and recreated rather than
-- inherited. Three changes, all of them deliberate:
--
--   1. `to authenticated`, not `to public`. The old policies were reachable by
--      `anon` and held out only because auth.uid() is null there — security by
--      arithmetic rather than by intent.
--   2. `(select auth.uid())` instead of `auth.uid()`. Postgres hoists the
--      subquery to an InitPlan and evaluates it once per statement instead of
--      once per row. On `run_points` (1,859 rows for one user today, and it
--      grows per GPS sample) that is the difference between a scan and a crawl.
--   3. Explicit `with check` everywhere. `FOR ALL ... USING` alone silently
--      reuses USING as the insert check; saying it out loud means a later edit
--      to one clause cannot quietly change the other.
-- ---------------------------------------------------------------------------

drop policy if exists "Users can view own profile"           on core.profiles;
drop policy if exists "Users can insert own profile"         on core.profiles;
drop policy if exists "Users can update own profile"         on core.profiles;
drop policy if exists "Users can manage own settings"        on core.user_settings;
drop policy if exists "Users can manage own progress photos" on core.progress_photos;
drop policy if exists "Public read published announcements"  on core.announcements;
drop policy if exists "Users can manage own workouts"        on lift.workouts;
drop policy if exists "Users can manage own exercises"       on lift.exercises;
drop policy if exists "Users can manage own sets"            on lift.sets;
drop policy if exists "Users can only see their own requests" on lift.ai_summary_requests;
drop policy if exists "own runner_profile"      on run.runner_profiles;
drop policy if exists "own runs"                on run.runs;
drop policy if exists "own run_points"          on run.run_points;
drop policy if exists "own run_splits"          on run.run_splits;
drop policy if exists "own plans"               on run.plans;
drop policy if exists "own plan_weeks"          on run.plan_weeks;
drop policy if exists "own plan_sessions"       on run.plan_sessions;
drop policy if exists "own coach_conversations" on coach.conversations;
drop policy if exists "own coach_turns"         on coach.turns;
drop policy if exists "own coach_summaries"     on coach.summaries;

create policy own_profile_select on core.profiles
  for select to authenticated using ((select auth.uid()) = id);
create policy own_profile_insert on core.profiles
  for insert to authenticated with check ((select auth.uid()) = id);
create policy own_profile_update on core.profiles
  for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

create policy own_user_settings on core.user_settings
  for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy own_progress_photos on core.progress_photos
  for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- Platform broadcast: readable by anyone, written only by service_role.
create policy announcements_read_published on core.announcements
  for select to anon, authenticated using (is_published = true);

create policy own_workouts on lift.workouts
  for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy own_exercises on lift.exercises
  for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy own_sets on lift.sets
  for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
-- Read-only to the client; the daily-ai-summary function writes as service_role.
create policy own_ai_summary_requests on lift.ai_summary_requests
  for select to authenticated using ((select auth.uid()) = user_id);

create policy own_runner_profile on run.runner_profiles
  for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy own_runs on run.runs
  for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy own_run_points on run.run_points
  for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy own_run_splits on run.run_splits
  for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy own_plans on run.plans
  for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy own_plan_weeks on run.plan_weeks
  for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy own_plan_sessions on run.plan_sessions
  for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

create policy own_conversations on coach.conversations
  for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy own_turns on coach.turns
  for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy own_summaries on coach.summaries
  for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- coach.usage keeps RLS on and no policy at all: reachable only through the
-- SECURITY DEFINER functions above, under service_role.


-- ---------------------------------------------------------------------------
-- 6. Privileges
--
-- Table ACLs travel with the table, so everything that came out of `public`
-- arrived still carrying Supabase's default `public` grants — including full
-- INSERT/UPDATE/DELETE for `anon`. RLS was the only thing standing in front of
-- that. Revoke it: a grant nobody needs is a grant that only matters the day a
-- policy has a bug.
-- ---------------------------------------------------------------------------

grant usage on schema core, coach, lift, run to authenticated, service_role;
grant usage on schema core to anon;   -- announcements only

revoke all on all tables in schema core, coach, lift, run from anon;
revoke all on all tables in schema core, coach, lift, run from authenticated;

grant select, insert, update, delete on
  core.profiles, core.user_settings, core.progress_photos,
  lift.workouts, lift.exercises, lift.sets,
  run.runner_profiles, run.runs, run.run_points, run.run_splits,
  run.plans, run.plan_weeks, run.plan_sessions,
  coach.conversations, coach.summaries
  to authenticated;

-- Append-only transcript: no UPDATE, so a turn cannot be rewritten after the
-- fact. Pruning to a rolling window still needs DELETE.
grant select, insert, delete on coach.turns to authenticated;

-- Read-only for the client; service_role writes both.
grant select on lift.ai_summary_requests to authenticated;
grant select on core.announcements to anon, authenticated;

grant all on all tables in schema core, coach, lift, run to service_role;
grant usage, select on all sequences in schema core, coach, lift, run to authenticated, service_role;

alter default privileges in schema core, lift, run
  grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema core, coach, lift, run
  grant all on tables to service_role;
-- No default grant to `authenticated` in `coach`: usage metering defaults to
-- unreachable, and anything a client should read is granted by name.


-- ---------------------------------------------------------------------------
-- 7. Retire `runio`
--
-- RESTRICT, not CASCADE — if anything is still in there, this migration should
-- fail loudly rather than quietly delete it.
-- ---------------------------------------------------------------------------

drop schema runio restrict;
