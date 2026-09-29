# `revenuecat` — the only writer of `core.entitlements`

```
App Store / Play  ─▶  RevenueCat  ─▶  this function  ─▶  core.entitlements
                                                          (service_role)
```

Chosen in [ADR-0028](../../../apps/mgk_run/docs/decisions/0028-revenuecat-is-the-purchase-path.md);
priced in [ADR-0029](../../../apps/mgk_run/docs/decisions/0029-what-a-tier-costs-and-buys.md);
made load-bearing by [ADR-0030](../../../apps/mgk_run/docs/decisions/0030-the-coach-is-the-paid-half.md),
which gates the coach behind a row this function is the only thing that writes.

**Nothing works until this is deployed and configured.** The coach is refused
for everybody without an entitlement, and no entitlement can exist without this.

## Deploying

```bash
supabase functions deploy revenuecat --no-verify-jwt
```

`--no-verify-jwt` is required and is not a hole. RevenueCat is not a signed-in
user and has no Supabase token; it authenticates with the shared secret below,
which is checked before anything else happens. Leaving JWT verification on
would reject every event with a 401 that looks like a RevenueCat problem.

## Secrets

```bash
supabase secrets set REVENUECAT_WEBHOOK_SECRET='<a long random string>'
supabase secrets set REVENUECAT_PRODUCTS='{
  "run.coach.monthly":       {"app":"run",  "product":"paid"},
  "run.coach.premium.monthly": {"app":"run",  "product":"premium"},
  "lift.coach.monthly":      {"app":"lift", "product":"paid"}
}'
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected by the platform.

**The product ids above are placeholders** — replace them with the real App
Store Connect ids when the subscription products exist. They are configuration
rather than code so that adding a SKU, or changing a price, does not need a
deploy. An unmapped product id writes nothing and says so in the log, which is
the safe direction: the alternative is a default that grants something.

`REVENUECAT_ACCEPT_SANDBOX=true` honours sandbox purchases. **The code
defaults to `false`, and production sets it to `true` on purpose**
([ADR-0037](../../../apps/mgk_run/docs/decisions/0037-the-sandbox-stays-open-in-production.md)).
App Review buys in the sandbox, against the production build: with the flag
off, the reviewer's purchase is ignored as `sandbox`, no row is written, and
the coach stays locked behind a purchase that went through. The cost is that
the people who can make a sandbox purchase — TestFlight testers, sandbox Apple
IDs, Play licence testers, App Review — get a coach without paying, for as long
as a sandbox subscription lasts. That is a list we write, as long as there is
never a public TestFlight link. A project that has not decided gets the safe
default. This paragraph said "development only" until 2026-09-29.

## Wiring the webhook

RevenueCat dashboard ▸ Integrations ▸ Webhooks:

- **URL** `https://cwpwzxjjhxbkwhrgnasn.supabase.co/functions/v1/revenuecat`
- **Authorization header** the value of `REVENUECAT_WEBHOOK_SECRET`, verbatim.
  RevenueCat sends it as-is, so it is compared as-is — no `Bearer` prefix.

Set the app user id to the **Supabase user id** in both apps
(`Purchases.logIn(session.user.id)`). It is what keys the row, and an
`RCAnonymousID:` is refused rather than written to nobody.

## What it does, and what it refuses

Every event either writes one row or is ignored with a reason, and **a
well-formed request always answers 200** — a webhook that 4xxs an event it
chose not to handle gets retried until RevenueCat gives up and alerts, turning
"we do not handle TRANSFER yet" into an outage page. 401 is the exception,
because a wrong secret should be loud.

| Event | `status` |
|---|---|
| `INITIAL_PURCHASE`, `RENEWAL`, `PRODUCT_CHANGE`, `UNCANCELLATION`, `NON_RENEWING_PURCHASE`, `SUBSCRIPTION_EXTENDED` | `active` |
| `CANCELLATION` | `active` — auto-renew off, access until it lapses |
| `EXPIRATION`, `SUBSCRIPTION_PAUSED` | `expired` |
| `BILLING_ISSUE` | `grace` |
| `REFUND` | `refunded` |
| `TRANSFER` | `revoked` |
| anything else | ignored, logged, not guessed |

`CANCELLATION` is the one worth reading twice: it does **not** end access.
Treating it as the end takes away time somebody paid for. `EXPIRATION` is what
ends access.

`grace` grants nothing — the coach's check treats everything but `active` as no
entitlement, so a billing retry deliberately locks while it resolves.

## Ordering and replays

Store webhooks arrive out of order routinely, and retries are normal. Each row
carries `event_ms`, the store's own timestamp for the event that wrote it, and
an incoming event must be strictly newer to win.

- A replay is a no-op, because equal does not supersede.
- A late `EXPIRATION` cannot revert a live `RENEWAL` that arrived first.
- A row with `event_ms IS NULL` — inserted by hand, as the TestFlight sheet
  does — loses to the first real event rather than blocking it forever.
- An `EXPIRATION` that never arrives, or that a later `CANCELLATION` outranks
  on `event_ms`, leaves the row `active` after the period has ended. This
  function does not correct for that — it writes only what the store said —
  but the coach's gate does: `tierFor` stops granting an `active` row a day
  after its `expires_at`.

## Testing

```bash
deno test          # the mapping, with no database and no store
```

The decision logic is pure (`entitlement_event.ts`) for the same reason
`limits.ts` is: this is the money path, and every mapping in it can be got
wrong in a way that either gives somebody a coach they did not buy or takes one
they did. None of that should need a deployed function to assert.

## Still to do

- Real product ids, once they exist in App Store Connect.
- The SDK in both apps, and the purchase screen behind `onUpgrade`.
- An end-to-end sandbox purchase on a device.
