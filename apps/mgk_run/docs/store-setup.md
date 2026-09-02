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

- [x] **Paid Applications agreement active.** Nothing about subscriptions works
      until it is, and it is the longest lead time on the whole release.
- [x] Tax forms complete for your territories.
- [x] Bank details added and verified.

**Done 2026-09-02, and it cost nothing: it was already Active from Liftio.** An
agreement is held by the team rather than by an app, which is worth knowing
before budgeting weeks for it — the same reason `codemagic.yaml` reuses one App
Store Connect API key across every app in the suite.

## 2. App Store Connect — the subscription group and two products

App Store Connect ▸ your app ▸ Subscriptions.

- [x] **One subscription group.** One, not two: the tiers are alternatives, and
      a group is what lets somebody move between them without a second purchase
      and without being charged twice.
- [x] **Localised group display name.** Shown in the runner's Apple ID
      subscription settings, so it should read as a thing they recognise.
- [x] **Rank Premium Coach as level 1 and Coach as level 2.**

      **Level 1 is the highest service level, not the lowest**, and the numbering
      reads backwards to almost everybody the first time. Apple uses the rank to
      decide what a switch *is*: moving to a lower number is an **upgrade**,
      which takes effect immediately with a prorated refund of the unused time,
      and moving to a higher number is a **downgrade**, deferred to the next
      renewal with no proration.

      Ranked the intuitive way round, a runner who pays £2.99 to move up is
      charged and then **waits up to a month** for the better model, because
      Apple treats it as a downgrade and defers it. RevenueCat only fires
      `PRODUCT_CHANGE` when the change takes effect, so `core.entitlements`
      would not carry `premium` until then either. Nothing looks broken; it is
      simply wrong and slow. Unlike a product id, the rank can be changed at any
      time.

Then, per product:

| | Coach | Premium Coach |
|---|---|---|
| Reference name | Run Coach Monthly | Run Coach Premium Monthly |
| Product ID | `run.coach.monthly` | `run.coach.premium.monthly` |
| Duration | 1 month | 1 month |
| Price | £0.99 | £2.99 |
| Display name | Coach | Premium Coach |

Then per product, **Localization ▸ English (U.K.)**:

| | Coach | Premium Coach |
|---|---|---|
| Display name (30) | `Coach` | `Premium Coach` |
| Description (45) | `A training plan, adjusted every week.` | `A better model behind every plan and answer.` |

**Those two limits are much tighter than they look** — 30 and 45 characters,
against the 170 and 4000 of the listing's own fields. The first draft of both
descriptions ran to 82 and 99 and would have been refused in the form.

**The product IDs above are the placeholders already in the webhook README.**
Keep them and there is nothing to change; use different ones and they must be
mirrored into `REVENUECAT_PRODUCTS` in step 6.

- [x] **A review screenshot per product.** Required, and a common cause of
      "Missing Metadata" holding up the whole submission. The `paywall` plate on
      [the board](https://claude.ai/code/artifact/9ddfd186-11ad-4260-bde9-ef8b7a5d9190)
      is what this screen looks like, and **is usable**: an IAP review
      screenshot only has to show where the purchase happens, so unlike the
      listing screenshots this one needs no device.

      Export it with `python tool/export_store_assets.py`. It lands in
      `store-assets/derived/` at **1290x2796**, with the alpha channel
      flattened. Both of those matter: App Store Connect refuses an image with
      an alpha channel, and it refuses arbitrary dimensions -- the "640x920
      minimum" in Apple's older documentation is not what the form accepts, and
      a 786x1704 render that cleared it was rejected outright.
- [x] **Review notes per product.** Say the coach is the paid half and recording
      is free, so a reviewer is not hunting for what changed.
- [x] **No free trial, no introductory offer.** Deliberate: a trial on a £0.99
      product costs more in support than it earns. Revisit later, not now.
- [x] Let Apple's matrix set every other storefront's price. The app never shows
      a figure of its own, so this is safe by construction.

**What "done" looks like, because the screen implies otherwise.** A finished
product reads **Ready to Submit**, and App Store Connect then shows a Draft
Submission saying *"Unable to Submit for Review"* with two reasons: the
subscription must be submitted with its group, and there is no app version for
the platform. **Both are correct and neither is a fault.** Subscriptions are
reviewed alongside an app version on the first submission and never on their
own, so the item sits in the draft until the rest of Gate 2 and Gate 4 are
filled in and goes up with the build.

Ready to Submit is also the bar that matters for everything downstream:
**RevenueCat cannot fetch a product below it**, and neither can sandbox
StoreKit. Do not submit anything to get past the warning.

**Do not leave items parked in that Draft Submission either.** App Store
Connect freezes a subscription's editable fields while it is part of a pending
submission, **including its level**, and the control simply greys out with no
explanation of why. It looks like something you have to wait for review to
change, and nothing has been submitted to wait on. Remove the items, or delete
the draft outright; it is scaffolding and rebuilds itself the moment there is an
app version to attach. Add them back when you actually submit, which is the one
time they genuinely do have to be in it.

### As configured, 2026-09-02

**Enrolled in the Apple Small Business Program since 2026-06-01**, so
[ADR-0029](decisions/0029-what-a-tier-costs-and-buys.md) holds as written: the
15% rate, £0.99 to £0.70 net, and every ceiling in `limits.ts` at roughly three
quarters of that. At the standard 30% they would each have been about 18%
oversized.

Both products reached **Ready to Submit**. Check RevenueCat against this table
rather than against the one above, which is what we meant to do.

| | Coach | Premium Coach |
|---|---|---|
| Product ID | `run.coach.monthly` | `run.coach.premium.monthly` |
| Level | 2 | **1** (the higher tier) |
| Price | £0.99 | £2.99 |
| Group | `Run Coach`, shown to runners as `MGKFitness: Run Coach` |||

The group's display name is deliberately longer than the group's reference name:
it appears in a runner's Apple ID subscription list among every other app's
subscriptions, with no context, so `Run Coach` alone would not say whose it is.
It matches the listing name, `MGKFitness: Run`.

## 3. App Store Connect — the two credentials RevenueCat needs

Three, not two, and the one that matters is not the one Apple's own
documentation puts first.

- [x] **In-App Purchase Key — the required one.** `purchases_flutter` 10.x is
      well past v5, so this app is on **StoreKit 2**, and RevenueCat's own form
      says it plainly: *"transactions will fail to be recorded without this key
      being set. This can result in users not accessing the purchases they are
      entitled to."* Not a nicety. Users and Access ▸ Integrations ▸ In-App
      Purchase.
      **The `.p8` downloads exactly once.** Same rule as the App Store Connect
      API key `codemagic.yaml` already uses; put it somewhere you will still
      have it in a year, and keep the **Key ID** with it.

      **The Issuer ID is on a different tab.** RevenueCat asks for the `.p8`,
      the Key ID and an Issuer ID together, but the In-App Purchase tab shows
      only the first two. The Issuer ID lives at the top of the **App Store
      Connect API** tab, above the key list, and is the same value for every key
      you own because it identifies the *team* rather than a key. Its field in
      RevenueCat carries a placeholder that looks exactly like a real UUID, so
      an empty field reads as a filled one.

      **Name it for the team, not for Run.** These keys are issued to the
      account and sign App Store Server API requests for every app you own, so
      an app-specific name describes a scope it does not have and invites a
      second key doing the same job. **Check whether Liftio's RevenueCat already
      uses one first** — the same key serves a second project, and two
      indistinguishable `.p8` files in circulation is worse than one well named.

      Distinct from the App Store Connect API key the build uses (`frunt_asc`).
      That one has the wrong scope for this; do not reuse it.
- [x] **App-Specific Shared Secret — legacy, and optional.** App Store Connect ▸
      your app ▸ App Information. RevenueCat labels this field
      **"(Legacy)"**: it is the older receipt-validation path, superseded by the
      key above. Fill it in if you like; it is not what makes StoreKit 2 work.
      **This one is genuinely per-app**, unlike the key, so Run's is not Lift's.
- [ ] **App Store Connect API key — only if you want products imported.**
      Without it the two product ids are typed into RevenueCat by hand, which
      takes a minute, and price changes are not applied automatically. A third
      key type again, and `frunt_asc`'s `.p8` may now exist only inside
      Codemagic. Addable later.

## 4. RevenueCat — project, products, entitlements, offering

- [x] **A new project for the suite, not Liftio's.** RevenueCat scopes
      entitlements and offerings per project, and the backend is already built
      for one project serving both apps: `core.entitlements.app` is
      `('lift', 'run')`, `REVENUECAT_PRODUCTS` maps a product id to
      `{app, product}`, and one webhook URL with one secret routes both.

      The existing Liftio project belongs to the React Native app being
      replaced — different product ids, its own webhook wiring. Folding Run into
      it would have the new suite sharing a webhook secret with a retired app.
      Name the project `mgk-fitness`, and add Lift to it when the rewrite ships.
- [x] An **App** in that project, with bundle id `com.mgkcodes.fitness.run`.

      **Name it `Run`, not after the project.** RevenueCat defaults the name to
      the project's, and Lift will be a second app in the same project — two
      entries called `MGKFitness (App Store)` are indistinguishable.

      Leave **Custom URL Scheme** blank: it exists for RevenueCat's hosted
      paywall previews, and the paywall here is `PurchaseScreen`, built in
      Flutter.
- [x] **Apple Small Business Program — set the start date if enrolled.** Not
      cosmetic. [ADR-0029](decisions/0029-what-a-tier-costs-and-buys.md) does its
      whole arithmetic at Apple's **15%** small-business rate, £0.99 to £0.70
      net, and every ceiling in `supabase/functions/coach/limits.ts` is roughly
      three quarters of that. At the standard 30% the net falls about 18% and
      every ceiling is oversized.
- [ ] Paste the **shared secret** and upload the **in-app purchase key** from
      step 3.
- [ ] **Import the two products.** They must exist in App Store Connect first.
- [ ] **Entitlements, named `paid` and `premium`.** One per product, matching
      the product ids one to one.

      **Our backend does not read them** — the webhook maps a *product id* to a
      tier, so these grant nothing. They are worth having anyway, for the moment
      somebody writes in saying they paid and have no coach: RevenueCat's
      customer page is the first place you look, and it should answer "what does
      this person have" without you doing the mapping in your head under
      pressure.

      **The names are the whole point.** `paid` and `premium` are the values
      `core.entitlements.product` takes and the values `REVENUECAT_PRODUCTS`
      maps to, so the two configurations are comparable at a glance rather than
      being two plausible-looking mappings that disagree.

      This is normally exactly the second-source-of-truth drift this repository
      keeps removing, and it is safe here for one specific reason: **the app
      cannot read them even by accident.** `PurchaseClient` has no
      `isSubscribed`, `restore()` reads `activeSubscriptions` rather than
      `CustomerInfo.entitlements`, and the gate is `tierFor` server-side. Add a
      client-side entitlement read and this stops being free.
- [ ] **An offering, marked CURRENT, containing a package per product.**

      Two monthly products cannot both be `$rc_monthly`, so at least one package
      needs a custom identifier. **Nothing in the app reads them**:
      `RevenueCatPurchases.offers()` maps by `storeProduct.identifier`, so any
      names work. The **order does** matter, because `availablePackages` comes
      back in the order configured and the paywall renders it in that order.

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
