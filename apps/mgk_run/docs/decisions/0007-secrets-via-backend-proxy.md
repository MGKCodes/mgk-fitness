# 0007 — AI calls go through a server-side proxy

**Status:** Accepted

## Context

Runio's source is public (open source). An LLM provider API key is a spending
credential. Any secret shipped in the client can be extracted from the bundle in
minutes, and here it would also be sitting in a public repository. Calling a
provider directly from the app is therefore not an option. Beyond the key
itself, unmetered client access to a model provider is an unbounded-cost risk.

## Decision

All AI calls route through a **Supabase Edge Function** that holds the provider
key as a server-side secret:

```
app (user JWT) ──▶ Edge Function (auth + rate limit) ──▶ LLM provider
```

The provider is deliberately **not** hard-wired: the function calls
[OpenRouter](https://openrouter.ai) (a gateway), and the model is a server-side
choice (`COACH_MODEL`). This keeps model and provider swaps to a config change.

The function authenticates the user, enforces per-user rate limits and a spend
ceiling, builds the prompt, calls the provider, validates the JSON response, and
returns it. The key (`OPENROUTER_API_KEY`) is set with `supabase secrets set`
and never appears in the repo, the `.env`, or the app bundle.

### How the ceilings are enforced

Settled when the limiter was built; the mechanics and exact numbers live in
[`supabase/functions/coach/README.md`](../../../../supabase/functions/coach/README.md).

- **Rate limits are per surface, not flat.** A plan generation legitimately
  bursts (one skeleton plus several weeks, each retried once against the
  validator) while an intake turn is a single cheap message. One shared number
  would either strangle generation or leave chat wide open.
- **The spend cap is denominated in the provider's own reported cost**, not in a
  price list held in our code. OpenRouter returns the credits charged on every
  completion, so the cap survives a `COACH_MODEL` change to a model that costs
  30× more. An unreported cost is estimated, never treated as free.
- **The counters live in Postgres, not in memory.** Edge Function instances are
  ephemeral, so per-instance counting would not bind. The usage table is
  service-role only: a user must not be able to delete their own rows and reset
  their own cap.
- **A limiter that cannot be consulted fails closed.** Spending money we cannot
  account for is the failure this ADR exists to prevent. The cost is acceptable
  because the client already degrades: a refused plan call falls back to the
  deterministic builder ([ADR-0003](0003-llm-generates-validator-enforces.md)),
  so the runner still gets a structurally sound plan.
- **Usage rows carry counts, never content** — a user id, a surface, tokens, and
  a cost. Spend logging is the obvious place to leak a request body, so the types
  have nowhere to put one (see [compliance.md](../compliance.md)).

## Consequences

- No credential ships in the client; nothing the app stores can call the
  provider directly.
- Abuse and cost are controlled at the proxy (rate limits, spend cap).
- The proxy needs durable per-user counters, so it needs the database — which
  means the coach cannot be deployed without its migration, and says so loudly
  (`503 coach_not_configured`, `reason: limiter_unavailable`) rather than quietly
  spending.
- Model/provider swaps are server-side; the app ships unchanged.
- The server is the single point that decides what data leaves the system —
  structured training context only, supporting data minimisation (see
  [compliance.md](../compliance.md)).
- Adds a backend component to build and operate; justified by the security and
  cost properties. See [llm-and-secrets.md](../architecture/llm-and-secrets.md).
