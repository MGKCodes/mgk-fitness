# Backend

The schema, the Edge Functions, and the tests that keep them honest. **This
directory is the source of truth for the database** — not the dashboard, and not
either of the legacy app repos.

```
supabase/
├─ migrations/   the schema, in order
├─ functions/    Edge Functions (Deno)
└─ tests/        pgTAP assertions against the real catalog
```

For *what* the schema looks like and why, read
[docs/database.md](../docs/database.md). This file is about working on it.

## Local development

Everything runs in Docker, so you can break it as often as you like.

```sh
supabase start        # Postgres, PostgREST, auth, storage, studio
supabase db reset     # drop, recreate, replay every migration
supabase test db      # pgTAP schema contract
supabase stop
```

Studio is at http://127.0.0.1:54323. The local keys are the same demo values on
every Supabase install — they are not secrets and are safe to share.

**Work locally. Always.** `supabase db reset` is destructive by design and takes
whatever database it is pointed at.

## Adding a migration

```sh
supabase migration new add_something
# edit supabase/migrations/<timestamp>_add_something.sql
supabase db reset     # must replay cleanly from empty
supabase test db      # invariants must still hold
```

Then, when you're confident:

```sh
supabase db push
```

### Five things a new table needs

Not style preferences — each of these has a specific failure mode.

1. **A `user_id` column.** Account deletion enumerates tables by that column
   rather than a hard-coded list. Without one the table silently escapes
   erasure. `supabase test db` fails if you forget.
2. **RLS enabled and a policy.** The anon key is public. RLS is the boundary,
   so a table without a policy is a leak, not a to-do.
3. **`TO authenticated`, not `TO public`.** `public` includes `anon`, held out
   only because `auth.uid()` is null there.
4. **`(select auth.uid())`, not `auth.uid()`.** The subquery form is hoisted to
   an InitPlan and evaluated once per statement rather than once per row.
5. **An explicit `REVOKE` if the table is read-only.** `core`, `lift` and `run`
   carry default privileges granting `authenticated` full CRUD on new tables —
   right for tables users own, wrong for derived or server-owned ones. Adding
   `grant select` does not remove what the default already gave you.

   **Granting SELECT is not the same as granting only SELECT.** That is exactly
   how `core.activities` shipped writable: created one migration after the
   defaults were set, it inherited INSERT/UPDATE/DELETE, and the explicit
   `grant select` that followed only added to the set. RLS still denied the
   writes — there was no INSERT policy — but the grant should never have been
   there. Test 10 in `tests/coach_contract.sql` guards it now.

## Verifying the repo still describes the database

The check that makes this directory trustworthy rather than merely tidy:

```sh
supabase db diff --linked
```

Anything other than *"No schema changes found"* means the repo and the database
have drifted. Fix the repo, not the database.

## Edge Functions

| Function | What it does |
|---|---|
| `coach` | The AI coach. Holds the provider key, enforces the rate limit and spend cap. |
| `delete-account` | App-aware account deletion. Calls `core.delete_account`. |
| `daily-ai-summary` | Lift's daily summary. Writes `lift.ai_summary_requests`. |

```sh
supabase functions serve                    # run locally
supabase functions deploy coach             # deploy one
deno test --allow-net --allow-env functions/coach/
```

Two rules:

- **The provider key never leaves here.** Every AI call is app → Edge Function →
  provider. `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY`
  are injected by the platform; anything else is a secret you set on the
  function, never in the repo.
- **Name the schema on every PostgREST call.** RPCs need a `Content-Profile`
  header and reads need `Accept-Profile`, or PostgREST resolves against the
  first exposed schema and 404s. In `coach` that 404 is read as "limiter
  missing", and the limiter fails closed — so a missing header takes the whole
  coach down rather than degrading it.

Functions live here rather than in an app repo for a concrete reason: when two
repos each defined a function under the same slug against the same project,
whichever deployed last silently became the one running for both apps. That is
how the account-deletion bug happened.

## Out-of-band configuration

Two things are project configuration rather than SQL, so they don't travel with
a migration and will bite you after a push:

1. **Exposed schemas** — Settings → API. `core`, `coach`, `lift` and `run` must
   all be listed or every client gets a 404.
2. **Auth settings** — providers, redirect URLs, email templates.

## The legacy repos

`Runio/supabase/` and `Liftio/supabase/` are frozen and carry README notices
saying so. Deploying anything from either would overwrite what's here with code
that calls routines which no longer exist.
