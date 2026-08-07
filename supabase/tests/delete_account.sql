-- What `core.delete_account` actually erases, run against real rows.
--
-- The schema contract next door asserts shapes. This asserts BEHAVIOUR, because
-- the failure that matters here is not a missing column — it is a deletion that
-- reports success and leaves data behind, or one that takes data the person did
-- not ask to lose. Neither is visible in a catalog.
--
-- Everything runs inside the outer transaction and is rolled back.
--
--     supabase test db

begin;
create extension if not exists pgtap with schema extensions;

select plan(14);

-- ---------------------------------------------------------------------------
-- Two accounts. The first uses both apps, which is the case every interesting
-- assertion below is about; the second is a bystander who must be untouched.
-- ---------------------------------------------------------------------------

create or replace function pg_temp.seed(p_user uuid, p_email text)
returns void language plpgsql as $$
begin
  insert into auth.users (id, instance_id, aud, role, email)
  values (p_user, '00000000-0000-0000-0000-000000000000',
          'authenticated', 'authenticated', p_email);

  -- `handle_new_user` creates core.profiles, so it is not inserted here.
  -- core.user_settings still carries Liftio's epoch-millis timestamps, and they
  -- have no defaults.
  insert into core.user_settings (user_id, created_at, updated_at)
  values (p_user, 0, 0);

  insert into lift.workouts (id, user_id, name, started_at)
  values (p_user || ':w', p_user, 'Push', now());

  insert into run.runs (id, user_id, started_at, duration_s, distance_m, source, type)
  values (p_user || ':r', p_user, now(), 1800, 5000, 'gps', 'easy');

  -- One conversation and one memory per app, which is the whole point of the
  -- app column: these must be separable.
  insert into coach.conversations (id, user_id, app, kind)
  values (p_user || ':lift', p_user, 'lift', 'coach'),
         (p_user || ':run',  p_user, 'run',  'coach');

  insert into coach.turns (id, conversation_id, user_id, seq, role, body)
  values (p_user || ':lift:1', p_user || ':lift', p_user, 1, 'user', 'shoulder is sore'),
         (p_user || ':run:1',  p_user || ':run',  p_user, 1, 'user', 'knee is sore');

  insert into coach.summaries (user_id, app, summary, turns_covered)
  values (p_user, 'lift', 'Trains four days.', 1),
         (p_user, 'run',  'Runs on Tuesdays.', 1);

  perform coach.record_usage(p_user, 'lift_chat', 10, 10, 20, 0.001, false, 'ok');
end;
$$;

select pg_temp.seed('aaaaaaaa-0000-0000-0000-000000000001', 'both@example.com');
select pg_temp.seed('bbbbbbbb-0000-0000-0000-000000000002', 'bystander@example.com');


-- ---------------------------------------------------------------------------
-- A partial deletion: Run leaves, Lift stays.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$select core.delete_account('aaaaaaaa-0000-0000-0000-000000000001', 'run')$$,
  'a partial deletion runs'
);

select is_empty(
  $$select 1 from run.runs where user_id = 'aaaaaaaa-0000-0000-0000-000000000001'$$,
  'the departing app''s own data is gone'
);

-- 3, 4, 5: the gap this migration closed. Before it, both of these survived a
-- partial deletion, and the only way to remove the running conversation was to
-- delete the entire account.
select is_empty(
  $$select 1 from coach.conversations
     where user_id = 'aaaaaaaa-0000-0000-0000-000000000001' and app = 'run'$$,
  'the departing app''s coach conversation is gone'
);

select is_empty(
  $$select 1 from coach.turns where id = 'aaaaaaaa-0000-0000-0000-000000000001:run:1'$$,
  'its turns go with it, by the conversation FK''s cascade'
);

select is_empty(
  $$select 1 from coach.summaries
     where user_id = 'aaaaaaaa-0000-0000-0000-000000000001' and app = 'run'$$,
  'the departing app''s memory is gone'
);

-- 6, 7, 8: and the half that must NOT go. A deletion that takes the other app's
-- memory is the same severity of bug as one that leaves data behind.
select isnt_empty(
  $$select 1 from coach.conversations
     where user_id = 'aaaaaaaa-0000-0000-0000-000000000001' and app = 'lift'$$,
  'the remaining app keeps its conversation'
);

select isnt_empty(
  $$select 1 from coach.summaries
     where user_id = 'aaaaaaaa-0000-0000-0000-000000000001' and app = 'lift'$$,
  'the remaining app keeps its memory'
);

select isnt_empty(
  $$select 1 from lift.workouts where user_id = 'aaaaaaaa-0000-0000-0000-000000000001'$$,
  'the remaining app keeps its training data'
);

-- 9: the spend ledger survives a partial deletion, or a partial deletion would
-- double as a way to reset a rate limit.
select isnt_empty(
  $$select 1 from coach.usage where user_id = 'aaaaaaaa-0000-0000-0000-000000000001'$$,
  'coach.usage survives: it holds no content, and erasing it would reset the cap'
);

-- 10: the login stays, because an app still holds data.
select is(
  (select (core.delete_account('aaaaaaaa-0000-0000-0000-000000000001', 'run')
           ->> 'auth_user_deletable')::boolean),
  false,
  'the login is not deletable while another app still holds data'
);


-- ---------------------------------------------------------------------------
-- The bystander is untouched throughout.
-- ---------------------------------------------------------------------------

select is(
  (select count(*)::int from coach.summaries
    where user_id = 'bbbbbbbb-0000-0000-0000-000000000002'),
  2,
  'another account keeps both of its memories'
);


-- ---------------------------------------------------------------------------
-- The last app leaves.
-- ---------------------------------------------------------------------------

select is(
  (select (core.delete_account('aaaaaaaa-0000-0000-0000-000000000001', 'lift')
           ->> 'auth_user_deletable')::boolean),
  true,
  'with no app left holding data, the login is reported deletable'
);

select is_empty(
  $$select 1 from coach.usage where user_id = 'aaaaaaaa-0000-0000-0000-000000000001'$$,
  'the spend ledger goes when the account does'
);

select is(
  (select count(*)::int from coach.summaries
    where user_id = 'bbbbbbbb-0000-0000-0000-000000000002'),
  2,
  'and the bystander is still untouched at the end'
);


select * from finish();
rollback;
