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
// POST, optional body `{ "app": "lift" | "run" }`.
//
//   app omitted   erase everything, everywhere, and the login
//   app: "run"    erase run.*; keep the login if lift.* still holds data
//
// The user id ALWAYS comes from the verified token and never from the body.
// `app` is the only thing the caller gets to decide, and it can only ever
// narrow what is deleted — a hostile value is rejected outright rather than
// widening the blast radius.
//
// Environment (all injected by Supabase; no new secret):
//
//     SUPABASE_URL
//     SUPABASE_ANON_KEY            used only to validate the caller's JWT
//     SUPABASE_SERVICE_ROLE_KEY    used only after that check passes
//
// Dependency-free (raw fetch), matching `coach/index.ts`, so the wire shape is
// explicit and the Deno edge build stays reproducible.

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const KNOWN_APPS = ["lift", "run"] as const;
type App = (typeof KNOWN_APPS)[number];

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "content-type": "application/json" },
  });
}

interface DeletionSummary {
  deleted_rows?: Record<string, number>;
  remaining_apps?: string[];
  shared_deleted?: boolean;
  auth_user_deletable?: boolean;
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

  // 4. The login itself, but only if the sweep said it is safe. Uses the
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

  const remaining = summary.remaining_apps ?? [];

  // Counts only — never a health value.
  console.log(
    "account deleted",
    JSON.stringify({
      scope: app ?? "all",
      account_deleted: accountDeleted,
      remaining_apps: remaining,
      rows: summary.deleted_rows ?? {},
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
