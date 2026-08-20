-- What the coach knows, kept where it can change without a release.
--
-- ## The problem this solves
--
-- Training guidance shapes what the coach tells somebody to do, and it goes out
-- of date. Held in Dart it ships on the app's cadence and needs a store review
-- to correct; held in the Edge Function's source it needs a function deploy,
-- which is faster but still a deploy, and still couples a wording fix to
-- whatever else is unreleased in that function.
--
-- In a table it changes when somebody changes it, and every reader picks it up
-- on the next call.
--
-- ## The repo is still the source of truth
--
-- This is NOT an invitation to edit training advice in a database console.
-- Claims here carry sources and a date, and advice that shapes somebody's
-- training should be reviewable and diffable like anything else — so the rows
-- are authored as files under `supabase/knowledge/` and pushed with
-- `deno task knowledge:sync`.
--
-- The table is the delivery mechanism; git is the record. That split is what
-- makes this different from the `coach.models` table that was dropped for being
-- configuration nobody could review.
--
-- ## Why `coach` rather than `lift`
--
-- The coach belongs to nobody (ADR: "One schema per domain, and the coach
-- belongs to nobody"), and there is one Supabase project for the suite
-- (ADR-0008) rather than a Liftio one and a Runio one. Progressive overload is
-- not a Lift fact. So the table lives in `coach` and rows carry an `app`.

create table coach.knowledge (
  -- Stable and human-chosen — 'c1-weekly-volume', 'split-selection'. It is
  -- what the prompt builder asks for and what a code comment cites, so it must
  -- survive a retitle.
  id text not null,

  -- **'all' as well as the two apps.** coach.summaries and coach.conversations
  -- check `app in ('lift','run')` because a memory belongs to one coach. A
  -- claim about progressive overload belongs to both, and duplicating it per
  -- app is how two copies of a fact drift apart.
  app text not null default 'all'
    check (app in ('all', 'lift', 'run')),

  primary key (id, app),

  -- `claim` is research with sources behind it. `guidance` is coaching prose —
  -- how to explain a split, what to say about a stall. Kept apart because they
  -- are checked differently: a claim goes stale against the literature, and
  -- guidance goes stale against the product.
  kind text not null check (kind in ('claim', 'guidance')),

  title text not null,
  body  text not null,

  -- ---- provenance, and the reason a stale claim is findable ----------------
  --
  -- The frequency claim this app was built on was superseded and survived
  -- anyway, because the code asserted it without saying where it came from.
  -- Nothing pointed at what to re-check. These columns are that pointer.
  confidence   text,
  sources      text[] not null default '{}',
  last_checked date,

  -- What in the app leans on this. Free text, kept deliberately loose: it is a
  -- search hint for whoever has to find the blast radius of a claim that moved.
  depends_on text[] not null default '{}',

  updated_at timestamptz not null default now()
);

comment on table coach.knowledge is
  'Training claims and coaching guidance. Authored as files under supabase/knowledge/ and synced here; the table is delivery, git is the record.';
comment on column coach.knowledge.depends_on is
  'What in the app leans on this, so a superseded claim can be traced to what it broke.';

-- The read the prompt builder makes: everything for one app, claims and shared
-- rows together.
create index knowledge_app_kind_idx on coach.knowledge (app, kind);

create trigger knowledge_touch
  before update on coach.knowledge
  for each row execute function core.touch_updated_at();


-- ---------------------------------------------------------------------------
-- Row-level security
--
-- **Readable by any signed-in client, and that is deliberate.** This is not
-- secret — it is what the coach would tell you anyway, and the app wants it for
-- the "why this split" text so the explanation on screen and the explanation in
-- the prompt are the same sentence rather than two that drift.
--
-- Writes are service_role only. A client that could edit training guidance
-- could edit what every other client is told.
-- ---------------------------------------------------------------------------

alter table coach.knowledge enable row level security;

create policy read_knowledge on coach.knowledge
  for select to authenticated
  using (true);

grant select on coach.knowledge to authenticated;
grant all    on coach.knowledge to service_role;
