// Account deletion for the whole suite — one function, app-aware.
//
//   app (user JWT)  ─▶  this function  ─▶  core.delete_account(user, app)
//                                     └─▶  auth admin API (delete the login)
//
// ## What this replaces
//
// Both apps shipped their own `delete-account` against the same project and the
// same slug, so whichever deployed last was the one running — for both. Liftio's
// won. It called `auth.admin.deleteUser` unconditionally, and every user-owned
// table in both schemas cascades from `auth.users`, so a Runio user tapping
// "delete account" erased their Liftio data too.
//
// Deploying Runio's version instead would have been worse, not better: a Liftio
// user would have got a 200 with nothing deleted. Neither function was right for
// both apps, because the question "what should this erase?" has no answer until
// you know who is asking. So now the caller says.
//
// ## Contract
//
// POST, optional body `{ "app": "lift" | "run", "apple": { "code", "client_id" } }`.
//
//   app omitted   erase everything, everywhere, and the login
//   app: "run"    erase run.*; keep the login if lift.* still holds data
//   app: "lift"   erase lift.* and the progress photos, rows and picture
//                 files; keep the login if run.* still holds data
//   apple         a fresh authorisation code from Apple, sent by an app whose
//                 account has an Apple identity; when the login is deleted,
//                 Apple's tokens are revoked with it (see apple.ts)
//
// The user id ALWAYS comes from the verified token and never from the body.
// `app` is the only thing the caller gets to decide, and it can only ever
// narrow what is deleted — a hostile value is rejected outright rather than
// widening the blast radius.
//
// Environment (the first three injected by Supabase, the Apple three set by hand):
//
//     SUPABASE_URL
//     SUPABASE_ANON_KEY            used only to validate the caller's JWT
//     SUPABASE_SERVICE_ROLE_KEY    used only after that check passes
//     APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY
//                                  set by hand; without them a revocation is
//                                  skipped and logged, never refused
//
// Raw fetch for everything the database and auth admin API can do, matching
// `coach/index.ts`, so the wire shape is explicit and the edge build stays
// reproducible. **One exception**, and it is deliberate: the storage sweep uses
// `supabase-js`, because the list and delete body shapes are the two here that
// are easy to hand-write subtly wrong — and a wrong one fails silently as
// "nothing to delete", leaving photographs of somebody's body behind after they
// asked to be erased. See `removeProgressPhotos`.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

import {
  appleKeyFromEnv,
  type AppleRequest,
  appleUserIdOf,
  readAppleRequest,
  revokeAppleTokens,
} from "./apple.ts";
import { type DeletionSummary, sweepsProgressPhotos } from "./summary.ts";

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const KNOWN_APPS = ["lift", "run"] as const;
type App = (typeof KNOWN_APPS)[number];

/// Every object under `<user id>/` in the progress-photos bucket.
///
/// The prefix is the whole of the access control on that bucket
/// (`(storage.foldername(name))[1] = auth.uid()`), which makes it exactly the
/// set of one person's photographs — there is no ambiguity about what belongs
/// to whom.
///
/// **Uses the client library rather than raw fetch, unlike the rest of this
/// file.** Everything else here talks to documented, stable REST endpoints —
/// `/auth/v1/user`, `/rest/v1/rpc/...`, the admin user delete. Storage list and
/// delete are the two shapes worth not hand-writing: the request bodies are
/// easy to get subtly wrong, a wrong one fails silently as "nothing to delete",
/// and the failure mode is retained photographs of somebody's body. The library
/// is the thing that knows the wire format.
///
/// Listed then removed, because there is no delete-by-prefix. `remove` caps at
/// 1000 keys per call, and `list` defaults to 100 — the loop is what makes this
/// correct for three years of weekly photos rather than only the first page.
async function removeProgressPhotos(
  supabaseUrl: string,
  serviceKey: string,
  userId: string,
): Promise<void> {
  try {
    const supabase = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const bucket = supabase.storage.from("progress-photos");

    for (let page = 0; page < 200; page++) {
      const { data, error } = await bucket.list(userId, { limit: 100 });
      if (error) {
        console.error("progress photo list failed", error.message);
        return;
      }
      if (!data || data.length === 0) return;

      const paths = data.map((o: { name: string }) => `${userId}/${o.name}`);
      const { error: removeError } = await bucket.remove(paths);
      if (removeError) {
        console.error("progress photo delete failed", removeError.message);
        return;
      }

      // The page just removed is gone, so the next hundred have moved up into
      // its place — there is no offset to advance. A short page means the
      // folder is now empty.
      if (data.length < 100) return;
    }
    console.error("progress photo sweep hit its guard", userId.slice(0, 8));
  } catch (e) {
    // Never fails the deletion. The rows are gone either way, and asking
    // somebody to retry something that has already mostly happened is worse
    // than a log line that turns this into a support job.
    console.error("progress photo sweep threw", String(e));
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "content-type": "application/json" },
  });
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const authHeader = req.headers.get("Authorization");

  if (!supabaseUrl || !anonKey || !serviceKey) {
    return json({ error: "not_configured" }, 503);
  }
  if (!authHeader) return json({ error: "unauthorized" }, 401);

  // 1. Which app is asking. An absent body means "all of it", which is the
  //    safe-by-omission default: a client that forgets to say gets the full
  //    erasure it asked for in plain English, not a silent partial one.
  let app: App | null = null;
  let apple: AppleRequest | null = null;
  const raw = await req.text();
  if (raw.trim() !== "") {
    let parsed: unknown;
    try {
      parsed = JSON.parse(raw);
    } catch {
      return json({ error: "bad_request" }, 400);
    }
    const candidate = (parsed as { app?: unknown } | null)?.app;
    if (candidate != null) {
      if (
        typeof candidate !== "string" ||
        !KNOWN_APPS.includes(candidate as App)
      ) {
        return json({ error: "unknown_app" }, 400);
      }
      app = candidate as App;
    }
    // Read leniently, unlike `app`: a malformed field narrows nothing and
    // widens nothing, and must not cost somebody their deletion.
    apple = readAppleRequest((parsed as { apple?: unknown } | null)?.apple);
  }

  // 2. The caller must be a signed-in user, and the id we delete comes from the
  //    verified token — never from the request body. Same check as `coach`.
  const userRes = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: { Authorization: authHeader, apikey: anonKey },
  });
  if (!userRes.ok) return json({ error: "unauthorized" }, 401);

  const user = await userRes.json().catch(() => null);
  const userId = user?.id;
  if (typeof userId !== "string" || !userId) {
    return json({ error: "unauthorized" }, 401);
  }

  // 3. Erase the data. One transactional call, so a partial sweep cannot leave
  //    half a user behind. `Content-Profile` is required: the routine lives in
  //    `core`, and without it PostgREST resolves the name in the first exposed
  //    schema and 404s.
  const rpcRes = await fetch(`${supabaseUrl}/rest/v1/rpc/delete_account`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "Content-Profile": "core",
      "apikey": serviceKey,
      "Authorization": `Bearer ${serviceKey}`,
    },
    body: JSON.stringify({ p_user_id: userId, p_app: app }),
  });

  if (!rpcRes.ok) {
    // Never echo the database's message to the client; it can carry schema
    // detail. The status code is what the app acts on.
    console.error("core.delete_account failed", rpcRes.status);
    return json({ error: "delete_failed" }, 500);
  }

  const summary = (await rpcRes.json().catch(() => null)) as
    | DeletionSummary
    | null;
  if (!summary || typeof summary !== "object") {
    console.error("core.delete_account returned no summary");
    return json({ error: "delete_failed" }, 500);
  }

  // 4. Progress photos are two stores, and SQL can only reach one of them.
  //
  //    `core.delete_account` removes the rows; the JPEGs live in the
  //    `progress-photos` bucket and no amount of `delete from` touches them.
  //    Left alone they are the worst possible residue: photographs of somebody's
  //    body, retained after they asked to be erased, invisible to every query
  //    anybody would think to run.
  //
  //    Keyed off what the row sweep reports, so the two cannot drift. The rows
  //    go when Lift leaves, with or without the account, and whenever the last
  //    app does; a Run-only deletion leaves both the rows and the objects,
  //    which is right while Lift still holds them. See `sweepsProgressPhotos`.
  //
  //    Failure here is logged and does not fail the request. The rows are gone
  //    and the objects are unreachable without them; reporting a deletion as
  //    failed would invite a retry of something that has already mostly
  //    happened. The log is what turns it into a support job.
  if (sweepsProgressPhotos(summary)) {
    await removeProgressPhotos(supabaseUrl, serviceKey, userId);
  }

  // 5. The login itself, but only if the sweep said it is safe. Uses the
  //    supported admin endpoint rather than deleting from `auth.users`
  //    directly, so Supabase's own bookkeeping (sessions, identities) is
  //    handled — and so the cascade is never what does the erasing.
  let accountDeleted = false;
  if (summary.auth_user_deletable === true) {
    const delRes = await fetch(
      `${supabaseUrl}/auth/v1/admin/users/${userId}`,
      {
        method: "DELETE",
        headers: {
          "apikey": serviceKey,
          "Authorization": `Bearer ${serviceKey}`,
        },
      },
    );
    accountDeleted = delRes.ok;
    if (!delRes.ok) {
      // The data is already gone, which is the part that matters for erasure.
      // Report the login as retained rather than failing the whole request.
      console.error("auth user delete failed", delRes.status);
    }
  }

  // 6. Apple's tokens, once the login is gone and only then: a login kept for
  //    the other app is one the person still signs in to with Apple.
  //    Whatever happens here, the deletion stands and the answer is the same.
  let appleRevocation: string | null = null;
  const appleUserId = appleUserIdOf(user);
  if (accountDeleted && apple && appleUserId) {
    appleRevocation = await revokeAppleTokens({
      request: apple,
      appleUserId,
      key: appleKeyFromEnv((name) => Deno.env.get(name)),
    });
    if (appleRevocation !== "revoked") {
      console.error("apple revocation", appleRevocation);
    }
  } else if (accountDeleted && appleUserId) {
    // An Apple account deleted without a code: Android, where the app cannot
    // get one yet, or a phone whose Apple sheet failed.
    appleRevocation = "no_code";
  }

  const remaining = summary.remaining_apps ?? [];

  // Counts only — never a health value.
  console.log(
    "account deleted",
    JSON.stringify({
      scope: app ?? "all",
      account_deleted: accountDeleted,
      remaining_apps: remaining,
      rows: summary.deleted_rows ?? {},
      apple: appleRevocation,
    }),
  );

  return json({
    account_deleted: accountDeleted,
    account_retained_reason: accountDeleted
      ? null
      : remaining.length > 0
      ? "other_app_data"
      : "auth_delete_failed",
    remaining_apps: remaining,
    deleted_rows: summary.deleted_rows ?? {},
  });
});
