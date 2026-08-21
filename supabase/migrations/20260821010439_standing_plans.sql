-- A plan that does not end.
--
-- `lift.plans` was shaped like Runio's: a start date, a number of weeks, an arc
-- of `plan_weeks` with a deload in it, and a row in `plan_sessions` for every
-- session of the block. That is right for a marathon — the plan ends on race
-- day, the taper only means anything relative to it, and `completed` is a real
-- event with a date.
--
-- Lifting has no race day. "Get stronger" does not finish, and a twelve-week
-- block leaves two bad answers on week thirteen: expire it and make somebody
-- re-answer an intake to carry on doing what they were already doing, or
-- quietly extend it and admit the twelve was decorative.
--
-- See docs/plan-model.md for the whole argument.
--
-- ## Why this drops rather than migrates
--
-- **No account has a plan.** The app is unreleased, `lift.plans` holds nothing
-- anybody is standing in the middle of, and there is therefore nobody to
-- convert. A migration that carefully preserved rows would be preserving rows
-- that do not exist, at the cost of carrying two models for ever. Verified
-- before writing this rather than assumed — see the guard below, which fails
-- the migration rather than destroying anything if that stops being true.
--
-- ## The shape
--
-- The plan stops being a list of sessions and becomes the rule that produces
-- them. `plan_sessions` held a row per session for a whole block, written up
-- front, rewritten on every change and thrown away at the end. `plan_slots`
-- holds one row per movement — a couple of dozen — that outlive every session
-- derived from them.

-- ---------------------------------------------------------------------------
-- 0. Refuse rather than destroy
--
-- The whole justification for dropping instead of migrating is that there is
-- nothing to migrate. If that is false on whatever database this runs against,
-- the correct behaviour is to stop: a drop that silently took somebody's
-- training with it is exactly the failure this project has been careful about
-- everywhere else.
-- ---------------------------------------------------------------------------

do $$
declare n bigint;
begin
  select count(*) into n from lift.plans;
  if n > 0 then
    raise exception
      'lift.plans holds % row(s). This migration drops the block model and is '
      'only safe while no plan exists. Write a converting migration instead.', n;
  end if;
end $$;


-- ---------------------------------------------------------------------------
-- 1. The block model goes
--
-- Children first. Both cascade from `lift.plans`, but stating the order means
-- this does not depend on that being true.
-- ---------------------------------------------------------------------------

drop table if exists lift.plan_sessions;
drop table if exists lift.plan_weeks;


-- ---------------------------------------------------------------------------
-- 2. `lift.plans` becomes a standing arrangement
-- ---------------------------------------------------------------------------

alter table lift.plans drop column if exists start_date;
alter table lift.plans drop column if exists weeks;

-- What the plan is CALLED, in the coach's words, and the day it runs on each
-- training day.
--
-- **Free text, deliberately, and this started life as a check constraint on
-- three values.** That quietly made the three templates the app ships the
-- definition of a valid plan: an upper/lower with a dedicated arm day is a
-- perfectly good four-day week and the database would have refused it. What
-- makes a plan good is checked by `PlanShape`, which judges what it DOES —
-- frequency, volume, recovery, movements that exist — and does not care what
-- anybody calls it.
alter table lift.plans
  add column if not exists split text not null default 'Full body';

-- Parallel to available_weekdays: the day each training day runs. Names are the
-- coach's — 'Upper', 'Push', 'Arms', 'Chest and back'. Repeats are normal.
alter table lift.plans
  add column if not exists day_order text[] not null default '{}';

-- One or two sentences on why this shape, written for the lifter. The part a
-- template could never do well, and the reason a model is worth calling here.
alter table lift.plans
  add column if not exists rationale text;

-- Kept for interest, not for arithmetic. Nothing is derived from it, no week
-- number is computed off it, and it expires nothing — it exists so the app can
-- say "running since March", which is a nice thing to know and not a schedule.
alter table lift.plans
  add column if not exists started_at date not null default current_date;

-- `days_per_week` stays and is now derived rather than declared: it is
-- `array_length(available_weekdays, 1)`, and the app chooses the split from it.

-- **`completed` goes.** There is no finish line to reach, so a status meaning
-- "reached the finish line" can only ever be wrong. `superseded` stays and does
-- the work people expect from `completed`: replacing a plan keeps the old one
-- in the history rather than erasing what somebody has run.
alter table lift.plans drop constraint if exists plans_status_check;
alter table lift.plans
  add constraint plans_status_check
  check (status in ('draft', 'active', 'superseded'));

comment on column lift.plans.split is
  'What the plan is called, in the coach''s words. Free text: the shape is judged by what it does, not by which template it matches.';
comment on column lift.plans.day_order is
  'The day of the split each training day runs, parallel to available_weekdays.';
comment on column lift.plans.started_at is
  'When this plan began. Nothing is derived from it and it expires nothing.';


-- ---------------------------------------------------------------------------
-- 3. `lift.plan_slots` — the plan itself
-- ---------------------------------------------------------------------------

create table lift.plan_slots (
  id      text primary key,
  plan_id text not null references lift.plans(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,

  -- Which day of the split this belongs to: 'Upper', 'Push', 'Full body A'.
  -- Text rather than an enum because the day names come from the split
  -- template, and adding a split should not need a migration.
  day        text     not null,
  sort_order smallint not null,

  -- **The role is the plan; the movement is this month's answer to it.**
  -- Swapping a barbell bench for a dumbbell press leaves the slot alone, which
  -- is what lets the app say "your horizontal press has stalled" across a
  -- change of equipment instead of losing the thread whenever a rack is busy.
  role     text    not null,
  movement text    not null,
  is_main  boolean not null default false,

  -- Enough to decide a rotation without reading the whole log. Maintained by
  -- the app when a session is finished.
  sessions_at_same_top smallint not null default 0
    check (sessions_at_same_top >= 0),
  last_top_kg   numeric  check (last_top_kg > 0),
  last_top_reps smallint check (last_top_reps > 0),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- One slot per position on a day. Reordering is an update, not an insert, and
-- two movements claiming the same position is a plan that renders differently
-- depending on which row came back first.
create unique index plan_slots_day_order_idx
  on lift.plan_slots (plan_id, day, sort_order);

-- The read the plan screen actually makes: every slot for one plan, in order.
create index plan_slots_plan_idx
  on lift.plan_slots (plan_id, day, sort_order);

create index plan_slots_user_idx on lift.plan_slots (user_id);

create trigger plan_slots_touch
  before update on lift.plan_slots
  for each row execute function core.touch_updated_at();


-- ---------------------------------------------------------------------------
-- 4. Row-level security
--
-- `(select auth.uid())` rather than `auth.uid()` so Postgres hoists it into an
-- InitPlan and evaluates it once per statement rather than once per row — the
-- same form every other policy in this database uses.
-- ---------------------------------------------------------------------------

alter table lift.plan_slots enable row level security;

create policy own_plan_slots on lift.plan_slots
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);


-- ---------------------------------------------------------------------------
-- 5. Privileges
--
-- Stated rather than left to the schema default, because "the default granted
-- it" is a worse answer than "this file granted it" when somebody is checking
-- what a client can write.
-- ---------------------------------------------------------------------------

grant select, insert, update, delete on lift.plan_slots to authenticated;
grant all on lift.plan_slots to service_role;

comment on table lift.plan_slots is
  'One movement''s place in a standing plan. Outlives every session derived from it.';
