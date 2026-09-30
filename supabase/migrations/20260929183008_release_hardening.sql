-- Four fixes from the 2026-09-29 pre-release review, applied that day under
-- this version (the ledger stamps the time of application; this file is named
-- to match it).

-- 1. The coach's usage ledger functions are service_role only.
--    Created SECURITY DEFINER in 20260806130000 and never revoked, so every
--    signed-in user could call rpc/record_usage for ANY p_user (locking that
--    person's coach for up to a month) and rpc/usage_window to read anyone's
--    usage timeline. The coach function calls both with the service key.
revoke execute on function coach.record_usage(uuid, text, integer, integer, integer, numeric, boolean, text)
  from public, anon, authenticated;
revoke execute on function coach.usage_window(uuid, timestamptz)
  from public, anon, authenticated;
grant execute on function coach.record_usage(uuid, text, integer, integer, integer, numeric, boolean, text)
  to service_role;
grant execute on function coach.usage_window(uuid, timestamptz)
  to service_role;

-- 2. core.user_settings timestamps get defaults. Both are bigint NOT NULL
--    with none, and Run's unit sync upserts only {user_id, distance_unit}, so
--    every write failed 23502 and the unit never followed a runner to a new
--    phone, which the privacy policy says it does.
alter table core.user_settings
  alter column created_at set default ((extract(epoch from now()) * 1000)::bigint),
  alter column updated_at set default ((extract(epoch from now()) * 1000)::bigint);

-- 3. A coach reply a runner reports (Google Play's AI-generated content
--    policy: in-app reporting, without leaving the app). Insert-only for the
--    signed-in user; read by us, in the dashboard. user_id and app make
--    core.delete_account sweep it by construction, which is what the privacy
--    policy promises.
create table coach.reports (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid()
             references auth.users (id) on delete cascade,
  app        text not null check (app in ('lift', 'run')),
  reply      text not null check (char_length(reply) between 1 and 8000),
  reason     text not null check (reason in ('harmful', 'wrong', 'offensive', 'other')),
  note       text check (note is null or char_length(note) <= 1000),
  created_at timestamptz not null default now()
);

alter table coach.reports enable row level security;

create policy "reports: a runner files their own"
  on coach.reports for insert to authenticated
  with check ((select auth.uid()) = user_id);

grant insert on coach.reports to authenticated;

create index coach_reports_user_idx on coach.reports (user_id);

comment on table coach.reports is
  'Coach replies a user reported from inside the app (Play AI-generated content policy). Client INSERT only, under RLS; no client read, update or delete. Swept by core.delete_account via user_id and app.';

-- 4. The one mutable search_path the security advisor reports.
alter function core.touch_updated_at() set search_path = '';

notify pgrst, 'reload schema';
