// Which screen *Continue with email* goes to next, for both apps
// (Run's ADR-0047, "Email first").
//
//   app (signed out)  ─▶  this function  ─▶  core.account_facts(email)
//
// ## Contract
//
// POST `{ "email": "you@example.com" }`
//
//   200 { "status": "new" | "unconfirmed" | "password" | "apple" | "google" }
//   400 { "error": "bad_email" }     nothing that could be an address
//   405                              not a POST
//   500 { "error": "lookup_failed" } the database did not answer
//
// The app shows "No connection" on anything but a 200, keeps what was typed,
// and never guesses new or returning.
//
// ## Who may ask
//
// Anybody: the person asking is, by definition, not signed in. That an address
// has an account is told to whoever types it, which the ADR accepts ("this
// address uses MGKFitness", nothing about anybody's training), and which
// Supabase's sign-up call already reveals to anyone holding the public key. So
// `verify_jwt` is off in `config.toml`, as for the other functions, and
// nothing here reads a token.
//
// **No rate limit of its own.** Supabase's edge limits apply; a per-address or
// per-caller limit is not built. Recorded as a known gap in the README.
//
// Environment, injected by Supabase:
//
//     SUPABASE_URL
//     SUPABASE_SERVICE_ROLE_KEY    the only key that may call core.account_facts

import { readEmail, readFacts, statusOf } from "./status.ts";

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "content-type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const email = readEmail(await req.json().catch(() => null));
  if (email === null) return json({ error: "bad_email" }, 400);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    console.error("account-lookup: missing environment");
    return json({ error: "lookup_failed" }, 500);
  }

  // `Content-Profile` is required: the routine lives in `core`, and without it
  // PostgREST resolves the name in the first exposed schema and 404s.
  const res = await fetch(`${supabaseUrl}/rest/v1/rpc/account_facts`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "Content-Profile": "core",
      "apikey": serviceKey,
      "Authorization": `Bearer ${serviceKey}`,
    },
    body: JSON.stringify({ p_email: email }),
  }).catch(() => null);

  if (!res || !res.ok) {
    // Never echo the database's message: it can carry schema detail.
    console.error("core.account_facts failed", res?.status);
    return json({ error: "lookup_failed" }, 500);
  }

  const facts = readFacts(await res.json().catch(() => null));
  if (facts === null) {
    console.error("core.account_facts: unexpected shape");
    return json({ error: "lookup_failed" }, 500);
  }

  // Never logged: an address is personal data, and the answer is about it.
  return json({ status: statusOf(facts) });
});
