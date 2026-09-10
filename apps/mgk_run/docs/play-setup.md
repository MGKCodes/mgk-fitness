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
- `codemagic.yaml` `run-android-release` — declares `android_signing: run_upload`,
  builds an **AAB** as well as an APK, emits `REVENUECAT_GOOGLE_KEY`, and
  carries a commented `publishing:` block.

---

## The order, and what actually blocks what

The dependencies are real and mostly one-way. Doing these out of order is how a
day disappears.

```
keystore ──▶ signed AAB ──▶ Play listing + FIRST MANUAL UPLOAD
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
keytool -genkey -v -keystore run-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

- Keep it **outside the repo**. `.gitignore` already covers `*.jks` and
  `android/key.properties`, but the safe place is not "ignored", it is "not
  there".
- Back it up somewhere you would still have after a disk failure.
- Run's own key, **not Lift's `liftio_upload`**. Two listings, two
  applicationIds, two independent uploads; a shared key means a reset on one
  reaches the other for nothing.

Then, in Codemagic → **Teams ▸ Code signing identities ▸ Android keystores**,
upload it with reference name **`run_upload`**. That exact string is what
`codemagic.yaml` declares; a different one fails the build with a message that
says so.

For a local release build, copy `android/key.properties.example` to
`android/key.properties` and fill in the four values.

- [ ] Keystore created and backed up
- [ ] Uploaded to Codemagic as `run_upload`

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

- [ ] App created

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

- [ ] First AAB uploaded manually

## 4. The declarations that gate every release

These are not optional and they are the usual reason a first Play submission
stalls. Several can be filled in now, before any of the billing work.

- [ ] **Privacy policy URL** — `https://mgkfitness.mgkcodes.com/run/privacy`.
      Already live and already CI-pinned; see the decision *The published legal
      page is the artefact CI pins*.
- [ ] **Data safety form.** Must agree with the privacy policy, which names the
      sub-processors. Location and health data are both collected.
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

**Do not guess the product id string the webhook will see.** RevenueCat reports
Play subscriptions in a `subscriptionId:basePlanId` form that differs by SDK
generation, so mirroring a guess into `REVENUECAT_PRODUCTS` is how you get a
paid subscriber with no entitlement. The webhook already solves this properly:
an id it does not recognise is logged as `unmapped_product` **and the log names
it**. Make the sandbox purchase in step 9, read the log, and add exactly what it
says. That is step 10.

- [ ] Two subscriptions created with base plans

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

- [ ] Google app added to RevenueCat
- [ ] Service account granted access to this app, JSON uploaded
- [ ] Products attached to the existing entitlement and offering
- [ ] `goog_` key copied

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

- [ ] `REVENUECAT_GOOGLE_KEY` set in `mgk_fitness_run_env`
- [ ] Publishing group name confirmed and corrected if needed

## 8. Turn on publishing

Uncomment the `publishing:` block at the end of `run-android-release` in
`codemagic.yaml`. It publishes to the **internal** track with
`submit_as_draft: true`, so a mistake is a draft to delete rather than a build
someone has installed.

Grant the Codemagic service account access to this app first (Play Console ▸
Users and permissions) or the publish step 403s.

- [ ] Publishing block uncommented, build green, bundle lands in internal

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

**Remove it before the production release.** It is the one setting here that
turns free money on.

```bash
supabase secrets unset REVENUECAT_ACCEPT_SANDBOX
```

- [ ] Flag set for testing
- [ ] Flag removed before production


Add your account under **Play Console ▸ Setup ▸ License testing** so purchases
are free and renew fast. Install from the internal testing link — **not** a
sideloaded APK, which cannot transact.

Walk section G of `testflight-1.0.0-test-sheet.md`, which is written
store-agnostically enough to reuse. The specific thing to prove, because it is
the one that has already bitten this app once on iOS: the purchase must be made
while RevenueCat is identified with a Supabase user id, never an
`RCAnonymousID:`. `PurchaseScreen` refuses that case up front — confirm the
refusal reads as *"sign in first"* and not as a failed payment.

- [ ] Licence tester configured
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
  `liftio_upload`, but its `publishing:` block is commented and it has no Play
  listing either. Everything above applies to it with the ids changed, and none
  of it is done.
- **Play App Signing key rotation**, which is a Google support request and has
  never been needed.
