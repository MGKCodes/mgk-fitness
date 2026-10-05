# Store setup — StoreKit, RevenueCat, App Store Connect

The half of payments that is not code, and every App Store Connect form the
submission needs. [app-store-1.0.0.md](app-store-1.0.0.md) says what is left
and in what order; this is what to actually type, and what breaks when a string
does not match. The Google side is [play-setup.md](play-setup.md).

Written 2026-09-02 against `4d0bd27`. **Updated 2026-09-29 for build 26.** §1–7
are configured against the real stores and have been since 2026-09-03:
TestFlight builds have shipped through them since 2026-09-02, and the webhook
has written real rows from sandbox events. What has never happened is a
submission, which is what §9 and §10 are for.

**Two things this file used to say are reversed**, and both would have cost
the review: `REVENUECAT_ACCEPT_SANDBOX` stays `true` in production
([ADR-0037](decisions/0037-the-sandbox-stays-open-in-production.md)), and
Premium is sold as more coaching, not a better model
([ADR-0038](decisions/0038-premium-buys-more-coaching-not-a-different-model.md)).

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
      charged and then **waits up to a month** for the larger allowance,
      because Apple treats it as a downgrade and defers it. RevenueCat only fires
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
| Description (45) | `A training plan, adjusted every week.` | `A better AI model and a bigger allowance.` |

**Those two limits are much tighter than they look** — 30 and 45 characters,
against the 170 and 4000 of the listing's own fields. The first draft of both
descriptions ran to 82 and 99 and would have been refused in the form.

- [ ] **Change Premium's description in App Store Connect.** It was entered as
      *"A better model behind every plan and answer."*, which production has
      never done
      ([ADR-0041](decisions/0041-premium-is-a-better-model-and-a-bigger-allowance.md)).
      Subscriptions ▸ Premium Coach ▸ Localization ▸ English (U.K.) ▸
      Description. **The paywall prints this field verbatim**, through
      RevenueCat, so until it changes the app makes the claim too. The copy is
      owned by [app-store-listing.md](app-store-listing.md).

**The product IDs above are the placeholders already in the webhook README.**
Keep them and there is nothing to change; use different ones and they must be
mirrored into `REVENUECAT_PRODUCTS` in step 6.

- [x] **A review screenshot per product.** Required, and a common cause of
      "Missing Metadata" holding up the whole submission. **Generated and
      verified 2026-09-03** at **1290×2796 with no alpha channel** — the two
      things App Store Connect actually refuses. An IAP review screenshot only
      has to show where the purchase happens, so unlike the listing screenshots
      this one needs no device.

      **It is not in the repository, on purpose.** `store-assets/.gitignore`
      excludes `/derived/`, because a committed copy of a generated file is a
      copy that drifts. So it exists on whichever machine last ran the script
      and nowhere else. Do not hunt for the path — inside a worktree it sits
      several levels down in a hidden `.claude` directory. Run:

      ```
      python tool/export_store_assets.py --downloads
      ```

      and take it from `~/Downloads`. `--downloads` is a correctness feature
      rather than a convenience: [store-assets/README.md](../../../store-assets/README.md)
      records that the first upload of this asset came from an easier-to-find
      copy that was two revisions stale, and nothing looked wrong until the
      form refused it.

      It comes from the `paywall-store` plate in `test/plates/flows.dart`, which
      renders at `kMaxPhone` × 3 for exactly this purpose, then
      `tool/export_store_assets.py` flattens and checks it. **It is not on
      [the board](https://claude.ai/code/artifact/9ddfd186-11ad-4260-bde9-ef8b7a5d9190)**,
      and this document said it was until 2026-09-03. The board was captured at
      `31b7ce3`, before the paywall existed; `board.state.json` carries neither
      `paywall` nor `paywall-store`. Regenerate it with
      `flutter test test/plates/flows.dart --plain-name paywall`, which writes
      into the git-ignored `plates/`.

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
own, so the item sits in the draft until the submission forms (§10) are
filled in and goes up with the build.

**The two reasons clear separately, and this page once implied they clear
together.** Adding the app version (Add for Review on the version page) clears
the second. The first, *"must be submitted with its subscription group"*,
stays until **the group itself** is in the draft: Subscriptions ▸ the `Run
Coach` group ▸ **Add for Review** on the group's own page, into the same
draft. A first submission carries three kinds of item: the version, the group,
and the subscriptions. Found on 2 October 2026, with Submit for Review greyed
out and everything else done.

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
- [x] **App Store Server Notifications — set on 2 October 2026**, both URLs,
      to RevenueCat's. App Store Connect ▸ the app ▸ App Information, near the
      foot: a *Production Server URL* and a *Sandbox Server URL*. Nothing in
      this runbook mentioned them until that day, and both were empty.

      **Both take RevenueCat's URL, not ours.** RevenueCat ▸ the project ▸
      the App Store app ▸ *Apple Server Notifications* shows the URL to copy.
      Paste the same one into both fields and choose **Version 2**. The
      `revenuecat` Edge Function is the wrong address: it speaks RevenueCat's
      webhook format, and Apple's notifications are a different one.

      **What it buys.** Without it RevenueCat still works: it learns of a
      renewal, a cancellation, a refund or a billing problem by asking Apple
      on its own schedule or when the app next opens, and only then tells our
      webhook. With it Apple tells RevenueCat as it happens, so a refund or a
      lapse reaches `core.entitlements` in seconds rather than hours.
      App Review does not check it and nothing is refused without it. Sandbox
      is set too because App Review buys in the sandbox
      ([ADR-0037](decisions/0037-the-sandbox-stays-open-in-production.md)).
- [ ] **App Store Connect API key — only if you want products imported.**
      Without it the two product ids are typed into RevenueCat by hand, which
      takes a minute, and price changes are not applied automatically. A third
      key type again, and `frunt_asc`'s `.p8` may now exist only inside
      Codemagic. Addable later.

## 4. RevenueCat — project, products, entitlements, offering

Confirmed configured on 2026-09-03. The four boxes below were done on
the 2nd and left unticked, which had this runbook and
[app-store-1.0.0.md](app-store-1.0.0.md) disagreeing about whether a CURRENT
offering existed — the single disagreement that would have sent a sandbox
failure hunting in the wrong layer.

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
- [x] Paste the **shared secret** and upload the **in-app purchase key** from
      step 3.
- [x] **Import the two products.** They must exist in App Store Connect first.
- [x] **Entitlements, named `paid` and `premium`.** One per product, matching
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
- [x] **An offering, marked CURRENT, containing a package per product.**

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

**Do step 6 first.** These are numbered in the order they were written, not the
order they work: the webhook wants a URL that resolves and a secret that exists,
and both are step 6's. Configuring it first leaves RevenueCat pointed at a 404
and you cannot tell a wrong URL from an undeployed function.

RevenueCat ▸ Integrations ▸ Webhooks.

- [x] **URL** `https://cwpwzxjjhxbkwhrgnasn.supabase.co/functions/v1/revenuecat`
- [x] **Authorization header** — the value of `REVENUECAT_WEBHOOK_SECRET`,
      **verbatim**. No `Bearer` prefix: RevenueCat sends the header as-is and
      the function compares it as-is.
- [x] **Send a test event and read the log.** RevenueCat ▸ the webhook ▸ Send
      test event. Expect **200** with `{"ok":true,"ignored":"unmapped_product"}`
      and a log line reading `unmapped_product: test_product` — `test_product`
      being the dummy id RevenueCat sends. A 401 means the header does not match
      Supabase; a 404 means the URL is wrong.

      **This does not prove `REVENUECAT_PRODUCTS` is right**, only that it is not
      implicated. The sandbox purchase in step 8 is what proves it, with a real
      product id — and it will name the id if it fails, which is the point of
      logging it.
- [x] Leave the event set at everything. The function ignores what it does not
      handle and answers 200 anyway, because a webhook that 4xxs an event it
      chose not to handle gets retried until RevenueCat gives up and alerts.
- [x] **Check there is exactly one webhook** (added 2026-09-29, before
      review). One integration, pointed at `…/functions/v1/revenuecat`, with
      the Authorization value verbatim and no `Bearer`. A second, older one
      left in the project would deliver every event twice, or to a URL that
      answers something else.

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

**Deployed 2026-09-02, version 1**, via the Supabase MCP rather than the CLI,
which is not installed here. Verified by probing the live endpoint:

| Request | Answer |
|---|---|
| `GET` | `405 method_not_allowed` |
| `OPTIONS` | `200` |
| `POST`, no Authorization | `401 unauthorized` |
| `POST`, wrong Authorization | `401 unauthorized` |

**The 401 is the interesting one.** The function answers `503 not_configured`
when `REVENUECAT_WEBHOOK_SECRET` is absent and only reaches the auth check when
it is present, so a 401 to an anonymous POST is proof the secret is set —
without anybody having to read it. Worth repeating after any secret change; it
is the cheapest confirmation available that the deploy and the dashboard agree.

- [x] **`REVENUECAT_ACCEPT_SANDBOX=true`, and it stays set in production**
      ([ADR-0037](decisions/0037-the-sandbox-stays-open-in-production.md)).
      **App Review buys in the sandbox**, against the production build: with
      the flag off the reviewer pays, the webhook ignores the event as
      `sandbox`, no row is written, and the coach stays locked behind a
      purchase that "went through". That is a Guideline 2.1 rejection, and
      this line used to say *"Unset it before you submit"*.

      What it costs: a sandbox purchase can only come from people we chose
      (TestFlight testers, sandbox Apple IDs, Play licence testers, App
      Review), and sandbox subscriptions stop by themselves. The one rule it
      brings: **never publish a public TestFlight link** while it is on.

## 7. Codemagic — the public key

- [x] Add `REVENUECAT_PUBLIC_KEY` to the `mgk_fitness_run_env` group, set to the
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
- [ ] Install via TestFlight and sign in to the app so there is a Supabase
      user. Tap the coach mark: agree on **Before your coach answers**,
      acknowledge the medical disclaimer, and the gate sheet opens ▸ **See the
      plans**. (Since build 26 the consent sheet comes before the price, on
      every way into the coach.)
- [ ] Buy. Then watch, in order:
      1. RevenueCat ▸ Customer history — the purchase, against your **Supabase
         UUID** rather than an `RCAnonymousID:`.
      2. RevenueCat ▸ Webhooks — a 200.
      3. `core.entitlements` — one row: `product` `paid`, `status` `active`,
         `platform` `apple`, an `expires_at` in the future and `event_ms`
         filled. The coach stops granting a day after `expires_at`, so a row
         without one is a hand-written row, not a purchase.
      4. The app — the coach unlocks. The screen polls for about eleven seconds
         and then says the payment went through and the unlock is coming, which
         is the correct message rather than an error.

These are the rows of section G of
[the test sheet](testflight-1.0.0-test-sheet.md), which is the copy to tick.
- [ ] **Restore purchases**, on a second install.
- [ ] Cancel from Apple ID settings and confirm the row goes `expired` **when it
      lapses**, not immediately. `CANCELLATION` means auto-renew is off and the
      runner keeps what they paid for; `EXPIRATION` is what ends access.

## 9. The two review accounts

App Review gets two accounts, because it has two jobs and one account cannot do
both: reviewing the coach needs a subscription that already works, and testing
the purchase needs an account that has none.

| | For | Row in `core.entitlements` |
|---|---|---|
| **A** | Reviewing the coach. Not for buying | `premium`, `active`, never lapses, and no store event can change it |
| **B** | Buying with the reviewer's sandbox Apple ID | none |

Play's reviewer uses A as well (play-setup.md §4, App access), which is why A's
row names no store.

- [x] **Both accounts created, 2026-09-30**, through the ordinary sign-up
      endpoint (email confirmation is off, so neither address needs a mailbox):
      **A** `review.subscribed@mgkfitness.mgkcodes.com`, **B**
      `review.free@mgkfitness.mgkcodes.com`. Passwords were handed to the owner
      for App Store Connect and Play's App access form and are not in this
      repository. Neither is a person's account.

      **Do not sign in as either on your own phone.** Its training is yours, so
      the app would show *"This phone has another account's training on it"*
      and offer only to erase it or sign out. Use a phone whose training you
      do not need: a spare, an emulator, or the Android test phone once the
      test sheet is done.
- [x] **A granted, 2026-09-30** (`premium`, `active`, `expires_at` null,
      `event_ms` 9999999999999, `source_txn_id` `manual:app-review-subscribed`).
      To re-grant it, the SQL is:

      ```sql
      insert into core.entitlements
        (user_id, app, product, status, platform, expires_at, event_ms)
      select id, 'run', 'premium', 'active', null, null, 9999999999999
      from auth.users
      where email = 'review.subscribed@mgkfitness.mgkcodes.com'
      on conflict (user_id, app) do update
        set product = 'premium', status = 'active', platform = null,
            expires_at = null, event_ms = 9999999999999, updated_at = now();
      ```

      Why each value:

      - `expires_at` **null**: never lapses. The coach refuses an `active` row
        a day after its `expires_at`, so a date here is a review account that
        stops working on its own.
      - `event_ms` **9999999999999** (the year 2286): the webhook only writes an
        event strictly newer than the row it finds, so nothing a store sends
        can change A, including a purchase a reviewer makes on it by mistake.
      - `platform` **null**: the app then names the store of the phone it is
        on. The draft of this said `'apple'`, which would tell Play's reviewer
        to cancel in the App Store.
      - `premium`, so the reviewer meets the higher allowance and cannot hit a
        ceiling mid-review.
- [x] **B has no row** (checked 2026-09-30). If a test ever leaves one:

      ```sql
      select u.email, e.product, e.status, e.platform, e.expires_at, e.event_ms
      from auth.users u
      left join core.entitlements e on e.user_id = u.id and e.app = 'run'
      where u.email in ('review.subscribed@mgkfitness.mgkcodes.com',
                  'review.free@mgkfitness.mgkcodes.com');

      delete from core.entitlements
      where app = 'run'
        and user_id = (select id from auth.users
                       where email = 'review.free@mgkfitness.mgkcodes.com');
      ```

- [ ] **Check both on that phone, then withdraw the AI permission on both.**
      A: coach mark ▸ consent ▸ disclaimer ▸ the conversation, no paywall. B:
      coach mark ▸ consent ▸ disclaimer ▸ gate ▸ **See the plans** with two
      prices. **Do not buy on B.** Then, on each, Profile ▸ Settings ▸ Privacy &
      legal ▸ **Coach and AI** ▸ Withdraw. The answer is kept on the account
      ([ADR-0036](decisions/0036-the-coach-asks-before-it-sends.md)), so an
      account you agreed on never shows the reviewer the sheet the review notes
      describe. Between the two, sign out with **Also remove my data from
      this phone** on, so B does not meet A's training.
- [ ] **Paste them.** A goes in App Review Information ▸ Sign-in required
      (user name and password); A and B both go in the notes, in place of the
      four bracketed values ([app-store-listing.md](app-store-listing.md) §
      Review notes).

**Keep both after approval.** Every later submission needs them, and deleting A
through the app's own Delete account takes its row with it.

## 10. App Store Connect — the submission forms

Field by field, in the order App Store Connect presents them. Where a value is
copy, it is owned by [app-store-listing.md](app-store-listing.md) and not
repeated here.

### App Information (once per app)

| Field | Answer |
|---|---|
| Name, subtitle, categories | [app-store-listing.md](app-store-listing.md) |
| Content Rights | **Yes**, it contains third-party content, and **yes**, we have the rights: the basemap tiles are Esri's (ArcGIS Location Platform, whose free tier allows commercial apps) and carry data from OpenStreetMap and the other sources Esri names. The map shows *Powered by Esri* and opens the sources on a tap, and the build fails if tiles are configured without a credit. True of build 27 on, once Codemagic's `MAP_TILE_URL_TEMPLATE` is Esri's; it was MapTiler's non-commercial plan before |
| Age Rating | The questionnaire below |
| Regulated Medical Device | **No: not a regulated medical device.** App Information asks every app in the Health & Fitness category to declare it (read off the page on 2 October 2026; it is the category that triggers it, not the age rating). The description, the terms and the in-app disclaimer all say the same thing |
| App Store Server Notifications | RevenueCat's URL in both fields, Version 2 (§3). Optional for review, wanted for launch |
| License Agreement | **Apple's Standard EULA.** The field takes plain text, not a URL; our terms are linked from the description and the app, and say Apple's EULA governs App Store purchases ([ADR-0040](decisions/0040-our-terms-and-apples-eula.md)) |

**EU trader status (Digital Services Act)** is set once for the account, under
Business: **trader, MGKCodes Ltd.** The address, phone and email given there are
shown on the EU product page.

### Age Rating — the 2025 questionnaire

| Question | Answer |
|---|---|
| Parental Controls | No |
| Age Assurance | No |
| Unrestricted Web Access | No |
| User-Generated Content | No |
| Social Media | No |
| Messaging and Chat | No |
| Advertising | No |
| Every violence, sexuality, nudity, profanity, horror, alcohol, tobacco and drug question | None |
| Health or Wellness Topics | **Frequent** |
| Medical or Treatment Information | **Infrequent** |
| Gambling, simulated gambling, contests, loot boxes | None / No |
| Made for Kids | No |

Expect **13+**. Two answers are judgement rather than fact. *Medical or
Treatment Information* is Infrequent because plans and the coach talk about
injury and rest; None is defensible, since nothing gives medical advice.
*Messaging and Chat* is No because the coach is a model, not a person, and no
runner can reach another.

### App Privacy

- **Privacy Policy URL** `https://mgkfitness.mgkcodes.com/run/privacy`
- **User Privacy Choices URL** (optional) `https://mgkfitness.mgkcodes.com/run/delete-account`
- **Do you or your third-party partners collect data from this app?** **Yes.**
- **Tracking: No, for every type.** Nothing is joined with other companies'
  data and there is no advertising anywhere.

Backup consent makes several of these conditional, and the form cannot say
"only if the runner turns it on". **Declare what is collected with backup on.**

| Data type | Linked to the user | Purposes | What it is |
|---|---|---|---|
| Email Address | Yes | App Functionality | The account: typed in, or passed on by Apple or Google at sign-in (with Hide My Email, Apple's relay address) |
| Name | Yes | App Functionality | The name the coach uses, if given; kept in auth metadata and never sent to the model |
| Health | Yes | App Functionality | HealthKit **step count** over a recorded run, stored with the run and sent to us only with backup on; injury notes and symptoms typed to the coach |
| Fitness | Yes | App Functionality | Runs, pace, splits, plans and effort ratings, sent to the coach and, with backup on, stored |
| Precise Location | Yes | App Functionality | Route traces, stored with backup on |
| Coarse Location | **No** | App Functionality | Esri's tile requests show roughly where the map is, or where the phone last was when the app opens. A judgement call: no account or id goes with them, and over-declaring costs nothing |
| Other User Content | Yes | App Functionality | Messages to the coach, the rolling summary, and replies the runner reports |
| User ID | Yes | App Functionality, Analytics | The Supabase user id, which RevenueCat holds as the app user id; and Apple's or Google's identifier for the runner, when they sign in with one |
| Purchase History | Yes | App Functionality, Analytics | The subscription, as RevenueCat declares it. **In the form's tick list it is the single box called *Purchases***; the name Purchase History only appears once it is saved. It was left off the first pass on 2 October for that reason |
| Product Interaction | Yes | App Functionality | The coach usage ledger: one row per request, kept 31 days |

Signing in with Apple or Google adds no type: they pass an email address and
an identifier, which are two rows already here.

**Not collected:** Photos (the profile photo never leaves the phone), Device
ID, Crash Data, Performance Data, Other Diagnostic Data, Contacts, Browsing
History, Search History, Payment Info, Sensitive Info, Audio Data, Gameplay
Content, Customer Support, Advertising Data.

`ios/Runner/PrivacyInfo.xcprivacy` declares the same list apart from Coarse
Location, and `the_privacy_manifest_declares_what_is_sent_test.dart` pins it.

### Pricing and availability

Free, with the two subscriptions as in-app purchases. **Never Paid**: the app is
free and the coach is the subscription.

**Untick the Mac and Apple Vision Pro.** The same page offers the iPhone app
on Apple silicon Macs and on Apple Vision Pro, and both boxes arrive ticked.
The app records runs by GPS, reads steps from Health and puts a Live Activity
on a lock screen; none of that has been run on either, and the description
says "iPhone only". An iPad still runs it, in the iPhone's shape, and that
cannot be switched off.

### The 1.0.0 version page

| Field | Answer |
|---|---|
| Screenshots, promotional text, description, keywords | [app-store-listing.md](app-store-listing.md) |
| Support URL | `https://mgkfitness.mgkcodes.com/run/support` |
| Marketing URL | `https://mgkfitness.mgkcodes.com` — the site's home page. Decided 2 October 2026: the marketing page is going to be built there, so the address is right before the page is. Today it is a plain page naming both apps with their legal links, which resolves and says nothing false. Not `/run`, which is a 404 |
| Version | The page offers `1.0`. The build says `1.0.0`, and App Store Connect treats the two as the same version, which is why build 29 attaches. Type `1.0.0` so the store shows what everything else calls it |
| Copyright | `2026 MGKCodes Ltd` |
| Build | The release candidate named in [app-store-1.0.0.md](app-store-1.0.0.md) (this row said 26 after 27 replaced it) |
| In-App Purchases and Subscriptions | **Add both**, Coach and Premium Coach. A first subscription is only ever reviewed with a version, so this is where they go up. **The section is not always there.** It sits between Build and Game Center, and only while a product is *Ready to Submit* and in no submission already. If it is missing, look in two places: the **Draft Submissions** button at the foot of the page, where the two may already be parked (§2 says why they should not be left there, and they go up with the version from there just the same), and Subscriptions ▸ the group, where a product reading *Missing Metadata* names what it lacks |
| App icon | Nothing to upload: it comes from the build |
| Sign-in required | **Yes**, demo account A (§9) |
| Notes | The review notes in [app-store-listing.md](app-store-listing.md), with A and B filled in |
| Contact information | Name, phone and email of whoever answers App Review |
| Version release | **Automatically release this version** (Matthew, 5 October 2026: updates go out as soon as they are approved; a chosen moment can come once there are users). `scripts/store/stores.py submit` sets it. 1.0.0 went in on manual release and was switched on 5 October |

**At submission**, two questions:

- **Export compliance** does not appear: `ITSAppUsesNonExemptEncryption` is
  `false` in `Info.plist`. If it does appear, something changed in the build.
- **Advertising Identifier (IDFA): No.** Nothing in the app reads it.

---

## 11. Sign in with Apple and Google — Run's half

Added 2026-09-30. Both apps sign into one account, so the providers were set
up **once, for the suite**, in the Lift session, and the full runbook is
[Lift's `docs/store-setup.md`](../../mgk_lift/docs/store-setup.md), step 7.
This is Run's half of it. **Recorded from that runbook, not re-checked from
Run's side:** the first build 27 on a phone is what proves it.

| Where | Run's part |
|---|---|
| Apple ▸ Identifiers | `com.mgkcodes.fitness.run` has Sign In with Apple, **grouped under** `com.mgkcodes.liftio` so one Apple ID is one account across both apps |
| Apple ▸ Services ID | `com.mgkcodes.fitness.web`, for Android's browser flow; key `43K62X7QPT`, team `ZTS7SQYSA5` |
| Google Cloud `mgk-fitness` | iOS client *Run iOS* (the id is in `lib/src/features/auth/data/provider_ids.dart`, reversed in `Info.plist`); Android clients for `com.mgkcodes.fitness.run` at the Play signing, upload and debug SHA-1s |
| Supabase ▸ Providers | Apple *Client IDs* include `com.mgkcodes.fitness.run`, with the Services ID first; Google *Client IDs* include Run's iOS id |
| Supabase ▸ URL Configuration | `com.mgkcodes.fitness.run://login-callback`, Android's way back from Apple |
| Supabase ▸ Edge Function secrets | `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`, which `delete-account` needs to revoke Apple's tokens |

**Two dates that stop things working if missed:**

- **Supabase's Apple secret expires around 2027-03-30.** Regenerate it by
  **2027-03-20**, or Android's Apple sign-in stops.
- **Run's Codemagic signing** is `mgkfitness_distribution`, expiring
  **2027-09-30**.

A profile is a snapshot of its App ID's capabilities: change one, and
regenerate the profile on the MGKFitness certificate, never Frunt's.

### The Live Activity extension has a profile of its own

Added 2026-10-01, for build 29. The run's figures on the lock screen are drawn
by a widget extension that ships inside the app
([ADR-0045](decisions/0045-the-runs-figures-on-the-lock-screen.md)). An
extension is signed separately, so the iPhone build **cannot be signed** until
these exist. Once, by the owner:

1. **Apple ▸ Identifiers ▸ +** ▸ App IDs ▸ App. Bundle ID, explicit:
   `com.mgkcodes.fitness.run.RunLiveActivity`. **No capabilities.** It uses no
   App Group and no entitlement.
2. **Apple ▸ Profiles ▸ +** ▸ Distribution ▸ App Store Connect. That App ID,
   the `mgkfitness_distribution` certificate (never Frunt's). Name it
   *Run Live Activity App Store*.
3. **Codemagic ▸ Team settings ▸ codemagic.yaml settings ▸ Code signing
   identities ▸ iOS provisioning profiles**: fetch or upload that profile.

Nothing changes in `codemagic.yaml`. Its `bundle_identifier:
com.mgkcodes.fitness.run` matches that id and every id under it, so the
extension's profile is picked up with the app's. It expires with the
certificate, on **2027-09-30**.

## When nothing happens

The webhook never throws and never guesses. Every event either writes a row or
is ignored **with a reason**, and the reason is in the function's logs. Read it
before changing anything.

| Reason | What it means | Fix |
|---|---|---|
| `unknown_app_user_id` | The event's `app_user_id` is not a UUID. Almost always an `RCAnonymousID:` — a purchase made before `Purchases.logIn` ran. | Sign in to the app before buying. The app calls `identify` when a session exists. |
| `unmapped_product` | The product id is not a key in `REVENUECAT_PRODUCTS`. **The log names it.** `test_product` is RevenueCat's own test event and is fine; anything beginning `run.` is a real mismatch. | Mirror the App Store Connect ids into the secret. Exactly, including case. |
| `sandbox` | A sandbox purchase, and `REVENUECAT_ACCEPT_SANDBOX` is not `true`. | Set it back to `true`. It stays on in production (ADR-0037), because App Review buys in the sandbox. |
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

- **Google Play.** Run 1.0.0 ships there too, from the same commit
  ([ADR-0039](decisions/0039-one-commit-two-stores-and-the-pubspec-owns-the-build-number.md)).
  That runbook is [play-setup.md](play-setup.md). This line said nothing ships
  to Play at 1.0.0 until 2026-09-29, citing ADR-0021 for the opposite of what
  it says.
- **A processor agreement with RevenueCat.** A separate obligation, tracked in
  [app-store-1.0.0.md](app-store-1.0.0.md) alongside the OpenRouter one.
