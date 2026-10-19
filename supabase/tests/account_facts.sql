-- What `core.account_facts` says about an address, and who may ask.
--
-- `account-lookup/status.ts` decides the screen from these facts and is tested
-- in Deno. This asserts the facts themselves against real `auth` rows, and
-- that only the service role can read them.
--
-- Everything runs inside the outer transaction and is rolled back.
--
--     supabase test db

begin;
create extension if not exists pgtap with schema extensions;

select plan(9);

create or replace function pg_temp.user(
  p_id uuid, p_email text, p_confirmed boolean, p_password text
) returns void language sql as $$
  insert into auth.users
    (id, instance_id, aud, role, email, email_confirmed_at, encrypted_password, created_at)
  values (p_id, '00000000-0000-0000-0000-000000000000', 'authenticated',
          'authenticated', p_email,
          case when p_confirmed then now() end, p_password, now());
$$;

create or replace function pg_temp.identity(p_user uuid, p_provider text)
returns void language sql as $$
  insert into auth.identities
    (id, user_id, provider, provider_id, identity_data, created_at, updated_at)
  values (gen_random_uuid(), p_user, p_provider, p_user || ':' || p_provider,
          jsonb_build_object('sub', p_user || ':' || p_provider), now(), now());
$$;

select pg_temp.user('a0000000-0000-0000-0000-000000000001', 'password@example.com', true, '$2a$10$hash');
select pg_temp.identity('a0000000-0000-0000-0000-000000000001', 'email');
select pg_temp.user('a0000000-0000-0000-0000-000000000002', 'waiting@example.com', false, '$2a$10$hash');
select pg_temp.user('a0000000-0000-0000-0000-000000000003', 'apple@example.com', true, '');
select pg_temp.identity('a0000000-0000-0000-0000-000000000003', 'apple');
select pg_temp.user('a0000000-0000-0000-0000-000000000004', 'both@example.com', true, null);
select pg_temp.identity('a0000000-0000-0000-0000-000000000004', 'google');
select pg_temp.identity('a0000000-0000-0000-0000-000000000004', 'apple');

select is(
  core.account_facts('nobody@example.com'),
  '{"exists": false}'::jsonb,
  'an address with no account says only that'
);

select is(
  core.account_facts('password@example.com'),
  '{"exists": true, "confirmed": true, "has_password": true, "providers": []}'::jsonb,
  'an email account: confirmed, a password, and the email identity left out'
);

select is(
  core.account_facts('  Password@Example.COM '),
  core.account_facts('password@example.com'),
  'what was typed is trimmed and matched without case'
);

select is(
  core.account_facts('waiting@example.com'),
  '{"exists": true, "confirmed": false, "has_password": true, "providers": []}'::jsonb,
  'a sign-up nobody confirmed'
);

select is(
  core.account_facts('apple@example.com'),
  '{"exists": true, "confirmed": true, "has_password": false, "providers": ["apple"]}'::jsonb,
  'an Apple account has no password'
);

select is(
  core.account_facts('both@example.com') -> 'providers',
  '["apple", "google"]'::jsonb,
  'providers come back sorted, whatever order they were added in'
);

select is(
  (select array_agg(key order by key) from jsonb_object_keys(core.account_facts('both@example.com')) as key),
  array['confirmed', 'exists', 'has_password', 'providers'],
  'nothing else about the account leaves the routine'
);

set local role anon;
select throws_ok(
  $$select core.account_facts('password@example.com')$$,
  '42501',
  null,
  'anon cannot call it'
);
reset role;

set local role authenticated;
select throws_ok(
  $$select core.account_facts('password@example.com')$$,
  '42501',
  null,
  'a signed-in user cannot call it either'
);
reset role;

select * from finish();
rollback;
