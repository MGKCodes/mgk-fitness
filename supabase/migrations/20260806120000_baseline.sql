-- Baseline: the shared MGKCodes fitness database as it actually stood on
-- 2026-08-06, immediately before the monorepo took ownership of the schema.
--
-- ## Why a baseline and not the two repos' migrations
--
-- Runio and Liftio both pushed into ONE ledger
-- (`supabase_migrations.schema_migrations`) on project `cwpwzxjjhxbkwhrgnasn`,
-- and neither repo's file set can rebuild the result:
--
--   * Liftio's `001_initial_schema` and `002_rename_exercises` were applied by
--     hand and were never recorded. The ledger's earliest entry is Liftio 003.
--   * Four recorded migrations exist in no repo at all — their source is gone:
--       20260427103330 create_announcements_table
--       20260427164619 ai_summary_requests_add_summary_column
--       20260427164738 ai_summary_requests_unique_user_date
--       20260427182103 profile_and_unit_sync_fields
--   * Two Runio migrations carry different versions in the repo than in the
--     ledger (repo 20260729150000 / 20260801090000 vs ledger 20260729173743 /
--     20260801120705), so `supabase db push` from Runio would re-run them.
--
-- So the live database was the only source of truth. This file is that truth,
-- written down. It supersedes all twenty ledger entries listed at the foot of
-- this comment; they are removed from the ledger in the same change that adds
-- this one, and migrations are frozen in both old repos.
--
-- ## Provenance and what is NOT verified
--
-- Derived by catalog introspection — `pg_get_constraintdef`, `pg_get_indexdef`,
-- `pg_get_functiondef`, `pg_get_triggerdef`, `pg_policies` — rather than by
-- `supabase db dump`. The DDL text is canonical Postgres output; the ordering,
-- schema-qualification, and grant reconstruction are hand-assembled.
--
-- Verified 2026-08-06 against the live project:
--
--     supabase start                              -- applied cleanly, no errors
--     supabase db diff --linked -s public,runio   -- "No schema changes found"
--
-- So for `public` and `runio` this file is not an approximation: a database
-- built from it is indistinguishable from production.
--
-- Two things sit OUTSIDE that diff's scope and were checked separately, by
-- comparing object counts between local and production:
--
--   * the `progress-photos` storage bucket and its four policies on
--     `storage.objects` (section 14);
--   * the `on_auth_user_created` trigger on `auth.users` (section 10).
--
-- Re-run both commands after any change here. `db diff` reporting anything at
-- all means the repo and the database have drifted apart again.
--
-- ## Deliberately excluded
--
--   * Supabase platform objects: the `auth`, `storage`, `realtime`, `vault`
--     and `graphql` schemas, and the platform's own event triggers
--     (pgrst_ddl_watch, pgrst_drop_watch, issue_pg_graphql_access,
--     issue_pg_cron_access, issue_pg_net_access, issue_graphql_placeholder).
--   * The `public` schema's default ACL (anon/authenticated/service_role get
--     full table grants automatically). It is Supabase's default and is
--     recreated by the platform. RLS — not the grant — is the boundary.
--   * Project-level API config. `runio` is exposed to PostgREST through the
--     dashboard's "Exposed schemas" setting, which lives outside the database
--     and outside this file. Any new schema must be added there by hand.
--   * Data. Row counts at baseline are recorded in the freeze notes.
--
-- Superseded ledger entries:
--   20260409180747 add_template_id                        (Liftio 003)
--   20260409233115 004_ai_summary_requests                (Liftio 004)
--   20260417114116 005_user_settings                      (Liftio 005)
--   20260417114227 006_progress_photos                    (Liftio 006)
--   20260417114249 007_progress_photos_storage            (Liftio 007)
--   20260420190715 008_workouts_sync                      (Liftio 008)
--   20260427103330 create_announcements_table             (no source)
--   20260427164619 ai_summary_requests_add_summary_column (no source)
--   20260427164738 ai_summary_requests_unique_user_date   (no source)
--   20260427182103 profile_and_unit_sync_fields           (no source)
--   20260427222712 profiles_insert_policy                 (Liftio 009)
--   20260725120000 runio_initial_schema                   (Runio)
--   20260726090000 runio_plan_tables                      (Runio)
--   20260726100000 account_deletion                       (Runio)
--   20260726180000 coach_usage_limits                     (Runio)
--   20260727090000 coach_memory                           (Runio)
--   20260728120000 plan_backup_parity                     (Runio)
--   20260728140000 updated_at_for_restore                 (Runio)
--   20260729173743 plan_backup_nullable_goal              (Runio)
--   20260801120705 plan_session_label                     (Runio)


-- ---------------------------------------------------------------------------
-- 1. Schemas and extensions
-- ---------------------------------------------------------------------------

create schema if not exists runio;

create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_stat_statements with schema extensions;


-- ---------------------------------------------------------------------------
-- 2. Sequences
--
-- Only `ai_summary_requests.id` uses a standalone sequence; `coach_usage.id`
-- is an identity column and carries its own.
-- ---------------------------------------------------------------------------

create sequence if not exists public.ai_summary_requests_id_seq;


-- ---------------------------------------------------------------------------
-- 3. Tables — public (Liftio, unnamespaced)
-- ---------------------------------------------------------------------------

create table public.profiles (
  id uuid not null,
  email text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  name text,
  dob date,
  weight_kg real
);

create table public.user_settings (
  user_id uuid not null,
  weight_unit text default 'lbs'::text not null,
  default_rest_timer integer default 90 not null,
  theme text default 'dark'::text not null,
  progress_pose_set text default '["front","back"]'::text not null,
  custom_pose_labels text,
  default_timer_duration integer default 0 not null,
  show_alignment_guide integer default 1 not null,
  camera_overlay_type text default 'grid'::text not null,
  alignment_references text,
  created_at bigint not null,
  updated_at bigint not null,
  synced_at timestamp with time zone default now() not null,
  distance_unit text default 'km'::text
);

create table public.workouts (
  id text not null,
  user_id uuid not null,
  name text not null,
  date bigint not null,
  duration integer default 0 not null,
  notes text,
  is_template integer default 0 not null,
  premade_id text,
  created_at text not null,
  updated_at text not null,
  synced_at timestamp with time zone default now() not null,
  template_id text,
  deleted_at bigint
);

create table public.exercises (
  id text not null,
  user_id uuid not null,
  workout_id text not null,
  exercise_name text not null,
  order_index integer default 0 not null,
  notes text,
  cardio_mode text,
  created_at text not null
);

create table public.sets (
  id text not null,
  user_id uuid not null,
  exercise_id text not null,
  set_number integer default 1 not null,
  reps integer default 0 not null,
  weight real default 0 not null,
  is_completed integer default 0 not null,
  duration integer,
  distance real,
  created_at text not null
);

create table public.progress_photos (
  id text not null,
  user_id uuid not null,
  date bigint not null,
  pose_type text not null,
  note text,
  storage_path text not null,
  crop_scale real,
  crop_offset_x real,
  crop_offset_y real,
  crop_rotation real,
  excluded integer default 0 not null,
  created_at bigint not null,
  updated_at bigint not null,
  deleted_at bigint,
  synced_at timestamp with time zone default now() not null
);

create table public.ai_summary_requests (
  id bigint default nextval('public.ai_summary_requests_id_seq'::regclass) not null,
  user_id uuid not null,
  date_key text not null,
  created_at timestamp with time zone default now() not null,
  summary text
);

alter sequence public.ai_summary_requests_id_seq
  owned by public.ai_summary_requests.id;

create table public.announcements (
  id uuid default gen_random_uuid() not null,
  version text not null,
  eyebrow text,
  title text not null,
  sections jsonb default '[]'::jsonb not null,
  published_at timestamp with time zone default now() not null,
  is_published boolean default true not null,
  created_at timestamp with time zone default now() not null
);


-- ---------------------------------------------------------------------------
-- 4. Tables — runio (namespaced)
-- ---------------------------------------------------------------------------

create table runio.runner_profiles (
  user_id uuid not null,
  current_weekly_m real,
  longest_run_m real,
  available_days smallint[],
  time_trial_distance_m real,
  time_trial_seconds integer,
  injury_notes text,
  updated_at timestamp with time zone default now() not null,
  days_per_week smallint,
  strength_days_per_week smallint
);

create table runio.runs (
  id text not null,
  user_id uuid not null,
  started_at timestamp with time zone not null,
  duration_s integer not null,
  distance_m real not null,
  avg_pace_s_per_km real,
  elevation_gain_m real,
  avg_hr integer,
  max_hr integer,
  cadence integer,
  calories_est real,
  source text not null,
  type text not null,
  external_id text,
  rpe integer,
  notes text,
  session_id text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table runio.run_points (
  run_id text not null,
  user_id uuid not null,
  seq integer not null,
  lat double precision not null,
  lng double precision not null,
  altitude_m real,
  accuracy_m real not null,
  recorded_at timestamp with time zone not null
);

create table runio.run_splits (
  run_id text not null,
  user_id uuid not null,
  seq integer not null,
  distance_m real not null,
  duration_s integer not null,
  avg_hr integer
);

create table runio.plans (
  id text not null,
  user_id uuid not null,
  goal_distance_m real,
  goal_time_s integer,
  event_date date,
  start_date date not null,
  weeks smallint not null,
  status text default 'active'::text not null,
  current_weekly_m real not null,
  longest_recent_m real not null,
  days_per_week smallint not null,
  available_weekdays smallint[] not null,
  time_trial_distance_m real,
  time_trial_seconds integer,
  injury_notes text,
  created_at timestamp with time zone default now() not null,
  strength_days_per_week smallint default 0 not null,
  commitments jsonb default '[]'::jsonb not null,
  updated_at timestamp with time zone default now() not null
);

create table runio.plan_weeks (
  id text not null,
  plan_id text not null,
  user_id uuid not null,
  week_number smallint not null,
  phase text not null,
  target_volume_m real not null,
  long_run_m real not null,
  is_deload boolean default false not null,
  generated_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table runio.plan_sessions (
  id text not null,
  plan_id text not null,
  user_id uuid not null,
  week_number smallint not null,
  weekday smallint not null,
  scheduled_date date not null,
  kind text not null,
  target_distance_m real default 0 not null,
  target_pace_s_per_km real,
  structure_json jsonb,
  rationale text,
  status text default 'planned'::text not null,
  status_at timestamp with time zone,
  provisional boolean default false not null,
  run_id text,
  updated_at timestamp with time zone default now() not null,
  label text
);

create table runio.coach_conversations (
  id text not null,
  user_id uuid not null,
  kind text default 'coach'::text not null,
  started_at timestamp with time zone default now() not null,
  last_turn_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);

create table runio.coach_turns (
  id text not null,
  conversation_id text not null,
  user_id uuid not null,
  seq integer not null,
  role text not null,
  body text not null,
  created_at timestamp with time zone default now() not null
);

create table runio.coach_summaries (
  user_id uuid not null,
  summary text not null,
  model text,
  turns_covered integer default 0 not null,
  updated_at timestamp with time zone default now() not null
);

create table runio.coach_usage (
  id bigint generated always as identity not null,
  user_id uuid not null,
  surface text not null,
  outcome text default 'ok'::text not null,
  prompt_tokens integer default 0 not null,
  completion_tokens integer default 0 not null,
  total_tokens integer default 0 not null,
  cost_credits numeric(12,8) default 0 not null,
  cost_estimated boolean default false not null,
  created_at timestamp with time zone default now() not null
);


-- ---------------------------------------------------------------------------
-- 5. Primary keys and unique constraints
-- ---------------------------------------------------------------------------

alter table public.ai_summary_requests add constraint ai_summary_requests_pkey PRIMARY KEY (id);
alter table public.announcements add constraint announcements_pkey PRIMARY KEY (id);
alter table public.exercises add constraint exercises_pkey PRIMARY KEY (id);
alter table public.profiles add constraint profiles_pkey PRIMARY KEY (id);
alter table public.progress_photos add constraint progress_photos_pkey PRIMARY KEY (id);
alter table public.sets add constraint sets_pkey PRIMARY KEY (id);
alter table public.user_settings add constraint user_settings_pkey PRIMARY KEY (user_id);
alter table public.workouts add constraint workouts_pkey PRIMARY KEY (id);

alter table runio.coach_conversations add constraint coach_conversations_pkey PRIMARY KEY (id);
alter table runio.coach_summaries add constraint coach_summaries_pkey PRIMARY KEY (user_id);
alter table runio.coach_turns add constraint coach_turns_pkey PRIMARY KEY (id);
alter table runio.coach_usage add constraint coach_usage_pkey PRIMARY KEY (id);
alter table runio.plan_sessions add constraint plan_sessions_pkey PRIMARY KEY (id);
alter table runio.plan_weeks add constraint plan_weeks_pkey PRIMARY KEY (id);
alter table runio.plans add constraint plans_pkey PRIMARY KEY (id);
alter table runio.run_points add constraint run_points_pkey PRIMARY KEY (run_id, seq);
alter table runio.run_splits add constraint run_splits_pkey PRIMARY KEY (run_id, seq);
alter table runio.runner_profiles add constraint runner_profiles_pkey PRIMARY KEY (user_id);
alter table runio.runs add constraint runs_pkey PRIMARY KEY (id);

alter table public.ai_summary_requests add constraint ai_summary_requests_user_date_unique UNIQUE (user_id, date_key);
alter table runio.coach_turns add constraint coach_turns_conversation_id_seq_key UNIQUE (conversation_id, seq);
alter table runio.plan_sessions add constraint plan_sessions_plan_id_week_number_weekday_key UNIQUE (plan_id, week_number, weekday);
alter table runio.plan_weeks add constraint plan_weeks_plan_id_week_number_key UNIQUE (plan_id, week_number);


-- ---------------------------------------------------------------------------
-- 6. Check constraints
-- ---------------------------------------------------------------------------

alter table runio.coach_summaries add constraint coach_summaries_turns_covered_nonneg CHECK ((turns_covered >= 0));
alter table runio.coach_turns add constraint coach_turns_role_known CHECK ((role = ANY (ARRAY['user'::text, 'assistant'::text])));
alter table runio.coach_turns add constraint coach_turns_seq_nonneg CHECK ((seq >= 0));
alter table runio.plan_sessions add constraint plan_sessions_kind_known CHECK ((kind = ANY (ARRAY['rest'::text, 'recovery'::text, 'easy'::text, 'long'::text, 'marathon_pace'::text, 'threshold'::text, 'interval'::text, 'time_trial'::text, 'strength'::text])));
alter table runio.plan_sessions add constraint plan_sessions_status_known CHECK ((status = ANY (ARRAY['planned'::text, 'completed'::text, 'skipped'::text])));
alter table runio.plan_sessions add constraint plan_sessions_weekday_range CHECK (((weekday >= 1) AND (weekday <= 7)));
alter table runio.plan_weeks add constraint plan_weeks_phase_known CHECK ((phase = ANY (ARRAY['base'::text, 'build'::text, 'peak'::text, 'taper'::text])));
alter table runio.plans add constraint plans_status_known CHECK ((status = ANY (ARRAY['active'::text, 'superseded'::text, 'completed'::text, 'abandoned'::text])));
alter table runio.plans add constraint plans_weeks_positive CHECK ((weeks > 0));


-- ---------------------------------------------------------------------------
-- 7. Foreign keys
--
-- Note the shape: every user-owned table in BOTH schemas cascades from
-- auth.users. That is why deleting the login erases both apps at once — the
-- fact that makes the shared `delete-account` function dangerous.
-- ---------------------------------------------------------------------------

alter table public.profiles add constraint profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.user_settings add constraint user_settings_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.workouts add constraint workouts_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.exercises add constraint exercises_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.exercises add constraint exercises_workout_id_fkey FOREIGN KEY (workout_id) REFERENCES public.workouts(id) ON DELETE CASCADE;
alter table public.sets add constraint sets_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.sets add constraint sets_exercise_id_fkey FOREIGN KEY (exercise_id) REFERENCES public.exercises(id) ON DELETE CASCADE;
alter table public.progress_photos add constraint progress_photos_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.ai_summary_requests add constraint ai_summary_requests_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

alter table runio.runner_profiles add constraint runner_profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table runio.runs add constraint runs_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table runio.run_points add constraint run_points_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table runio.run_points add constraint run_points_run_id_fkey FOREIGN KEY (run_id) REFERENCES runio.runs(id) ON DELETE CASCADE;
alter table runio.run_splits add constraint run_splits_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table runio.run_splits add constraint run_splits_run_id_fkey FOREIGN KEY (run_id) REFERENCES runio.runs(id) ON DELETE CASCADE;
alter table runio.plans add constraint plans_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table runio.plan_weeks add constraint plan_weeks_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table runio.plan_weeks add constraint plan_weeks_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES runio.plans(id) ON DELETE CASCADE;
alter table runio.plan_sessions add constraint plan_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table runio.plan_sessions add constraint plan_sessions_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES runio.plans(id) ON DELETE CASCADE;
alter table runio.plan_sessions add constraint plan_sessions_run_id_fkey FOREIGN KEY (run_id) REFERENCES runio.runs(id) ON DELETE SET NULL;
alter table runio.coach_conversations add constraint coach_conversations_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table runio.coach_turns add constraint coach_turns_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table runio.coach_turns add constraint coach_turns_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES runio.coach_conversations(id) ON DELETE CASCADE;
alter table runio.coach_summaries add constraint coach_summaries_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table runio.coach_usage add constraint coach_usage_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


-- ---------------------------------------------------------------------------
-- 8. Indexes (those not already backing a constraint)
-- ---------------------------------------------------------------------------

CREATE INDEX idx_ai_summary_user_date ON public.ai_summary_requests USING btree (user_id, date_key);
CREATE INDEX announcements_published_at_idx ON public.announcements USING btree (published_at DESC) WHERE (is_published = true);
CREATE INDEX idx_exercises_user_id ON public.exercises USING btree (user_id);
CREATE INDEX idx_exercises_workout_id ON public.exercises USING btree (workout_id);
CREATE INDEX idx_progress_photos_date ON public.progress_photos USING btree (user_id, date DESC);
CREATE UNIQUE INDEX idx_progress_photos_slot ON public.progress_photos USING btree (user_id, date, pose_type) WHERE (deleted_at IS NULL);
CREATE INDEX idx_progress_photos_updated ON public.progress_photos USING btree (user_id, updated_at DESC);
CREATE INDEX idx_progress_photos_user_id ON public.progress_photos USING btree (user_id);
CREATE INDEX idx_sets_exercise_id ON public.sets USING btree (exercise_id);
CREATE INDEX idx_sets_user_id ON public.sets USING btree (user_id);
CREATE INDEX idx_workouts_date ON public.workouts USING btree (user_id, date DESC);
CREATE INDEX idx_workouts_updated ON public.workouts USING btree (user_id, updated_at DESC);
CREATE INDEX idx_workouts_user_id ON public.workouts USING btree (user_id);

CREATE INDEX coach_conversations_user_recent_idx ON runio.coach_conversations USING btree (user_id, last_turn_at DESC);
CREATE INDEX coach_turns_conversation_idx ON runio.coach_turns USING btree (conversation_id, seq);
CREATE INDEX coach_turns_user_recent_idx ON runio.coach_turns USING btree (user_id, created_at DESC);
CREATE INDEX coach_usage_user_created_idx ON runio.coach_usage USING btree (user_id, created_at DESC);
CREATE INDEX plan_sessions_plan_week_idx ON runio.plan_sessions USING btree (plan_id, week_number);
CREATE INDEX plan_sessions_user_date_idx ON runio.plan_sessions USING btree (user_id, scheduled_date);
CREATE INDEX plan_weeks_plan_idx ON runio.plan_weeks USING btree (plan_id, week_number);
CREATE UNIQUE INDEX plans_one_active_per_user_idx ON runio.plans USING btree (user_id) WHERE (status = 'active'::text);
CREATE INDEX plans_user_status_idx ON runio.plans USING btree (user_id, status, created_at DESC);
CREATE INDEX runs_user_started_idx ON runio.runs USING btree (user_id, started_at DESC);


-- ---------------------------------------------------------------------------
-- 9. Functions
--
-- Ordered after the tables because the SQL-language ones are parsed at
-- creation time and reference runio.coach_usage.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  INSERT INTO public.profiles (id, email)
  VALUES (NEW.id, NEW.email)
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION runio.touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at := now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.runio_coach_record_usage(p_user uuid, p_surface text, p_prompt_tokens integer, p_completion_tokens integer, p_total_tokens integer, p_cost_credits numeric, p_cost_estimated boolean, p_outcome text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  insert into runio.coach_usage (
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

  delete from runio.coach_usage
   where user_id = p_user
     and created_at < now() - interval '31 days';
$function$;

CREATE OR REPLACE FUNCTION public.runio_coach_usage_window(p_user uuid, p_since timestamp with time zone)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'at', u.created_at,
        'surface', u.surface,
        'cost_credits', u.cost_credits
      ) order by u.created_at
    ),
    '[]'::jsonb
  )
  from runio.coach_usage u
  where u.user_id = p_user
    and u.created_at >= p_since;
$function$;

CREATE OR REPLACE FUNCTION public.runio_delete_account(p_user_id uuid, p_delete_shared boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_sibling_tables constant text[] := array[
    'public.workouts',
    'public.exercises',
    'public.sets',
    'public.progress_photos',
    'public.ai_summary_requests'
  ];
  v_table          text;
  v_has_row        boolean;
  v_sibling_data   boolean := false;
  v_deleted        bigint;
  v_counts         jsonb := '{}'::jsonb;
  v_shared_deleted boolean := false;
begin
  if p_user_id is null then
    raise exception 'runio_delete_account: p_user_id is required';
  end if;

  -- 1. Is this login in use by the sibling app? Guarded by to_regclass and a
  --    column lookup, so the check simply reports "no data" instead of erroring
  --    if Liftio's v2 moves these tables into a `liftio` schema.
  foreach v_table in array v_sibling_tables loop
    if to_regclass(v_table) is not null
      and exists (
        select 1
        from pg_attribute a
        where a.attrelid = to_regclass(v_table)::oid
          and a.attname = 'user_id'
          and a.attnum > 0
          and not a.attisdropped
      )
    then
      execute format(
        'select exists (select 1 from %s where user_id = $1)', v_table
      ) into v_has_row using p_user_id;
      v_sibling_data := v_sibling_data or v_has_row;
    end if;
  end loop;

  -- 2. Sweep every table in the `runio` schema that is keyed to a user, rather
  --    than a hard-coded list: a table added later (persisted plans, check-ins)
  --    is then covered by construction instead of by remembering to edit this.
  --    Ordered by inbound foreign-key count so children go before parents, which
  --    holds whether or not a future table declares ON DELETE CASCADE.
  for v_table in
    -- Always schema qualified and quoted, never bare `oid::regclass::text`,
    -- which would drop the schema for anything on the search path.
    select format('%I.%I', n.nspname, c.relname)
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    join pg_attribute a on a.attrelid = c.oid
      and a.attname = 'user_id'
      and a.attnum > 0
      and not a.attisdropped
    where n.nspname = 'runio'
      -- 'r' ordinary tables, 'p' partitioned — never views or foreign tables.
      and c.relkind in ('r', 'p')
    order by (
      select count(*)
      from pg_constraint fk
      where fk.confrelid = c.oid
        and fk.contype = 'f'
    ) asc, c.relname asc
  loop
    execute format('delete from %s where user_id = $1', v_table)
      using p_user_id;
    get diagnostics v_deleted = row_count;
    v_counts := v_counts || jsonb_build_object(v_table, v_deleted);
  end loop;

  -- 3. The health columns Runio added to the shared profile. Cleared even when
  --    the profile row stays, because they are Runio's special-category data and
  --    nothing else is using them yet (ADR-0008).
  update public.profiles
     set dob = null, weight_kg = null
   where id = p_user_id;

  -- 4. The shared rows and the login, but only when nothing else needs them.
  if p_delete_shared and not v_sibling_data then
    delete from public.user_settings where user_id = p_user_id;
    delete from public.profiles where id = p_user_id;
    v_shared_deleted := true;
  end if;

  return jsonb_build_object(
    'deleted_rows', v_counts,
    'sibling_app_data', v_sibling_data,
    'shared_deleted', v_shared_deleted,
    -- The Edge Function removes the auth.users row itself, via the Admin API,
    -- only when this is true.
    'auth_user_deletable', p_delete_shared and not v_sibling_data
  );
end;
$function$;

comment on function public.runio_delete_account(uuid, boolean) is
  'Erases a user''s Runio data; removes the shared profile/settings only when '
  'the account holds no Liftio data. service_role only — see '
  'supabase/functions/delete-account.';

-- Event-trigger function backing `ensure_rls` below. Auto-enables RLS on any
-- table created in `public`. Present on the live database; recreated here so a
-- from-scratch replay behaves the same.
CREATE OR REPLACE FUNCTION public.rls_auto_enable()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$;


-- ---------------------------------------------------------------------------
-- 10. Triggers
--
-- `on_auth_user_created` lives on auth.users and needs elevated privileges to
-- create. It is the only reason a `public.profiles` row appears at signup.
-- ---------------------------------------------------------------------------

CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

CREATE TRIGGER touch_updated_at BEFORE UPDATE ON runio.runs
  FOR EACH ROW EXECUTE FUNCTION runio.touch_updated_at();
CREATE TRIGGER touch_updated_at BEFORE UPDATE ON runio.plans
  FOR EACH ROW EXECUTE FUNCTION runio.touch_updated_at();
CREATE TRIGGER touch_updated_at BEFORE UPDATE ON runio.plan_weeks
  FOR EACH ROW EXECUTE FUNCTION runio.touch_updated_at();
CREATE TRIGGER touch_updated_at BEFORE UPDATE ON runio.plan_sessions
  FOR EACH ROW EXECUTE FUNCTION runio.touch_updated_at();
CREATE TRIGGER touch_updated_at BEFORE UPDATE ON runio.coach_conversations
  FOR EACH ROW EXECUTE FUNCTION runio.touch_updated_at();

CREATE EVENT TRIGGER ensure_rls ON ddl_command_end
  EXECUTE FUNCTION public.rls_auto_enable();


-- ---------------------------------------------------------------------------
-- 11. Row-level security
--
-- Recorded as-is. Two things are worth knowing before the restructure rewrites
-- these: every policy below targets the `public` ROLE (i.e. anon included, held
-- out only because auth.uid() is null for anon) rather than `authenticated`;
-- and Liftio's policies are `FOR ALL ... USING` with no WITH CHECK, so the
-- insert path is governed by the USING clause alone.
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.user_settings enable row level security;
alter table public.workouts enable row level security;
alter table public.exercises enable row level security;
alter table public.sets enable row level security;
alter table public.progress_photos enable row level security;
alter table public.ai_summary_requests enable row level security;
alter table public.announcements enable row level security;

alter table runio.runner_profiles enable row level security;
alter table runio.runs enable row level security;
alter table runio.run_points enable row level security;
alter table runio.run_splits enable row level security;
alter table runio.plans enable row level security;
alter table runio.plan_weeks enable row level security;
alter table runio.plan_sessions enable row level security;
alter table runio.coach_conversations enable row level security;
alter table runio.coach_turns enable row level security;
alter table runio.coach_summaries enable row level security;
alter table runio.coach_usage enable row level security;

create policy "Users can view own profile" on public.profiles
  as permissive for SELECT to public using ((auth.uid() = id));
create policy "Users can insert own profile" on public.profiles
  as permissive for INSERT to public with check ((auth.uid() = id));
create policy "Users can update own profile" on public.profiles
  as permissive for UPDATE to public using ((auth.uid() = id));

create policy "Users can manage own settings" on public.user_settings
  as permissive for ALL to public using ((auth.uid() = user_id));
create policy "Users can manage own workouts" on public.workouts
  as permissive for ALL to public using ((auth.uid() = user_id));
create policy "Users can manage own exercises" on public.exercises
  as permissive for ALL to public using ((auth.uid() = user_id));
create policy "Users can manage own sets" on public.sets
  as permissive for ALL to public using ((auth.uid() = user_id));
create policy "Users can manage own progress photos" on public.progress_photos
  as permissive for ALL to public using ((auth.uid() = user_id));

create policy "Users can only see their own requests" on public.ai_summary_requests
  as permissive for SELECT to public using ((auth.uid() = user_id));
create policy "Public read published announcements" on public.announcements
  as permissive for SELECT to anon, authenticated using ((is_published = true));

create policy "own runner_profile" on runio.runner_profiles
  as permissive for ALL to public using ((user_id = auth.uid())) with check ((user_id = auth.uid()));
create policy "own runs" on runio.runs
  as permissive for ALL to public using ((user_id = auth.uid())) with check ((user_id = auth.uid()));
create policy "own run_points" on runio.run_points
  as permissive for ALL to public using ((user_id = auth.uid())) with check ((user_id = auth.uid()));
create policy "own run_splits" on runio.run_splits
  as permissive for ALL to public using ((user_id = auth.uid())) with check ((user_id = auth.uid()));
create policy "own plans" on runio.plans
  as permissive for ALL to public using ((user_id = auth.uid())) with check ((user_id = auth.uid()));
create policy "own plan_weeks" on runio.plan_weeks
  as permissive for ALL to public using ((user_id = auth.uid())) with check ((user_id = auth.uid()));
create policy "own plan_sessions" on runio.plan_sessions
  as permissive for ALL to public using ((user_id = auth.uid())) with check ((user_id = auth.uid()));
create policy "own coach_conversations" on runio.coach_conversations
  as permissive for ALL to public using ((user_id = auth.uid())) with check ((user_id = auth.uid()));
create policy "own coach_turns" on runio.coach_turns
  as permissive for ALL to public using ((user_id = auth.uid())) with check ((user_id = auth.uid()));
create policy "own coach_summaries" on runio.coach_summaries
  as permissive for ALL to public using ((user_id = auth.uid())) with check ((user_id = auth.uid()));

-- runio.coach_usage has RLS enabled and deliberately NO policy: it is reachable
-- only through the SECURITY DEFINER functions above, under service_role.


-- ---------------------------------------------------------------------------
-- 12. Privileges
--
-- `public` relies on Supabase's schema default ACL and is not restated here.
-- `runio` is explicit: `authenticated` gets CRUD on everything except
-- coach_usage, which is service-role only because it is the rate limiter's
-- ledger — a client that can write it can lift its own spend cap.
-- ---------------------------------------------------------------------------

grant usage on schema runio to authenticated, service_role;

alter default privileges in schema runio
  grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema runio
  grant all on tables to service_role;

grant select, insert, update, delete on
  runio.runner_profiles, runio.runs, runio.run_points, runio.run_splits,
  runio.plans, runio.plan_weeks, runio.plan_sessions,
  runio.coach_conversations, runio.coach_summaries
  to authenticated;

-- Append-only transcript: no UPDATE for clients.
grant select, insert, delete on runio.coach_turns to authenticated;

grant all on
  runio.runner_profiles, runio.runs, runio.run_points, runio.run_splits,
  runio.plans, runio.plan_weeks, runio.plan_sessions,
  runio.coach_conversations, runio.coach_turns, runio.coach_summaries,
  runio.coach_usage
  to service_role;

revoke all on runio.coach_usage from authenticated;

revoke all on function public.runio_delete_account(uuid, boolean) from public, anon, authenticated;
grant execute on function public.runio_delete_account(uuid, boolean) to service_role;


-- ---------------------------------------------------------------------------
-- 13. Comments
-- ---------------------------------------------------------------------------

comment on table public.announcements is 'In-app announcements / release notes. Read by all clients; written via service_role only.';
comment on column public.announcements.sections is 'JSON array of {label, title, body} objects — the structured body of the announcement card.';

comment on table runio.coach_conversations is 'A coach conversation. Retention is applied to its turns; see runio.coach_turns.';
comment on table runio.coach_turns is 'Append-only coach transcript. Special-category data — pruned by the client to a rolling window; UPDATE is revoked from `authenticated`.';
comment on table runio.coach_summaries is 'One rolling prose summary per runner — replaced on regeneration, never appended to. Special-category data.';
comment on table runio.coach_usage is 'Per-user coach model-call accounting for the ADR-0007 rate limit and spend cap. Service-role only. Token counts and cost only — never prompt or response content.';

comment on column runio.plans.goal_distance_m is 'Null for a rhythm or log plan: they are not training toward a distance (ADR-0011). Not missing data.';
comment on column runio.plans.event_date is 'Null when there is no race entered -- a horizon plan ramps with nothing to taper into, and a rhythm plan has no date at all (ADR-0011).';
comment on column runio.plans.commitments is 'Repeating weekly commitments for a PlanShape.rhythm, as [{"weekday":6,"distance_meters":5000,"timed":true,"label":"parkrun"}]. Empty for every other shape.';
comment on column runio.runner_profiles.strength_days_per_week is 'Strength days the runner asked for. Nullable here (unlike plans, where it is part of a plan that was actually built) because a profile row can predate the question being asked.';


-- ---------------------------------------------------------------------------
-- 14. Storage
--
-- One private bucket. Ownership is the first path segment, so a user's objects
-- live under `<uid>/…` and the policies compare that segment to auth.uid().
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('progress-photos', 'progress-photos', false, 10485760,
        array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy "Users can read own progress photos" on storage.objects
  as permissive for SELECT to public
  using (((bucket_id = 'progress-photos'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
create policy "Users can upload own progress photos" on storage.objects
  as permissive for INSERT to public
  with check (((bucket_id = 'progress-photos'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
create policy "Users can update own progress photos" on storage.objects
  as permissive for UPDATE to public
  using (((bucket_id = 'progress-photos'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
create policy "Users can delete own progress photos" on storage.objects
  as permissive for DELETE to public
  using (((bucket_id = 'progress-photos'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));
