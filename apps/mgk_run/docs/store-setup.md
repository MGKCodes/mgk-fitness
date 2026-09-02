# Store setup — StoreKit, RevenueCat, App Store Connect

The half of payments that is not code. [app-store-1.0.0.md](app-store-1.0.0.md)'s
Gate 3 lists these as steps 1 to 5 and stops; this is what to actually do, in
what order, and what breaks when a string does not match.

Written 2026-09-02 against `4d0bd27`, with the client side built: the SDK, the
paywall, and the webhook that writes the row are all in the repo and tested. **No
part of this has met a real store.**

---

## The chain

Every setting below exists to keep one link intact. Worth reading once, because
most of the ways this fails are a mismatch rather than a mistake.

```
  App Store Connect          a product id, priced, in a subscription group
          |
  RevenueCat                 that product, in a package, in the CURRENT offering
          |
  the app                    Offerings.current.availablePackages  ->  the paywall
          |                  Purchases.logIn(<supabase user uuid>)
          v
  a purchase
          |
  RevenueCat                 webhook, server to server
          |
  supabase/functions/revenuecat        Authorization header == the shared secret
          |                            product_id -> {app, product}
          v
  core.entitlements          one row: product paid|premium, status active
          |
  supabase/functions/coach   tierFor() -> a model tier, or a refusal
          |
  the app                    SupabaseEntitlements reads the same row, to DRAW
```

**Nothing in the app decides any of this.** The client presents and pays; the
row is written by the webhook under `service_role` and enforced by the coach
function ([ADR-0030](decisions/0030-the-coach-is-the-paid-half.md)).

## The five values that must match exactly

Nearly every failure in this document is one of these five being *nearly* right.

| Value | Set in | Must equal | When it is wrong |
|---|---|---|---|
| **Product id** | App Store Connect | every key of `REVENUECAT_PRODUCTS` | webhook ignores the event, `unmapped_product` |
| **App user id** | `Purchases.logIn()` | the Supabase user **UUID** | webhook ignores it, `unknown_app_user_id` |
| **Authorization** | RevenueCat webhook header | `REVENUECAT_WEBHOOK_SECRET`, **verbatim** | every event 401s |
| **Bundle id** | App Store Connect | `com.mgkcodes.fitness.run` | products never appear in the app |
| **Public SDK key** | Codemagic `REVENUECAT_PUBLIC_KEY` | the **`appl_`** key | the build fails on purpose |

The app user id is the one worth staring at. `HomeShell` calls
`Purchases.logIn(auth.currentUser.id)` whenever there is a session, and the
webhook validates it against a UUID regex before writing anything. Anonymous
purchases are refused rather than written to nobody, which is the safe
direction and also a silent one: **the payment succeeds and the coach never
unlocks.**

---

## 1. Apple — agreements, tax, banking

App Store Connect ▸ Business.

- [ ] **Paid Applications agreement active.** Nothing about subscriptions works
      until it is, and it is the longest lead time on the whole release.
- [ ] Tax forms complete for your territories.
- [ ] Bank details added and verified.

Start this first. Everything below can be done while it clears, but none of it
can be *tested* until it is Active.

## 2. App Store Connect — the subscription group and two products

App Store Connect ▸ your app ▸ Subscriptions.

- [ ] **One subscription group.** One, not two: the tiers are alternatives, and
      a group is what lets somebody move between them without a second purchase
      and without being charged twice.
- [ ] **Localised group display name.** Shown in the runner's Apple ID
      subscription settings, so it should read as a thing they recognise.

Then, per product:

| | Coach | Premium Coach |
|---|---|---|
| Reference name | Run Coach Monthly | Run Coach Premium Monthly |
| Product ID | `run.coach.monthly` | `run.coach.premium.monthly` |
| Duration | 1 month | 1 month |
| Price | £0.99 | £2.99 |
| Display name | Coach | Premium Coach |

Descriptions are drafted in
[app-store-listing.md](app-store-listing.md#subscription-products).

**The product IDs above are the placeholders already in the webhook README.**
Keep them and there is nothing to change; use different ones and they must be
mirrored into `REVENUECAT_PRODUCTS` in step 6.

- [ ] **A review screenshot per product.** Required, and a common cause of
      "Missing Metadata" holding up the whole submission. The `paywall` plate on
      [the board](https://claude.ai/code/artifact/9ddfd186-11ad-4260-bde9-ef8b7a5d9190)
      is what this screen looks like; take the real one off a device.
- [ ] **Review notes per product.** Say the coach is the paid half and recording
      is free, so a reviewer is not hunting for what changed.
- [ ] **No free trial, no introductory offer.** Deliberate: a trial on a £0.99
      product costs more in support than it earns. Revisit later, not now.
- [ ] Let Apple's matrix set every other storefront's price. The app never shows
      a figure of its own, so this is safe by construction.

## 3. App Store Connect — the two credentials RevenueCat needs

Both are easy to miss and both fail quietly.

- [ ] **App-Specific Shared Secret** — App Store Connect ▸ your app ▸ App
      Information ▸ App-Specific Shared Secret. RevenueCat uses it to validate
      receipts. Without it, purchases appear to work on device and never
      validate.
- [ ] **In-App Purchase Key** — Users and Access ▸ Integrations ▸ In-App
      Purchase ▸ generate a key. **The `.p8` downloads exactly once.** Same rule
      as the App Store Connect API key `codemagic.yaml` already uses; put it
      somewhere you will still have it in a year.

## 4. RevenueCat — project, products, entitlements, offering

- [ ] Project, then an **App** with bundle id `com.mgkcodes.fitness.run`.
- [ ] Paste the **shared secret** and upload the **in-app purchase key** from
      step 3.
- [ ] **Import the two products.** They must exist in App Store Connect first.
- [ ] **Entitlements.** RevenueCat's own entitlement identifiers are for its
      dashboard and its SDK, and **our backend does not read them** — the webhook
      maps a *product id* to a tier. Create them if you like the reporting; do
      not expect them to change what the app grants.
- [ ] **An offering, marked CURRENT, containing a package per product.**

**This last one is the trap.** `RevenueCatPurchases.offers()` reads
`Offerings.current.availablePackages`. Products that exist but sit in no current
offering produce an empty list, and the paywall then shows *"Not available to
buy yet"* — which is a correct, calm, and completely misleading screen, because
everything else looks configured.

## 5. RevenueCat — the webhook

RevenueCat ▸ Integrations ▸ Webhooks.

- [ ] **URL** `https://cwpwzxjjhxbkwhrgnasn.supabase.co/functions/v1/revenuecat`
- [ ] **Authorization header** — the value of `REVENUECAT_WEBHOOK_SECRET`,
      **verbatim**. No `Bearer` prefix: RevenueCat sends the header as-is and
      the function compares it as-is.
- [ ] Leave the event set at everything. The function ignores what it does not
      handle and answers 200 anyway, because a webhook that 4xxs an event it
      chose not to handle gets retried until RevenueCat gives up and alerts.

## 6. Supabase — deploy and configure

```bash
supabase functions deploy revenuecat --no-verify-jwt

supabase secrets set REVENUECAT_WEBHOOK_SECRET='<a long random string>'
supabase secrets set REVENUECAT_PRODUCTS='{
  "run.coach.monthly":       {"app":"run",  "product":"paid"},
  "run.coach.premium.monthly": {"app":"run",  "product":"premium"}
}'
```

`--no-verify-jwt` is required rather than lax: RevenueCat is not a signed-in
user, has no Supabase token, and authenticates with the shared secret, which is
checked before anything else happens.

- [ ] **For sandbox testing only**, and never in production:
      `supabase secrets set REVENUECAT_ACCEPT_SANDBOX=true`. A sandbox event is
      a real event from a fake payment, so accepting them in production lets
      anybody with a tester account grant themselves a coach. **Unset it before
      you submit.**

## 7. Codemagic — the public key

- [ ] Add `REVENUECAT_PUBLIC_KEY` to the `mgk_fitness_run_env` group, set to the
      **Apple** key from RevenueCat ▸ Project settings ▸ API keys. It begins
      `appl_`, and the build fails if it does not: a Google or web key would
      configure the SDK against the wrong store and fail at the moment of
      purchase, which is the one moment worth failing early instead.

A build without it still ships. The coach gate then explains what a subscription
buys and offers no button, and the build log says so in a banner.

## 8. Sandbox testing

- [ ] **A sandbox Apple ID** — App Store Connect ▸ Users and Access ▸ Sandbox ▸
      Testers. Do not sign into iCloud with it; iOS asks for it at purchase.
- [ ] Sign out of the App Store on the device first (Settings ▸ App Store ▸
      Sandbox Account).
- [ ] Install via TestFlight, sign in to the app so there is a Supabase user,
      then open the coach gate ▸ **See the plans**.
- [ ] Buy. Then watch, in order:
      1. RevenueCat ▸ Customer history — the purchase, against your **Supabase
         UUID** rather than an `RCAnonymousID:`.
      2. RevenueCat ▸ Webhooks — a 200.
      3. `core.entitlements` — one row, `product` `paid`, `status` `active`.
      4. The app — the coach unlocks. The screen polls for about eleven seconds
         and then says the payment went through and the unlock is coming, which
         is the correct message rather than an error.
- [ ] **Restore purchases**, on a second install.
- [ ] Cancel from Apple ID settings and confirm the row goes `expired` **when it
      lapses**, not immediately. `CANCELLATION` means auto-renew is off and the
      runner keeps what they paid for; `EXPIRATION` is what ends access.

---

## When nothing happens

The webhook never throws and never guesses. Every event either writes a row or
is ignored **with a reason**, and the reason is in the function's logs. Read it
before changing anything.

| Reason | What it means | Fix |
|---|---|---|
| `unknown_app_user_id` | The event's `app_user_id` is not a UUID. Almost always an `RCAnonymousID:` — a purchase made before `Purchases.logIn` ran. | Sign in to the app before buying. The app calls `identify` when a session exists. |
| `unmapped_product` | The product id is not a key in `REVENUECAT_PRODUCTS`. | Mirror the App Store Connect ids into the secret. Exactly, including case. |
| `sandbox` | A sandbox purchase, and `REVENUECAT_ACCEPT_SANDBOX` is not `true`. | Set it for testing. **Unset it for production.** |
| `unhandled_type` | An event type the map does not carry. | Usually fine and deliberate. RevenueCat adds types; guessing at one is worse than ignoring it. |
| `no_event_timestamp` | No `event_timestamp_ms`. | Malformed. Check you are pointed at the right URL. |
| 401 on every event | The Authorization header does not match. | No `Bearer`. Compare the exact string, watch for a trailing newline from a paste. |

Two more that are not the webhook's fault:

- **The paywall says "Not available to buy yet".** No current offering, or no
  packages in it. See step 4.
- **The purchase works and the coach stays locked.** The row exists but
  `status` is not `active` — `grace` during a billing retry reads as unpaid on
  purpose, which is why the column has five values rather than a boolean.

## What this does not cover

- **Google Play.** `core.entitlements.platform` allows `google` and the webhook
  handles it, but nothing ships to Play for Run at 1.0.0
  ([ADR-0021](decisions/0021-android-is-a-target.md)).
- **A processor agreement with RevenueCat.** A separate obligation, tracked in
  Gate 3 alongside the OpenRouter one.
- **App Privacy.** Purchases and the identifier both get declared; that is
  Gate 2.
