# Store setup for Lift: what to do in each dashboard

Everything Lift 2.0.0 needs that lives in a dashboard rather than in this
repository, in the order it has to happen. The code side is done: the purchase
sheet, RevenueCat behind the `Purchases` seam, the renewal disclosure, and the
`revenuecat` webhook (deployed 2026-09-29, v6).

Written 2026-09-29. Run went through the same chain first, and
[its runbook](../../mgk_run/docs/store-setup.md) records every trap it hit. The
steps here reuse Run's accounts wherever one serves both apps.

**The chain, and the values that must match exactly:**

| Value | Set in | Must equal |
|---|---|---|
| Product ids | App Store Connect / Play Console | every key in `REVENUECAT_PRODUCTS` (step 5) |
| Bundle / package | App Store Connect, Play, RevenueCat | `com.mgkcodes.liftio` |
| Public SDK keys | RevenueCat, then Codemagic | `appl_…` (iOS), `goog_…` (Android), **Lift's own**, not Run's |
| App user id | the app, automatically | the Supabase user id (already wired) |

---

## 0. First: count Liftio's paying subscribers

Everything about the legacy products depends on this number.

- [ ] **Old Liftio RevenueCat project** (the React Native app's, not
      `mgk-fitness`) › Overview › *Active subscriptions*. Then Customers,
      filtered to the `pro` entitlement, active. Note each customer's app user
      id: Liftio set it to the Supabase user id, and 2.0.0 uses the same
      Supabase project, so every one of them maps to an account that still
      exists.
- [ ] Tell me the ids (or "zero"). For each active one I grant `lift` / `paid`
      with `core.grant_entitlement()` so they open 2.0.0 already unlocked.

**Leave `liftio_monthly` and `liftio_annual` on sale in App Store Connect.** The
app never offers them (they are not in the offering, step 3), so nobody new can
buy them, and existing subscribers keep renewing exactly as they do today.
Taking them off sale is the one move here that could cost a paying customer
something, and it gains nothing.

## 1. App Store Connect: two new products

App Store Connect › Apps › Liftio (6759969740) › Monetization › Subscriptions ›
the existing subscription group (the one holding `liftio_monthly`).

- [ ] **Add both to the existing group.** One group is what lets somebody move
      between tiers, and between a legacy product and a new one, without paying
      twice.

| | Coach | Premium Coach |
|---|---|---|
| Reference name | Lift Coach Monthly | Lift Coach Premium Monthly |
| Product ID | `lift.coach.monthly` | `lift.coach.premium.monthly` |
| Duration | 1 month | 1 month |
| Price | **£0.99** (recommended) | **£2.99** (recommended) |
| Display name (30 chars) | `Coach` | `Premium Coach` |
| Description (45 chars) | `A training plan, adjusted every week.` | `Far more room to talk to your coach.` |

- [ ] **Levels: Premium Coach level 1, Coach level 2, and both legacy products
      level 2.** Level 1 is the *highest*. Ranked the other way round, moving
      up to Premium is treated as a downgrade and waits up to a month (Run's
      runbook, step 2).
- [ ] **Why those prices.** The coach's usage limits are set per tier, not per
      app, and they were sized against Run's £0.99 / £2.99 at the Small
      Business Program's 15% rate (Run's ADR-0029). Pricing Lift's Coach higher
      is fine; pricing it lower makes every Lift conversation cost more than it
      earns. Liftio's £1.99 is not a constraint: its subscribers keep their
      product.
- [ ] **A review screenshot per product** (1290 × 2796, no transparency). The
      purchase sheet is what it should show. I will render it once the web
      pages land; say if you want it sooner.
- [ ] **Review notes per product:** "The coach, training plans and progress
      photos are the paid half. Tracking, saved workouts, history and stats are
      free with no account."
- [ ] Group display name: `MGKFitness: Lift Coach`.
- [ ] App Information › **App-Specific Shared Secret** › generate one (RevenueCat
      step 3 asks for it). Per app: Run's is not Lift's.
- [ ] A **sandbox tester**: Users and Access › Sandbox › Testers. Do not sign
      into iCloud with it; iOS asks for it at the moment of purchase.

A new product reads **Ready to Submit** when it is done. That is the bar
RevenueCat needs; do not submit anything to get past the "Unable to Submit"
warning, which clears when the 2.0.0 version is submitted with the products
attached.

## 2. Google Play Console: the app, then the products

Lift has never been on Play, so this is a new app. The account already has
production access (frunt is live on it), so no 14-day closed test is needed.

- [x] **Create app:** name `MGKFitness: Lift`, default language English (UK),
      App, Free, with in-app purchases. *Done 2026-09-30.*
- [x] **Upload the first `.aab` by hand** to Internal testing. The Play API
      cannot create a listing, only add to one. *Done 2026-09-30, as a **draft**
      release nobody receives: the bundle from Codemagic build
      `6abbfae2126571e3df662103` (`4d12c46`), signed with the suite's
      `mgkfitness_upload` key (checked: `EC:4D:11:…:33:CF`). This claimed
      `com.mgkcodes.liftio` on Play and made Play generate Lift's app-signing
      key, whose fingerprint Google sign-in needed (7c).*
- [ ] Monetize › Subscriptions:
  - `lift.coach.monthly`, base plan id `monthly`, auto-renewing, 1 month.
  - `lift.coach.premium.monthly`, base plan id `monthly`.
  - **Price ex-VAT**, as Run did, so Android and iOS charge the same.
- [ ] Setup › API access › give the **existing** service account (the one
      Codemagic and RevenueCat use for Run) access to this app, with Release
      manager permission.
- [ ] Settings › License testing: add your Google account, for test purchases.
- [ ] The declarations (store listing, content rating, target audience, Data
      safety, ads = none, app access = the demo account). The answers are
      drafted in `store-listing.md`; the form-filling is yours.
- [ ] **Account deletion URL** (Play requires one):
      `https://mgkfitness.mgkcodes.com/lift/delete-account`, live once the web
      pages are deployed.

## 3. RevenueCat: add Lift to the `mgk-fitness` project

Not the old Liftio project. One project serves both apps: one webhook, one
secret, and `core.entitlements.app` keeps Run and Lift apart.

- [ ] **Apps › + › App Store:** name it `Lift`, bundle id `com.mgkcodes.liftio`.
      Paste the App-Specific Shared Secret (step 1). Upload the **In-App
      Purchase key**: the same team `.p8`, Key ID and Issuer ID Run's app uses.
      It is issued to the team, not to an app.
- [ ] **Apps › + › Play Store:** name it `Lift (Play)`, package
      `com.mgkcodes.liftio`, the same service-account JSON as Run's Play app.
- [ ] **Products:** add `lift.coach.monthly` and `lift.coach.premium.monthly`
      for the App Store app, the two Play subscriptions for the Play app, and
      the legacy `liftio_monthly` and `liftio_annual` for the App Store app (so
      their renewals are recorded here from now on).
- [ ] **Entitlements:** attach Coach and both legacy products to `paid`, and
      Premium Coach to `premium`. These grant nothing on their own (the webhook
      maps product ids), but they make the customer page readable when
      somebody writes in.
- [ ] **Offering:** in the **current** offering (the one Run uses), put Lift's
      products into the existing packages. A package holds one product per app,
      so the Coach package gets `lift.coach.monthly` for Lift beside Run's, and
      the Premium package gets `lift.coach.premium.monthly`. **Do not add the
      legacy products to the offering.** The app shows exactly what the offering
      holds, in its order.
- [ ] **API keys:** Project settings › API keys. Copy **Lift's** App Store key
      (`appl_…`) and Play key (`goog_…`) for step 4.
- [ ] **App Store Server Notifications:** RevenueCat shows a notification URL on
      the Lift App Store app's page. Paste it into App Store Connect › Lift ›
      App Information › App Store Server Notifications (production and
      sandbox). That points legacy renewals at this project instead of the old
      one.
- [ ] Nothing to do for the webhook: the project's existing one already points
      at the `revenuecat` function and serves both apps.

## 4. Codemagic: Lift's keys

- [ ] Team settings › Global variables and secrets › new group
      **`mgk_fitness_lift_env`**, available to the mgk-fitness app:
  - `REVENUECAT_PUBLIC_KEY` = Lift's `appl_…` key, Secure
  - `REVENUECAT_GOOGLE_KEY` = Lift's `goog_…` key, Secure
- [ ] Tell me, and I uncomment `mgk_fitness_lift_env` in both Lift workflows in
      `codemagic.yaml`. It stays commented until the group exists, because a
      workflow naming a missing group may fail before any script runs. Until
      then builds ship unable to sell, and say so in a banner.

## 5. Supabase: map Lift's products

The webhook maps a product id to an app and a tier through one secret shared
with Run. **Setting it replaces the whole value**, so it carries Run's ids too.
Run's four are as recorded in `apps/mgk_run/docs/app-store-1.0.0.md`; if you
added anything else to it, keep that as well.

From **Git Bash, not PowerShell**. PowerShell strips the quotes and unmaps both
apps, which is exactly what happened to Run for thirteen minutes on
2026-09-11. I can run this for you once the Play ids are confirmed.

```bash
npx supabase secrets set --project-ref cwpwzxjjhxbkwhrgnasn REVENUECAT_PRODUCTS='{
  "run.coach.monthly":                  {"app":"run",  "product":"paid"},
  "run.coach.premium.monthly":          {"app":"run",  "product":"premium"},
  "run.coach.monthly:monthly":          {"app":"run",  "product":"paid"},
  "run.coach.premium.monthly:monthly":  {"app":"run",  "product":"premium"},
  "lift.coach.monthly":                 {"app":"lift", "product":"paid"},
  "lift.coach.premium.monthly":         {"app":"lift", "product":"premium"},
  "lift.coach.monthly:monthly":         {"app":"lift", "product":"paid"},
  "lift.coach.premium.monthly:monthly": {"app":"lift", "product":"premium"},
  "liftio_monthly":                     {"app":"lift", "product":"paid"},
  "liftio_annual":                      {"app":"lift", "product":"paid"}
}'
```

The Play keys (`…:monthly`) are what Play reports as `product:basePlan`. If a
test purchase logs `unmapped_product`, the log names the exact id; use that.

- [ ] **Decide the sandbox setting before submitting.**
      `REVENUECAT_ACCEPT_SANDBOX` is `true` today. App Review purchases in the
      sandbox, so with it off a reviewer's purchase unlocks nothing. With it on,
      a TestFlight tester can unlock the coach without paying, but only people
      you invited. Leave it on through review.

## 6. Supabase Auth: email that actually sends

**Signing up is effectively broken until this is done.** Email confirmation is
on, and with no custom SMTP Supabase's built-in mailer sends a handful of
messages an hour for the whole project, Run included.

- [ ] Pick a sender. Resend is the least work: resend.com › add domain
      `mgkcodes.com` › add the DNS records it shows › create an API key.
- [ ] Supabase › Authentication › Emails › SMTP settings: host
      `smtp.resend.com`, port `465`, user `resend`, password = the API key,
      sender `MGKFitness <no-reply@mgkcodes.com>`.
- [ ] Authentication › URL configuration › **Site URL**
      `https://mgkfitness.mgkcodes.com`, so the confirmation link lands on a
      real page rather than on `localhost`.
- [ ] Then prove it: sign up from the app with a real address. Supabase rejects
      `example.com` and `.invalid` outright.

## 7. Sign in with Apple and Google, both apps

Added 2026-09-30 for the redesign ([lift-2.0.0-redesign.md](lift-2.0.0-redesign.md),
R10). Lift and Run share one account, so both providers are set up once, for the
suite, and both apps ship with them. Four dashboards, in this order, because each
hands the next a value:

| Value | From | Goes into |
|---|---|---|
| Team ID | Apple, top right of the portal | Supabase's Apple secret; an Edge Function secret |
| Services ID `com.mgkcodes.fitness.web` | 7a | Supabase's Apple *Client IDs*, first |
| Key ID, and the `.p8` file | 7a | Supabase's Apple secret; an Edge Function secret |
| Web client id and secret | 7c | Supabase's Google provider |
| iOS client ids, Lift's and Run's | 7c | Supabase's Google *Client IDs*; each app's `Info.plist` (me) |

Only the `.p8` file and the Google client secret are secret. They go into
Supabase and nowhere else: not into this repository, not into a chat.

### 7a. Apple Developer: the capability, a Services ID, a key

- [x] Identifiers › `com.mgkcodes.liftio` › tick **Sign In with Apple** › Edit ›
      *Enable as a primary App ID* › Save. Apple warns that this invalidates the
      app's provisioning profiles; 7b replaces them. *Done 2026-09-30.*
- [x] Identifiers › `com.mgkcodes.fitness.run` › tick **Sign In with Apple** ›
      Edit › *Group with an existing primary App ID* › `com.mgkcodes.liftio` ›
      Save. One Apple ID then signs into both apps as one person. *Done.*
- [x] Identifiers › **+** › *Services IDs* › description `MGKFitness`,
      identifier `com.mgkcodes.fitness.web` › Register. Open it › tick Sign In
      with Apple › Configure › primary App ID `com.mgkcodes.liftio`, domain
      `cwpwzxjjhxbkwhrgnasn.supabase.co`, return URL
      `https://cwpwzxjjhxbkwhrgnasn.supabase.co/auth/v1/callback` › Save. This
      is what Android's Apple sign-in goes through. *Done. Liftio 1.x's older
      Services ID, `com.mgkcodes.liftio.siwa`, is still there and left alone:
      check Supabase's current Apple settings before 7d changes them.*
- [x] Keys › **+** › name `MGKFitness Sign in with Apple` › tick Sign In with
      Apple › Configure › `com.mgkcodes.liftio` › Save › Register › **Download**
      the `.p8`. Apple allows one download. *Done: Team ID `ZTS7SQYSA5`, Key ID
      `43K62X7QPT`.*

### 7b. Signing: MGKFitness's own key, certificate and profiles

*Settled differently from the first draft, 2026-09-30.* Regenerating Lift's
profile, Apple picked the team's newest distribution certificate, which is
Frunt's, and Run's profile already used it; both apps also published through
Frunt's App Store Connect key. **Nothing MGKFitness ships depends on anything of
Frunt's**, so both apps now have their own, and `codemagic.yaml` points at them.

- [x] App Store Connect › Users and Access › Integrations › Team Keys › **+** ›
      `MGKFitness Codemagic`, App Manager › Download the `.p8`. *Key ID
      `4HNLTYJL55`, issuer `12c1530c-e102-40b4-9b6c-932a0c120fde`.*
- [x] Codemagic › Settings › Integrations › Developer Portal › Manage keys ›
      Add another key: `mgkfitness_asc`, with that issuer, key id and `.p8`.
- [x] Codemagic › Code signing identities › iOS certificates › **Generate
      certificate** with `mgkfitness_asc`, Apple Distribution, reference name
      `mgkfitness_distribution`. *Expires 2027-09-30.*
- [x] Apple › Profiles › *Lift MGKFitness App Store* › Edit › the certificate
      **expiring 2027-09-30** › Save › Download. Codemagic › iOS provisioning
      profiles › delete the old one and upload this under the same reference
      name (Lift signs by hand; `codemagic.yaml`, `lift-ios-release`).
- [x] Apple › Profiles › *Run MGKFitness App Store* › Edit › the same
      certificate › Save. Codemagic keeps its own copy of Run's profile too:
      delete the old `mgk_fitness_run_appstore_profile` › **Fetch profiles**
      with `mgkfitness_asc` › reference name `Run MGKFitness App Store`.
- [ ] Run's workflow change (`app_store_connect: mgkfitness_asc`) reaches Run's
      builds through `main`. Until then Run publishes through `frunt_asc`, which
      still works; its signing is already MGKFitness's.

### 7c. Google Cloud: one project, and a client per platform

*Done 2026-09-30, in the **existing** `mgk-fitness` project (number
365688330886), where Run's Play publishing account already lives, rather than a
new one.*

- [x] Google Auth Platform › **Branding**: app name `MGKFitness`, support email
      and developer contact `mgkcodes@gmail.com` (the dropdown only offers the
      Google account's own addresses). **No logo**: a logo sends the app to
      Google for verification, which takes days. Home, privacy and terms links
      are Run's pages (`https://mgkfitness.mgkcodes.com`, `/run/privacy`,
      `/run/terms`), the only live ones; **move them to pages that cover both
      apps once Lift's are live.** Authorized domains `mgkcodes.com` and
      `cwpwzxjjhxbkwhrgnasn.supabase.co`: `supabase.co` itself is refused,
      because it is on the public suffix list.
- [x] **Audience**: External › *Publish app*, now *In production*. The scopes
      are Google's basic three, which need no review.
- [x] **Clients**, eight:
      - *Web application* `Supabase`, redirect URI
        `https://cwpwzxjjhxbkwhrgnasn.supabase.co/auth/v1/callback`:
        `365688330886-s5g8kf5kvmpo5qao0atqepufvfbkhmca.apps.googleusercontent.com`.
        Its secret is in Matthew's password manager and in Supabase, nowhere
        else.
      - *iOS* `Lift iOS` (`com.mgkcodes.liftio`, team `ZTS7SQYSA5`):
        `365688330886-ql9t29qtqbq15ove1nv3b0irh5dhr7vu.apps.googleusercontent.com`
      - *iOS* `Run iOS` (`com.mgkcodes.fitness.run`):
        `365688330886-vmjfroatcea25al1ggm524bhcfkkqqht.apps.googleusercontent.com`
      - *Android*, one per package and fingerprint (Android needs no client id
        in the app; the web id is its `serverClientId`):

        | Client | Package | SHA-1 |
        |---|---|---|
        | `Run Android Play` | `com.mgkcodes.fitness.run` | `B6:DD:0A:6D:D8:E3:B9:7A:9F:45:D3:27:6D:78:D7:8D:CD:AE:5B:4E` |
        | `Run Android upload` | `com.mgkcodes.fitness.run` | `EC:4D:11:C1:E7:EA:1C:B7:57:4F:5F:B5:71:ED:96:33:C1:C3:33:CF` |
        | `Run Android debug` | `com.mgkcodes.fitness.run` | `05:EC:3F:BF:39:2D:7D:3B:EA:36:26:C8:FA:B7:FB:C9:00:99:C9:98` |
        | `Lift Android Play` | `com.mgkcodes.liftio` | `61:B5:49:8F:DD:AB:BF:D9:E4:2A:96:C8:0D:22:B5:E1:AD:1E:BF:60` |
        | `Lift Android upload` | `com.mgkcodes.liftio` | `EC:4D:11:C1:E7:EA:1C:B7:57:4F:5F:B5:71:ED:96:33:C1:C3:33:CF` |
        | `Lift Android debug` | `com.mgkcodes.liftio` | `05:EC:3F:BF:39:2D:7D:3B:EA:36:26:C8:FA:B7:FB:C9:00:99:C9:98` |

        The upload key is `mgkfitness_upload`, which both apps share; the debug
        key is this computer's. Play's app-signing fingerprints are on each
        app's Protected with Play › Play Store protection › *Manage Play app
        signing* page (App integrity moved there). Firebase App Check is off.

### 7d. Supabase: switch both on

*Done 2026-09-30. Both providers were already on, from Liftio 1.x: Apple with
`com.mgkcodes.liftio.siwa,com.mgkcodes.liftio`, Google with a client from
another project (`864868708679-…`). Ten accounts sign in with Apple, from
April and May 2026, several on hidden relay addresses; none with Google.*

- [x] Authentication › Sign In / Providers › **Apple**. *Client IDs*:
      `com.mgkcodes.fitness.web,com.mgkcodes.liftio,com.mgkcodes.fitness.run,com.mgkcodes.liftio.siwa`,
      with the Services ID **first**, or Apple refuses Android's sign-in, and
      Liftio's old one last until 2.0.0 has replaced Liftio 1.x. The existing
      Apple accounts keep working because Lift's App ID is the group's primary:
      Apple's user ids and relay addresses belong to it. *Secret Key (for
      OAuth)*: generated with Supabase's in-browser tool from the Team ID, Key
      ID, Services ID and the `.p8`. **It expires after six months, around
      2027-03-30: regenerate it by 2027-03-20** or Android's Apple sign-in
      stops.
- [x] **Google**. *Client IDs*: the web client id first, then Lift's and Run's
      iOS ids; the old project's client is gone, since nobody signs in with
      Google. *Client Secret*: the new web client's. *Skip nonce checks*:
      **on**, for Google's iOS sign-in; switch it back off if the plugin can
      pass a nonce.
- [x] Authentication › URL Configuration › Redirect URLs:
      `com.mgkcodes.liftio://login-callback` and
      `com.mgkcodes.fitness.run://login-callback`, the way back from Android's
      Apple sign-in.
- [x] Edge Functions › Secrets: `APPLE_TEAM_ID`, `APPLE_KEY_ID`, and
      `APPLE_PRIVATE_KEY` (the `.p8` file's contents), so `delete-account` can
      revoke Apple's tokens when an account is deleted. The two ids' digests
      were checked against their values; nothing reads them until the
      redesign's Phase 1.

*Found on the way:* the **Site URL** was still `http://localhost:3000` (step 6),
so every emailed link — a sign-up confirmation, a password reset — led to a dead
page. It is `https://mgkfitness.mgkcodes.com` now. And a password reset still
cannot finish: no page on the site lets somebody choose a new password, and
neither app asks Supabase to send them back into it. The redesign's Phase 1
adds that page.

*Later, with step 6:* Apple's hidden addresses only accept mail from senders
registered with Apple (Services › Sign in with Apple for Email Communication).
Nothing the app sends needs it yet.

## 8. When each of these lands

| Done | Unblocks |
|---|---|
| 0 | legacy subscribers (I grant, same day) |
| 1 + 3 + 4 | a TestFlight build that can sell; a sandbox purchase |
| 2 | the first Android internal build |
| 5 | purchases reaching `core.entitlements` |
| 6 | new people being able to sign up at all |
| 7 | the sign-in build for both apps (the redesign's Phase 1) |
| web pages deployed (mine) | privacy URL, support URL, deletion URL in both stores |

The sandbox pass after that follows Run's runbook, step 8: buy, watch
RevenueCat's customer history show your Supabase id, the webhook answer 200,
`core.entitlements` gain one row, and the app unlock. Then restore on a second
install, and cancel.
