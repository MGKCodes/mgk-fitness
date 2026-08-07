-- The plan invariants, exercised rather than inspected.
--
-- Each of these is a rule the schema enforces and the app would otherwise have
-- to remember. They are asserted by trying to break them, because a constraint
-- that exists and a constraint that binds are different claims — and the
-- second is the one that matters at 2am when a generator retries.
--
--     supabase test db

begin;
create extension if not exists pgtap with schema extensions;

select plan(6);

insert into auth.users (id, instance_id, aud, role, email)
values ('dddddddd-0000-0000-0000-000000000004',
        '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'lifter@example.com');

insert into lift.plans (id, user_id, start_date, weeks, status,
                        days_per_week, available_weekdays)
values ('p1', 'dddddddd-0000-0000-0000-000000000004', current_date, 8, 'active',
        4, array[1,2,4,5]::smallint[]);


-- 1 --------------------------------------------------------------------------
-- Two active blocks is not a state with a meaning: Track would have to pick
-- which one today belongs to, and whichever it picked would be wrong half the
-- time. A generator that retries after a timeout is how you get here.
select throws_ok(
  $$insert into lift.plans (id, user_id, start_date, weeks, status,
                            days_per_week, available_weekdays)
    values ('p2', 'dddddddd-0000-0000-0000-000000000004', current_date, 8,
            'active', 4, array[1,2,4,5]::smallint[])$$,
  '23505',
  null,
  'a lifter cannot have two active plans at once'
);


-- 2 --------------------------------------------------------------------------
-- The draft is where a generated plan waits to be accepted, so any number of
-- them must be allowed alongside the active one — the partial index must not
-- have become a total one.
select lives_ok(
  $$insert into lift.plans (id, user_id, start_date, weeks, status,
                            days_per_week, available_weekdays)
    values ('p3', 'dddddddd-0000-0000-0000-000000000004', current_date, 8,
            'draft', 4, array[1,2,4,5]::smallint[]),
           ('p4', 'dddddddd-0000-0000-0000-000000000004', current_date, 8,
            'draft', 4, array[1,2,4,5]::smallint[])$$,
  'drafts are unlimited: only one plan may be ACTIVE'
);


-- 3 --------------------------------------------------------------------------
-- One session per weekday per week. A generator asked to fill a week twice
-- would otherwise double it, and the second copy is indistinguishable from a
-- session the lifter added.
insert into lift.plan_weeks (id, plan_id, user_id, week_number, phase)
values ('w1', 'p1', 'dddddddd-0000-0000-0000-000000000004', 1, 'base');

insert into lift.plan_sessions (id, plan_id, user_id, week_number, weekday,
                                scheduled_date, kind)
values ('s1', 'p1', 'dddddddd-0000-0000-0000-000000000004', 1, 1,
        current_date, 'push');

select throws_ok(
  $$insert into lift.plan_sessions (id, plan_id, user_id, week_number, weekday,
                                    scheduled_date, kind)
    values ('s2', 'p1', 'dddddddd-0000-0000-0000-000000000004', 1, 1,
            current_date, 'pull')$$,
  '23505',
  null,
  'a week cannot have two sessions on the same day'
);


-- 4, 5 -----------------------------------------------------------------------
-- Deleting a logged workout must not delete the planned session that asked for
-- it. CASCADE here would mean a lifter tidying their history silently punched
-- holes in their own block, and the block is the record of what was PRESCRIBED
-- — it stays true whether or not they kept the session they did.
insert into lift.workouts (id, user_id, name, started_at)
values ('wk1', 'dddddddd-0000-0000-0000-000000000004', 'Push', now());

update lift.plan_sessions set workout_id = 'wk1', status = 'completed'
 where id = 's1';

delete from lift.workouts where id = 'wk1';

select isnt_empty(
  $$select 1 from lift.plan_sessions where id = 's1'$$,
  'deleting a logged workout leaves the planned session standing'
);

select is(
  (select workout_id from lift.plan_sessions where id = 's1'),
  null,
  'and its link is nulled rather than left pointing at nothing'
);


-- 6 --------------------------------------------------------------------------
-- Deleting the plan DOES take its weeks and sessions: they have no meaning
-- without it, unlike a workout, which is the lifter's own record.
delete from lift.plans where id = 'p1';

select is_empty(
  $$select 1 from lift.plan_sessions where plan_id = 'p1'
    union all
    select 1 from lift.plan_weeks where plan_id = 'p1'$$,
  'deleting a plan takes its weeks and sessions with it'
);


select * from finish();
rollback;
