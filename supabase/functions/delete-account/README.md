# `delete-account` Edge Function

One function, both apps. The user deletes their account and their data is
**actually removed**, not hidden.

```
app (user JWT)  ─▶  delete-account  ─▶  core.delete_account(user, app)
                                   └─▶  auth admin API (delete the login)
```

The client cannot do this itself. Removing an `auth.users` row needs the
service-role key, and the sweep crosses schemas that RLS deliberately walls off.
So the function verifies the caller's JWT with the anon key — exactly as
[`coach`](../coach/index.ts) does — and only then acts with elevated privilege,
**on the id from the verified token**, never one supplied by the caller.

## The bug this replaces

Both apps shipped a `delete-account` function against the same project under the
same slug, so whichever deployed last was the one running — for both. Liftio's
won. It called `auth.admin.deleteUser` unconditionally, and every user-owned
table in both schemas cascades from `auth.users`. A Runio user tapping "delete
account" therefore erased their Liftio data too.

Deploying Runio's version instead would have been *worse*: it never touched a
Liftio table, so a Liftio user would have received a `200` with nothing deleted
and been told their account was gone. A silent failure to honour an erasure
request is harder to notice than an over-deletion, and harder to defend.

Neither was right for both apps, because "what should this erase?" has no answer
until you know who is asking. Now the caller says.

## Contract

`POST`, optional body:

```json
{ "app": "run" }
```

| body | erases |
|---|---|
| omitted | everything, everywhere, and the login |
| `{"app":"run"}` | `run.*`; the login survives if `lift.*` still holds data |
| `{"app":"lift"}` | `lift.*` and the progress photos, rows and picture files; the login survives if `run.*` still holds data |

When the last app goes, the coach data and the shared `core` rows go with it and
the login is deleted.

**Progress photos are Lift's**, though the table is `core.progress_photos`. They
go whenever Lift does. The routine deletes the rows and reports
`photos_deleted`; the function then empties `<user id>/` in the
`progress-photos` bucket, which no SQL reaches ([`summary.ts`](summary.ts)).

An app whose account has an Apple identity also sends
`"apple": { "code": "<fresh authorisation code>", "client_id": "<its bundle id>" }`;
see *Apple's tokens* below.

`app` is the only thing the caller decides, and it can only ever **narrow** what
is erased. An unrecognised value is rejected with `400 unknown_app` rather than
being ignored — ignoring it would silently widen the deletion to everything.

Response `200`:

```json
{
  "account_deleted": false,
  "account_retained_reason": "other_app_data",
  "remaining_apps": ["lift"],
  "deleted_rows": { "run.runs": 10, "run.run_points": 1859 }
}
```

`account_retained_reason` is `"other_app_data"` when the login was kept because
another app still holds data, or `"auth_delete_failed"` if the data went but the
login did not.

Errors: `400 bad_request` / `400 unknown_app`, `401 unauthorized`,
`503 not_configured`, `500 delete_failed`. On `delete_failed` the transaction
rolled back — nothing was removed.

## Deploy

Needs the migrations first; the function is a thin wrapper around the SQL.

```sh
supabase db push                      # core.delete_account must exist
supabase functions deploy delete-account
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are
injected by the platform. `APPLE_TEAM_ID`, `APPLE_KEY_ID` and
`APPLE_PRIVATE_KEY` (the `.p8` file's contents) are set by hand, under Edge
Functions › Secrets; without them a deletion still happens and the revocation
is logged as `not_configured`.

`core` must be in the dashboard's **Exposed schemas** list, or the RPC 404s and
every deletion returns `500 delete_failed`.

**One change goes the other way round.**
`20261001120000_lift_deletion_takes_progress_photos.sql` makes a Lift-only
deletion remove the photo rows. Deploy the function **before** applying it: the
old function would not sweep the bucket for that deletion, and the picture
files would be left with no row pointing at them.

## Two things worth knowing before changing this

**The sweep enumerates tables by their `user_id` column**, not a hard-coded
list, so a table added later is covered by construction. Give every new
user-owned table a `user_id` or it silently escapes erasure — a GDPR problem no
test would catch.

**Coach data is erased only when the last app goes.** `coach.conversations` has
no `app` column, so there is no honest way to erase "the running half" of a
conversation. Once conversations are app-tagged, scope this the same way the app
schemas are scoped.

## Apple's tokens

Apple requires an app offering Sign in with Apple to revoke the person's
tokens when their account is deleted (guideline 5.1.1(v)). Supabase keeps no
Apple token to revoke with, so the app asks Apple for a **fresh authorisation
code** just before deleting and sends it. [`apple.ts`](apple.ts) exchanges it
at `appleid.apple.com/auth/token` and revokes the refresh token that bought.

- **Only when the login is actually deleted.** A login kept for the other app
  is one the person still signs in to with Apple.
- **Only if the code is this account's.** The exchange returns an id token;
  its `sub` must be the account's Apple identity, or an iPhone signed in to
  somebody else's Apple ID would sign a stranger out.
- **Never at the deletion's expense.** Every failure is an outcome in the log
  line's `apple` field (`revoked`, `exchange_failed`, `other_apple_user`,
  `revoke_failed`, `unreachable`, `not_configured`, `no_code`), and the answer
  to the app is the same either way.
- **The client secret** is a five-minute ES256 JWT signed with the `.p8` key,
  for the `client_id` the app names, which must be one of `APPLE_CLIENT_IDS`.

**Android sends no code yet.** Apple's sign-in there is a web sign-in through
Supabase, and getting a fresh code from Android needs Apple's web flow with a
callback route that hands the result back to the app, plus that route on the
Services ID in Apple's portal. Until then an Android deletion logs `no_code`,
and the person can remove the app at appleid.apple.com. Apple's rule is
enforced on the App Store build, which does send one.

```sh
deno test          # apple_test.ts: a fake Apple, and a key made in the test
                   # summary_test.ts: when the picture files are swept
```

## Try it

```sh
curl -i -X POST "$SUPABASE_URL/functions/v1/delete-account" \
  -H "Authorization: Bearer <a user access token>" \
  -H "content-type: application/json" \
  -d '{"app":"run"}'
```

Use a throwaway account. There is no undo.
