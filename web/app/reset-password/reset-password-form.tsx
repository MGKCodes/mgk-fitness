"use client";

import { useSearchParams } from "next/navigation";
import { useRef, useState, type FormEvent } from "react";

// Public values, the same two every copy of both apps carries. Set in Vercel,
// not committed, the way the apps take theirs from the build.
const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL;
const PUBLISHABLE_KEY = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

// Lift asks for eight at sign-up and Run for six. It is one account, so the
// stricter of the two.
const MIN_LENGTH = 8;

const ASK_AGAIN =
  "Open Lift or Run, choose Sign in, then Forgot your password? to get a new link.";

type Stage = "choosing" | "saving" | "done" | "spent";

class AuthCallError extends Error {
  constructor(
    readonly status: number,
    readonly code: string | undefined,
    message: string,
  ) {
    super(message);
  }
}

// Two calls to Supabase Auth and one courtesy call, so no client library: it
// would also keep the session in local storage, and this page wants the
// session to live exactly as long as the form does.
async function auth<T>(
  path: string,
  init: { method: string; body?: unknown; token?: string },
): Promise<T> {
  const response = await fetch(`${SUPABASE_URL}/auth/v1${path}`, {
    method: init.method,
    headers: {
      apikey: PUBLISHABLE_KEY ?? "",
      "Content-Type": "application/json",
      ...(init.token ? { Authorization: `Bearer ${init.token}` } : {}),
    },
    body: init.body === undefined ? undefined : JSON.stringify(init.body),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new AuthCallError(
      response.status,
      body.error_code,
      body.msg ?? body.error_description ?? "",
    );
  }
  return body as T;
}

export function ResetPasswordForm() {
  const params = useSearchParams();
  const tokenHash = params.get("token_hash");
  const type = params.get("type");

  const [password, setPassword] = useState("");
  const [show, setShow] = useState(false);
  const [stage, setStage] = useState<Stage>("choosing");
  const [error, setError] = useState<string | null>(null);

  // Verifying spends the link. If the new password is then refused, as too
  // short say, the next try must reuse this rather than verify again.
  const session = useRef<string | null>(null);

  // Before the link is checked: success takes the token out of the address,
  // and the search params follow it.
  if (stage === "done") {
    return (
      <div className="card" role="status">
        <p>
          <strong>Your password is changed.</strong> Open Lift or Run and sign
          in with it. You can close this page.
        </p>
      </div>
    );
  }

  if (stage === "spent") {
    return (
      <div className="card" role="alert">
        <p>This link has expired or has already been used. {ASK_AGAIN}</p>
      </div>
    );
  }

  if (!SUPABASE_URL || !PUBLISHABLE_KEY) {
    return (
      <div className="card">
        <p>
          Changing a password here is not working at the moment. Email{" "}
          <a href="mailto:hello@mgkcodes.com">hello@mgkcodes.com</a> and we
          will sort it out.
        </p>
      </div>
    );
  }

  if (!tokenHash || (type !== null && type !== "recovery")) {
    return (
      <div className="card">
        <p>
          This page opens from the link in a password reset email. {ASK_AGAIN}
        </p>
      </div>
    );
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (password.length < MIN_LENGTH) {
      setError(`Use at least ${MIN_LENGTH} characters.`);
      return;
    }
    setStage("saving");
    setError(null);

    try {
      if (session.current === null) {
        const verified = await auth<{ access_token: string }>("/verify", {
          method: "POST",
          body: { type: "recovery", token_hash: tokenHash },
        });
        session.current = verified.access_token;
      }
      await auth("/user", {
        method: "PUT",
        token: session.current,
        body: { password },
      });
    } catch (e) {
      const said = explain(e, session.current !== null);
      if (said === "spent") {
        setStage("spent");
      } else {
        setError(said);
        setStage("choosing");
      }
      return;
    }

    // The session was only ever for this. Ending it means a browser left open
    // on a shared computer holds nothing.
    void auth("/logout?scope=local", {
      method: "POST",
      token: session.current,
    }).catch(() => {});
    session.current = null;
    window.history.replaceState(null, "", "/reset-password");
    setStage("done");
  }

  const saving = stage === "saving";
  return (
    <form className="form" onSubmit={submit} noValidate>
      <label htmlFor="password">New password</label>
      <input
        id="password"
        name="password"
        type={show ? "text" : "password"}
        autoComplete="new-password"
        minLength={MIN_LENGTH}
        required
        value={password}
        onChange={(e) => setPassword(e.target.value)}
        aria-describedby="password-hint"
        aria-invalid={error !== null}
        disabled={saving}
      />
      <p id="password-hint" className="hint">
        At least {MIN_LENGTH} characters.
      </p>
      <label className="check">
        <input
          type="checkbox"
          checked={show}
          onChange={(e) => setShow(e.target.checked)}
        />
        Show password
      </label>
      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}
      <button type="submit" disabled={saving}>
        {saving ? "Changing…" : "Change password"}
      </button>
    </form>
  );
}

// What to tell somebody, or "spent" when the link itself is no good any more.
function explain(e: unknown, verified: boolean): string | "spent" {
  if (!(e instanceof AuthCallError)) {
    return "We could not reach the server. Check your connection and try again.";
  }
  if (e.status === 429) {
    return "Too many tries in a row. Wait a few minutes, then try again.";
  }
  if (e.code === "same_password") {
    return "That is the password you already have. Sign in with it, or choose a different one.";
  }
  if (e.code === "weak_password") {
    // Supabase's own words, because they name the rule the server holds,
    // which may be stricter than the length checked above.
    return e.message || `Use at least ${MIN_LENGTH} characters.`;
  }
  // Refused before verifying: the token is expired, used or unknown. Refused
  // after: the session it bought has lapsed, which only happens once the link
  // would have lapsed too. Either way the answer is a new email.
  if (e.status === 401 || e.status === 403 || (!verified && e.status < 500)) {
    return "spent";
  }
  return "Something went wrong on our side. Try again, or email hello@mgkcodes.com.";
}
