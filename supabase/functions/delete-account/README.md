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
| `{"app":"lift"}` | `lift.*`; the login survives if `run.*` still holds data |

When the last app goes, the coach data and the shared `core` rows go with it and
the login is deleted.

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

**No new secrets.** `SUPABASE_URL`, `SUPABASE_ANON_KEY` and
`SUPABASE_SERVICE_ROLE_KEY` are all injected by the platform.

`core` must be in the dashboard's **Exposed schemas** list, or the RPC 404s and
every deletion returns `500 delete_failed`.

## Two things worth knowing before changing this

**The sweep enumerates tables by their `user_id` column**, not a hard-coded
list, so a table added later is covered by construction. Give every new
user-owned table a `user_id` or it silently escapes erasure — a GDPR problem no
test would catch.

**Coach data is erased only when the last app goes.** `coach.conversations` has
no `app` column, so there is no honest way to erase "the running half" of a
conversation. Once conversations are app-tagged, scope this the same way the app
schemas are scoped.

## Try it

```sh
curl -i -X POST "$SUPABASE_URL/functions/v1/delete-account" \
  -H "Authorization: Bearer <a user access token>" \
  -H "content-type: application/json" \
  -d '{"app":"run"}'
```

Use a throwaway account. There is no undo.
