-- What the email-first sign-in needs to know about an address
-- (Run's ADR-0047, "Email first").
--
-- *Continue with email* asks for the address alone, and the `account-lookup`
-- Edge Function answers which screen comes next: `new`, `unconfirmed`,
-- `password`, `apple` or `google`. This routine is the half that reads
-- `auth`: it returns the facts about one address and leaves the deciding to
-- the function, where it is tested (`account-lookup/status.ts`).
--
-- ## What it returns
--
--   { "exists": false }
--   { "exists": true, "confirmed": bool, "has_password": bool,
--     "providers": ["apple", "google", ...] }
--
-- `providers` lists the account's identities other than `email`. Nothing else
-- about the account leaves this routine: no id, no dates, no metadata, no
-- name. The function narrows it further, to one word.
--
-- ## Who may call it
--
-- The service role only, so the one caller is `account-lookup`, which runs
-- with that key. Telling a stranger that an address has an account is accepted
-- (the ADR's "Email first", point 7), but this routine reads `auth.users` and
-- `auth.identities` as their owner, so it is not handed to `anon` directly.
--
-- ## Matching an address
--
-- gotrue stores addresses lower-cased, and the comparison lower-cases both
-- sides anyway, after trimming what was typed. A soft-deleted user
-- (`deleted_at`) is treated as no account. Should two rows ever share an
-- address, the oldest answers.
--
-- ## Rollout
--
-- Additive and called by nothing until `account-lookup` is deployed, which in
-- turn is called by no app until Lift 2.0.1 and Run 1.0.2. Apply it, then
-- deploy the function. Per `migration-history-drift`: once applied, rename this
-- file to the version the project stamped.

create or replace function core.account_facts(p_email text)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $$
  select case
    when u.id is null then jsonb_build_object('exists', false)
    else jsonb_build_object(
      'exists', true,
      'confirmed', u.email_confirmed_at is not null,
      'has_password', coalesce(u.encrypted_password, '') <> '',
      'providers', coalesce(
        (
          select jsonb_agg(distinct i.provider order by i.provider)
          from auth.identities i
          where i.user_id = u.id and i.provider <> 'email'
        ),
        '[]'::jsonb
      )
    )
  end
  from (select 1) as one
  left join lateral (
    select users.id, users.email_confirmed_at, users.encrypted_password
    from auth.users
    where lower(users.email) = lower(btrim(p_email))
      and users.deleted_at is null
    order by users.created_at
    limit 1
  ) as u on true;
$$;

comment on function core.account_facts(text) is
  'Facts about one address for account-lookup (ADR-0047): exists, confirmed, has_password, providers. Service role only.';

revoke all on function core.account_facts(text) from public, anon, authenticated;
grant execute on function core.account_facts(text) to service_role;
