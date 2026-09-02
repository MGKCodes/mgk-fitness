# LLM integration & secrets

This is an addition to the original handoff, and it is load-bearing for an
**open-source** app: the source is public, so a key in the client is a key in
everyone's hands.

## The rule

**The provider API key never reaches the client.** All AI calls go:

```
Flutter app  ──▶  Supabase Edge Function  ──▶  OpenRouter  ──▶  a model
   (user JWT)      (auth + rate limit)          (key = Edge Function secret)
```

- The app calls our own Edge Function, authenticated with the user's Supabase
  session (JWT).
- The provider is **not** hard-wired. We call [OpenRouter](https://openrouter.ai)
  (a gateway) and pick the model with a `COACH_MODEL` secret, so model and
  provider are a server-side choice — the app ships unchanged.
- The Edge Function holds `OPENROUTER_API_KEY` as a **server-side secret**
  (`supabase secrets set`), never in the repo, never in the bundle.
- The function verifies the user, applies rate limits and spend caps, builds the
  prompt, calls the provider, and returns validated JSON.

See [ADR-0007](../decisions/0007-secrets-via-backend-proxy.md).

## Why a proxy, not direct calls

- **Public source.** Anyone can read the repo. A shipped key would be extracted
  in minutes and abused.
- **Abuse control.** The proxy is where we enforce per-user rate limits and a
  spend ceiling, so a compromised client can't run up unbounded model cost.
  Limits are **per surface** (a plan generation is not an intake turn) and the
  spend cap is denominated in the credits the provider reports it charged, so it
  keeps binding when `COACH_MODEL` changes. Counters live in Postgres because
  Edge Function instances are ephemeral, and the limiter **fails closed**: if it
  can't be consulted, the call is refused rather than spent. The numbers, the SQL
  and the error contract are in
  [`supabase/functions/coach/README.md`](../../supabase/functions/coach/README.md).
- **Model portability.** Swapping model or provider is a server change; the app
  ships unchanged.
- **Data minimisation.** The server decides exactly what context leaves the
  system — structured training data, not raw GPS or unnecessary identifiers
  (see [compliance.md](../compliance.md)).

## Prompt surfaces

The coach persona and tone are defined **once** and shared across all prompts:

| Prompt | Purpose |
|---|---|
| `intake` | Slot-filling onboarding conversation. |
| `skeleton` | Block structure from the runner profile. |
| `week` | Seven sessions from a skeleton slot + recent history. |
| `adapt` | Natural-language request → structured diff. |
| `rationale` | Why this session, given the block and recent history. |
| `checkin` | Post-run and weekly reflection. |
| `chat` | The open conversation — anything the runner asks. |
| `summarise` | Rewrites the coach's rolling memory when the conversation sheet closes, over the turns said since the last rewrite. |

## Structured output & validation

Every prompt returns **JSON against a fixed schema**. Two layers of checking:

1. **At the boundary** — the Edge Function validates shape/schema before
   returning.
2. **In Dart** — the app re-validates against the domain rules (the plan
   [validator](plan-generation.md), profile sanity checks) before anything is
   stored or shown.

The model never writes a value straight into a plan or profile. It proposes; the
validator disposes.

## What the client stores

The client stores generated plans, sessions, rationale text, and profiles —
**results**, not credentials. Nothing the client holds can call the provider
directly.
