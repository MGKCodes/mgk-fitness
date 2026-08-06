-- lift.*: give it Postgres types instead of SQLite-shaped ones.
--
-- These tables came from Liftio's on-device SQLite and were carried into
-- Postgres unchanged: epoch-millisecond integers for dates, `integer` for
-- booleans, and — the strangest one — **`text` columns holding epoch
-- milliseconds as strings**. The 2026-08-06 restructure moved them out of
-- `public` but deliberately did not touch their shape, because moving and
-- rewriting at once makes a failure impossible to diagnose.
--
-- This is the rewrite. It runs second, on a schema already verified in place.
--
-- ## The weight column, and why this is safe
--
-- `sets.weight` was a **unitless number**. Liftio never converted: `formatWeight`
-- rounds the value and appends whatever unit the account is currently set to, so
-- switching units silently reinterpreted the lifter's entire history. There is
-- therefore no general, correct conversion — the unit a row was written in is
-- not recorded anywhere.
--
-- What makes this migration safe is the data rather than the design. Only two
-- accounts hold any non-zero weight (383 sets and 6 sets), **both set to `kg`**,
-- ranging 8–120 with a mean of 44.7 — kilograms for a real lifter. So every
-- stored weight is already metric and the rename is a no-op numerically.
--
-- Renaming it `weight_kg` is the actual fix: the column now carries its unit in
-- its name, so the ambiguity that made this migration risky cannot recur.
--
-- ## A template has no date
--
-- `date = 0` held for exactly the 47 templates and for nothing else, checked in
-- both directions. So `started_at` becomes nullable and a constraint states the
-- rule outright, instead of `0` standing in for "not applicable" and reading as
-- 1 January 1970 to anything that forgets.


-- ---------------------------------------------------------------------------
-- 1. Stand the activity trigger down
--
-- It reads `new.date`, `new.is_template`, `new.deleted_at` and `new.duration`.
-- plpgsql resolves those at execution, so the backfill UPDATE below would fire
-- it against columns mid-rename. Dropped here, rebuilt against the new names at
-- the end — the feed is untouched either way, since none of this changes what a
-- workout *is*.
-- ---------------------------------------------------------------------------

drop trigger if exists sync_activity on lift.workouts;


-- ---------------------------------------------------------------------------
-- 2. lift.workouts
-- ---------------------------------------------------------------------------

alter table lift.workouts add column started_at timestamptz;

update lift.workouts
   set started_at = case when date > 0 then to_timestamp(date / 1000.0) end;

alter table lift.workouts drop column date;

alter table lift.workouts
  alter column is_template drop default,
  alter column is_template type boolean using (is_template <> 0),
  alter column is_template set default false;

alter table lift.workouts
  alter column deleted_at type timestamptz
    using case when deleted_at is null then null
               else to_timestamp(deleted_at / 1000.0) end;

alter table lift.workouts
  alter column created_at type timestamptz
    using to_timestamp(created_at::bigint / 1000.0),
  alter column created_at set default now();

alter table lift.workouts
  alter column updated_at type timestamptz
    using to_timestamp(updated_at::bigint / 1000.0),
  alter column updated_at set default now();

alter table lift.workouts rename column duration to duration_s;

-- Says the rule rather than relying on everyone remembering it.
alter table lift.workouts add constraint workouts_template_has_no_date check (
  (is_template and started_at is null) or (not is_template and started_at is not null)
);

comment on column lift.workouts.started_at is
  'When the session happened. NULL for a template, which has no date — enforced by workouts_template_has_no_date.';
comment on column lift.workouts.deleted_at is
  'Soft delete. Kept rather than hard-deleted so a delete syncs to other devices instead of the row reappearing from backup.';


-- ---------------------------------------------------------------------------
-- 3. lift.exercises
-- ---------------------------------------------------------------------------

alter table lift.exercises rename column exercise_name to name;

alter table lift.exercises
  alter column created_at type timestamptz
    using to_timestamp(created_at::bigint / 1000.0),
  alter column created_at set default now();


-- ---------------------------------------------------------------------------
-- 4. lift.sets
-- ---------------------------------------------------------------------------

alter table lift.sets rename column weight to weight_kg;
alter table lift.sets rename column duration to duration_s;
alter table lift.sets rename column distance to distance_m;

alter table lift.sets
  alter column is_completed drop default,
  alter column is_completed type boolean using (is_completed <> 0),
  alter column is_completed set default false;

alter table lift.sets
  alter column created_at type timestamptz
    using to_timestamp(created_at::bigint / 1000.0),
  alter column created_at set default now();

comment on column lift.sets.weight_kg is
  'Kilograms, always. Store metric, convert at display. The predecessor column was unitless and its meaning depended on the account''s current display setting, which made every history silently reinterpretable.';


-- ---------------------------------------------------------------------------
-- 5. Rebuild the activity trigger against the new column names
--
-- Simpler than it was: no /1000 conversion, no `<> 0` boolean test, and the
-- three exclusions collapse to two because a template is now identifiable
-- without consulting its date.
-- ---------------------------------------------------------------------------

create or replace function core.sync_activity_from_workout()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if new.is_template or new.deleted_at is not null or new.started_at is null then
    delete from core.activities where workout_id = new.id;
    return new;
  end if;

  insert into core.activities
    (user_id, app, kind, occurred_at, duration_s, title, workout_id)
  values
    (new.user_id, 'lift', 'workout', new.started_at,
     nullif(new.duration_s, 0), nullif(new.name, ''), new.id)
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
