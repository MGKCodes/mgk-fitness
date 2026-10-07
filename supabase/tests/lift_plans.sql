-- The plan invariants, exercised rather than inspected.
--
-- Each of these is a rule the schema enforces and the app would otherwise have
-- to remember. They are asserted by trying to break them, because a constraint
-- that exists and a constraint that binds are different claims — and the
-- second is the one that matters at 2am when a generator retries.
--
-- Rewritten for the standing plan. The block model's invariants — a week
-- number, one session per weekday per week, a session belonging to a week that
-- exists — went with `plan_weeks` and `plan_sessions`. What replaces them is
-- about slots, and the two that survived unchanged are the ones that were never
-- about blocks: a lifter has one active plan, and a plan belongs to one person.
--
--     supabase test db

begin;
create extension if not exists pgtap with schema extensions;

select plan(12);

insert into auth.users (id, instance_id, aud, role, email)
values ('dddddddd-0000-0000-0000-000000000004',
        '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'lifter@example.com');

insert into lift.plans (id, user_id, status, days_per_week,
                        available_weekdays, split, started_at)
values ('plan-1', 'dddddddd-0000-0000-0000-000000000004', 'active', 4,
        '{1,2,4,5}', 'upper_lower', date '2026-03-02');


-- ---------------------------------------------------------------------------
-- One live plan
--
-- Two active plans is not a state with a meaning: the plan screen would have to
-- choose which one today belongs to, and whichever it chose would be wrong half
-- the time. Survives the model change unchanged, because it was never about
-- weeks.
-- ---------------------------------------------------------------------------

select throws_ok(
  $$insert into lift.plans (id, user_id, status, days_per_week,
                            available_weekdays, split)
    values ('plan-2', 'dddddddd-0000-0000-0000-000000000004', 'active', 3,
            '{1,3,5}', 'full_body')$$,
  '23505',
  null,
  'a lifter cannot have two active plans at once'
);

select lives_ok(
  $$insert into lift.plans (id, user_id, status, days_per_week,
                            available_weekdays, split)
    values ('plan-3', 'dddddddd-0000-0000-0000-000000000004', 'superseded', 3,
            '{1,3,5}', 'full_body')$$,
  'a replaced plan stays in the history beside the live one'
);


-- ---------------------------------------------------------------------------
-- There is no finish line, so there is no status for reaching one
-- ---------------------------------------------------------------------------

select throws_ok(
  $$update lift.plans set status = 'completed' where id = 'plan-1'$$,
  '23514',
  null,
  'a standing plan cannot be completed, because it does not end'
);


-- ---------------------------------------------------------------------------
-- Slots
-- ---------------------------------------------------------------------------

insert into lift.plan_slots (id, plan_id, user_id, day, sort_order,
                             role, movement, is_main)
values ('slot-1', 'plan-1', 'dddddddd-0000-0000-0000-000000000004',
        'Upper', 0, 'horizontal press', 'Barbell Bench Press', true);

select throws_ok(
  $$insert into lift.plan_slots (id, plan_id, user_id, day, sort_order,
                                 role, movement, is_main)
    values ('slot-2', 'plan-1', 'dddddddd-0000-0000-0000-000000000004',
            'Upper', 0, 'vertical pull', 'Wide Grip Lat Pull Down', true)$$,
  '23505',
  null,
  'two movements cannot claim the same position on a day'
);

select lives_ok(
  $$insert into lift.plan_slots (id, plan_id, user_id, day, sort_order,
                                 role, movement, is_main)
    values ('slot-3', 'plan-1', 'dddddddd-0000-0000-0000-000000000004',
            'Lower', 0, 'squat', 'Barbell Back Squat', true)$$,
  'the same position on a different day is a different slot'
);

-- A movement that has never been done has no numbers, and a zero is not the
-- same claim as an absence: the app renders null as a blank field and would
-- render 0 kg as a prescription.
select throws_ok(
  $$insert into lift.plan_slots (id, plan_id, user_id, day, sort_order,
                                 role, movement, last_top_kg)
    values ('slot-4', 'plan-1', 'dddddddd-0000-0000-0000-000000000004',
            'Lower', 1, 'hinge', 'Barbell Deadlift', 0)$$,
  '23514',
  null,
  'a logged top set cannot weigh nothing'
);


-- ---------------------------------------------------------------------------
-- What the app writes
--
-- SupabaseStandingPlanStore writes sets and reps on every slot. For seven weeks
-- they were columns the app had and the database did not, and every plan save
-- in production failed on them while every Dart test passed against a fake. A
-- column the app writes is asserted here, where the real schema is.
-- ---------------------------------------------------------------------------

select has_column('lift', 'plan_slots', 'sets', 'a slot stores its sets');
select has_column('lift', 'plan_slots', 'reps', 'a slot stores its reps');

select lives_ok(
  $$insert into lift.plan_slots (id, plan_id, user_id, day, sort_order,
                                 role, movement, is_main, sets, reps)
    values ('slot-6', 'plan-1', 'dddddddd-0000-0000-0000-000000000004',
            'Lower', 2, 'lunge', 'Dumbbell Walking Lunge', false, 3, 12)$$,
  'a slot is written the way the app writes it'
);

select throws_ok(
  $$insert into lift.plan_slots (id, plan_id, user_id, day, sort_order,
                                 role, movement, sets, reps)
    values ('slot-7', 'plan-1', 'dddddddd-0000-0000-0000-000000000004',
            'Lower', 3, 'calves', 'Standing Calf Raise', 0, 10)$$,
  '23514',
  null,
  'a slot of no sets is not a prescription'
);


-- ---------------------------------------------------------------------------
-- Slots belong to their plan
-- ---------------------------------------------------------------------------

select throws_ok(
  $$insert into lift.plan_slots (id, plan_id, user_id, day, sort_order,
                                 role, movement)
    values ('slot-5', 'no-such-plan',
            'dddddddd-0000-0000-0000-000000000004',
            'Upper', 9, 'triceps', 'Cable Tricep Pushdown')$$,
  '23503',
  null,
  'a slot cannot belong to a plan that does not exist'
);

-- Replacing a plan takes its slots with it. Without this the next plan inherits
-- movements from the one it replaced, which is the kind of bug that looks like
-- the coach having strange opinions.
delete from lift.plans where id = 'plan-1';
select is(
  (select count(*)::int from lift.plan_slots where plan_id = 'plan-1'),
  0,
  'deleting a plan takes its slots with it'
);

select * from finish();
rollback;
