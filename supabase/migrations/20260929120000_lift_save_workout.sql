-- lift.save_workout: one workout, whole, in one transaction.
--
-- Lift sent a workout as four requests: upsert the row, delete its movements,
-- insert the movements, insert the sets. A connection dropped between the
-- delete and the inserts left the server's copy with nothing in it until the
-- next sync, and a phone lost before then took the only full copy with it.
-- This takes the workout as one JSON document and writes all of it or none.
--
-- ## Who it runs as
--
-- SECURITY INVOKER, deliberately. It runs as the caller, so the row-level
-- security already guarding lift.* guards this too: every row is written with
-- the caller's own id, and a workout id that belongs to somebody else fails
-- the policy instead of being overwritten.
--
-- ## Whose clock
--
-- `updated_at` is the server's, always — on insert as well as update. The pull
-- asks for rows changed since the newest `updated_at` it has seen, so a phone
-- whose clock runs behind must not be able to write one in the past, where
-- another phone's pull would never look.
--
-- ## Templates, sessions, deletions
--
-- A saved workout arrives with `is_template` true and no `started_at`; a
-- session with a date. `workouts_template_has_no_date` holds either way, and a
-- payload that breaks it is refused as a whole. A deletion is the same
-- document with `deleted_at` set; the activity trigger already drops a deleted
-- workout from the feed.

create or replace function lift.save_workout(payload jsonb)
returns timestamptz
language plpgsql
security invoker
set search_path to ''
as $$
declare
  caller uuid := auth.uid();
  workout text := payload ->> 'id';
  saved timestamptz;
begin
  if caller is null then
    raise exception 'save_workout needs a signed-in caller'
      using errcode = '42501';
  end if;
  if workout is null or workout = '' then
    raise exception 'save_workout needs a workout id'
      using errcode = '22023';
  end if;

  insert into lift.workouts as w
    (id, user_id, name, started_at, duration_s, notes, is_template,
     template_id, premade_id, deleted_at, updated_at)
  values
    (workout,
     caller,
     coalesce(payload ->> 'name', ''),
     (payload ->> 'started_at')::timestamptz,
     coalesce((payload ->> 'duration_s')::integer, 0),
     payload ->> 'notes',
     coalesce((payload ->> 'is_template')::boolean, false),
     payload ->> 'template_id',
     payload ->> 'premade_id',
     (payload ->> 'deleted_at')::timestamptz,
     now())
  on conflict (id) do update set
    name        = excluded.name,
    started_at  = excluded.started_at,
    duration_s  = excluded.duration_s,
    notes       = excluded.notes,
    is_template = excluded.is_template,
    template_id = excluded.template_id,
    premade_id  = excluded.premade_id,
    deleted_at  = excluded.deleted_at,
    updated_at  = now()
  returning w.updated_at into saved;

  -- The movements, and through the cascade their sets, replaced wholesale.
  -- They carry no clock of their own, so there is nothing to diff against, and
  -- replacing them is what makes a set removed on the phone go here too.
  delete from lift.exercises where workout_id = workout;

  insert into lift.exercises
    (id, user_id, workout_id, name, order_index, notes, cardio_mode)
  select ex.movement ->> 'id',
         caller,
         workout,
         coalesce(ex.movement ->> 'name', ''),
         coalesce((ex.movement ->> 'order_index')::integer, 0),
         ex.movement ->> 'notes',
         ex.movement ->> 'cardio_mode'
    from jsonb_array_elements(coalesce(payload -> 'exercises', '[]'::jsonb))
         as ex(movement);

  insert into lift.sets
    (id, user_id, exercise_id, set_number, reps, weight_kg, is_completed,
     set_type, duration_s, distance_m)
  select st.one ->> 'id',
         caller,
         ex.movement ->> 'id',
         coalesce((st.one ->> 'set_number')::integer, 1),
         coalesce((st.one ->> 'reps')::integer, 0),
         coalesce((st.one ->> 'weight_kg')::real, 0),
         coalesce((st.one ->> 'is_completed')::boolean, false),
         coalesce(st.one ->> 'set_type', 'working'),
         (st.one ->> 'duration_s')::integer,
         (st.one ->> 'distance_m')::real
    from jsonb_array_elements(coalesce(payload -> 'exercises', '[]'::jsonb))
         as ex(movement)
   cross join lateral
         jsonb_array_elements(coalesce(ex.movement -> 'sets', '[]'::jsonb))
         as st(one);

  return saved;
end;
$$;

revoke all on function lift.save_workout(jsonb) from public, anon;
grant execute on function lift.save_workout(jsonb) to authenticated;

comment on function lift.save_workout(jsonb) is
  'Writes one workout — row, movements, sets — in one transaction, as the '
  'caller (RLS applies). updated_at is always the server''s clock. Replaces '
  'the four-request upload that could leave a workout empty on a dropped '
  'connection.';
