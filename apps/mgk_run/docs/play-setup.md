# Play setup — keystore, listing, Play Billing, RevenueCat, declarations

The Google half of [store-setup.md](store-setup.md), which covers Apple. Run
1.0.0 ships on Play from the same commit and build number as the App Store
([ADR-0039](decisions/0039-one-commit-two-stores-and-the-pubspec-owns-the-build-number.md)).
The listing copy and graphics are in [play-listing.md](play-listing.md); the
live status for both stores is in [app-store-1.0.0.md](app-store-1.0.0.md).

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
  publishes to the internal track (the `publishing:` block was commented at
  first and has been live since build 24; §8).

---

## Where this got to

**Build 25 is on the internal track**, published automatically on 2026-09-11
from `12d74d8`, and **build 26 is the release candidate** for both stores. The
whole chain in this document works: the first real purchase went through on
2026-09-11 after step 10's product-id mapping turned out to be the thing
standing in the way, exactly as this document warned it would be.

**What is left is in [app-store-1.0.0.md](app-store-1.0.0.md)**, which carries
the live status for both stores rather than having it in two places. The short
version, for Play: developer verification is **done** (§8b), and what is left is every
declaration in §4, the listing and its graphics
([play-listing.md](play-listing.md)), Premium's new description (§5), and a
premium purchase on build 26 (§9).

**`REVENUECAT_ACCEPT_SANDBOX` stays on.** This paragraph used to say it had to
come off before anything was public; ADR-0037 reversed that, and §9 says why.

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

- **App name:** as per [play-listing.md](play-listing.md), kept identical to
  the Apple listing so the two stores name one product one way.
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
console. This is why the `publishing:` block in `codemagic.yaml` started out
commented; it went live after this upload (§8).

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

## 4. App content — every declaration, with the answers

Play Console ▸ Policy ▸ **App content**. Every item here must be complete
before a release can go to production review, and they are the usual reason a
first Play submission stalls. None of them depends on the billing work.

**Rewritten 2026-09-29** from a compliance review of the build 26 code. Where a
judgement was made rather than read off the code, it says so. The form and the
privacy policy are compared, and a disagreement between them is a rejection, so
do not change an answer here without changing the policy with it.

- [ ] **Privacy policy** — `https://mgkfitness.mgkcodes.com/run/privacy`.
      Already live and CI-pinned.
- [ ] **App access — "All or some functionality is restricted".** Add one set
      of instructions:
      - Name: `Demo account A`
      - User name and password: demo account A, from
        [store-setup.md](store-setup.md) §9 (the same account App Review
        gets; its row names no store, so the app reads right on Android)
      - Any other information: *"On the first screen tap 'I already have an
        account' and sign in. This account already has the coach
        subscription, so please do not buy on it. Recording runs needs no
        account; the coach, plans and backup need one. The first time you open
        the coach it asks permission to send training data to the AI provider,
        then shows a medical disclaimer."*
- [ ] **Ads — No,** the app contains no ads. No ad SDK, no advertising id.
- [ ] **Content rating** — the IARC questionnaire, answers below.
- [ ] **Target audience and content** — **18 and over only**; appeals to
      children **No**. Reasoning below.
- [ ] **News apps — No.**
- [ ] **Data safety** — answers below, including the deletion URL
      `https://mgkfitness.mgkcodes.com/run/delete-account`. Play requires that
      URL for any app offering account creation, because somebody who has
      **uninstalled** the app must still be able to ask; the in-app Delete
      account cannot help them (the page was added 2026-09-11).
- [ ] **Government apps — No.**
- [ ] **Financial features — none.** The app sells a subscription through Play
      Billing, which is not a financial feature.
- [ ] **Health apps — mandatory for every app, not "if prompted".** Tick
      **Health and fitness ▸ Activity and fitness** and nothing else. The app
      reads no Health Connect data and has no medical, disease or clinical
      feature.
- [ ] **Advertising ID — No.** Nothing in the app reads it, and the app's own
      manifest does not declare `AD_ID`. If Play warns at upload that the
      bundle declares it, a dependency added it: find which before answering
      anything else.
- [ ] **Foreground service permissions — location**, with a video. Below.
      This is the one most likely to be queried.

### Foreground service declaration

Run declares `FOREGROUND_SERVICE_LOCATION` and deliberately **not**
`ACCESS_BACKGROUND_LOCATION` (see the note in `AndroidManifest.xml`), which
keeps this much simpler than it would otherwise be. Paste these exactly:

| Field | Answer |
|---|---|
| Type | Location |
| Describe the feature | When the user taps Start to record a run, the app starts a foreground service of type location with an ongoing "Recording your run" notification so it keeps receiving GPS fixes while the screen is locked or the phone is in a pocket. It computes the route, distance, pace and splits of that run. The service stops when the user taps Finish. The app does not request ACCESS_BACKGROUND_LOCATION. When no run is being recorded it reads location only while the app is open on screen, to centre the map before a run starts. |
| Impact if the task is deferred | The start of the run would have no location, so route, distance and pace would be missing. |
| Impact if the task is interrupted | Distance freezes while the timer runs; pace, splits and route become wrong and the run is lost. |
| Video | A link to the video below (an unlisted YouTube video works) |

**The video**, on a real Android phone running the Play build:

1. **First turn notifications on for Run**: Settings ▸ Apps ▸ Run ▸
   Notifications. The app never asks for the Android 13+ notification
   permission (a known gap, in after-1.0.0.md), so without this the
   notification that the video exists to show does not appear in the shade.
2. Open Run ▸ Record a run ▸ **Start**.
3. Lock the screen, wake it, and show the **"Recording your run"**
   notification.
4. Walk for a minute or two with the screen locked.
5. Unlock and show that the **distance went up** while it was locked.
6. Tap **Finish**, then show the notification has **gone**.

Test sheet row V1 captures the same thing.

**One sentence differs from the draft the compliance review supplied**, which
said the app "never accesses location when no run is being recorded". The run
start screen reads the phone's last known position, in the foreground, to draw
its map (`run_start_screen.dart`), so the declaration says that instead. A
declaration a reviewer can falsify by opening the app is worse than a longer
one.

### The Data safety answers

Filled in from the privacy policy and the code rather than from memory.
**This describes the Android app.** It reads no health permissions at all, so
nothing HealthKit-shaped belongs here even though the policy discusses it for
iOS.

Top-level questions:

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **Yes** |
| Is all of the user data collected by your app encrypted in transit? | **Yes** — HTTPS/TLS throughout |
| Which of the following methods of account creation does your app support? | **Username and password** (email and password, in the app) |
| Delete account URL | `https://mgkfitness.mgkcodes.com/run/delete-account` |
| Do you provide a way for users to request that some or all of their data is deleted, without requiring them to delete their account? | **Yes** — turning backup off erases the server copy of their training |

Then per type. **Every type: Shared = No, Processed ephemerally = No.**

| Category | Type | Collection | Purposes | What it is |
|---|---|---|---|---|
| Location | Approximate location | Optional | App functionality | MapTiler's tile requests for the map on screen |
| Location | Precise location | Optional | App functionality | Route traces, sent only with backup on |
| Personal info | Name | Optional | App functionality, Account management | The name the coach uses, if given |
| Personal info | Email address | Optional | Account management | The account; the app works signed out |
| Personal info | User IDs | Optional | Account management, App functionality | The Supabase user id, also RevenueCat's app user id |
| Financial info | Purchase history | Optional | App functionality, Analytics | The subscription, via RevenueCat |
| Health and fitness | Health info | Optional | App functionality | Injury notes and symptoms the runner types, a heart rate typed in by hand |
| Health and fitness | Fitness info | Optional | App functionality | Runs, distance, pace, plans, effort ratings |
| Messages | Other in-app messages | Optional | App functionality | Coach conversations, their summary, reported replies |
| App activity | App interactions | Optional | App functionality, Fraud prevention, security and compliance | The coach usage ledger that enforces the spend limits |
| Device or other IDs | Device or other IDs | Optional | App functionality | RevenueCat's own per-install id |

**Why everything is Optional.** Nothing leaves the phone for a runner who
records with no account, no backup and no coach, apart from map tiles, and the
app works with location refused (runs can be added by hand). The tile requests
are the closest call; they happen whenever a map is shown, and refusing
location is what opts out of them in practice.

**Device or other IDs is a judgement to keep.** RevenueCat's own Data safety
page says an app needs it only when it uses their advertising-id integrations,
which this app does not. It stays declared because the privacy policy says the
SDK collects "a device-scoped identifier", and the form and the policy should
agree. Over-declaring costs nothing on this form; under-declaring against the
policy is the rejection.

**Not collected:** photos and videos, files and docs, audio, calendar,
contacts, web browsing history, installed apps, crash logs, diagnostics, and
advertising id. The app carries no analytics, no ad SDK and no crash reporter,
which is a rare set of honest zeroes on this form.

**Photos is the one that needs saying out loud**, because the app gained a
profile photo on 2026-09-11 and the answer is still *not collected*. Play
defines collection as data **transmitted off the device**; this photo is copied
into the app's own storage and never sent to us or to the coach. The same
reasoning keeps it off Apple's App Privacy answers and out of
`PrivacyInfo.xcprivacy`. **If the photo is ever synced, all three answers
become false at once** — that is the whole reason it is a rule in
`ProfilePhotoStore` rather than an accident of where the file lives.

**Why nothing is marked "shared".** Play's definition of sharing excludes
transfer to a service provider processing on the developer's behalf, and all
four sub-processors are exactly that — Supabase, OpenRouter, RevenueCat,
MapTiler. **This is the one judgement call on the form.** If it is ever wrong,
it is wrong about OpenRouter, which receives training data and message text;
the defence is that it processes on our instruction and does not use it for its
own purposes, which is also what the policy tells the runner.

### Content rating (IARC questionnaire)

| Question | Answer |
|---|---|
| Category | **Utility, Productivity, Communication, or Other** |
| Violence, fear, sexuality, language, controlled substances, crude humour, gambling | **No** to all |
| Can users interact or exchange content with other users? | **No** — the coach is a model, not a person, and no runner can see, message or find another |
| Does the app share the user's current physical location with other users? | **No** |
| Does the app allow users to purchase digital goods? | **Yes** — the subscription |
| Unrestricted internet access, such as a web browser? | **No** |
| AI-generated content or a chatbot, if asked | **Yes** — the coach's replies, which can be reported in the app |

Saying yes to user interaction pulls in social-feature declarations and a
heavier rating for nothing. Expect **PEGI 3 / Everyone**, with an in-app
purchases notice.

### Target audience

**18 and over, only.** The terms allow accounts from 16, so 16–17 would be
permitted too; it is not chosen because nothing in the product is made for
teenagers, and the app gives training advice, holds health information and
sells a subscription. Appeals to children: **No**.

**Corrected 2026-09-29:** this used to say that selecting any bracket under 18
pulls the listing into the Families policy. That is wrong. The Families policy
applies when the target audience includes children **under 13**. The answer
stays 18+; the reason given for it was the error.

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
- [ ] **Each subscription's description and benefits set from
      [play-listing.md](play-listing.md) § Subscriptions** (added 2026-09-29).
      Premium's says *"Three times the coaching each month."*, not a better
      model ([ADR-0038](decisions/0038-premium-buys-more-coaching-not-a-different-model.md)).
      Google calls the description internal, but the paywall prints it on
      Android through RevenueCat, so it is copy a runner reads.

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
workflow names **`mgk_fitness_play`** (this said `mgk_play_publishing` until
2026-09-29, a name `codemagic.yaml` does not use). A name that does not exist
fails the build immediately, which is loud and cheap.

- [x] `REVENUECAT_GOOGLE_KEY` set in `mgk_fitness_run_env` — and **proved** by
      build 24 rather than taken on trust: the config step rejects a key that
      does not begin `goog_`, and the build went green
- [x] Publishing group name confirmed — the publish step succeeded, which it
      cannot do against a group that does not exist

## 8. Turn on publishing

**Done, and live since build 24.** The `publishing:` block at the end of
`run-android-release` publishes to the **internal** track with
**`submit_as_draft: false`**. It was `true` until 2026-09-11: the draft held
build 24 behind build 23 for an hour, invisibly, and the internal track only
reaches a tester list anyway. Keep it `true` for any track that reaches the
public.

Grant the Codemagic service account access to this app first (Play Console ▸
Users and permissions) or the publish step 403s.

- [x] Publishing block uncommented, build green, bundle lands in internal —
      **build 24, 2026-09-11**, every step green including `Publishing`. First
      fully automated Play release from a commit.

## 8b. Register for Android developer verification — due 2026-09-30

**The most urgent item in this document.** Play Console says every app must be
registered for **Android developer verification by 30 September 2026**, and an
app that is not faces removal from Google Play.

The account banner saying *"All of your apps have been successfully
registered"* refers to the apps that existed when it was shown — **frunt**. A
newly created listing is not covered by it.

**Android developer verification** is its own item at the bottom of the Play
Console account-level sidebar. It wants the package name and the signing
certificate, which is why this sits after the first upload rather than before.
The upload certificate's SHA-256 is recorded in §1; if the form asks for the
app signing key instead, Play Console shows it under Test and release ▸ App
integrity.

- [x] `com.mgkcodes.fitness.run` registered — **done 2026-09-10**. Checked in
      Play Console on 2026-09-29: Package names shows it *Registered*, 3 keys,
      beside frunt (*Registered*, 1 key, 2026-06-03). Nothing left to do here.

## 9. A real purchase, on a real device

### The sandbox flag stays on

**Google licence-tester purchases arrive at the webhook as `environment:
"SANDBOX"`**, and the webhook honours them only while
`REVENUECAT_ACCEPT_SANDBOX` is `true`. Without it the test *looks* like a total
failure: the purchase succeeds, RevenueCat shows it, and `core.entitlements`
stays empty, so the coach never unlocks. Every layer is working correctly and
the symptom is indistinguishable from none of them working at all.

**It is `true`, has been since it was introduced, and stays `true` in
production** ([ADR-0037](decisions/0037-the-sandbox-stays-open-in-production.md)).
This section used to call switching it off a launch blocker, with an unticked
box. That was reversed on 2026-09-29: App Review buys in the sandbox against the
production build, so with the flag off a reviewer's purchase unlocks nothing and
the paid half cannot be reviewed. A sandbox purchase can only come from people
we chose — licence testers, TestFlight testers, sandbox Apple IDs and App
Review — and sandbox subscriptions stop on their own.

- [x] Flag on — and it stays on (ADR-0037)
- The one rule it brings: **never publish a public TestFlight link**, the only
  way a stranger gets a sandbox purchase.

### Buy through build 26

Test on the release candidate. Builds 23 and 24 are history, and testing build
25 was dropped: 26 carries everything 25 did plus the consent sheet, the
account and purchase fixes and the recording fixes, so a purchase proved on 25
would have to be proved again.

1. **Licence testing.** Your Google account under Play Console ▸ Setup ▸
   License testing, so purchases are free and a month renews in minutes.
2. **Install from the internal testing link**, signed into that Google account
   on the phone — **not** a sideloaded APK, which cannot transact (§3).
3. **Sign in to the app with an account that has no Run row** — not the one
   you use on the iPhone, or a Play purchase and an Apple one land on the same
   row and neither proves anything.
4. **Buy Premium Coach first.** It is the product whose Play id was never read
   off a real payload (§10). Then read the result, in order: RevenueCat ▸
   Customer history (against your Supabase UUID, never an `RCAnonymousID:`),
   the `revenuecat` function log, and `core.entitlements`, which should hold
   one row: `premium`, `active`, `google`, an `expires_at` and `event_ms`.
5. **Restore purchases** after reinstalling, and **Manage subscription**
   (Profile ▸ Settings ▸ the account card at the top ▸ Coaching) opening
   Play's subscription page for Run.
6. **Cancel in Play** and watch the row stay `active` until the period ends,
   then go `expired`. A licence-test month lasts minutes, so this is quick.

Section P of [the test sheet](testflight-1.0.0-test-sheet.md) is the same list
with boxes. The specific thing to prove, because it has already bitten this app
once on iOS: the purchase must be made while RevenueCat is identified with a
Supabase user id. `PurchaseScreen` refuses the other case before the store —
confirm it reads *"Sign in first"* with a Sign in button, not as a failed
payment.

- [x] Licence tester configured — 2026-09-10
- [x] A Coach purchase completed on Android — 2026-09-11, once §10's mapping
      was fixed
- [ ] **Premium purchase on build 26** writes `premium` / `active` / `google`

## 10. Map the Play product ids

**Coach is mapped and proved.** The webhook logged `run.coach.monthly:monthly`
from the 2026-09-11 purchase — Play's `subscriptionId:basePlanId` form — and
that key was added.

**Premium is mapped and not proved.** `run.coach.premium.monthly:monthly` was
added by inference from the Coach one, not read off a payload. If the §9
purchase writes no row, the log line `unmapped_product: <id>` names the real
id; add exactly that, keeping every existing key:

```bash
supabase secrets set REVENUECAT_PRODUCTS='{
  "run.coach.monthly":                 {"app":"run", "product":"paid"},
  "run.coach.premium.monthly":         {"app":"run", "product":"premium"},
  "run.coach.monthly:monthly":         {"app":"run", "product":"paid"},
  "<exactly what the log named>":      {"app":"run", "product":"premium"}
}'
```

**Set it from Git Bash or the Supabase dashboard, not Windows PowerShell.**
PowerShell 5.1 strips the double quotes out of a native command's argument, so
this JSON arrives unparseable and **both stores stop mapping**. That happened
for thirteen minutes on 2026-09-11. Read the secret back afterwards, and buy
once more to confirm.

- [x] Coach's Play id mapped — `run.coach.monthly:monthly`, 2026-09-11
- [ ] Premium's Play id proved by a real row with `platform = 'google'`

## 11. Production

In this order, once §4, §5, §8b and the listing are done:

1. **Managed publishing on** (Publishing overview). The Play equivalent of
   App Store Connect's manual release: an approved release waits for you to
   press Publish instead of going live at whatever hour review finishes.
2. **Promote build 26** from internal testing to Production, as a new release
   with release notes. It goes to review.
3. **Publish** when both stores are approved, or when you decide Play goes
   first.

---

## What this does not cover

- **Lift.** `lift-android-release` builds an AAB and already declares
  `mgkfitness_upload`, but its `publishing:` block is commented and it has no Play
  listing either. Everything above applies to it with the ids changed, and none
  of it is done.
- **Play App Signing key rotation**, which is a Google support request and has
  never been needed.
