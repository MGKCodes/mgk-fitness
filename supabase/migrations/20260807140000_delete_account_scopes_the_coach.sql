-- Account deletion erases one app's coach data, not all of it or none of it.
--
-- `20260806130300_account_deletion.sql` left this stated rather than hidden:
--
--     Coach data is erased only when the LAST app goes. `coach.conversations`
--     has no `app` column, so there is no honest way to erase "the running
--     half" of a conversation. Once conversations are app-tagged, scope this
--     the same way the app schemas are scoped.
--
-- They are app-tagged now (`20260807130000_coach_memory_per_app.sql`), so this
-- is the other half of that change and the closing of a real GDPR gap: a lifter
-- who deletes their Run data was leaving behind a stored record of running
-- conversations, and the only way to remove it was to delete the whole account.
--
-- ## What changes
--
-- A partial deletion now also erases, for the departing app only:
--
--   * `coach.conversations` for that app — and its `coach.turns` with them, by
--     the FK's ON DELETE CASCADE;
--   * `coach.summaries` for that app.
--
-- The full sweep in step 4 is unchanged and still takes everything, so a total
-- deletion behaves exactly as before.
--
-- ## What deliberately does NOT change
--
-- **`coach.usage` survives a partial deletion.** It is the rate limiter's
-- ledger: token counts, costs and a surface name, with no prompt, no reply and
-- no training value in it — `RecordedUsage` has nowhere to put one. Three
-- reasons to leave it, and the last is the one that decides it:
--
--   1. it holds no content to erase;
--   2. `coach.record_usage` prunes it at 31 days anyway;
--   3. **erasing it on partial deletion would be a spend-cap reset.** Delete one
--      app's data, get a fresh allowance. The account is still live, so its
--      ceilings still need their ledger, and a deletion path that doubles as a
--      way to buy more tokens is worse than a retained cost figure.
--
-- It is still erased in full when the last app goes and the account ends.
--
-- ## How the tables are found
--
-- By catalog, like every other sweep in this function: any table in `coach`
-- carrying both `user_id` and `app` is scoped by construction, so a table added
-- later is covered without anyone remembering to add it here. `coach.turns` has
-- no `app` and needs none — it reaches its app through its conversation, and
-- goes with it.


create or replace function core.delete_account(p_user_id uuid, p_app text default null)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, pg_temp
as $$
declare
  c_apps constant text[] := array['lift', 'run'];
  v_targets        text[];
  v_schema         text;
  v_table          text;
  v_deleted        bigint;
  v_counts         jsonb := '{}'::jsonb;
  v_remaining      text[] := array[]::text[];
  v_has            boolean;
  v_shared_deleted boolean := false;
begin
  if p_user_id is null then
    raise exception 'core.delete_account: p_user_id is required';
  end if;
  if p_app is not null and not (p_app = any (c_apps)) then
    raise exception 'core.delete_account: unknown app %', p_app;
  end if;

  v_targets := case when p_app is null then c_apps else array[p_app] end;

  -- 1. Erase the target app schema(s). Tables are enumerated by their
  --    `user_id` column rather than a hard-coded list, so a table added later
  --    is covered by construction. Children before parents, ordered by inbound
  --    foreign-key count, so it holds whether or not a future table declares
  --    ON DELETE CASCADE.
  foreach v_schema in array v_targets loop
    for v_table in
      select format('%I.%I', n.nspname, c.relname)
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      join pg_attribute a on a.attrelid = c.oid
        and a.attname = 'user_id' and a.attnum > 0 and not a.attisdropped
      where n.nspname = v_schema and c.relkind in ('r', 'p')
      order by (
        select count(*) from pg_constraint fk
        where fk.confrelid = c.oid and fk.contype = 'f'
      ) asc, c.relname asc
    loop
      execute format('delete from %s where user_id = $1', v_table) using p_user_id;
      get diagnostics v_deleted = row_count;
      v_counts := v_counts || jsonb_build_object(v_table, v_deleted);
    end loop;
  end loop;

  -- 2. The departing app's coach data goes with it.
  --
  --    Only on a PARTIAL deletion: when p_app is null every app is leaving, and
  --    step 4 takes the whole of `coach` including the tables this cannot see.
  --
  --    `coach.turns` is not listed and must not be — it has no `app` of its own,
  --    reaching one through its conversation, and it is erased by that FK's
  --    ON DELETE CASCADE. Its rows therefore do not appear in `deleted_rows`,
  --    which is a reporting gap rather than a retention one.
  if p_app is not null then
    for v_table in
      select format('%I.%I', n.nspname, c.relname)
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      join pg_attribute a on a.attrelid = c.oid
        and a.attname = 'user_id' and a.attnum > 0 and not a.attisdropped
      where n.nspname = 'coach' and c.relkind in ('r', 'p')
        and exists (
          select 1 from pg_attribute app_col
          where app_col.attrelid = c.oid and app_col.attname = 'app'
            and app_col.attnum > 0 and not app_col.attisdropped
        )
      order by (
        select count(*) from pg_constraint fk
        where fk.confrelid = c.oid and fk.contype = 'f'
      ) asc, c.relname asc
    loop
      execute format('delete from %s where user_id = $1 and app = $2', v_table)
        using p_user_id, p_app;
      get diagnostics v_deleted = row_count;
      v_counts := v_counts || jsonb_build_object(v_table, v_deleted);
    end loop;
  end if;

  -- 3. Does any OTHER app still hold data for this account?
  foreach v_schema in array c_apps loop
    continue when v_schema = any (v_targets);
    v_has := false;
    for v_table in
      select format('%I.%I', n.nspname, c.relname)
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      join pg_attribute a on a.attrelid = c.oid
        and a.attname = 'user_id' and a.attnum > 0 and not a.attisdropped
      where n.nspname = v_schema and c.relkind in ('r', 'p')
    loop
      execute format('select exists (select 1 from %s where user_id = $1)', v_table)
        into v_has using p_user_id;
      exit when v_has;
    end loop;
    if v_has then
      v_remaining := v_remaining || v_schema;
    end if;
  end loop;

  -- 4. Nothing left to keep the account alive for: take the coach, the shared
  --    core rows, and report the login as deletable.
  if cardinality(v_remaining) = 0 then
    for v_table in
      select format('%I.%I', n.nspname, c.relname)
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      join pg_attribute a on a.attrelid = c.oid
        and a.attname = 'user_id' and a.attnum > 0 and not a.attisdropped
      where n.nspname = 'coach' and c.relkind in ('r', 'p')
      order by (
        select count(*) from pg_constraint fk
        where fk.confrelid = c.oid and fk.contype = 'f'
      ) asc, c.relname asc
    loop
      execute format('delete from %s where user_id = $1', v_table) using p_user_id;
      get diagnostics v_deleted = row_count;
      v_counts := v_counts || jsonb_build_object(v_table, v_deleted);
    end loop;

    delete from core.activities     where user_id = p_user_id;
    delete from core.entitlements   where user_id = p_user_id;
    delete from core.progress_photos where user_id = p_user_id;
    delete from core.user_settings  where user_id = p_user_id;
    delete from core.profiles       where id = p_user_id;
    v_shared_deleted := true;
  end if;

  return jsonb_build_object(
    'deleted_rows', v_counts,
    'remaining_apps', to_jsonb(v_remaining),
    'shared_deleted', v_shared_deleted,
    -- The Edge Function removes the auth.users row itself, via the Admin API,
    -- and only when this is true.
    'auth_user_deletable', v_shared_deleted
  );
end;
$$;

comment on function core.delete_account(uuid, text) is
  'Erases a user''s data for one app, or for every app when p_app is null. A partial deletion also takes that app''s coach conversations, turns and memory, but not coach.usage — that is the spend ledger, holds no content, and erasing it would let a partial deletion reset a rate limit. Removes shared core rows and reports the login as deletable only when no app still holds data. service_role only.';

-- CREATE OR REPLACE keeps the existing grants, but they are restated so this
-- file is readable on its own: a SECURITY DEFINER function taking a user id
-- must never be reachable by a signed-in client, and the source is public.
revoke all on function core.delete_account(uuid, text) from public, anon, authenticated;
grant execute on function core.delete_account(uuid, text) to service_role;
