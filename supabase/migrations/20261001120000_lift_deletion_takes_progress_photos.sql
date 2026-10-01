-- "Delete my Lift data" takes the progress photos with it.
--
-- Until now a Lift-only deletion kept them. `core.progress_photos` is filed in
-- `core`, and `core` was only ever swept when the last app left, so somebody
-- who deleted Lift's data while Run still held runs kept a set of photographs
-- of their own body on our servers, in an app they had just left.
--
-- The filing was the mistake, not the rule. Nothing but Lift has ever read or
-- written this table (`20260806130000_restructure_schemas.sql` moved it into
-- `core` as account data, before anything was built on it), and Run has no
-- photo feature. So the photos leave when Lift does: on `p_app = 'lift'`, and
-- on a full deletion as before.
--
-- ## What changes
--
--   * A deletion that targets `lift` deletes this account's rows in
--     `core.progress_photos`, whether or not another app still holds data.
--   * The summary gains `photos_deleted`, true whenever those rows were removed
--     by either route. The `delete-account` Edge Function sweeps the
--     `progress-photos` bucket on it: the rows are only half of a photograph.
--
-- ## What deliberately does NOT change
--
--   * A Run-only deletion leaves the photos alone while Lift still holds data.
--   * The full sweep in step 5 still deletes them, so an account whose only
--     data is photographs is still emptied when its last app leaves.
--   * `shared_deleted` and `auth_user_deletable` mean what they meant.
--
-- ## Order of rollout
--
-- **Deploy the Edge Function first, then apply this.** A function that knows
-- `photos_deleted` is harmless against the old routine, which never sends it.
-- This routine against the old function would delete the rows of a Lift-only
-- deletion and leave the picture files in the bucket with nothing pointing at
-- them, which is the residue the sweep exists to prevent.

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
  v_photos_deleted boolean := false;
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
  --    step 5 takes the whole of `coach` including the tables this cannot see.
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

  -- 3. Progress photos are Lift's, though they are filed in `core`. They leave
  --    when Lift does, whether or not Run still holds data.
  --
  --    Named rather than found by catalog, unlike everything above: this is one
  --    table that sits in the wrong schema, not a pattern to be covered by
  --    construction.
  if 'lift' = any (v_targets) then
    delete from core.progress_photos where user_id = p_user_id;
    get diagnostics v_deleted = row_count;
    v_counts := v_counts || jsonb_build_object('core.progress_photos', v_deleted);
    v_photos_deleted := true;
  end if;

  -- 4. Does any OTHER app still hold data for this account?
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

  -- 5. Nothing left to keep the account alive for: take the coach, the shared
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
    -- Still here, for the account whose last app was Run and whose only Lift
    -- data was photographs: step 3 did not run for it.
    delete from core.progress_photos where user_id = p_user_id;
    delete from core.user_settings  where user_id = p_user_id;
    delete from core.profiles       where id = p_user_id;
    v_shared_deleted := true;
    v_photos_deleted := true;
  end if;

  return jsonb_build_object(
    'deleted_rows', v_counts,
    'remaining_apps', to_jsonb(v_remaining),
    'shared_deleted', v_shared_deleted,
    -- True whenever this call removed the photo rows. The Edge Function removes
    -- the picture files from storage when it is.
    'photos_deleted', v_photos_deleted,
    -- The Edge Function removes the auth.users row itself, via the Admin API,
    -- and only when this is true.
    'auth_user_deletable', v_shared_deleted
  );
end;
$$;

comment on function core.delete_account(uuid, text) is
  'Erases a user''s data for one app, or for every app when p_app is null. A partial deletion also takes that app''s coach conversations, turns and memory, but not coach.usage — that is the spend ledger, holds no content, and erasing it would let a partial deletion reset a rate limit. A deletion that includes lift also takes core.progress_photos, which only Lift uses, and reports photos_deleted so the caller sweeps the storage bucket. Removes shared core rows and reports the login as deletable only when no app still holds data. service_role only.';

-- CREATE OR REPLACE keeps the existing grants, but they are restated so this
-- file is readable on its own: a SECURITY DEFINER function taking a user id
-- must never be reachable by a signed-in client, and the source is public.
revoke all on function core.delete_account(uuid, text) from public, anon, authenticated;
grant execute on function core.delete_account(uuid, text) to service_role;
