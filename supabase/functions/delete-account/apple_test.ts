// Unit tests for revoking Apple's tokens on deletion, against a fake Apple.
//
// The key is generated here, so no real .p8 is ever near a test; the fake
// checks the client secret against its public half, the way Apple would.
//
//     deno test

import { assert, assertEquals } from "jsr:@std/assert@1";

import {
  type AppleKey,
  appleKeyFromEnv,
  appleUserIdOf,
  readAppleRequest,
  revokeAppleTokens,
} from "./apple.ts";

const APPLE_USER = "001234.abcdef.5678";
const REQUEST = { code: "c-fresh", clientId: "com.mgkcodes.liftio" };

async function testKey(): Promise<{ key: AppleKey; publicKey: CryptoKey }> {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const der = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", pair.privateKey),
  );
  let binary = "";
  for (const b of der) binary += String.fromCharCode(b);
  const body = btoa(binary).match(/.{1,64}/g)!.join("\n");
  return {
    key: {
      teamId: "TEAM123456",
      keyId: "KEY1234567",
      privateKey:
        `-----BEGIN PRIVATE KEY-----\n${body}\n-----END PRIVATE KEY-----\n`,
    },
    publicKey: pair.publicKey,
  };
}

function unsignedJwt(payload: Record<string, unknown>): string {
  const part = (v: unknown) =>
    btoa(JSON.stringify(v)).replace(/\+/g, "-").replace(/\//g, "_")
      .replace(/=+$/, "");
  return `${part({ alg: "RS256" })}.${part(payload)}.sig`;
}

function fromBase64url(s: string): Uint8Array<ArrayBuffer> {
  return Uint8Array.from(
    atob(s.replace(/-/g, "+").replace(/_/g, "/")),
    (c) => c.charCodeAt(0),
  );
}

interface Call {
  path: string;
  form: Record<string, string>;
}

/// A stand-in for appleid.apple.com. [exchange] and [revoke] say how each
/// endpoint answers.
function fakeApple(opts: {
  exchange?: { status: number; body?: unknown };
  revoke?: { status: number };
  sub?: string;
}) {
  const calls: Call[] = [];
  const fetch = (input: string | URL | Request, init?: RequestInit) => {
    const url = new URL(String(input));
    const form = Object.fromEntries(
      new URLSearchParams(String(init?.body ?? "")),
    );
    calls.push({ path: url.pathname, form });
    if (url.pathname === "/auth/token") {
      const e = opts.exchange ?? {
        status: 200,
        body: {
          access_token: "a-token",
          refresh_token: "r-token",
          id_token: unsignedJwt({ sub: opts.sub ?? APPLE_USER }),
        },
      };
      return Promise.resolve(
        new Response(JSON.stringify(e.body ?? {}), { status: e.status }),
      );
    }
    if (url.pathname === "/auth/revoke") {
      return Promise.resolve(
        new Response("", { status: opts.revoke?.status ?? 200 }),
      );
    }
    return Promise.resolve(new Response("", { status: 404 }));
  };
  return { calls, fetch: fetch as typeof globalThis.fetch };
}

// ---- the exchange and the revoke --------------------------------------------

Deno.test("exchanges the code, then revokes the refresh token it bought", async () => {
  const { key } = await testKey();
  const apple = fakeApple({});

  const outcome = await revokeAppleTokens({
    request: REQUEST,
    appleUserId: APPLE_USER,
    key,
    fetch: apple.fetch,
    baseUrl: "https://apple.test",
  });

  assertEquals(outcome, "revoked");
  assertEquals(apple.calls.map((c) => c.path), ["/auth/token", "/auth/revoke"]);
  assertEquals(apple.calls[0].form.code, "c-fresh");
  assertEquals(apple.calls[0].form.grant_type, "authorization_code");
  assertEquals(apple.calls[0].form.client_id, "com.mgkcodes.liftio");
  assertEquals(apple.calls[1].form.token, "r-token");
  assertEquals(apple.calls[1].form.token_type_hint, "refresh_token");
  assertEquals(apple.calls[1].form.client_id, "com.mgkcodes.liftio");
});

Deno.test("the client secret is a JWT Apple can verify with the key's public half", async () => {
  const { key, publicKey } = await testKey();
  const apple = fakeApple({});
  const now = Date.UTC(2026, 8, 30, 12, 0, 0);

  await revokeAppleTokens({
    request: REQUEST,
    appleUserId: APPLE_USER,
    key,
    fetch: apple.fetch,
    baseUrl: "https://apple.test",
    now,
  });

  const secret = apple.calls[0].form.client_secret;
  const [h, p, s] = secret.split(".");
  const header = JSON.parse(new TextDecoder().decode(fromBase64url(h)));
  const payload = JSON.parse(new TextDecoder().decode(fromBase64url(p)));
  assertEquals(header, { alg: "ES256", kid: "KEY1234567", typ: "JWT" });
  assertEquals(payload, {
    iss: "TEAM123456",
    iat: now / 1000,
    exp: now / 1000 + 300,
    aud: "https://appleid.apple.com",
    sub: "com.mgkcodes.liftio",
  });
  assert(
    await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      publicKey,
      fromBase64url(s),
      new TextEncoder().encode(`${h}.${p}`),
    ),
    "signature does not verify",
  );
  // The same secret signs both calls.
  assertEquals(apple.calls[1].form.client_secret, secret);
});

Deno.test("a key pasted with its newlines escaped still signs", async () => {
  const { key } = await testKey();
  const apple = fakeApple({});
  const escaped = { ...key, privateKey: key.privateKey.replace(/\n/g, "\\n") };

  const outcome = await revokeAppleTokens({
    request: REQUEST,
    appleUserId: APPLE_USER,
    key: escaped,
    fetch: apple.fetch,
    baseUrl: "https://apple.test",
  });

  assertEquals(outcome, "revoked");
});

Deno.test("a code from somebody else's Apple ID is not revoked", async () => {
  const { key } = await testKey();
  const apple = fakeApple({ sub: "somebody.else" });

  const outcome = await revokeAppleTokens({
    request: REQUEST,
    appleUserId: APPLE_USER,
    key,
    fetch: apple.fetch,
    baseUrl: "https://apple.test",
  });

  assertEquals(outcome, "other_apple_user");
  assertEquals(apple.calls.map((c) => c.path), ["/auth/token"]);
});

Deno.test("a refused exchange revokes nothing", async () => {
  const { key } = await testKey();
  const apple = fakeApple({
    exchange: { status: 400, body: { error: "invalid_grant" } },
  });

  const outcome = await revokeAppleTokens({
    request: REQUEST,
    appleUserId: APPLE_USER,
    key,
    fetch: apple.fetch,
    baseUrl: "https://apple.test",
  });

  assertEquals(outcome, "exchange_failed");
  assertEquals(apple.calls.length, 1);
});

Deno.test("a refused revoke is reported, not thrown", async () => {
  const { key } = await testKey();
  const apple = fakeApple({ revoke: { status: 400 } });

  const outcome = await revokeAppleTokens({
    request: REQUEST,
    appleUserId: APPLE_USER,
    key,
    fetch: apple.fetch,
    baseUrl: "https://apple.test",
  });

  assertEquals(outcome, "revoke_failed");
});

Deno.test("no network is an outcome, not an exception", async () => {
  const { key } = await testKey();

  const outcome = await revokeAppleTokens({
    request: REQUEST,
    appleUserId: APPLE_USER,
    key,
    fetch: () => Promise.reject(new TypeError("connection refused")),
  });

  assertEquals(outcome, "unreachable");
});

Deno.test("with no key configured, nothing is sent to Apple", async () => {
  const apple = fakeApple({});

  const outcome = await revokeAppleTokens({
    request: REQUEST,
    appleUserId: APPLE_USER,
    key: null,
    fetch: apple.fetch,
  });

  assertEquals(outcome, "not_configured");
  assertEquals(apple.calls.length, 0);
});

// ---- reading the request and the account ------------------------------------

Deno.test("the apple field is read only when it names a known client", () => {
  assertEquals(
    readAppleRequest({ code: "c", client_id: "com.mgkcodes.fitness.run" }),
    { code: "c", clientId: "com.mgkcodes.fitness.run" },
  );
  assertEquals(
    readAppleRequest({ code: "c", client_id: "com.evil.app" }),
    null,
  );
  assertEquals(readAppleRequest({ client_id: "com.mgkcodes.liftio" }), null);
  assertEquals(
    readAppleRequest({ code: "", client_id: "com.mgkcodes.liftio" }),
    null,
  );
  assertEquals(readAppleRequest("c"), null);
  assertEquals(readAppleRequest(null), null);
  assertEquals(readAppleRequest(undefined), null);
});

Deno.test("the Apple user id comes from the account's Apple identity", () => {
  assertEquals(
    appleUserIdOf({
      identities: [
        { provider: "email", id: "uuid-1", identity_data: { sub: "uuid-1" } },
        {
          provider: "apple",
          id: APPLE_USER,
          identity_data: { sub: APPLE_USER },
        },
      ],
    }),
    APPLE_USER,
  );
  // Older records carry the provider's id only as `id`.
  assertEquals(
    appleUserIdOf({ identities: [{ provider: "apple", id: APPLE_USER }] }),
    APPLE_USER,
  );
  assertEquals(
    appleUserIdOf({ identities: [{ provider: "google", id: "g-1" }] }),
    null,
  );
  assertEquals(appleUserIdOf({}), null);
  assertEquals(appleUserIdOf(null), null);
});

Deno.test("the key is read from all three secrets or not at all", () => {
  const env: Record<string, string> = {
    APPLE_TEAM_ID: "T",
    APPLE_KEY_ID: "K",
    APPLE_PRIVATE_KEY: "P",
  };
  assertEquals(appleKeyFromEnv((n) => env[n]), {
    teamId: "T",
    keyId: "K",
    privateKey: "P",
  });
  delete env.APPLE_KEY_ID;
  assertEquals(appleKeyFromEnv((n) => env[n]), null);
});
