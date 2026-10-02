-- The waiting list, called as the website calls it.
--
-- As `anon`, not as the superuser the tests start as: the whole design is what
-- a stranger with the publishable key can and cannot do, and the superuser can
-- do all of it.
--
--     supabase test db

begin;
create extension if not exists pgtap with schema extensions;

select plan(11);


-- ---------------------------------------------------------------------------
-- A stranger can join
-- ---------------------------------------------------------------------------

set local role anon;

select lives_ok(
  $$select core.join_waiting_list('  Runner@Example.com ')$$,
  'an address goes on the list'
);
select lives_ok(
  $$select core.join_waiting_list('runner@example.com')$$,
  'and asking again is not an error, so nothing is learnt by trying'
);

reset role;

select is(
  (select count(*)::int from core.waiting_list),
  1,
  'twice is still one row'
);
select is(
  (select email from core.waiting_list),
  'runner@example.com',
  'kept lowered and trimmed'
);
select is(
  (select source from core.waiting_list),
  'web',
  'and marked as left on the website'
);


-- ---------------------------------------------------------------------------
-- What is not an address is refused
-- ---------------------------------------------------------------------------

set local role anon;

select throws_ok(
  $$select core.join_waiting_list('not an address')$$,
  '23514',
  null,
  'something that is not an address is turned down'
);
select throws_ok(
  $$select core.join_waiting_list('a@b.co', 'NOT A SOURCE')$$,
  '23514',
  null,
  'and so is a source that is not a short lowercase word'
);


-- ---------------------------------------------------------------------------
-- And a stranger can do nothing else
-- ---------------------------------------------------------------------------

select throws_ok(
  $$select email from core.waiting_list$$,
  '42501',
  null,
  'the list cannot be read'
);
select throws_ok(
  $$insert into core.waiting_list (email) values ('direct@example.com')$$,
  '42501',
  null,
  'or written to directly'
);

set local role authenticated;

select throws_ok(
  $$select email from core.waiting_list$$,
  '42501',
  null,
  'nor by somebody signed in, whatever the schema grants by default'
);

reset role;

select ok(
  (select relrowsecurity from pg_class where oid = 'core.waiting_list'::regclass),
  'and row-level security is on behind all of that'
);


select * from finish();
rollback;
