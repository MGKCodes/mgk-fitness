-- core.waiting_list — addresses left on the website before the apps are live.
--
-- ## One door, and it only opens inwards
--
-- The site is static and holds no secret, so its form writes with the
-- publishable key, as `anon`. That makes this the one place anybody on the
-- internet may put a row, and the design is what follows from that:
--
-- - **Nobody outside can touch the table.** RLS is on with no policy, and the
--   grants `core`'s default privileges hand `authenticated` are revoked, as
--   `20260806140000` says a table like this needs. Only `service_role` reads
--   the list, which is Matthew in the dashboard.
-- - **The only way in is `core.join_waiting_list`.** It takes an address and
--   adds it. It returns nothing, so it cannot be made to say anything about
--   what the table holds.
-- - **Asking twice is one row and no error.** A caller therefore cannot learn
--   whether an address is already on the list, which a unique violation would
--   tell them.
-- - **The checks are the validation.** The form checks an address before it
--   sends one, but the form is not the only thing that can call this.
--
-- What it does not stop is somebody scripting junk addresses into it. The
-- checks bound what a row can be, not how many there are. If that happens the
-- answer is a challenge on the form, not a change here.
--
-- ## What the list is for
--
-- Telling people when Run and Lift are in the stores, which is what the site
-- says beside the form. Nothing sends that email yet; this is only the list.
--
-- Written so that running it twice is harmless.

create table if not exists core.waiting_list (
  -- Lowered and trimmed by the function, so one person is one row however they
  -- typed it.
  email text primary key
    check (char_length(email) between 6 and 254)
    check (email = lower(email))
    check (email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),

  -- Where the address was left. Only the website today.
  source text not null default 'web'
    check (source ~ '^[a-z0-9-]{1,32}$'),

  created_at timestamptz not null default now()
);

comment on table core.waiting_list is
  'Addresses left on the website to be told when the apps are live. No client access: written only through core.join_waiting_list, read only by service_role.';

alter table core.waiting_list enable row level security;

-- No policy, on purpose. The absence is the control, so it is stated here
-- rather than left to be noticed.
revoke all on core.waiting_list from anon, authenticated;
grant all on core.waiting_list to service_role;


-- `security definer` because the caller has no rights on the table at all, and
-- `set search_path = ''` for the usual reason a definer function needs it.
create or replace function core.join_waiting_list(
  p_email  text,
  p_source text default 'web'
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into core.waiting_list (email, source)
  values (lower(btrim(p_email)), p_source)
  on conflict (email) do nothing;
$$;

comment on function core.join_waiting_list(text, text) is
  'The website''s waiting-list form. Adds an address; says nothing about whether it was already there.';

revoke all on function core.join_waiting_list(text, text) from public;
grant execute on function core.join_waiting_list(text, text) to anon, authenticated, service_role;
