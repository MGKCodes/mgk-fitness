-- lift.save_workout, run as a signed-in lifter would run it.
--
-- As the caller, not as the superuser the tests start as: the function is
-- SECURITY INVOKER precisely so row-level security applies, and a test run as
-- the superuser would pass through every policy it exists to respect.
--
--     supabase test db

begin;
create extension if not exists pgtap with schema extensions;

select plan(15);

insert into auth.users (id, instance_id, aud, role, email)
values ('aaaaaaaa-5a5e-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'lifter@example.com'),
       ('bbbbbbbb-5a5e-0000-0000-000000000002',
        '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'other@example.com');

create or replace function pg_temp.as_lifter(p_user text)
returns void language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
                     json_build_object('sub', p_user, 'role', 'authenticated')::text,
                     true);
end;
$$;

-- A session's payload: one movement, [p_sets] sets. In `public` rather than
-- `pg_temp`, because it is called after the switch to `authenticated`, which
-- has no use of the superuser's temporary schema. Rolled back with the rest.
create or replace function public.pgtap_session(p_id text, p_sets int,
                                           p_started text default '2026-09-28T17:00:00Z')
returns jsonb language sql as $$
  select jsonb_build_object(
    'id', p_id,
    'name', 'Push',
    'started_at', p_started,
    'duration_s', 3600,
    'is_template', false,
    'updated_at', '2000-01-01T00:00:00Z',
    'exercises', jsonb_build_array(jsonb_build_object(
      'id', p_id || ':e',
      'name', 'Barbell Bench Press',
      'order_index', 0,
      'sets', (select coalesce(jsonb_agg(jsonb_build_object(
                 'id', p_id || ':s' || n,
                 'set_number', n,
                 'reps', 5,
                 'weight_kg', 100,
                 'is_completed', true,
                 'set_type', 'working')), '[]'::jsonb)
               from generate_series(1, p_sets) as g(n))
    ))
  );
$$;


-- ---------------------------------------------------------------------------
-- A workout goes up whole
-- ---------------------------------------------------------------------------

select pg_temp.as_lifter('aaaaaaaa-5a5e-0000-0000-000000000001');

select lives_ok(
  $$select lift.save_workout(public.pgtap_session('s1', 2))$$,
  'a session saves in one call'
);
select is(
  (select count(*)::int from lift.sets where exercise_id = 's1:e'),
  2,
  'with its movement and both sets'
);
select is(
  (select user_id::text from lift.workouts where id = 's1'),
  'aaaaaaaa-5a5e-0000-0000-000000000001',
  'written as the caller'
);
select ok(
  (select updated_at > '2020-01-01' from lift.workouts where id = 's1'),
  'stamped with the server''s clock, not the phone''s'
);

select lives_ok(
  $$select lift.save_workout(public.pgtap_session('s1', 1))$$,
  'saving it again replaces it'
);
select is(
  (select count(*)::int from lift.sets where exercise_id = 's1:e'),
  1,
  'a set removed on the phone is removed here too'
);


-- ---------------------------------------------------------------------------
-- All of it or none of it
-- ---------------------------------------------------------------------------

-- A session with no date breaks workouts_template_has_no_date.
select throws_ok(
  $$select lift.save_workout(public.pgtap_session('s1', 3, null))$$,
  '23514',
  null,
  'a session with no date is refused'
);
select is(
  (select count(*)::int from lift.sets where exercise_id = 's1:e'),
  1,
  'and the refusal leaves the saved copy exactly as it was'
);


-- ---------------------------------------------------------------------------
-- Saved workouts and deletions
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select lift.save_workout(jsonb_build_object(
      'id', 't1', 'name', 'Push', 'is_template', true, 'started_at', null,
      'premade_id', 'push',
      'exercises', jsonb_build_array(jsonb_build_object(
        'id', 't1:e', 'name', 'Bench', 'order_index', 0,
        'sets', jsonb_build_array(
          jsonb_build_object('id', 't1:s1', 'set_number', 1, 'reps', 8),
          jsonb_build_object('id', 't1:s2', 'set_number', 2, 'reps', 8)))))) $$,
  'a saved workout goes up as a template with no date'
);

reset role;
select is(
  (select count(*)::int from core.activities where workout_id = 's1'),
  1,
  'a session is in the activity feed'
);
select is(
  (select count(*)::int from core.activities where workout_id = 't1'),
  0,
  'a template never is'
);

select pg_temp.as_lifter('aaaaaaaa-5a5e-0000-0000-000000000001');
select lives_ok(
  $$select lift.save_workout(public.pgtap_session('s1', 1)
      || jsonb_build_object('deleted_at', '2026-09-29T08:00:00Z'))$$,
  'a deletion goes up as the same document with deleted_at'
);
reset role;
select is(
  (select count(*)::int from core.activities where workout_id = 's1'),
  0,
  'and leaves the activity feed'
);


-- ---------------------------------------------------------------------------
-- Not somebody else's
-- ---------------------------------------------------------------------------

select pg_temp.as_lifter('bbbbbbbb-5a5e-0000-0000-000000000002');
select throws_ok(
  $$select lift.save_workout(public.pgtap_session('t1', 1))$$,
  '42501',
  null,
  'another account cannot overwrite a workout by knowing its id'
);

reset role;
select is(
  (select is_template from lift.workouts where id = 't1'),
  true,
  'and the owner''s workout is untouched'
);

select * from finish();
rollback;
