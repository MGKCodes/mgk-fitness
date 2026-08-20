-- Schema contract: the invariants that are silently true today and silently
-- false the day someone adds a table in a hurry.
--
-- These began life as Dart tests in the Runio repo that regex-parsed migration
-- files. That checked a proxy for the schema. These check the schema.
--
--     supabase test db

begin;
create extension if not exists pgtap with schema extensions;

select plan(14);


-- 1 ------------------------------------------------------------------------
-- core.delete_account enumerates tables by their `user_id` column rather than
-- a hard-coded list. A user-owned table without one silently escapes erasure —
-- a GDPR problem that no application test would catch.
--
-- **The exemption list is the dangerous part of this test, so it is short and
-- it is argued.** A table earns a place on it only by holding no personal data
-- at all — the same rows for every account, nothing traceable to a person. If
-- adding a table here feels like the quick way to make this pass, it is the
-- wrong table.
--
--   coach.knowledge — training claims and coaching guidance, identical for
--   everybody, authored in the repo and synced. Deleting an account must not
--   delete the coach's knowledge of how to train.
select is(
  (select count(*)::int
   from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('coach', 'lift', 'run')
     and c.relkind = 'r'
     and (n.nspname || '.' || c.relname) not in ('coach.knowledge')
     and not exists (
       select 1 from pg_attribute a
       where a.attrelid = c.oid and a.attname = 'user_id'
         and a.attnum > 0 and not a.attisdropped
     )),
  0,
  'every user-owned table in coach/lift/run declares user_id, so the deletion sweep finds it'
);

-- 1b -----------------------------------------------------------------------
-- The other half of that exemption: a table excused from the sweep had better
-- genuinely hold nothing personal. Asserted rather than trusted, because the
-- exemption above is a hole and this is what keeps it the size it was dug.
select is(
  (select count(*)::int
   from pg_attribute a
   where a.attrelid = 'coach.knowledge'::regclass
     and a.attnum > 0 and not a.attisdropped
     and a.attname in ('user_id', 'email', 'account_id')),
  0,
  'coach.knowledge holds nothing that identifies a person'
);


-- 2 ------------------------------------------------------------------------
-- RLS is the security boundary, not the grants. The repo is public: the anon
-- key ships in every binary and is meant to.
select is(
  (select count(*)::int
   from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('core', 'coach', 'lift', 'run')
     and c.relkind = 'r' and not c.relrowsecurity),
  0,
  'every table in core/coach/lift/run has row-level security enabled'
);


-- 3 ------------------------------------------------------------------------
-- RLS on with no policy denies everything, which is only correct on purpose.
select is(
  (select count(*)::int
   from pg_class c
   join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('core', 'coach', 'lift', 'run')
     and c.relkind = 'r' and c.relrowsecurity
     and (n.nspname, c.relname) <> ('coach', 'usage')
     and not exists (
       select 1 from pg_policies p
       where p.schemaname = n.nspname and p.tablename = c.relname
     )),
  0,
  'every table has at least one policy, except coach.usage which is deliberately unreachable'
);


-- 4 ------------------------------------------------------------------------
select is(
  (select count(*)::int from pg_policies
   where schemaname = 'coach' and tablename = 'usage'),
  0,
  'coach.usage has no policy at all: reachable only via SECURITY DEFINER under service_role'
);


-- 5 ------------------------------------------------------------------------
-- The rate limiter's ledger. A client that can write it can lift its own cap.
select ok(
  not has_table_privilege('authenticated', 'coach.usage', 'SELECT')
  and not has_table_privilege('authenticated', 'coach.usage', 'INSERT')
  and not has_table_privilege('authenticated', 'coach.usage', 'UPDATE')
  and not has_table_privilege('authenticated', 'coach.usage', 'DELETE'),
  'authenticated holds no privilege on coach.usage'
);


-- 6 ------------------------------------------------------------------------
-- Append-only transcript: a turn must not be rewritable after the fact.
-- DELETE stays, because the client prunes to a rolling window.
select ok(
  not has_table_privilege('authenticated', 'coach.turns', 'UPDATE')
  and has_table_privilege('authenticated', 'coach.turns', 'INSERT')
  and has_table_privilege('authenticated', 'coach.turns', 'DELETE'),
  'coach.turns is append-only for authenticated: no UPDATE, but INSERT and DELETE'
);


-- 7 ------------------------------------------------------------------------
-- With public source, anyone can read exactly how entitlements are granted. If
-- a client write path exists, someone will use it.
select ok(
  has_table_privilege('authenticated', 'core.entitlements', 'SELECT')
  and not has_table_privilege('authenticated', 'core.entitlements', 'INSERT')
  and not has_table_privilege('authenticated', 'core.entitlements', 'UPDATE')
  and not has_table_privilege('authenticated', 'core.entitlements', 'DELETE'),
  'core.entitlements is client-read-only'
);


-- 8 ------------------------------------------------------------------------
-- A SECURITY DEFINER function taking a user id is an "erase anyone" primitive
-- if a signed-in client can call it.
select ok(
  not has_function_privilege('authenticated', 'core.delete_account(uuid, text)', 'EXECUTE')
  and not has_function_privilege('anon', 'core.delete_account(uuid, text)', 'EXECUTE'),
  'core.delete_account is not callable by anon or authenticated'
);


-- 9 ------------------------------------------------------------------------
-- Policies targeting the PUBLIC role include anon, and are held out only
-- because auth.uid() is null there — security by arithmetic rather than by
-- intent. The 2026-08-06 restructure removed the last of them.
select is(
  (select count(*)::int from pg_policies
   where schemaname in ('core', 'coach', 'lift', 'run')
     and 'public' = any (roles)
     and policyname <> 'announcements_read_published'),
  0,
  'no policy targets the PUBLIC role: every one names authenticated (or anon, deliberately)'
);


-- 10 -----------------------------------------------------------------------
-- Every derived or server-owned table must be SELECT-only for clients.
--
-- Stated as a set rather than one assertion per table, because the failure this
-- catches is a table quietly acquiring writes it was never granted: `core` /
-- `lift` / `run` carry default privileges that grant new tables full CRUD, so a
-- read-only table needs an explicit REVOKE. Granting SELECT is not the same as
-- granting only SELECT — which is exactly how core.activities shipped writable
-- on 2026-08-06.
select is(
  (select coalesce(string_agg(t, ', ' order by t), '')
   from (
     select format('%I.%I', s, n) as t
     from (values ('core','activities'), ('core','entitlements'),
                  ('core','announcements'), ('lift','ai_summary_requests')) as v(s, n)
     where has_table_privilege('authenticated', format('%I.%I', s, n), 'INSERT')
        or has_table_privilege('authenticated', format('%I.%I', s, n), 'UPDATE')
        or has_table_privilege('authenticated', format('%I.%I', s, n), 'DELETE')
   ) x),
  '',
  'derived and server-owned tables grant authenticated SELECT and nothing else'
);


-- 11 -----------------------------------------------------------------------
-- The coach's memory is keyed per (person, app), not per person.
--
-- This is a data-loss assertion, not a tidiness one. With `user_id` alone as
-- the key, an account that uses both apps has ONE memory row, and each app's
-- regeneration overwrites the other's — silently, on special-category data,
-- with no earlier version left to restore. The column existing is not enough;
-- the KEY is what makes two memories possible, so that is what is asserted.
select set_eq(
  $$select a.attname::text
      from pg_index i
      join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey)
     where i.indrelid = 'coach.summaries'::regclass and i.indisprimary$$,
  array['user_id', 'app'],
  'coach.summaries is keyed by (user_id, app): one memory per app, never one per account'
);


-- 12 -----------------------------------------------------------------------
-- A conversation must say which app it belongs to, or account deletion cannot
-- erase one app's coach data without taking the other's — the gap named in
-- 20260806130300_account_deletion.sql.
select has_column(
  'coach', 'conversations', 'app',
  'a conversation says which app it belongs to, so deletion can be scoped to one'
);


-- 13 -----------------------------------------------------------------------
-- `coach.turns` deliberately has NO app column: it reaches its app through its
-- NOT NULL conversation FK. A second copy of that fact could disagree with the
-- first, and nothing would say which was right.
select hasnt_column(
  'coach', 'turns', 'app',
  'a turn inherits its app from its conversation rather than copying it'
);


select * from finish();
rollback;
