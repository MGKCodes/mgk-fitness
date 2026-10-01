# Store setup for Lift: what to do in each dashboard

Everything Lift 2.0.0 needs that lives in a dashboard rather than in this
repository, in the order it has to happen. The code side is done: the sales
screen, RevenueCat behind the `Purchases` seam, the renewal disclosure, and the
`revenuecat` webhook, which Run shares and which is deployed.

Written 2026-09-29. This file stands on its own: every trap that matters to
these steps is written into the step. Some accounts and secrets serve the whole
suite, and each step says which values are shared and which are Lift's own.

**Where this stands, 1 October 2026.** Steps 6 (email) and 7 (Apple and Google
sign-in) are done and kept for the values they record. Steps 0 to 5 are open,
except the Play app and its first upload in step 2. What else stands between
Lift and the stores is in [submission-week.md](submission-week.md).

**The chain, and the values that must match exactly:**

| Value | Set in | Must equal |
|---|---|---|
| Product ids | App Store Connect / Play Console | every key in `REVENUECAT_PRODUCTS` (step 5) |
| Bundle / package | App Store Connect, Play, RevenueCat | `com.mgkcodes.liftio` |
| Public SDK keys | RevenueCat, then Codemagic | `appl_…` (iOS), `goog_…` (Android), **Lift's own**, not Run's |
| App user id | the app, automatically | the Supabase user id (already wired) |

---

## 0. Liftio's subscribers: ended, not carried over

**Decided 1 October 2026, and it reverses what this step used to say.** The plan
was to leave Liftio's two products on sale, let their subscribers keep renewing,
and grant each of them the coach in 2.0.0. Matthew does not want the old
subscription to continue: anyone who wants the coach subscribes to Coach or
Premium Coach. So nothing is granted, nothing maps the legacy products, and the
app no longer counts them as Lift's.

- [x] **Old Liftio RevenueCat project** (the React Native app's, not
      `mgk-fitness`) › Overview › *Active subscriptions*. Then Customers,
      filtered to the `pro` entitlement, active. Note each customer's app user
      id: Liftio set it to the Supabase user id, and 2.0.0 uses the same
      Supabase project, so every one of them maps to an account that still
      exists. *Counted 1 October: four customers are active. Two pay, both on
      the monthly product and set to renew; nobody holds the annual one. The
      other two are active with nothing ever spent and set to cancel, which
      looks like access granted by hand.*
- [x] **`liftio_monthly` and `liftio_annual` are off sale** in App Store
      Connect: both read *Developer Removed from Sale* since 1 October, and
      nobody can buy them. The expectation is that the two who pay are not
      renewed and keep what they paid for until the period ends. That is what
      Apple is understood to do, and it has not been watched happening.
- [x] **The two legacy products are out of the `mgk-fitness` RevenueCat
      project again.** They were added on 1 October under the earlier plan
      (step 3) and removed the same day: *Lift (App Store)* lists Coach and
      Premium Coach only.
- [x] No grants. `core.grant_entitlement()` is not run for any Liftio customer.

## 1. App Store Connect: two new products

App Store Connect › Apps › Liftio (6759969740) › Monetization › Subscriptions ›
the existing subscription group (the one holding `liftio_monthly`).

- [x] **Add both to the existing group.** One group is what lets somebody move
      between tiers, and between a legacy product and a new one, without paying
      twice.

| | Coach | Premium Coach |
|---|---|---|
| Reference name | Lift Coach Monthly | Lift Coach Premium Monthly |
| Product ID | `lift.coach.monthly` | `lift.coach.premium.monthly` |
| Duration | 1 month | 1 month |
| Price | **£0.99** (decided 1 October) | **£2.99** (decided 1 October) |
| Display name (30 chars) | `Coach` | `Premium Coach` |
| Description (45 chars) | `A training plan, adjusted every week.` | `Far more room to talk to your coach.` |

- [x] **Levels: Premium Coach level 1, Coach level 2, and both legacy products
      level 2.** Level 1 is the *highest*. Ranked the other way round, moving
      up to Premium is treated as a downgrade and waits up to a month.
- [x] **Why those prices.** The coach's usage limits are set per tier, not per
      app, and they were sized against Run's £0.99 / £2.99 at the Small
      Business Program's 15% rate (Run's ADR-0029). Pricing Lift's Coach higher
      is fine; pricing it lower makes every Lift conversation cost more than it
      earns. Liftio's £1.99 is not a constraint: its subscribers keep their
      product.
- [ ] **A review screenshot per product** (1290 × 2796, no transparency). The
      sales screen is what it should show: plate P8 on the screen board. It is
      rendered with the store screenshots, at that size, from the release
      candidate.
- [ ] **Review notes per product:** "The coach, training plans and progress
      photos are the paid half. Tracking, saved workouts, history and stats are
      free with no account."
- [x] Group display name: `MGKFitness: Lift Coach`, on the English (U.K.)
      localisation, with the app name left to follow the app.
- [x] App Information › **App-Specific Shared Secret** › generate one (RevenueCat
      step 3 asks for it). Per app: Run's is not Lift's.
- [x] A **sandbox tester**: Users and Access › Sandbox › Testers. Do not sign
      into iCloud with it; iOS asks for it at the moment of purchase. *One was
      already there, `mgkcodes+sandbox@gmail.com`, last used in March: clear its
      purchase history before the sandbox pass.*

App Store Connect now shows **Prepare for Submission** on a new product whether
or not it is complete, so the label says nothing. A product is done when its own
page no longer shows the red "Unable to Add for Review" banner. Do not press
*Add for Review*: the products go in with the 2.0.0 version.

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
- [x] Monetize › Subscriptions *(created 1 October, one active base plan each)*:
  - `lift.coach.monthly`, base plan id `monthly`, auto-renewing, 1 month.
  - `lift.coach.premium.monthly`, base plan id `monthly`.
  - **Price before VAT**, so Android and iOS charge the same: Play adds 20% to
    what is typed, and £0.99 typed shows as £1.19. Enter 0.83 and 2.49, then
    check the United Kingdom row reads £0.99 and £2.99.
- [x] Users and permissions › give the **existing** service account,
      `mgk-fitness-play-publisher`, access to this app. *Done 1 October: it had
      none, and RevenueCat could not see the app until it did. Whether it also
      holds the release permissions Codemagic needs to publish is not
      confirmed.*
- [ ] Settings › License testing: add your Google account, for test purchases.
- [ ] The declarations (store listing, content rating, target audience, Data
      safety, ads = none, app access = the demo account). The answers are
      drafted in `store-listing.md`; the form-filling is yours.
- [ ] **Account deletion URL** (Play requires one):
      `https://mgkfitness.mgkcodes.com/lift/delete-account`, live (it answered
      200 on 1 October).

## 3. RevenueCat: add Lift to the `mgk-fitness` project

Not the old Liftio project. One project serves both apps: one webhook, one
secret, and `core.entitlements.app` keeps Run and Lift apart.

- [x] **Apps › + › App Store:** name it `Lift`, bundle id `com.mgkcodes.liftio`.
      Paste the App-Specific Shared Secret (step 1). Upload the **In-App
      Purchase key**: the same team `.p8`, Key ID and Issuer ID Run's app uses.
      It is issued to the team, not to an app.
- [x] **Apps › + › Play Store:** name it `Lift (Play)`, package
      `com.mgkcodes.liftio`, the same service-account JSON as Run's Play app.
      *Saved as `Lift (Play Store)`, with a second key made for the same
      service account because the first file could not be found. RevenueCat
      reads the catalogue; its check on purchases still says the package was
      not found, most likely because Play has only a draft release. Check it
      again once a build is on internal testing.*
- [x] **Products:** add `lift.coach.monthly` and `lift.coach.premium.monthly`
      for the App Store app, the two Play subscriptions for the Play app, and
      the legacy `liftio_monthly` and `liftio_annual` for the App Store app.
      *The legacy pair was added under the plan as it stood that morning, and
      comes out again: step 0.*
- [x] **Entitlements:** attach Coach to `paid` and Premium Coach to `premium`
      (the legacy pair was attached to `paid` too, and is detached in step 0). These grant nothing on their own (the webhook
      maps product ids), but they make the customer page readable when
      somebody writes in.
- [x] **Offering:** in the **current** offering (the one Run uses), put Lift's
      products into the existing packages. A package holds one product per app,
      so the Coach package gets `lift.coach.monthly` for Lift beside Run's, and
      the Premium package gets `lift.coach.premium.monthly`. **Do not add the
      legacy products to the offering.** The app shows exactly what the offering
      holds, in its order.
- [x] **API keys:** Project settings › API keys. Copy **Lift's** App Store key
      (`appl_…`) and Play key (`goog_…`) for step 4.
- [x] **App Store Server Notifications:** RevenueCat shows a notification URL on
      the Lift App Store app's page. Paste it into App Store Connect › Lift ›
      App Information › App Store Server Notifications (production and
      sandbox). *Both set 1 October. Neither had ever been set, so the old
      Liftio project was not receiving them and nothing was taken from it.*
- [x] Nothing to do for the webhook: the project's existing one already points
      at the `revenuecat` function and serves both apps.

## 4. Codemagic: Lift's keys

- [x] The mgk-fitness app's environment variables › new group
      **`mgk_fitness_lift_env`** *(created 1 October)*:
  - `REVENUECAT_PUBLIC_KEY` = Lift's `appl_…` key, Secure
  - `REVENUECAT_GOOGLE_KEY` = Lift's `goog_…` key, Secure
- [x] `mgk_fitness_lift_env` is named in both Lift workflows in
      `codemagic.yaml`. It was commented out until the group existed, because a
      workflow naming a missing group may fail before any script runs. The
      change is on the Lift branch: a build reads the file from the branch it
      builds, so it applies once that branch is in `develop`.

## 5. Supabase: map Lift's products

The webhook maps a product id to an app and a tier through one secret shared
with Run. **Setting it replaces the whole value**, so the command below carries
the four `run.*` ids as well as Lift's. They are not Lift's to change: they go
back exactly as they are, and if the secret holds anything else, keep that too.

From **Git Bash, not PowerShell**. PowerShell strips the quotes and unmaps both
apps, which is exactly what happened to Run for thirteen minutes on
2026-09-11. **Matthew runs it:** Claude Code's auto mode refuses to write a
secret even with a go-ahead (1 October). The legacy ids are not in it, by the
decision in step 0.

**Set on 1 October 2026 at 16:10 UTC**, and checked: the digest Supabase lists
for the secret is the SHA-256 of exactly the eight entries below, written on
one line with no spaces.

```bash
npx supabase secrets set --project-ref cwpwzxjjhxbkwhrgnasn REVENUECAT_PRODUCTS='{
  "run.coach.monthly":                  {"app":"run",  "product":"paid"},
  "run.coach.premium.monthly":          {"app":"run",  "product":"premium"},
  "run.coach.monthly:monthly":          {"app":"run",  "product":"paid"},
  "run.coach.premium.monthly:monthly":  {"app":"run",  "product":"premium"},
  "lift.coach.monthly":                 {"app":"lift", "product":"paid"},
  "lift.coach.premium.monthly":         {"app":"lift", "product":"premium"},
  "lift.coach.monthly:monthly":         {"app":"lift", "product":"paid"},
  "lift.coach.premium.monthly:monthly": {"app":"lift", "product":"premium"}
}'
```

The Play keys (`…:monthly`) are what Play reports as `product:basePlan`. If a
test purchase logs `unmapped_product`, the log names the exact id; use that.

- [x] **The sandbox setting stays on.** `REVENUECAT_ACCEPT_SANDBOX` is `true`
      and is one secret for both apps. App Review purchases in the sandbox, so
      with it off a reviewer's purchase unlocks nothing. With it on, a
      TestFlight tester can unlock the coach without paying, but only people
      you invited. Decided for the whole suite (ADR-0037).

## 6. Supabase Auth: email that actually sends

**Done 30 September, and proved end to end** (below). Without custom SMTP,
Supabase's own mailer sends only to members of the Supabase team, so no user
got a confirmation or a reset.

- [x] **A sender: SMTP2GO's free plan** (1,000 a month, 200 a day), on its
      **EU** region, account under `mgkcodes@gmail.com`. Resend is the
      favoured provider, but a second Resend team is paid and Frunt's account
      is never used; the move to Resend Pro comes when volume nears 1,000
      emails a month, and is only a change of SMTP details here.
      `mgkfitness.mgkcodes.com` is verified with two CNAMEs in Cloudflare
      (`em1053897.mgkfitness` and `s1053897._domainkey.mgkfitness`, DNS only).
      The `link.` tracking record is **deliberately absent**, and open and
      click tracking are off: a rewritten reset link is not something this
      mail should carry.
- [x] Supabase › Authentication › Emails › SMTP settings: host
      `mail-eu.smtp2go.com`, port `587`, user `mgkfitness-supabase`, sender
      `MGKFitness <noreply@mgkfitness.mgkcodes.com>`, 60 seconds between
      emails to one person.
- [x] Authentication › URL configuration › **Site URL**
      `https://mgkfitness.mgkcodes.com`.
- [x] The templates, pasted whole from `supabase/templates/` (subjects in its
      README): **Reset password**, **Confirm sign up**, and the **Password
      changed** security notification, switched on.
- [x] **Proved:** a throwaway account's reset email reached a Gmail inbox
      (not spam) as "MGKFitness", with DKIM, SPF and DMARC passing and the
      link unrewritten; the link opened `/reset-password`, the new password
      was accepted, the old one then refused, and the "password was changed"
      notice followed a minute later. The account was deleted through
      `delete-account`, which answered `account_deleted: true`.
- [x] **Email confirmation is on**, since 30 September, for both apps. It
      has to be: Apple and Google sign-in link to any account with the same
      email, and with confirmation off somebody could register an address
      first and keep a way into the account its owner later signs in to. The
      email is `confirmation.html`, sent through SMTP2GO.

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
- [x] Run's workflow names `mgkfitness_asc` too, on `main` and on `develop`
      (checked 1 October), so neither app publishes through `frunt_asc`.

### 7c. Google Cloud: one project, and a client per platform

*Done 2026-09-30, in the **existing** `mgk-fitness` project (number
365688330886), where Run's Play publishing account already lives, rather than a
new one.*

- [x] Google Auth Platform › **Branding**: app name `MGKFitness`, support email
      and developer contact `mgkcodes@gmail.com` (the dropdown only offers the
      Google account's own addresses). **No logo**: a logo sends the app to
      Google for verification, which takes days. Home, privacy and terms links
      are Run's pages (`https://mgkfitness.mgkcodes.com`, `/run/privacy`,
      `/run/terms`), the only live ones at the time. **Still to do: Lift's
      pages are live now, and somebody signing into Lift with Google is shown
      Run's policy. Point these at pages that cover both apps** (tracked in
      submission-week.md). Authorized domains `mgkcodes.com` and
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
      were checked against their values. Read by `delete-account/apple.ts`,
      deployed as version 18.

*Found on the way:* the **Site URL** was still `http://localhost:3000` (step 6),
so every emailed link — a sign-up confirmation, a password reset — led to a dead
page. It is `https://mgkfitness.mgkcodes.com` now. And a password reset could
not finish: no page on the site let somebody choose a new password. The
redesign's Phase 1 added one (`web/app/reset-password`), which is live and was
proved with step 6's template.

*Later, with step 6:* Apple's hidden addresses only accept mail from senders
registered with Apple (Services › Sign in with Apple for Email Communication).
Nothing the app sends needs it yet.

## 8. When each of these lands

| Step | State | Unblocks |
|---|---|---|
| 0 | done 1 October: ended, not carried over | nothing waits on it |
| 1 + 3 + 4 | done 1 October | a TestFlight build that can sell; a sandbox purchase |
| 2 | products done; declarations open | an Android build that can sell |
| 5 | done 1 October | purchases reaching `core.entitlements` |
| 6 | done | new people being able to sign up at all |
| 7 | done | the sign-in build for both apps |
| web pages | live | privacy URL, support URL, deletion URL in both stores |

The sandbox pass after that: buy, watch
RevenueCat's customer history show your Supabase id, the webhook answer 200,
`core.entitlements` gain one row, and the app unlock. Then restore on a second
install, and cancel.
