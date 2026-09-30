// Revoking Apple's tokens when an account with an Apple identity is deleted.
//
// Apple requires it of any app offering Sign in with Apple (App Review
// guideline 5.1.1(v)): deleting the account must also end the app's
// authorisation at Apple, or the person still finds the app under "Sign in with
// Apple" in their Apple ID settings with nothing behind it.
//
// Supabase keeps no Apple token to revoke with. So the app asks Apple for a
// fresh authorisation code just before deleting, and sends it; this exchanges
// the code for a refresh token and revokes that, which ends every token the
// person's Apple ID has issued to the app.
//
//   app ─ code ─▶ delete-account ─▶ appleid.apple.com/auth/token   (exchange)
//                                └▶ appleid.apple.com/auth/revoke  (revoke)
//
// **A revocation never blocks a deletion.** Apple requires the deletion to
// happen regardless, so every failure here is an outcome to log, not an error
// to return.
//
// Environment (Edge Functions › Secrets; see Lift's docs/store-setup.md, step 7):
//
//     APPLE_TEAM_ID
//     APPLE_KEY_ID
//     APPLE_PRIVATE_KEY     the .p8 file's contents

/// The ids Apple can have issued a code to. A code is only good for the client
/// it was issued to, so the app says which; anything else is ignored rather
/// than signed for. Android's Services ID is not here yet: the app cannot get
/// a fresh code on Android (see README).
export const APPLE_CLIENT_IDS: readonly string[] = [
  "com.mgkcodes.liftio",
  "com.mgkcodes.fitness.run",
];

export interface AppleKey {
  teamId: string;
  keyId: string;
  /// PKCS#8, as Apple hands it over in the .p8: PEM, or the same with its
  /// newlines escaped by whatever it was pasted through.
  privateKey: string;
}

export interface AppleRequest {
  code: string;
  clientId: string;
}

export type RevokeOutcome =
  | "revoked"
  | "not_configured"
  | "exchange_failed"
  | "other_apple_user"
  | "revoke_failed"
  | "unreachable";

/// The `apple` field of a deletion request, or null if there is none worth
/// acting on. Never throws: a malformed field must not cost the deletion.
export function readAppleRequest(value: unknown): AppleRequest | null {
  if (value == null || typeof value !== "object") return null;
  const { code, client_id: clientId } = value as Record<string, unknown>;
  if (typeof code !== "string" || code.length === 0 || code.length > 1024) {
    return null;
  }
  if (typeof clientId !== "string" || !APPLE_CLIENT_IDS.includes(clientId)) {
    return null;
  }
  return { code, clientId };
}

/// The account's Apple user id, from the user record Supabase returned, or
/// null when it has no Apple identity.
export function appleUserIdOf(user: unknown): string | null {
  const identities = (user as { identities?: unknown } | null)?.identities;
  if (!Array.isArray(identities)) return null;
  for (const identity of identities) {
    if (identity?.provider !== "apple") continue;
    const sub = identity.identity_data?.sub ?? identity.id;
    if (typeof sub === "string" && sub.length > 0) return sub;
  }
  return null;
}

/// The key from the environment, or null when any part is missing.
export function appleKeyFromEnv(
  get: (name: string) => string | undefined,
): AppleKey | null {
  const teamId = get("APPLE_TEAM_ID");
  const keyId = get("APPLE_KEY_ID");
  const privateKey = get("APPLE_PRIVATE_KEY");
  if (!teamId || !keyId || !privateKey) return null;
  return { teamId, keyId, privateKey };
}

/// Exchanges [request]'s code and revokes what it bought, if the code belongs
/// to [appleUserId]. Never throws.
export async function revokeAppleTokens(opts: {
  request: AppleRequest;
  appleUserId: string;
  key: AppleKey | null;
  fetch?: typeof fetch;
  baseUrl?: string;
  now?: number;
}): Promise<RevokeOutcome> {
  const { request, appleUserId, key } = opts;
  if (!key) return "not_configured";
  const send = opts.fetch ?? fetch;
  const base = opts.baseUrl ?? "https://appleid.apple.com";

  try {
    const secret = await clientSecret(key, request.clientId, opts.now);

    const exchange = await send(`${base}/auth/token`, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: request.clientId,
        client_secret: secret,
        code: request.code,
        grant_type: "authorization_code",
      }),
    });
    if (!exchange.ok) return "exchange_failed";
    const tokens = await exchange.json().catch(() => null) as
      | { id_token?: string; refresh_token?: string; access_token?: string }
      | null;

    // The code has to be this account's. An iPhone signed in to somebody
    // else's Apple ID would hand over theirs, and revoking that would sign a
    // stranger out of the app.
    if (subjectOf(tokens?.id_token) !== appleUserId) return "other_apple_user";

    const token = tokens?.refresh_token ?? tokens?.access_token;
    if (!token) return "exchange_failed";

    const revoke = await send(`${base}/auth/revoke`, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: request.clientId,
        client_secret: secret,
        token,
        token_type_hint: tokens?.refresh_token
          ? "refresh_token"
          : "access_token",
      }),
    });
    return revoke.ok ? "revoked" : "revoke_failed";
  } catch {
    // A network failure, or a key that will not import. Neither is worth the
    // deletion.
    return "unreachable";
  }
}

/// The client secret Apple asks for: a JWT signed with the .p8 key, naming the
/// team, the key and the client. Five minutes is plenty for two requests.
export async function clientSecret(
  key: AppleKey,
  clientId: string,
  now = Date.now(),
): Promise<string> {
  const iat = Math.floor(now / 1000);
  const header = { alg: "ES256", kid: key.keyId, typ: "JWT" };
  const payload = {
    iss: key.teamId,
    iat,
    exp: iat + 300,
    aud: "https://appleid.apple.com",
    sub: clientId,
  };
  const signingInput = `${base64url(JSON.stringify(header))}.${
    base64url(JSON.stringify(payload))
  }`;
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    pkcs8Bytes(key.privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  // WebCrypto's ECDSA signature is already r || s, the form JWS wants.
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    cryptoKey,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64url(new Uint8Array(signature))}`;
}

function pkcs8Bytes(pem: string): Uint8Array<ArrayBuffer> {
  const body = pem
    .replace(/\\n/g, "\n")
    .replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
}

/// The `sub` of a JWT that came straight from Apple over TLS, in answer to our
/// own request. Its signature is not checked because nothing else could have
/// written it; it is read only to tell whose code this was.
function subjectOf(jwt: string | undefined): string | null {
  const payload = jwt?.split(".")[1];
  if (!payload) return null;
  try {
    const json = atob(payload.replace(/-/g, "+").replace(/_/g, "/"));
    const sub = JSON.parse(json)?.sub;
    return typeof sub === "string" ? sub : null;
  } catch {
    return null;
  }
}

function base64url(input: string | Uint8Array): string {
  const bytes = typeof input === "string"
    ? new TextEncoder().encode(input)
    : input;
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(
    /=+$/,
    "",
  );
}
