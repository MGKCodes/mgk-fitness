-- Columns the sync layer needs, and one the local schema already had.
--
-- Found while writing the client sync: `lift.sets` has no `set_type`, so every
-- warm-up uploaded from a device would come back as a working set. That would
-- silently inflate volume and personal bests on restore — the exact bug the
-- local schema was given a `set_type` column to prevent, reintroduced at the
-- network boundary.

-- Warm-ups. Defaults to 'working', so the 1,249 existing rows keep counting
-- exactly as they do now: the concept did not exist when they were written, so
-- none of them was a warm-up.
alter table lift.sets
  add column if not exists set_type text not null default 'working'
  check (set_type in ('working', 'warmup'));

comment on column lift.sets.set_type is
  'working | warmup. Warm-ups are logged but excluded from volume and from '
  'every personal best. Mirrors the local column of the same name.';

-- Sessions still in progress are never uploaded, so a workout row always has a
-- duration. This is the index the modernise migration dropped with the old
-- `date` column and did not replace: the client pulls by user and recency, and
-- Profile reads the log ordered by when a session started.
create index if not exists idx_workouts_user_started
  on lift.workouts (user_id, started_at desc)
  where deleted_at is null;

-- `updated_at` has to move on its own, or last-write-wins compares a column
-- nothing maintains. The client sets it too, but a trigger is what makes the
-- rule true for every writer rather than for the well-behaved ones.
drop trigger if exists touch_updated_at on lift.workouts;
create trigger touch_updated_at
  before update on lift.workouts
  for each row execute function core.touch_updated_at();
