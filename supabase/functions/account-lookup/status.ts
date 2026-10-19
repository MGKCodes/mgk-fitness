// Which screen *Continue with email* goes to next, from the facts about an
// address (Run's ADR-0047, "Email first").
//
//     deno test
//
// Kept apart from `index.ts` so the decision is tested without a database or a
// server: `core.account_facts` reads `auth`, and this decides.

/// What the app is told about an address, and nothing else.
///
///   new           no account: *Create your account*, then a code by email
///   unconfirmed   an account made and never confirmed. **Looks exactly like
///                 `new` on screen**; the app needs to know only so that the
///                 password typed now replaces the first one once the code
///                 proves the inbox (the ADR's point 6)
///   password      *Welcome back* and a password field
///   apple, google this address signs in with that provider, so the screen
///                 offers its button, and *Set a password instead*
export type AccountStatus =
  | "new"
  | "unconfirmed"
  | "password"
  | "apple"
  | "google";

/// What `core.account_facts` returns.
export type AccountFacts =
  | { exists: false }
  | {
    exists: true;
    confirmed: boolean;
    has_password: boolean;
    providers: string[];
  };

/// The one decision.
///
/// **A password wins.** An account made by email and later joined by Google
/// (Supabase links them by address) still signs in with its password, so
/// asking for it is the shortest way in. Only an account with no password is
/// pointed at a provider.
///
/// **Apple before Google**, when an account has both and no password: either
/// works, and Apple is the one whose sheet every iPhone has. Android reaches
/// Apple through the browser, so it is not a dead end there either.
///
/// **Unconfirmed is checked after the providers**, not before: an account with
/// a provider identity was confirmed by that provider, so reaching the last
/// branch unconfirmed means a sign-up nobody finished.
export function statusOf(facts: AccountFacts): AccountStatus {
  if (!facts.exists) return "new";
  if (facts.has_password && facts.confirmed) return "password";
  if (facts.providers.includes("apple")) return "apple";
  if (facts.providers.includes("google")) return "google";
  if (!facts.confirmed) return "unconfirmed";
  // Confirmed, no password, no provider we offer: an account made some other
  // way (an invite, the dashboard). The password path's *Forgot your password?*
  // is its way in, so it is treated as one.
  return "password";
}

/// Reads `{ "email": "..." }`, or null when there is no plausible address.
///
/// **Plausible, not valid.** The app has already checked the shape; this only
/// refuses what could never be an address, so the database is not asked about
/// a megabyte of text. Trimmed and lower-cased, as gotrue stores addresses.
export function readEmail(body: unknown): string | null {
  if (typeof body !== "object" || body === null) return null;
  const raw = (body as Record<string, unknown>).email;
  if (typeof raw !== "string") return null;
  const email = raw.trim().toLowerCase();
  if (email.length < 3 || email.length > 320) return null;
  const at = email.indexOf("@");
  if (at < 1 || at !== email.lastIndexOf("@") || at === email.length - 1) {
    return null;
  }
  if (/\s/.test(email)) return null;
  return email;
}

/// Reads `core.account_facts`'s answer defensively, so a shape the routine
/// never sends is an error rather than a guess at new or returning.
export function readFacts(value: unknown): AccountFacts | null {
  if (typeof value !== "object" || value === null) return null;
  const v = value as Record<string, unknown>;
  if (v.exists === false) return { exists: false };
  if (
    v.exists === true &&
    typeof v.confirmed === "boolean" &&
    typeof v.has_password === "boolean" &&
    Array.isArray(v.providers) &&
    v.providers.every((p) => typeof p === "string")
  ) {
    return {
      exists: true,
      confirmed: v.confirmed,
      has_password: v.has_password,
      providers: v.providers as string[],
    };
  }
  return null;
}
