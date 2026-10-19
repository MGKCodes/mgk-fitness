# `account-lookup` Edge Function

One function, both apps. *Continue with email* asks for the address alone, and
this says which screen comes next ([Run's ADR-0047](../../../apps/mgk_run/docs/decisions/0047-email-first-a-code-to-confirm-a-name-on-the-account.md),
"Email first").

```
app (signed out)  ─▶  account-lookup  ─▶  core.account_facts(email)
```

## Contract

`POST { "email": "you@example.com" }`

| Answer | Means | The app shows |
|---|---|---|
| `200 { "status": "new" }` | No account | *Create your account*, then a code by email |
| `200 { "status": "unconfirmed" }` | A sign-up nobody confirmed | The same as `new`; the password typed now replaces the first once the code checks out |
| `200 { "status": "password" }` | An account with a password | *Welcome back* and a password field |
| `200 { "status": "apple" }`, `"google"` | An account made with that provider, no password | That provider's button, and *Set a password instead* |
| `400 { "error": "bad_email" }` | Nothing that could be an address | |
| `500 { "error": "lookup_failed" }` | The database did not answer | "No connection", with what was typed kept |

The decision is `statusOf` in [`status.ts`](status.ts), tested in
[`status_test.ts`](status_test.ts) (`deno test`). The facts it decides from come
from `core.account_facts`, migration `20261019220000_core_account_facts.sql`,
tested in [`supabase/tests/account_facts.sql`](../../tests/account_facts.sql)
(`supabase test db`).

## What it tells a stranger

Whether an address has an account, and how it signs in. Nothing about the
account itself: the routine returns four facts and this returns one word. The
ADR accepts this, because the sign-up API already says as much to anyone with
the public key, and Google's and Microsoft's sign-ins work the same way. The
address is never logged.

## Known gaps

- **No rate limit of its own.** Supabase's platform limits apply. A per-caller
  limit would need somewhere to count, and is not built.

## Deploying

Not called by any app until Lift 2.0.1 and Run 1.0.2. Apply the migration
first, then deploy:

```
npx supabase functions deploy account-lookup --project-ref <ref> --use-api --no-verify-jwt
```

`verify_jwt` is off in `config.toml` as well, so a deploy without the flag
cannot switch it back on: the caller has no session to send.
