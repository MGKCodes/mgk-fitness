# `coach` Edge Function

The single server-side path from **either app** to the LLM provider. No app
holds the provider key — see
[ADR-0007](../../../apps/mgk_run/docs/decisions/0007-secrets-via-backend-proxy.md)
and
[llm-and-secrets.md](../../../apps/mgk_run/docs/architecture/llm-and-secrets.md).

```
app (user JWT)  ─▶  coach (auth + entitlement + limits + key + prompt)  ─▶  OpenRouter  ─▶  a model
```

The provider is a **server-side choice**. OpenRouter is a gateway: you pick the
model with the `COACH_MODEL` secret and can swap it for any structured-output
model without touching either app.

## One function, both apps

`comment on schema coach` says the coach is app-agnostic, and this is where that
is either true or a claim. Lift and Run share this function, its limiter, its
spend cap and its counters.

**Which app a request belongs to is read from the surface, never from the
body.** `SURFACES[name].app` decides which `core.entitlements` row is consulted,
so a caller cannot ask for its Run subscription to pay for a Lift turn. A
surface added without an `app` does not compile.

There is exactly one function per slug per Supabase project, so this directory
is the only place a `coach` function may be defined. Two repos deploying the
same slug against the same project is how the account-deletion bug happened —
see [database.md](../../../docs/database.md#the-bug-this-replaced).

## What it does

1. Verifies the caller is a signed-in Supabase user (rejects otherwise).
2. Reads `core.entitlements` for the surface's app and resolves a **tier**, or
   refuses with `402` where that app sells coaching.
3. **Enforces a per-user rate limit and spend cap before spending any tokens.**
4. Loads whatever the prompt needs that the client is not trusted to supply —
   for `lift_chat`, the training log, the transcript and the memory, all read as
   the caller so RLS scopes them.
5. Builds the prompt for the requested `surface` and calls OpenRouter with a
   JSON-schema-constrained response (`response_format`).
6. Validates the response **shape** and returns it. The app re-validates the
   **values** before using them.
7. Records what the call cost, so step 3 has something to work from.
8. Stores the exchange, and rewrites the memory if it has fallen behind.

Surfaces wired up: `intake`, `skeleton`, `week`, `adapt`, `chat`, `summarise`,
`log_run`, `edit_run`, `set_goal` (Run) and `lift_chat`, `lift_summarise`
(Lift). A new one adds a message builder, a schema, an `app` and a rate rule,
and slots into the same `SURFACES` table.

## Layout

| File              | Role                                                                                    |
| ----------------- | --------------------------------------------------------------------------------------- |
| `index.ts`        | The HTTP handler. Auth, entitlement, limits, the provider call, and nothing else.       |
| `surfaces.ts`     | **Pure** prompts, schemas, personas, and the shape checks. Every prompt is unit-tested. |
| `limits.ts`       | **Pure** limit decisions: thresholds, windows, usage accounting. Also unit-tested.      |
| `entitlements.ts` | The tier policy (pure) and the `core.entitlements` read, behind an injectable `fetch`.  |
| `lift_log.ts`     | Lift's training log: the read (as the caller) and its rendering (pure).                 |
| `coach_memory.ts` | The rolling memory and the transcript: read, appended and replaced as the caller.       |
| `usage_store.ts`  | The durable counters in Postgres, behind an injectable `fetch`.                         |
| `*_test.ts`       | Deno tests for every pure module and every failure mapping.                             |

The prompts live in `surfaces.ts` rather than in `index.ts` because `index.ts`
calls `Deno.serve` at load: anything defined there could only be tested through
a socket.

## Who may spend

`core.entitlements` holds one row per `(user, app)`. `tierFor` turns it into a
tier or a refusal, and every way it can be wrong is a way that costs nothing:

| Row                      | Lift                 | Run                  |
| ------------------------ | -------------------- | -------------------- |
| `premium` / `active`     | `sharp`              | `sharp`              |
| `paid` / `active`        | `standard`           | `standard`           |
| `free` / `active`        | **402 not_entitled** | **402 not_entitled** |
| any other `status`       | **402 not_entitled** | **402 not_entitled** |
| no row, or a failed read | **402 not_entitled** | **402 not_entitled** |

Three properties are deliberate:

- **Only `active` grants anything.** `core.entitlements.status` has five values
  and the column comment says to treat every other one as no entitlement.
  `grace` is the tempting mistake — it reads like "still fine" and means "the
  store has not been paid".
- **An unknown product is the cheapest tier, never the dearest.** A typo or a
  future SKU must not be able to bill at the Sharp model's rate.
- **Both apps refuse an unentitled caller.** The coach is the paid half of each
  ([ADR-0030](../../../apps/mgk_run/docs/decisions/0030-the-coach-is-the-paid-half.md)),
  so a failed entitlement read fails closed on both. Run gave everyone a coach
  on the cheapest model until then, which was a placeholder that outlived its
  excuse rather than a product choice.

## Surfaces

Every request is `POST` with `{"surface": "<name>", ...}` and a user JWT. The
conversational surfaces are the ones the apps talk to most:

### `lift_chat`

Lift's conversation. Request:

```jsonc
{
  "surface": "lift_chat",
  "message": "<what the lifter just said>"
}
```

```json
{ "reply": "<what the coach says>" }
```

**The request is one line, and everything else is read here.** The log, the
conversation and the memory all come from Postgres under the CALLER's JWT, so
RLS decides what the coach can see. Anything sent as `brief`, `memory` or
`history` is discarded. Run's `chat` takes its brief from the app because the
numbers a runner cares about are computed client-side; Lift's inputs are all
records, and a record the client narrates is a record it can invent.

Working sets only — completed, and not warm-ups. A session with nothing that
counts is dropped rather than listed empty. A coach that reads a warm-up as a
top set will prescribe from it.

There is no `intent` yet: Lift has no validated path for the coach to act
through, so it can only talk. When plans land, that is the surface to add rather
than a field to loosen here.

### `lift_summarise`

Not called by the app. The function calls it itself, after a reply, when the
memory has fallen `REGENERATE_AFTER` turns behind the transcript — see
[What the coach remembers](#what-the-coach-remembers).

### `chat`

Run's open-ended conversation. Request:

```jsonc
{
  "surface": "chat",
  "brief": "<prose paragraphs about this runner>",  // optional on first contact
  "history": [{ "role": "user" | "coach", "text": "..." }],
  "message": "<what the runner just said>"
}
```

```jsonc
{
  "reply": "<what the coach says>",
  "intent": null
  // or: { "kind": "adapt_week", "request": "move Thursday's threshold to Friday" }
}
```

`brief` is **prose on purpose** and goes into the system prompt verbatim. The
app renders its typed state into paragraphs (`CoachBrief`) because a model
handed a struct recites it back at the runner. This function never parses or
reformats it.

`intent` is how the coach asks the app to _do_ something rather than only talk.
`adapt_week` is the only kind, and the app routes its `request` into the
existing `adapt` surface, which is still validated in Dart. **The chat surface
never emits a plan, a session, or any structured training data** — that is
[ADR-0003](../../../apps/mgk_run/docs/decisions/0003-llm-generates-validator-enforces.md),
and the prompt is written against exactly that failure. Anything that is not a
well-formed, actionable `adapt_week` comes back as `null`, so the app gets
either a real request or nothing.

A `message` that is missing or blank is a `400 bad_request` before the limiter:
it spends nothing and cannot produce an answer.

### `summarise`

Condenses a conversation into the rolling memory the app stores and feeds into
the next brief. Request:

```jsonc
{
  "surface": "summarise",
  "previous": "<the existing summary>" | null,
  "transcript": [{ "role": "user" | "coach", "text": "..." }]
}
```

```json
{ "summary": "<a few sentences of prose>" }
```

The summary is **regenerated, not appended to**: appending a line per turn is a
re-encode of a re-encode, it grows without bound, and it drifts. It carries only
what a schema cannot (constraints mentioned in passing, what they are anxious
about, what they have tried and dropped, how they talk about training) and
deliberately **not** anything the database already holds (goal, volume,
available days, session results) — two copies of a number eventually disagree
and nothing says which is wrong. An empty string is a legitimate answer.
`max_tokens` is 512, which is the hard ceiling on a memory that is re-read on
every future turn.

An empty `transcript` is a `400 bad_request`: the only honest answer is the
previous summary, which the app already has.

### Input ceilings

Prompt length is the one input the client picks, and the proxy is where cost is
controlled, so client text is bounded server-side before it becomes tokens. The
limits are far above real use and the Dart side does not need to pre-trim, but
it should not assume a 400-turn history arrives intact:

| Input                                | Kept              |
| ------------------------------------ | ----------------- |
| `chat.history`                       | the last 20 turns |
| `summarise.transcript`               | the last 60 turns |
| any single turn                      | 2000 characters   |
| `chat.message` / `lift_chat.message` | 4000 characters   |
| `chat.brief`                         | 8000 characters   |
| `summarise.previous`                 | 4000 characters   |
| a stored memory, in or out           | 4000 characters   |

The memory's ceiling is the tightest of the prose ones on purpose: it is re-read
on every future turn, so it is also the ceiling on what a six-month-old
conversation costs.

`lift_chat` takes no `history` — the server replays its own. The same ceiling
bounds `lift_chat`'s log, which the function renders itself — so a lifter with
years of history cannot grow the prompt without limit either.

Anything clipped ends in `…` so the model can see it was cut. Blank turns are
dropped; a `role` that is not `coach` (or `assistant`) is sent as `user`, so a
client cannot inject a system message.

## What the coach remembers

Two tiers with opposite lifecycles, and the split is the whole design:

| Tier           | Table             | Sent        | Lifecycle                    |
| -------------- | ----------------- | ----------- | ---------------------------- |
| the memory     | `coach.summaries` | every turn  | regenerated and replaced     |
| the transcript | `coach.turns`     | the last 20 | append-only, never rewritten |

Sending the whole history instead works for a fortnight and then does not.
Appending to the memory instead makes each version a re-encode of a re-encode,
drifting with nothing to say which copy was right.

**Keyed per (person, app).** `coach.summaries` was keyed on `user_id` alone,
which was right while the coach served one app and is a data-loss bug now: on an
account that uses both, each app's regeneration would silently overwrite the
other's memory, on special-category data, with no earlier version to restore.
`20260807130000_coach_memory_per_app.sql` widens the key and adds the same
column to `coach.conversations`; `coach.turns` reaches its app through its
conversation FK rather than carrying a second copy of the fact.

Lift keeps **one conversation per person**, addressed as `lift:<user_id>` so it
needs no lookup. Nothing in the design asks for a boundary between visits: the
memory is what survives and the last 20 turns are what get replayed, and neither
is improved by knowing which evening a turn came from. Runio keeps many, from
its own client — that difference is in the clients, not the schema.

The memory is rewritten when the transcript has run 20 turns ahead of it, not on
a timer and not on every turn. Every-turn regeneration is a re-encode loop and
the most expensive way to run a coach. The rewrite happens inline, on the turn
that triggers it, so about one turn in twenty pays for a second short call —
moving it into the background needs the platform's `waitUntil` and is worth
doing only if that latency is ever felt.

Writes are per app and per caller. `MEMORY_TURNS` must not be smaller than
`REGENERATE_AFTER`, or a rewrite would be made from less of the conversation
than it had fallen behind by, and the turns in the gap would be lost from the
memory permanently — there is a test for exactly that.

### What it is allowed to say

`lift_summarise`'s prompt is constrained harder than Run's, for a reason that is
about the product rather than the model: **the lifter can read this and cannot
edit it.** So it records what they said and never what the model concluded —
"says their shoulder hurts on overhead press" is memory, "seems anxious about
their weight" is a guess about a person from a chat window, and it is the kind
that is quietly wrong for months. Nothing about their body, their weight, or how
they look. Nothing the database already holds, because two copies of a number
eventually disagree and nothing says which is wrong.

## Rate limits

Per authenticated user, evaluated against actual call timestamps — the windows
**slide**, so there is no calendar boundary at which a user gets double their
allowance.

| Surface          | Limit              | Why                                                                                                                                                                                             |
| ---------------- | ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `intake`         | 12 / 5 min         | One cheap chat turn. Onboarding is four to six turns and a runner may restart it, so this has to be generous and feel instant.                                                                  |
| `skeleton`       | 6 / hour           | The most expensive single call, but generated once per training block (every 8–20 weeks) with up to two validator attempts. Enough to re-plan a few times while onboarding.                     |
| `week`           | 12 / hour          | One call per week of the block, generated a week ahead, up to two attempts. Covers backfilling several weeks at once.                                                                           |
| `adapt`          | 10 / hour          | A runner typing a request. A handful a week is real use.                                                                                                                                        |
| `chat`           | 15 / 5 min         | The cheapest call and the most frequent. A message every twenty seconds sustained is faster than anyone converses, so it never binds in real use.                                               |
| `summarise`      | 6 / hour           | Not a runner action: the app condenses a conversation when one ends. Six an hour is six conversations plus a retry.                                                                             |
| `lift_chat`      | 15 / 5 min         | A lifter talking. Sized like `chat`, and given its own window rather than a shared one — a lifter who also runs would otherwise spend one allowance on two coaches.                             |
| `lift_summarise` | 6 / hour           | Not a lifter action: the coach rewrites its own memory once every ~20 turns. Deliberately too low to rewrite after every turn, which is the re-encode loop the two-tier memory exists to avoid. |
| **all surfaces** | 120 / rolling 24 h | Backstop for a client bug that loops slowly enough to stay under every window above.                                                                                                            |

`summarise` is deliberately **too low to summarise after every chat turn**. That
usage is a re-encode of a re-encode, which is the failure the surface exists to
avoid, and it would be the most expensive way to use the coach; the memory is
meant to be rewritten when a conversation ends. If the app ever needs it per
turn, this number is not the thing to change.

What actually bounds a long conversation is the spend cap, not the chat rate:
the prompt carries the brief and the history, so it grows with the exchange even
though each turn is cheap.

The limits are **per surface on purpose**. A single flat number either strangles
plan generation (which legitimately bursts: one skeleton plus several weeks,
each retried once) or leaves chat wide open. See
[plan-generation.md](../../../apps/mgk_run/docs/architecture/plan-generation.md)
for the call profile these are sized against.

## Spend cap

A ceiling on **credits per user per rolling 24 hours** (default `0.50`).

Spend is real, not guessed. OpenRouter returns a `usage` block on every
chat-completion containing native token counts and `cost` — the credits actually
charged to the account. The cap is denominated in that, so it stays correct when
`COACH_MODEL` changes to a model that costs 30× more, without this function ever
knowing a price list.

If a provider ever omits `cost`, the call is **not** treated as free (that would
be a hole straight through the cap). It is estimated from `total_tokens` at
`COACH_FALLBACK_CREDITS_PER_MTOK`, and if tokens are missing too, charged as if
the surface spent its whole `max_tokens` budget. Estimated rows are flagged
`cost_estimated` so a spend figure is never mistaken for a billed amount.

Set a **hard credit limit on the OpenRouter key** as well. The per-user cap
bounds one user; the key's own limit bounds everything, including a bug in this
function.

### Privacy

A usage row holds a user id, a surface name, token counts, a cost, and an
outcome. It never holds a prompt, a response, or any training or health value —
`RecordedUsage` has nowhere to put one. Usage accounting is exactly where a
request body gets logged by accident, so the types make it impossible. Upstream
provider error text is truncated in logs for the same reason.

## Error responses

Everything is `{ "error": "<code>", ... }` with a matching status.

| Status | `error`                                              | Meaning                                                                                                                                                                                                         |
| ------ | ---------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 429    | `rate_limited`                                       | A request-rate ceiling bound. Also `scope` (any surface name, or `daily_requests`) and `retry_after_seconds`, plus a `Retry-After` header.                                                                      |
| 429    | `spend_cap_reached`                                  | The rolling 24 h credit cap bound. `scope` is `daily_spend`; same `retry_after_seconds` / `Retry-After`.                                                                                                        |
| 503    | `coach_not_configured`                               | A secret is missing. With `"reason": "limiter_unavailable"` it means the SQL below has not been applied (or the service key is wrong) — **the coach refuses rather than spending money it cannot account for**. |
| 503    | `coach_unavailable`                                  | The counter store had a transient failure, so the limit could not be checked. Same fail-closed reasoning.                                                                                                       |
| 402    | `not_entitled`                                       | The caller has not bought coaching on the app this surface belongs to. Lift only — Run's bottom tier is free, so it never returns this.                                                                         |
| 401    | `unauthorized`                                       | No or bad JWT.                                                                                                                                                                                                  |
| 400    | `bad_request` / `unsupported_surface`                | Malformed body, a request a surface cannot answer (a `chat` with no `message`, a `summarise` with no `transcript`), or a `surface` this function does not serve.                                                |
| 422    | `refused`                                            | The model's content filter tripped.                                                                                                                                                                             |
| 502    | `coach_upstream` / `coach_empty` / `coach_malformed` | The provider failed, returned nothing, or returned something that is not the schema.                                                                                                                            |

The spend cap is a **429, not a 402**: it is a rolling window that clears on its
own, so "come back later" is the honest semantics. A 402 means something else
entirely — you have not bought this — and it does not clear by waiting. Keeping
them apart is what lets the app say the right one.

**Fail closed is deliberate.** If the limiter cannot be consulted, the request
is refused. Spending money we cannot account for is the exact failure ADR-0007
exists to prevent, and the client degrades gracefully: `PlanService` treats a
refused `skeleton`/`week` as a failed attempt and falls back to the
deterministic builder, so the runner still gets a structurally sound
(provisional) plan. Only `intake` surfaces a message.

## Counter storage

Edge Function instances are ephemeral, so the counters live in Postgres, in
`coach.usage`. The table is **service-role only** — a user must not be able to
delete their own usage rows and reset their own cap — so it has RLS on with no
policy at all, and is reached through two `SECURITY DEFINER` functions,
`coach.record_usage` and `coach.usage_window`.

> **Apply the migrations before (or with) `supabase functions deploy coach`.**
> Until they exist the function returns
> `503 {"error":"coach_not_configured","reason":"limiter_unavailable"}` for
> every request. That is intentional, not a bug.

The DDL is in
**[`20260806130000_restructure_schemas.sql`](../../migrations/20260806130000_restructure_schemas.sql)**,
which promoted the whole subsystem out of `runio` into the app-agnostic `coach`
schema. It applies with the rest of the set via `supabase db push`.

Two things follow from `coach` not being PostgREST's default schema, and both
have already caused a fail-closed 503 once:

- RPCs need a **`Content-Profile: coach`** header (`usage_store.ts` sets it).
  Without it PostgREST resolves the name against the first exposed schema, 404s,
  and `classifyFailure` reads that as "the limiter is missing".
- `core` and `lift` need **`Accept-Profile`** on their reads for the same reason
  — see `entitlements.ts` and `lift_log.ts`.

Adding a surface needs **no SQL**. `surface` is a free-text column with no check
constraint, precisely so a new prompt is a code change and not a migration.

### Known limits of this design

- **Bounded overshoot.** The check happens before the call and the cost is
  recorded after, so requests already in flight are not yet counted. A user can
  exceed a ceiling by at most the number of calls they have concurrently open.
  Closing that needs a reservation write before the model call; it is not worth
  the extra round trip at this scale.
- A call that dies mid-flight (instance killed after the provider responded) is
  not recorded, so it goes uncounted.
- Requests rejected before the gate (`bad_request`, `unsupported_surface`,
  `unauthorized`) do not consume rate budget. They spend no tokens; blocking
  that traffic is the platform's job, not the spend cap's.

## Deploy

Two required **server-side secrets**, never committed:

```sh
# 1. The OpenRouter key
supabase secrets set OPENROUTER_API_KEY=sk-or-...

# 2. The model. Pick a current, cheap, structured-output-capable id from
#    https://openrouter.ai/models?supported_parameters=structured_outputs
#    (a Google Gemini Flash-Lite is a good cheap default). Use the exact id
#    shown there.
supabase secrets set COACH_MODEL='google/gemini-...-flash-lite'

# 3. Apply the migrations (installs the limiter counters), then deploy
supabase db push
supabase functions deploy coach
```

`lift_chat` additionally needs
[`20260807120000_lift_sync_columns.sql`](../../migrations/20260807120000_lift_sync_columns.sql),
which adds `lift.sets.set_type`. Without it the log read is a 400 and the coach
sees an empty log — which looks exactly like a lifter who has never trained, so
it is worth knowing rather than debugging.

Optional, and recommended once the coach is talking to real people:

```sh
# The model for the human-facing surfaces only: `chat`, `summarise` and
# `lift_chat`. Those three reach a person with no Dart validator in between, so
# a cheap model's mistake arrives as prose rather than as a rejected plan. They
# are also the SMALLEST token budgets (1024, 512, 1024), so upgrading them is
# the cheap half of the bill — the 4096-token `skeleton` stays on COACH_MODEL
# and stays validated.
supabase secrets set COACH_CHAT_MODEL='google/gemini-3.6-flash'
```

Unset, every surface runs on `COACH_MODEL` exactly as before — see `modelFor` in
`surfaces.ts`. Note the split makes `coach.summaries.model` genuinely ambiguous:
the app passes `null` today, so a stored summary does not record which of the
two models wrote it.

**The model is configuration, not a code path.** That is the whole reason this
goes through a gateway: making `chat` cheaper, or plan generation bigger, is a
`secrets set` and a function restart rather than a release. A `coach.models`
table keyed by surface was considered and dropped — `modelFor` already routes by
surface and by tier, so the table would buy a per-request read and a second
place for the configuration to be wrong.

Optional, for tuning the ceilings without a code change. Each falls back to its
default if unset, unparseable, zero or negative — a typo can never become "no
limit":

```sh
supabase secrets set COACH_DAILY_SPEND_LIMIT=0.20          # credits / user / 24h
supabase secrets set COACH_WEEKLY_SPEND_LIMIT=0.50         # credits / user / 7d
supabase secrets set COACH_MONTHLY_SPEND_LIMIT=0.85        # credits / user / 30d
supabase secrets set COACH_DAILY_REQUEST_LIMIT=120         # requests / user / 24h
supabase secrets set COACH_FALLBACK_CREDITS_PER_MTOK=1.0   # only if cost is unreported
```

**Three spend windows, not one.** They answer different questions: a daily
ceiling bounds a runaway loop, a monthly one bounds the bill. A £1/month
subscription is a _monthly_ figure, so the monthly window is the one that has to
sit under it — a daily cap alone silently authorises thirty times itself. All
three are evaluated together and the ceiling that clears **last** is the one
reported, so `retry_after_seconds` is never optimistic.

The shipped defaults are **provisional placeholders, not measured figures**.
Once the coach has run against live traffic, the real numbers come from the
usage table:

```sql
select surface,
       count(*)                                  as calls,
       sum(cost_credits)                         as spent,
       sum(cost_credits) filter (where cost_estimated) as estimated
  from coach.usage
 where created_at > now() - interval '7 days'
 group by surface order by spent desc;
```

⚠️ The write function prunes rows older than **31 days**. That must always
outlive `lookbackSeconds(config)` — add a longer spend window and the prune
interval moves first, or the new ceiling silently stops binding.

`SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are injected
by the platform — you do not set those. The service-role key is what reads and
writes the counters; without it the function fails closed with
`coach_not_configured`.

The per-surface rate limits live in `limits.ts` rather than in secrets: they
encode product knowledge about the call profile, so they belong in a reviewed,
tested file.

## Tests

The prompts, the limiter's decision logic and the entitlement policy are pure
and covered by Deno tests. From this directory:

```sh
deno test          # 170 tests: thresholds, window boundaries, retry-after,
                   # usage accounting, the entitlement policy, when the memory
                   # is rewritten, the four stores' failure mappings, and what
                   # each surface sends and will accept back
deno check index.ts surfaces.ts limits.ts usage_store.ts entitlements.ts \
           lift_log.ts coach_memory.ts
deno lint
deno fmt .         # --check in CI
```

No permissions flags and no network are needed — `surfaces.ts` and `limits.ts`
do no I/O, and the four stores each take `fetch` as a constructor argument so
the tests stub it. There is deliberately **no `deno.json`** in this directory:
`supabase functions
deploy` reads one if it is present, and Deno's defaults are
already what we want.

## Try it

```sh
curl -i "$SUPABASE_URL/functions/v1/coach" \
  -H "Authorization: Bearer <a user access token>" \
  -H "content-type: application/json" \
  -d '{"surface":"intake","slots":{},"missing":["goal"],"history":[]}'
```

A first call with empty history returns the coach's opening question.

```sh
curl -i "$SUPABASE_URL/functions/v1/coach" \
  -H "Authorization: Bearer <a user access token>" \
  -H "content-type: application/json" \
  -d '{"surface":"chat","brief":"They are two weeks out from a half marathon.","history":[],"message":"can we move Thursday to Friday, I am away"}'
```

That one should come back with a short reply **and** an
`"intent":{"kind":"adapt_week", ...}`. A reply that instead lists the week back
at the runner, or quotes a distance the brief never mentioned, is the prompt
regressing — both are what the instructions in `surfaces.ts` are written
against.

```sh
curl -i "$SUPABASE_URL/functions/v1/coach" \
  -H "Authorization: Bearer <a user access token>" \
  -H "content-type: application/json" \
  -d '{"surface":"lift_chat","history":[],"message":"why has my bench stalled?"}'
```

No brief is sent and none should be: the answer should quote sessions from that
account's own log. A reply that recites the log back, or names a weight that is
not in it, is the prompt regressing.

- `not_entitled` — the account has no `active` Lift entitlement. Expected on a
  free account; it is what the paywall is.
- `coach_not_configured` — one of the two required secrets is unset.
- `coach_not_configured` with `"reason":"limiter_unavailable"` — the migrations
  have not been applied.
- Repeat the call 16 times inside five minutes to see a `429 rate_limited` with
  a `Retry-After`.
