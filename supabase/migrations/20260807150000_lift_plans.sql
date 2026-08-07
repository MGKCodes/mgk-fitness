-- What the coach has a lifter working toward.
--
-- Deliberately `run.plans` / `run.plan_weeks` / `run.plan_sessions` with the
-- units changed, because that trio already solves this exact problem for
-- running and re-deriving it would produce something subtly different for no
-- reason. Where this diverges from Run it is because lifting differs, and each
-- divergence is noted below.
--
-- ## The three levels
--
--   plans          one block. The goal, the dates, what the lifter can do.
--   plan_weeks     the arc: which week is building, which is a deload.
--   plan_sessions  the unit that matters: a day, its movements, and its targets.
--
-- The arc exists separately from the sessions because it is generated
-- separately: the coach lays out the block once, then fills in one week at a
-- time, a week ahead. A single call that produced every session of a twelve
-- week block would be the most expensive request in the product, would fail
-- entirely on one bad number, and would have to be regenerated wholesale every
-- time somebody's shoulder hurt on a Tuesday.
--
-- ## The column that makes the whole thing answerable
--
-- `plan_sessions.workout_id`. Set when a planned session is actually trained,
-- so "did they do the plan" is a join rather than a guess at which workout was
-- probably which. It is `text` because `lift.workouts.id` is text — Liftio's
-- client-generated ids, kept.
--
-- ## Why movements are jsonb
--
-- A fourth table (`plan_movements`) would be more queryable, and nothing yet
-- needs to query them: they are written as a block by the generator, read as a
-- block by the app, and validated as a block in Dart. Run made the same call
-- with `plan_sessions.structure_json`. Promote it to a table when something
-- genuinely needs to ask a question across movements — "how much did the coach
-- prescribe for bench in March" is that question, and it is not being asked
-- yet.
--
-- What goes in it is a list of objects, and the shape is the generator's
-- contract rather than the database's:
--
--   [{"name": "Bench press", "sets": 3, "reps": 5, "target_kg": 85,
--     "note": "from your 3x5 at 82.5 on 2026-07-30"}]
--
-- `target_kg` is nullable in that shape, and has to be: an accessory the lifter
-- has never logged has no number to derive one from, and inventing one is the
-- failure the whole "targets come from their own numbers" rule exists to stop.


-- ---------------------------------------------------------------------------
-- 1. The block
-- ---------------------------------------------------------------------------

create table lift.plans (
  id      text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,

  -- What they said they are training for, in their own words. Not an enum:
  -- "get my bench past 100 by Christmas" and "stop my back hurting" are both
  -- real answers and neither survives being turned into a category.
  goal text,

  start_date date     not null,
  weeks      smallint not null check (weeks between 1 and 52),

  -- `draft` is the state a generated plan sits in until the lifter accepts it.
  -- A plan that became active the moment a model produced it would be the app
  -- imposing training rather than proposing it.
  status text not null default 'draft'
    check (status in ('draft', 'active', 'completed', 'superseded')),

  days_per_week      smallint   not null check (days_per_week between 1 and 7),
  -- 1=Monday..7=Sunday, matching the coach surfaces and ISO. A plan is laid out
  -- on named days, so "four days" alone cannot be turned into a week.
  available_weekdays smallint[] not null,

  -- What they have to train with, and what hurts. Both are prompt input rather
  -- than anything the app reasons over, so they stay as the lifter said them.
  equipment    text,
  injury_notes text,

  -- The intake answers as captured, kept so a plan can be explained after the
  -- fact and regenerated from the same inputs. Not read by the app.
  intake jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table lift.plans is
  'One training block. `draft` until the lifter accepts it — a plan that went active the moment a model produced it would be the app imposing training rather than proposing it.';

-- One active plan per lifter, enforced rather than assumed. Two active blocks
-- is not a state with a meaning: Track would have to choose which one today
-- belongs to, and whichever it chose would be wrong half the time.
create unique index plans_one_active_per_user_idx
  on lift.plans (user_id) where status = 'active';
create index plans_user_status_idx
  on lift.plans (user_id, status, created_at desc);


-- ---------------------------------------------------------------------------
-- 2. The arc
-- ---------------------------------------------------------------------------

create table lift.plan_weeks (
  id      text primary key,
  plan_id text not null references lift.plans(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,

  week_number smallint not null check (week_number >= 1),

  -- Run's fourth phase is `taper`, which is a race-week idea. Lifting's is
  -- `deload`, which recurs every third or fourth week rather than arriving once
  -- at the end — so it is a phase here and a boolean there.
  phase text not null check (phase in ('base', 'build', 'peak', 'deload')),

  -- What this week is FOR, in a sentence, written when the arc is laid out and
  -- read by the generator when it fills the week in. It is the only thing
  -- carrying the block's intent from one call to the next.
  intent text,

  generated_at timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  unique (plan_id, week_number)
);

comment on column lift.plan_weeks.intent is
  'What this week is for, in a sentence. Written when the block is laid out and read back when the week is filled in — it is what carries the arc between two separate model calls.';


-- ---------------------------------------------------------------------------
-- 3. The sessions
-- ---------------------------------------------------------------------------

create table lift.plan_sessions (
  id      text primary key,
  plan_id text not null references lift.plans(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,

  week_number    smallint not null check (week_number >= 1),
  weekday        smallint not null check (weekday between 1 and 7),
  scheduled_date date     not null,

  -- What sort of session it is, as the templates name them: `push`, `pull`,
  -- `legs`, `upper`, `full-body`. Free text rather than an enum because the
  -- template set is app data and a check constraint here would make adding one
  -- a migration.
  kind text,

  -- The movements and their targets. See the header for the shape.
  movements jsonb not null default '[]'::jsonb,

  -- Why this session looks like this, in the coach's words, shown to the
  -- lifter. A plan nobody can interrogate is one they follow on trust or not at
  -- all.
  rationale text,

  status text not null default 'planned'
    check (status in ('planned', 'completed', 'skipped')),
  status_at timestamptz,

  -- The join that makes "did they do the plan" answerable without guessing.
  -- ON DELETE SET NULL rather than CASCADE: deleting a logged workout must not
  -- delete the plan that asked for it, or a lifter tidying their history would
  -- silently punch holes in their own block.
  workout_id text references lift.workouts(id) on delete set null,

  updated_at timestamptz not null default now(),

  unique (plan_id, week_number, weekday)
);

comment on column lift.plan_sessions.workout_id is
  'The session actually trained, when it has been. This is what makes "did they follow the plan" a join rather than a guess. SET NULL on delete: tidying the log must not rewrite the plan.';

create index plan_sessions_user_date_idx
  on lift.plan_sessions (user_id, scheduled_date);
-- Track asks "what is today", which is this index; the plan screen asks for a
-- week, which is the unique constraint above.
create index plan_sessions_plan_week_idx
  on lift.plan_sessions (plan_id, week_number);


-- ---------------------------------------------------------------------------
-- 4. Row-level security
--
-- RLS is auto-enabled on new tables by the `rls_auto_enable` event trigger, so
-- these are the policies rather than the enabling. Stated explicitly anyway:
-- RLS on with no policy denies everything, which is only correct on purpose,
-- and the schema contract fails a table that has none.
--
-- `(select auth.uid())` rather than `auth.uid()` so Postgres hoists it into an
-- InitPlan and evaluates it once per statement instead of once per row.
-- ---------------------------------------------------------------------------

alter table lift.plans         enable row level security;
alter table lift.plan_weeks    enable row level security;
alter table lift.plan_sessions enable row level security;

create policy own_plans on lift.plans
  for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy own_plan_weeks on lift.plan_weeks
  for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy own_plan_sessions on lift.plan_sessions
  for all to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);


-- ---------------------------------------------------------------------------
-- 5. Privileges
--
-- `alter default privileges in schema lift` already grants `authenticated` full
-- CRUD on new tables, so these are restatements rather than additions. They are
-- here because "the default granted it" is a worse answer than "this file
-- granted it" when someone is checking what a client can write.
--
-- The client writes plans directly rather than through a function: it accepts a
-- draft, ticks a session off, and reschedules one. All three are its own rows,
-- all three are scoped by RLS, and none of them costs money.
-- ---------------------------------------------------------------------------

grant select, insert, update, delete on
  lift.plans, lift.plan_weeks, lift.plan_sessions
  to authenticated;
grant all on lift.plans, lift.plan_weeks, lift.plan_sessions to service_role;
