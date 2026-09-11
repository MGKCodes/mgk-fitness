# Play setup — keystore, listing, Play Billing, RevenueCat

The Google half of `store-setup.md`, which covers Apple and says at its end that
Play is not covered. This is that gap.

**What is already true**, and is why this is shorter than the Apple one: the
backend is store-agnostic and was built that way. `core.entitlements.platform`
already allows `google`, `entitlement_event.ts` already maps `PLAY_STORE` to it,
and `REVENUECAT_PRODUCTS` is a flat product-id map that takes Play ids as extra
keys. Nothing server-side is Apple-shaped. The work is a keystore, a listing,
and a second RevenueCat app.

**What changed in the repo to make this possible** (2026-09-10):

- `android/app/build.gradle.kts` — real release signing, ported verbatim from
  Lift's. Refuses to fall back to the debug key on a CI machine.
- `android/key.properties.example` — the local half.
- `AppConfig.revenueCatGoogleKey` + `AppConfig.storeKey` — the Apple and Google
  SDK keys are *different strings* and the wrong one does not degrade, it
  configures nothing. `storeKey` picks by platform at runtime.
- `codemagic.yaml` `run-android-release` — declares `android_signing: mgkfitness_upload`,
  builds an **AAB** as well as an APK, emits `REVENUECAT_GOOGLE_KEY`, and
  carries a commented `publishing:` block.

---

## The order, and what actually blocks what

The dependencies are real and mostly one-way. Doing these out of order is how a
day disappears.

```
MERCHANT ACCOUNT ──────────────────────────▶ (minutes here; do not assume)
     │                                              │
     │  keystore ──▶ signed AAB ──▶ listing + FIRST MANUAL UPLOAD
                                      │
                                      ├──▶ in-app products can be created
                                      │             │
                                      │             ▼
                                      │    RevenueCat Google app ──▶ goog_ key
                                      │             │                    │
                                      │             ▼                    ▼
                                      │    REVENUECAT_PRODUCTS      Codemagic var
                                      │             │                    │
                                      │             └────────┬───────────┘
                                      ▼                      ▼
                          service account granted     rebuild + publish
                          access to THIS app                 │
                                      └────────┬─────────────┘
                                               ▼
                                        sandbox purchase
                                               ▼
                                          production
```

**The single most important sequencing fact: Play will not let you create
in-app products until a bundle has been uploaded.** So the first AAB is
necessarily one that cannot sell anything — no products exist yet, so there is
no `goog_` key to give it. That is correct and expected, not a mistake. The
build says so plainly (the config step prints a warning), and the app's coach
gate renders its no-button state, which is the honest thing for a build that
genuinely cannot transact.

---

## 1. The upload keystore

Once, locally. **Nothing in the repo or in CI generates a key** — an upload key
Play has already seen cannot be swapped without a Google support request, so
creating one silently is worse than failing.

```bash
keytool -genkey -v -keystore mgkfitness-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

- Keep it **outside the repo**. `.gitignore` already covers `*.jks` and
  `android/key.properties`, but the safe place is not "ignored", it is "not
  there".
- Back it up somewhere you would still have after a disk failure.
- **One key for every app in the MGKFitness suite** — Run, Lift, and whatever follows.
  A Play listing records the upload certificate it expects; nothing requires
  that certificate to be unique to a listing, and the benefit of sharing is one
  secret to hold rather than several.

  This document argued the opposite for a few hours on 2026-09-10 — a separate
  key per listing, because "a shared key means a reset on one reaches the
  other for nothing". The premise was a blast-radius argument with no scenario
  behind it, and both failure modes resolve identically anyway: Google resets a
  lost **or** compromised upload key by support request.

  It also collided with a fact nobody had checked. `lift-android-release`
  declared `liftio_upload` and **no keystore of that name had ever been
  uploaded to Codemagic** — only frunt's. That workflow would have failed on
  its first run, and nothing surfaced it, because Lift has never had a Play
  listing to publish to.

- **frunt is the permanent exception.** It is live on Play under `frunt_upload`,
  and a shipped listing's upload key cannot be swapped without that same support
  request, for nothing in return. Leave it alone.

Then, in Codemagic → **Teams ▸ Code signing identities ▸ Android keystores**,
upload it with reference name **`mgkfitness_upload`**. That exact string is what
`codemagic.yaml` declares; a different one fails the build with a message that
says so.

For a local release build, copy `android/key.properties.example` to
`android/key.properties` and fill in the four values.

### The key that was actually created, 2026-09-10

Recorded because a fingerprint is the only way to answer "was this signed with
the right key?" after the fact, and because Android developer verification
(step 8b) asks for one. **None of this is secret** — a certificate fingerprint
is derivable from any signed artefact and Play Console displays it. The
password and the `.jks` are the secrets, and neither is here.

```
Alias          upload
Owner          CN=Matthew Kay, OU=Unknown, O=MGKCodes, L=London, ST=London, C=GB
Created        10 Sep 2026
Valid until    26 Jan 2054
Algorithm      2048-bit RSA, SHA256withRSA

SHA-1     EC:4D:11:C1:E7:EA:1C:B7:57:4F:5F:B5:71:ED:96:33:C1:C3:33:CF
SHA-256   A5:0B:EE:F9:77:8A:B6:91:06:F4:0B:67:98:D9:4E:47:17:C3:46:FE:
          BD:28:75:87:44:E8:9E:0D:7A:16:12:06
```

The validity is not arbitrary: **Play requires an upload key valid beyond 22
October 2033**, and `-validity 10000` clears that by two decades. A key with a
default one-year validity is accepted at upload and becomes an unfixable
problem later.

To re-derive at any time:

```powershell
keytool -list -v -keystore mgkfitness-upload.jks -alias upload
```

- [x] Keystore created and backed up
- [x] Uploaded to Codemagic as `mgkfitness_upload`

## 2. Create the app in Play Console

MGKCodes is an **organisation account and already verified** (frunt ships from
it), so none of the personal-account closed-testing requirements apply — there
is no 12-tester, 14-day clock. Production access is available immediately.

- **App name:** as per `docs/app-store-listing.md`, kept identical to the Apple
  listing so the two stores name one product one way.
- **Default language:** English (United Kingdom), matching the Apple listing.
- **App or game:** App.
- **Free or paid:** **Free.** The app is free; the coach is an in-app
  subscription. Choosing Paid here is irreversible and would be wrong.

**The package name is fixed by the first upload and can never be changed:**
`com.mgkcodes.fitness.run`.

- [x] App created

## 3. First AAB upload — by hand

Codemagic can publish to a track. It **cannot create the listing**, and the Play
Developer API refuses an app whose first bundle has never gone through the
console. This is why the `publishing:` block in `codemagic.yaml` ships
commented, with a note saying not to uncomment it yet.

Either build locally once `key.properties` exists:

```bash
cd apps/mgk_run
flutter build appbundle --release --dart-define-from-file=config/app_config.json
```

…or run the `run-android-release` workflow and download the `.aab` artefact.

Upload it at **Testing ▸ Internal testing ▸ Create new release**.

**The opt-in link, once the track exists:**

```
https://play.google.com/apps/internaltest/4701369090633386524
```

Open it in a browser signed into an account on the testers list, accept, and
Play offers the install. It grants nothing to anybody not on that list, which is
why it can sit here.

**Install from Play, never by sideloading.** A `flutter run` or `adb install`
build has the right signature and still cannot transact: Play Billing checks
that Play delivered the app. The failure is an empty product list or
`BILLING_UNAVAILABLE`, which reads exactly like a configuration mistake and
sends you looking in the wrong four places.

- [x] First AAB uploaded manually — 1.0.0 (22), internal testing, 2026-09-10

## 4. The declarations that gate every release

These are not optional and they are the usual reason a first Play submission
stalls. Several can be filled in now, before any of the billing work.

- [ ] **Privacy policy URL** — `https://mgkfitness.mgkcodes.com/run/privacy`.
      Already live and already CI-pinned; see the decision *The published legal
      page is the artefact CI pins*.
- [ ] **Data safety form.** Must agree with the privacy policy, which names the
      sub-processors. The answers are worked out below.
- [ ] **Account deletion URL** — `https://mgkfitness.mgkcodes.com/run/delete-account`.
      Required for any app offering account creation, and the rule is specific:
      somebody who has **uninstalled** the app must still be able to ask. Run's
      in-app Delete account is better for anyone who still has the app and no
      use at all to the person this rule protects, which is why the page exists
      (added 2026-09-11; Apple has no equivalent requirement, which is why it
      was missing).
- [ ] **Content rating questionnaire.**
- [ ] **Target audience and content.**
- [ ] **Foreground service permission declaration.** Run declares
      `FOREGROUND_SERVICE_LOCATION`, and Play requires a written justification
      plus, usually, a demo video showing the in-run screen with the screen
      locked. This is the one most likely to be queried — budget for it.
      `ACCESS_BACKGROUND_LOCATION` is deliberately **not** requested (see the
      note in `AndroidManifest.xml`), which keeps this much simpler than it
      would otherwise be. Say so in the justification.
- [ ] **Health apps declaration**, if prompted — the app reads HealthKit on iOS
      but on Android reads no Health Connect data, so this should be a short
      answer.

### The Data safety answers, worked out

Filled in from the privacy policy rather than from memory, because the form and
the policy are compared and a disagreement between them is a rejection. Where a
judgement was made rather than read off, it says so.

**This describes the Android app.** Apple Health does not exist here — Run asks
for no health permissions on Android at all — so nothing HealthKit-shaped
belongs in these answers, even though the policy discusses it for iOS.

Three top-level questions:

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **Yes** |
| Is all of the user data collected by your app encrypted in transit? | **Yes** — HTTPS/TLS throughout |
| Do you provide a way for users to request that their data is deleted? | **Yes** — in-app, and the URL above |

Then, per type. Everything below is **collected and not shared**, for the reason
given after the table:

| Category | Type | Optional? | Purpose | Where it comes from |
|---|---|---|---|---|
| Personal info | Name | Optional | App functionality, Account management | `AuthRepository.signUp` / `updateName`, auth metadata |
| Personal info | Email address | Optional | Account management | Supabase auth; the app works signed out |
| Personal info | User IDs | Required | Account management, App functionality | the Supabase user id, which is also the RevenueCat app user id |
| Financial info | Purchase history | Optional | App functionality | `core.entitlements` — product and status |
| Location | Approximate location | Required | App functionality | `ACCESS_COARSE_LOCATION` |
| Location | Precise location | Required | App functionality | `ACCESS_FINE_LOCATION`, the route trace |
| Health and fitness | Fitness info | Required | App functionality | runs, distance, pace, plans, sessions |
| Health and fitness | Health info | Optional | App functionality | injury notes, RPE, a heart rate if typed in |
| Messages | Other in-app messages | Optional | App functionality | coach conversations and their rolling summary |
| Device or other IDs | Device or other IDs | Required | App functionality | RevenueCat's own device-scoped identifier |

**Everything else is "not collected"**, and the notable absences are worth
knowing you can answer cleanly: no crash logs, no diagnostics, no advertising ID,
no contacts, files, web history or installed apps.

**Photos is the one that needs saying out loud**, because the app gained a
profile photo on 2026-09-11 and the answer is still *not collected*. Play
defines collection as data **transmitted off the device**; this photo is copied
into the app's own storage and is deliberately excluded from the backup mirror,
so nothing transmits it. The same reasoning keeps Apple's App Privacy on "Data
Not Collected" and keeps it out of `PrivacyInfo.xcprivacy`. **If the photo is
ever synced, all three of those answers become false at once** — that is the
whole reason it is a rule in `ProfilePhotoStore` rather than an accident of
where the file happens to live. The app carries no
analytics, no ad SDK and no crash reporter, which is a rare set of honest zeroes
on this form.

**Why nothing is marked "shared".** Play's definition of sharing excludes
transfer to a service provider processing on the developer's behalf, and all
four sub-processors are exactly that under Article 28 — Supabase, OpenRouter,
RevenueCat, MapTiler. **This is the one judgement call on the form.** If it is
ever wrong, it is wrong about OpenRouter, which receives training data and
message text; the defence is that it processes on our instruction and does not
use it for its own purposes, which is also what the policy tells the runner. Do
not quietly change the answer without changing the policy with it.

**Two answers that look like the opposite choice.** *Location marked Required*
even though runs can be added by hand and the app technically functions without
it — recording a run is the app, and "optional" would understate. *Device IDs
marked collected* even though we neither read nor store one: RevenueCat's SDK
collects it directly, and Play counts what an SDK collects as what the app
collects.

### Content rating, and target audience

The one answer that changes everything on the rating questionnaire: **the app
has no user-to-user interaction.** The coach is a model, not a person, and no
runner can see, message, or find another. Saying yes there pulls in social
features declarations and a much heavier rating for nothing.

Otherwise: no violence, no sexual content, no profanity, no controlled
substances, no gambling. It **does** sell digital goods (the subscription), and
it **does** share the user's location with the app itself but never with other
users. Expect PEGI 3 / Everyone.

**Target audience: 18 and over, only.** The terms set the floor at 16 and the
policy says the app is not directed at under-16s, so 16–17 would be defensible —
but selecting any bracket below 18 pulls the listing into the Families policy,
which brings its own review, ad rules and content requirements for an app that
has no business being marketed to children. Health data and a medical disclaimer
argue the same way. Choose 18+ and the question stops costing anything.

## 4b. A Google Payments merchant account — the real long pole

**Found on 2026-09-10 by walking into it.** Monetise ▸ Subscriptions refuses to
open at all:

> Missing requirements for accessing this page — you need to set up a Google
> Payments merchant account to access this page.

**Why it was not obvious.** MGKCodes has shipped to Play before, and never
needed one: frunt is free on Play and bills through Stripe on the web. Run is
the first product in the account to take money *through Google*, so this is the
first time Google needs to know where to send it. Nothing in the Play Console
mentions it until you try to create a product.

**It gates the entire revenue path**, and everything below in this document
sits behind it:

- creating the two subscriptions
- importing them into RevenueCat
- the `goog_` key having anything to sell
- the sandbox purchase, and therefore step 10's product-id mapping

**It gates nothing else.** The listing, internal testing, the declarations in
step 4, developer verification and every iOS path are unaffected. The bundle is
already live to internal testers without it.

What it wants: MGKCodes Ltd's registered details, a bank account for payouts,
and tax information.

**It went through in minutes on 2026-09-10, not days.** This section warned of a
multi-day verification when it was written an hour earlier, on the general case;
for an already-verified organisation account with company details on file,
Google cleared it immediately and Subscriptions opened straight after. Recorded
because the warning was the more useful thing to be wrong about — but do not
plan a day around it being slow, and do not plan one around it being fast
either. Start it early because it costs nothing to have done, not because it is
guaranteed to take a while.

- [x] Merchant account submitted
- [x] Verified — same sitting

## 5. Create the subscriptions

**Monetise ▸ Subscriptions.** ADR-0029 settled the tiers and the prices, and the
Apple side is already configured to match (`store-setup.md` §2):

| | Coach | Premium Coach |
|---|---|---|
| Price | £0.99/month | £2.99/month |
| Display name | `Coach` | `Premium Coach` |

Play's model is a **subscription** with one or more **base plans**, which is not
Apple's shape — Apple has a subscription group with two products. Keep the
subscription ids aligned with the Apple product ids (`run.coach.monthly`,
`run.coach.premium.monthly`) and give each a single monthly base plan.

### Play takes the price EXCLUSIVE of tax. The App Store takes it inclusive.

**The single most expensive thing to get wrong in this document**, because it is
silent: type the Apple price into Play and Play grosses it up. Entering `0.99`
against Great Britain showed **£1.19** in the price table, VAT at 20% added on
top — so a UK customer would have paid **20% more on Android than on iOS for the
same subscription**, and nothing anywhere would have flagged it. The paywall
prints `storeProduct.priceString` and does not reason about it; the two stores
would simply have disagreed.

It also quietly invalidates the cost model. [ADR-0029](decisions/0029-what-a-tier-costs-and-buys.md)
does its arithmetic on the **ex-VAT** column, and every ceiling in
`supabase/functions/coach/limits.ts` is sized at roughly three quarters of the
net revenue that column produces. A 20% overshoot on the gross is not free
money; it is a model that no longer describes the product.

**So enter the ex-VAT figure that grosses up to the Apple price point**, not the
price itself. Divide by 1.2 and let Play add the tax back:

| Product | Apple charges | Enter into Play (ex-VAT) | Play then shows |
|---|---|---|---|
| `run.coach.monthly` | £0.99 | **£0.825** | £0.99 |
| `run.coach.premium.monthly` | £2.99 | **£2.49** | £2.99 |

(£2.49 grosses to £2.988, which Play rounds to £2.99. Check the rounding in the
price table before saving; a market where it lands a penny out wants the figure
nudged.)

ADR-0029's *Ex-VAT* column is the same arithmetic on its own round £1/£3
figures; these are the same column recomputed against the App Store price points
actually in use.

**Entered 2026-09-10; verified 2026-09-11 from the app rather than from the
console:** build 23's paywall on an Android emulator rendered

```
Coach          £0.99 / month
Premium Coach  £2.99 / month
```

which is what App Store Connect charges, to the penny. The console's own price
table is the wrong place to check this — it shows the gross-up working, not what
the customer sees. The app is the check, because `priceString` is the localised
price actually charged.

Repeat the same reasoning for any market added later: Play's bulk-price tool
converts whatever figure it is given, so a tax-exclusive base converts to a
tax-exclusive price everywhere and the relationship holds.

**Do not guess the product id string the webhook will see.** RevenueCat reports
Play subscriptions in a `subscriptionId:basePlanId` form that differs by SDK
generation, so mirroring a guess into `REVENUECAT_PRODUCTS` is how you get a
paid subscriber with no entitlement. The webhook already solves this properly:
an id it does not recognise is logged as `unmapped_product` **and the log names
it**. Make the sandbox purchase in step 9, read the log, and add exactly what it
says. That is step 10.

- [x] Two subscriptions created with base plans — active, entered ex-VAT, and
      verified rendering as £0.99 / £2.99 in build 23 on 2026-09-11

## 6. RevenueCat — the Google app

**Project ▸ Apps ▸ + New ▸ Google Play.**

- Package name: `com.mgkcodes.fitness.run`
- **Service account credentials JSON** for server-side purchase validation.
  MGKCodes already has a Play service account from frunt; it can be reused, but
  it must be **granted access to this new app** in Play Console ▸ Users and
  permissions, and RevenueCat needs the JSON key file itself.

**RevenueCat warns these credentials can take up to 36 hours to become valid.**
That is the one genuine multi-hour wait in this document. Start it early — it
can be done as soon as step 2 is finished, in parallel with everything else.

Then attach the two Play products to the **same entitlement** the Apple products
use, so one entitlement is granted by either store, and add them to the existing
offering.

Finally, **Project settings ▸ API keys**: copy the **Google** public SDK key,
which begins `goog_`.

- [x] Google app added to RevenueCat — `Run (Play Store)`
- [x] Service account granted access to this app, JSON uploaded — `mgk-fitness-play-publisher@mgk-fitness.iam.gserviceaccount.com`, its own GCP project
- [x] Products attached to the existing entitlement and offering — 2026-09-10
- [x] `goog_` key copied

## 7. Codemagic — the Google key

Add `REVENUECAT_GOOGLE_KEY` to the **`mgk_fitness_run_env`** group, value the
`goog_` key from step 6.

The config step validates it: a value that does not begin `goog_` fails the
build outright rather than producing a bundle that looks able to sell and is
not. An unset value only warns, because that is the correct state for the step-3
upload.

Also confirm the group holding `GCLOUD_SERVICE_ACCOUNT_CREDENTIALS`. The
workflow currently names **`mgk_play_publishing`**; if frunt's credentials live
under a different group name, change the reference in `codemagic.yaml` to match.
A name that does not exist fails the build immediately, which is loud and cheap.

- [x] `REVENUECAT_GOOGLE_KEY` set in `mgk_fitness_run_env` — and **proved** by
      build 24 rather than taken on trust: the config step rejects a key that
      does not begin `goog_`, and the build went green
- [x] Publishing group name confirmed — the publish step succeeded, which it
      cannot do against a group that does not exist

## 8. Turn on publishing

Uncomment the `publishing:` block at the end of `run-android-release` in
`codemagic.yaml`. It publishes to the **internal** track with
`submit_as_draft: true`, so a mistake is a draft to delete rather than a build
someone has installed.

Grant the Codemagic service account access to this app first (Play Console ▸
Users and permissions) or the publish step 403s.

- [x] Publishing block uncommented, build green, bundle lands in internal —
      **build 24, 2026-09-11**, every step green including `Publishing`. First
      fully automated Play release from a commit.

## 8b. Register for Android developer verification

New since this runbook was first written (Google notice, 2026-09-08): every app
must be registered for **Android developer verification by 30 September 2026**
or it stops being installable on certified devices in some countries.

The account banner saying *"All of your apps have been successfully
registered"* refers to the apps that existed when it was shown — **frunt**. A
newly created listing is not covered by it.

**Android developer verification** is its own item at the bottom of the Play
Console account-level sidebar. It wants the package name and the signing
certificate, which is why this sits after the first upload rather than before.

- [ ] `com.mgkcodes.fitness.run` registered

## 9. A real purchase, on a real device

### Before you buy anything: the sandbox flag

**Google license-tester purchases arrive at the webhook as `environment:
"SANDBOX"`, and the webhook ignores them by default.** See
`entitlement_event.ts` — a sandbox purchase is a real event from a fake payment,
and honouring those in production would let anyone with a tester account grant
themselves a coach.

So without this flag the test *looks* like a total failure: the purchase
succeeds, RevenueCat shows it, and `core.entitlements` stays empty, so the coach
never unlocks. Every layer is working correctly and the symptom is
indistinguishable from none of them working at all.

```bash
supabase secrets set REVENUECAT_ACCEPT_SANDBOX=true
```

**It is already `true`, and has been since it was introduced** (confirmed
2026-09-10). So nothing needs setting before a test purchase — but the
consequence runs the other way and is worth stating plainly:

> **Sandbox purchases have been granting real entitlements in production this
> whole time.**

The exposure today is close to nothing: there are no public users, and a
sandbox purchase needs a tester account on a list we control. It stops being
nothing the moment the app is public, because then anybody who can obtain a
sandbox tester account can grant themselves a coach — which is precisely what
`entitlement_event.ts` refuses by default and what this flag switches off.

So this is **not a step to remember**. It is a launch blocker:

```bash
supabase secrets unset REVENUECAT_ACCEPT_SANDBOX
```

- [x] Flag set for testing — was already on
- [ ] **Flag removed before either store goes public** ← blocks production


### Buy through build 24, not build 23

Build 23 reached internal testing and is the build the price check above was
made on, which is all it was needed for. **Do not make the purchase through
it.** Two things landed after it was cut, both on the path a buyer walks:

- The paywall told Android customers payment would be charged to their **Apple
  ID** and to cancel it in Apple ID settings (`4ae7615`). That is the one
  sentence on the screen Google actually reviews, and it was false.
- The intro asked Android for Apple Health permission (`fe14c82`), a step that
  cannot be granted on the platform being tested.

Build 24 is the first build that is both purchase-capable and honest about which
store is taking the money. Testing through 23 would produce a purchase that
works and a screen that could not ship.

Add your account under **Play Console ▸ Setup ▸ License testing** so purchases
are free and renew fast. Install from the internal testing link — **not** a
sideloaded APK, which cannot transact.

Walk section G of `testflight-1.0.0-test-sheet.md`, which is written
store-agnostically enough to reuse. The specific thing to prove, because it is
the one that has already bitten this app once on iOS: the purchase must be made
while RevenueCat is identified with a Supabase user id, never an
`RCAnonymousID:`. `PurchaseScreen` refuses that case up front — confirm the
refusal reads as *"sign in first"* and not as a failed payment.

- [x] Licence tester configured — 2026-09-10
- [ ] Purchase completes and the coach unlocks

## 10. Map the Play product ids

Read the webhook log from the step-9 purchase. If it logged `unmapped_product`,
it named the id. Add those exact strings:

```bash
supabase secrets set REVENUECAT_PRODUCTS='{
  "run.coach.monthly":         {"app":"run", "product":"paid"},
  "run.coach.premium.monthly": {"app":"run", "product":"premium"},
  "<exactly what the log named>": {"app":"run", "product":"paid"},
  "<exactly what the log named>": {"app":"run", "product":"premium"}
}'
```

Then purchase again and confirm `core.entitlements` gains a row with
`platform = 'google'` and `status = 'active'`.

- [ ] Play ids mapped, entitlement row written with `platform = 'google'`

## 11. Production

Promote the internal release. The declarations from step 4 must all be green.

---

## What this does not cover

- **Lift.** `lift-android-release` builds an AAB and already declares
  `mgkfitness_upload`, but its `publishing:` block is commented and it has no Play
  listing either. Everything above applies to it with the ids changed, and none
  of it is done.
- **Play App Signing key rotation**, which is a Google support request and has
  never been needed.
