-- Granting an entitlement by hand, for support.
--
-- ## Why this exists before RevenueCat does
--
-- `core.entitlements` is written by exactly one thing: an Edge Function running
-- as `service_role`. That is the right design and it has one gap — when a
-- purchase does not land, there is no way to put somebody right. Liftio needed
-- exactly this repeatedly, and the TestFlight test sheet already opens with a
-- hand-written `insert` under "Before you start", which is the same operation
-- performed less safely.
--
-- The insert-by-hand is what this replaces. Typing the row out means typing a
-- uuid, which means looking one up from an email, which is where the mistake
-- gets made: a grant landing on the wrong account is invisible until somebody
-- complains that they paid and got nothing.
--
-- ## Keyed by email, deliberately
--
-- A support conversation gives you an address, never a uuid. Taking the email
-- and doing the lookup here is the entire ergonomic point; a function that
-- wanted a uuid would leave the dangerous step exactly where it already is.
--
-- The lookup is exact and case-insensitive, and it **fails rather than guesses**
-- if it matches no one. Silence on a missing account would read as success.
--
-- ## Who can call it
--
-- Not `authenticated`. Not `anon`. The repo is public, so the same reasoning the
-- entitlements table carries applies harder here: this function grants paid
-- access, and a `security definer` function reachable by a signed-in user is a
-- self-service upgrade button. `execute` is revoked from everyone and granted
-- back to `service_role` alone, which is what the SQL editor and an Edge
-- Function run as, and what a client can never reach.
--
-- `set search_path = ''` for the usual reason a definer function needs it: an
-- unqualified name would otherwise resolve through the caller's search path.

create or replace function core.grant_entitlement(
  p_email      text,
  p_app        text,
  p_product    text        default 'paid',
  p_status     text        default 'active',
  p_expires_at timestamptz default null,
  p_note       text        default null
)
returns core.entitlements
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_row     core.entitlements;
begin
  select id into v_user_id
  from auth.users
  where lower(email) = lower(trim(p_email));

  if v_user_id is null then
    raise exception 'no account for %', p_email
      using hint = 'Check the address. This grants nothing rather than guessing.';
  end if;

  -- The table's own checks carry the vocabulary; this repeats none of it, so a
  -- new tier or status is a change in one place.
  insert into core.entitlements as e
    (user_id, app, product, status, platform, expires_at, source_txn_id)
  values
    (v_user_id, p_app, p_product, p_status, null, p_expires_at,
     'manual:' || coalesce(nullif(trim(p_note), ''), 'support'))
  on conflict (user_id, app) do update
    set product       = excluded.product,
        status        = excluded.status,
        expires_at    = excluded.expires_at,
        -- Provenance is overwritten on purpose. A row that was a real purchase
        -- and has since been fixed by hand is a manual row now, and pretending
        -- otherwise would make the next reconciliation against the store lie.
        source_txn_id = excluded.source_txn_id,
        platform      = null
  returning * into v_row;

  return v_row;
end;
$$;

comment on function core.grant_entitlement(text, text, text, text, timestamptz, text) is
  'Support escape hatch: set somebody''s entitlement by email. service_role only. '
  'Writes a `manual:` source_txn_id so a hand-granted row is never mistaken for '
  'a store purchase when reconciling. Raises if the address matches no account.';

-- Revoking is its own verb rather than `grant_entitlement(..., 'revoked')`,
-- because the common support action is "take it back" and making that a
-- four-argument call with a magic string is how the wrong string gets typed.
create or replace function core.revoke_entitlement(
  p_email text,
  p_app   text,
  p_note  text default null
)
returns core.entitlements
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row core.entitlements;
begin
  -- Status, not deletion. A deleted row and a revoked row read identically to
  -- the app -- neither grants anything -- but only one of them can answer "did
  -- this person ever pay, and what happened".
  update core.entitlements e
     set status        = 'revoked',
         source_txn_id = 'manual:' || coalesce(nullif(trim(p_note), ''), 'support')
    from auth.users u
   where u.id = e.user_id
     and lower(u.email) = lower(trim(p_email))
     and e.app = p_app
  returning e.* into v_row;

  -- `not found` rather than `v_row is null`: a composite is only NULL when every
  -- field is, which happens to be true here but is a coincidence, not a check.
  if not found then
    raise exception 'no % entitlement for %', p_app, p_email
      using hint = 'Check the address and the app. Nothing was changed.';
  end if;

  return v_row;
end;
$$;

comment on function core.revoke_entitlement(text, text, text) is
  'Support escape hatch: revoke somebody''s entitlement by email. service_role '
  'only. Sets status rather than deleting, so the history survives.';

-- The security control, stated rather than left to the default. PostgREST
-- exposes `execute` to whatever role can reach the schema, and the default on a
-- new function is `public`.
revoke execute on function core.grant_entitlement(text, text, text, text, timestamptz, text) from public, anon, authenticated;
revoke execute on function core.revoke_entitlement(text, text, text) from public, anon, authenticated;
grant  execute on function core.grant_entitlement(text, text, text, text, timestamptz, text) to service_role;
grant  execute on function core.revoke_entitlement(text, text, text) to service_role;
