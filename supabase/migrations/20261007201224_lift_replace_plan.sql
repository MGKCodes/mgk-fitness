-- lift.replace_plan: a new standing plan, whole, in one transaction.
--
-- Lift replaced a plan in three requests: supersede the live one, insert the
-- new one, insert its slots. When the slots failed -- every time, for seven
-- weeks, on columns that did not exist -- the lifter was left with a live plan
-- holding nothing and their old one superseded. A draft-then-promote order in
-- the app narrowed that and could not close it: a promote whose answer was
-- lost, followed by the app's own clean-up, deleted the plan that had just
-- gone live. One call, all of it or none.
--
-- ## Who it runs as
--
-- SECURITY INVOKER, like lift.save_workout: RLS on lift.plans and
-- lift.plan_slots guards this as it guards the direct writes, and every row
-- is written with the caller's own id rather than one from the payload.
--
-- ## What it keeps
--
-- The intake -- goal, equipment, injury notes and the answers whole -- goes on
-- the plan row. Those columns have existed since the block model and nothing
-- wrote them, so every answer a lifter gave the coach was dropped the moment
-- the plan was built.

create or replace function lift.replace_plan(plan jsonb, slots jsonb)
returns void
language plpgsql
security invoker
set search_path to ''
as $$
declare
  caller uuid := auth.uid();
  new_plan text := plan ->> 'id';
begin
  if caller is null then
    raise exception 'replace_plan needs a signed-in caller'
      using errcode = '42501';
  end if;
  if new_plan is null or new_plan = '' then
    raise exception 'replace_plan needs a plan id'
      using errcode = '22023';
  end if;

  -- Supersede first: the partial unique index allows one active plan.
  update lift.plans
     set status = 'superseded'
   where user_id = caller and status = 'active';

  insert into lift.plans
    (id, user_id, status, split, day_order, rationale, days_per_week,
     available_weekdays, started_at, goal, equipment, injury_notes, intake)
  values
    (new_plan,
     caller,
     'active',
     coalesce(plan ->> 'split', 'Full body'),
     coalesce(array(select jsonb_array_elements_text(plan -> 'day_order')),
              '{}'),
     plan ->> 'rationale',
     (plan ->> 'days_per_week')::smallint,
     array(select (jsonb_array_elements_text(plan -> 'available_weekdays'))
                    ::smallint),
     coalesce((plan ->> 'started_at')::date, current_date),
     plan ->> 'goal',
     plan ->> 'equipment',
     plan ->> 'injury_notes',
     plan -> 'intake');

  insert into lift.plan_slots
    (id, plan_id, user_id, day, sort_order, role, movement, is_main, sets,
     reps, sessions_at_same_top, last_top_kg, last_top_reps)
  select s ->> 'id',
         new_plan,
         caller,
         s ->> 'day',
         (s ->> 'sort_order')::smallint,
         s ->> 'role',
         s ->> 'movement',
         coalesce((s ->> 'is_main')::boolean, false),
         coalesce((s ->> 'sets')::smallint, 3),
         coalesce((s ->> 'reps')::smallint, 10),
         coalesce((s ->> 'sessions_at_same_top')::smallint, 0),
         (s ->> 'last_top_kg')::numeric,
         (s ->> 'last_top_reps')::smallint
    from jsonb_array_elements(coalesce(slots, '[]'::jsonb)) as s;
end;
$$;

comment on function lift.replace_plan(jsonb, jsonb) is
  'Supersedes the caller''s active plan and writes a new one with its slots, in one transaction. Security invoker: RLS applies.';

revoke all on function lift.replace_plan(jsonb, jsonb) from public, anon;
grant execute on function lift.replace_plan(jsonb, jsonb) to authenticated;
