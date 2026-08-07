-- The coach remembers per app, not per person.
--
-- `coach.summaries` has primary key `(user_id)` — one rolling prose memory per
-- account, full stop. That was right while the coach served one app. It is not
-- right now: Lift is about to start writing memory, and on any account that
-- uses both apps the two would take turns overwriting each other. A runner's
-- "cannot run in the dark, shift work Tuesdays" would be replaced by "training
-- 4x/week, shoulder impingement on overhead press", then replaced back.
--
-- Nothing is broken today, because Lift writes nothing yet. That is exactly why
-- this lands before the memory feature rather than after it: the failure mode
-- is silent, it corrupts special-category data, and it is unrecoverable — there
-- is no version of the runner's memory left to restore once it is overwritten.
--
-- `coach.conversations` gains the same column, for the same reason and one
-- more: `20260806130300_account_deletion.sql` says in as many words that coach
-- data can only be erased when the LAST app goes, because there was no honest
-- way to tell which half of a conversation belonged to which app. Now there is.
-- Scoping the deletion sweep is a follow-up, not this migration — but it is
-- unblocked by this one.
--
-- ## Why `default 'run'` and not a required column
--
-- Every coach row that exists today is Runio's, so the default backfills them
-- correctly. The default then STAYS, which is a deliberate compromise rather
-- than an oversight: Runio's shipped client (`coach_memory_mirror.dart`) writes
-- these tables without naming an app, and this repo cannot redeploy it. A
-- required column would break its memory writes the moment this is pushed.
--
-- The cost is that a future app which forgets to send `app` files its data as
-- running rather than failing loudly. **Drop the default once Runio names its
-- app explicitly** — that is the whole to-do, and it is one line here.
--
-- ## The upsert this depends on
--
-- Runio's `pushSummary` upserts with no explicit conflict target, so PostgREST
-- resolves it against the primary key — which this migration widens. The insert
-- omits `app`, the column default supplies it, and `ON CONFLICT (user_id, app)`
-- is evaluated against the row as defaulted, so the write still lands on the
-- runner's own row.
--
-- Verified against local PostgREST rather than reasoned about, because the
-- failure would have been Runio's memory writes starting to 409 in production:
-- Runio's exact payload POSTed twice returns 201 then 200 (an update, not a
-- duplicate), and a Lift write naming its own app creates a second row instead
-- of colliding. What that does NOT cover is Runio's compiled client itself, so
-- run its memory tests the next time that repo is opened.


-- ---------------------------------------------------------------------------
-- 1. Conversations
-- ---------------------------------------------------------------------------

alter table coach.conversations
  add column app text not null default 'run'
    check (app in ('lift', 'run'));

comment on column coach.conversations.app is
  'Which app this conversation belongs to. Defaults to `run` so Runio''s shipped client, which does not send it, keeps writing to the right place — drop the default once it does.';

-- The old index answered "this user's recent conversations". Every caller now
-- wants "this user's recent conversations IN THIS APP", and a leading (user_id,
-- last_turn_at) index cannot serve that without a filter step.
drop index if exists coach.coach_conversations_user_recent_idx;
create index conversations_user_app_recent_idx
  on coach.conversations (user_id, app, last_turn_at desc);


-- ---------------------------------------------------------------------------
-- 2. Summaries
--
-- The primary key is the fix. Widening it is what makes two memories possible;
-- the column on its own would just be a label on a row that still collides.
-- ---------------------------------------------------------------------------

alter table coach.summaries
  add column app text not null default 'run'
    check (app in ('lift', 'run'));

alter table coach.summaries drop constraint coach_summaries_pkey;
alter table coach.summaries add constraint coach_summaries_pkey
  primary key (user_id, app);

comment on table coach.summaries is
  'One rolling prose memory per (person, app) — replaced on regeneration, never appended to. Special-category data. Keyed per app because a lifting memory and a running memory are different things about the same person, and a shared row means whichever app spoke last decides what is remembered.';
comment on column coach.summaries.app is
  'Which app''s coach this is the memory of. Defaults to `run` for the same compatibility reason as coach.conversations.app.';
comment on column coach.summaries.turns_covered is
  'How many turns this memory was written from. The regeneration trigger is the gap between this and the live turn count, so a memory is rewritten when it has fallen behind rather than on every turn — which would be a re-encode of a re-encode.';


-- ---------------------------------------------------------------------------
-- 3. Turns are partitioned by their conversation, not by a column of their own
--
-- `coach.turns` deliberately does NOT get an `app`. It has a NOT NULL FK to
-- `coach.conversations` with ON DELETE CASCADE, so every turn already belongs
-- to exactly one app through its parent. A second copy of that fact could
-- disagree with the first, and nothing would say which was right.
--
-- Stated here because its absence otherwise reads as the oversight this whole
-- migration exists to fix.
-- ---------------------------------------------------------------------------
