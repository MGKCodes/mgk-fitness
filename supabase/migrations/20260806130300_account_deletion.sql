-- Account deletion, rebuilt for the suite.
--
-- ## What this replaces, and why it had to be replaced
--
-- One Edge Function slug, `delete-account`, was shared by both apps against one
-- project, and Liftio's version was the one actually deployed. It called
-- `auth.admin.deleteUser` unconditionally, and every user-owned table in both
-- schemas cascades from `auth.users` — so a Runio user tapping "delete account"
-- erased their Liftio data too. Runio's careful version, which existed and was
-- correct, was never deployed.
--
-- Neither function was right for both apps. The fix is not to pick one: it is
-- one function that knows which app is asking.
--
-- ## Semantics
--
--   delete_account(user)          erase everything, everywhere, and the login
--   delete_account(user, 'run')   erase run.*; keep the login if lift.* holds
--                                 data, otherwise finish the job
--
-- The old asymmetry is gone: the answer no longer depends on which binary the
-- request came from.
--
-- ## Two deliberate choices
--
-- `core.profiles.dob` and `.weight_kg` are no longer cleared when a single app
-- leaves. Runio treated them as its own special-category data and wiped them;
-- they now live in `core.profiles`, belong to the person, and survive as long
-- as the profile does. That is a real change in meaning, not an oversight.
--
-- Coach data is erased only when the LAST app goes. `coach.conversations` has
-- no `app` column, so there is no honest way to erase "the running half" of a
-- conversation. Once conversations are app-tagged, scope this the same way the
-- app schemas are scoped. Until then, erasing on partial deletion would take
-- data the user did not ask to lose.


create function core.delete_account(p_user_id uuid, p_app text default null)
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

  -- 2. Does any OTHER app still hold data for this account?
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

  -- 3. Nothing left to keep the account alive for: take the coach, the shared
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
  'Erases a user''s data for one app, or for every app when p_app is null. Removes shared core rows and reports the login as deletable only when no app still holds data. service_role only.';

-- A SECURITY DEFINER function that takes a user id must not be reachable by a
-- signed-in client: that would be an "erase anyone" primitive, and the source
-- is public.
revoke all on function core.delete_account(uuid, text) from public, anon, authenticated;
grant execute on function core.delete_account(uuid, text) to service_role;
