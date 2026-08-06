-- core.entitlements — who has paid for what.
--
-- ## Client-read-only is the whole design
--
-- The repo is public. Anyone can read exactly how entitlements are granted, so
-- if a client write path exists, someone will use it. There is no INSERT,
-- UPDATE or DELETE policy on this table and no such grant to `authenticated` —
-- only `service_role` writes, and only from an Edge Function that has already
-- validated the receipt with Apple or Google.
--
-- Nothing enforces "the function validated the receipt" at the database level;
-- what the database enforces is that nothing else can write at all.
--
-- ## Shape: one row per (user, app), never a single is_pro flag
--
-- Pricing is per-app and never cross-app — you pay separately for Lift and
-- Run. A row per app means a future suite bundle is two rows, not a migration.
-- `product` carries the tier, so moving someone between tiers is an UPDATE.


create table core.entitlements (
  user_id uuid not null references auth.users(id) on delete cascade,
  app     text not null check (app in ('lift', 'run')),

  -- The user-facing framing is a 1/3, 2/3, 3/3 star coach rather than a model
  -- name, so the underlying model can be swapped as prices move without the
  -- tier meaning anything different to the user.
  product text not null check (product in ('free', 'paid', 'premium')),
  status  text not null check (status  in ('active', 'expired', 'grace', 'refunded', 'revoked')),

  platform   text check (platform in ('apple', 'google')),
  expires_at timestamptz,

  -- Provenance for support and for reconciling against the store, never shown
  -- to the user. No receipt bodies — those stay with the validating function.
  source_txn_id text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  primary key (user_id, app)
);

comment on table core.entitlements is
  'Per-app purchase state. Client-read-only: written solely by the receipt-validating Edge Function under service_role. A bundle is two rows, not a schema change.';
comment on column core.entitlements.status is
  'Store-reported state. `active` is the only value that grants anything; treat every other value as no entitlement.';

create index entitlements_user_idx on core.entitlements (user_id) where status = 'active';

create trigger touch_updated_at
  before update on core.entitlements
  for each row execute function core.touch_updated_at();

alter table core.entitlements enable row level security;

-- SELECT and nothing else. The absence of the other three policies is the
-- security control, so it is stated here rather than left implicit.
create policy own_entitlements_read on core.entitlements
  for select to authenticated using ((select auth.uid()) = user_id);

grant select on core.entitlements to authenticated;
revoke insert, update, delete on core.entitlements from authenticated;
grant all on core.entitlements to service_role;
