# Release 2.0.0 — Liftio, rewritten

The plan to put `apps/mgk_lift` on the App Store and Google Play as **Liftio
2.0.0**, replacing the shipped Expo build at 1.4.0.

Written 2026-08-17. Tick items as they land; when something is settled
differently from how it is written here, change the item and say why — the
reasoning is worth more than the checkbox, which is the lesson
[roadmap.md](roadmap.md) records about itself.

---

## The decisions this plan rests on

**It replaces Liftio rather than launching beside it.** The App Store listing
(`6759969740`) and its ratings stay; the bundle id `com.mgkcodes.liftio` stays;
the version goes 1.4.0 → **2.0.0**, which is what a rewrite that changes
language, storage and business model is entitled to claim.

**The migration is smaller than it looks, and mostly done.**
`20260806130000_restructure_schemas.sql` already moved Liftio's live tables into
`lift.` and `core.` with `ALTER TABLE ... SET SCHEMA`, so the cloud history —
1249 sets and the rest — is already where the Flutter app reads. What is left is
local device data, and the same migration records that there are **two users and
both are known**. There is no population to migrate carefully.

**The shipped app is already broken.** That same migration emptied `public`,
which 1.4.0 queries through PostgREST. It has been non-functional since
2026-08-07. That is not a crisis with two known users, but it does mean there is
no working version to regress and no reason to protect the old build.

**Payments are ours.** `in_app_purchase` plus our own receipt validation writing
`core.entitlements`, rather than RevenueCat. The argument for RevenueCat was
migrating live subscribers; there are none, so the cheapest moment to own this
is now, before anyone is paying and a validator bug costs somebody access.

**Both stores at once.** iOS is a replacement, Android is new — Liftio never
shipped to Play (`eas.json` has iOS submit config only), so the Play listing is
a clean first upload with nothing to migrate.

---

## Phase 0 — Identity

Blocks everything else: signing, store records and product ids all key off these.

- [x] Change the iOS bundle id `com.mgkcodes.fitness.lift` →
      `com.mgkcodes.liftio` in `apps/mgk_lift/ios/Runner.xcodeproj`. The App ID
      and provisioning already exist from Liftio, so this reuses them rather
      than creating anything.
- [x] Change `applicationId` in `apps/mgk_lift/android/app/build.gradle.kts` →
      `com.mgkcodes.liftio`. **`namespace` moved with it**, which the plan did
      not ask for — leaving the internal package as `com.mgkcodes.fitness.lift`
      would have left the code contradicting the store identity. `MainActivity.kt`
      moved to match.
- [x] `version: 2.0.0+1` in `apps/mgk_lift/pubspec.yaml`, replacing `0.1.0+1`
      and the comment explaining why it was 0.1.0 — it says the app claims a
      real number "when it can replace what is shipped today", and this plan is
      that. Build numbers must strictly increase within the 2.0.0 train.
- [x] Display names: `CFBundleDisplayName` is `Mgk Lift` and `android:label` is
      `mgk_lift`. Both are dev placeholders. Both become **Liftio**.
- [x] **Record the bundle-id decision** —
      [ADR-0001](../apps/mgk_lift/docs/decisions/0001-liftio-is-replaced-not-relaunched.md),
      the first in Lift's own `docs/decisions/`. It turned out to **reverse** a
      decision, not fill a gap: `apps/mgk_lift/README.md` explicitly recorded
      the opposite — *"this is a new record, not an update. The existing listing
      gets retired rather than upgraded."* The README, `docs/architecture.md`
      and the `codemagic.yaml` comment were all updated in the same commit,
      since each stated the old decision as current.

**Verified:** analyzer clean, 252 tests pass, and a debug APK builds reporting
`applicationId: com.mgkcodes.liftio`, `versionName: 2.0.0`. iOS signing is not
provable from here — it needs the Codemagic macOS runner.

## Phase 1 — A build on the phone

The soonest goal: TestFlight, off the live server, on a real device.

- [x] **`NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` in
      `Info.plist`.** Neither existed, and `image_picker` is a dependency with
      progress photos as a core feature — iOS *crashes* on picker launch
      without them, and Apple rejects on the metadata scan. Liftio paid for this
      once at build #17, so its accepted strings were carried over verbatim
      rather than rewritten.
- [x] **`ITSAppUsesNonExemptEncryption: false`**, also carried from Liftio. Not
      in the original plan — without it App Store Connect asks the export
      compliance question on *every* upload, which is friction on a phase whose
      whole point is fast iteration on TestFlight.
- [x] Add a `lift-ios-release` workflow to `codemagic.yaml`, mirroring Run's.
      Lift needs only two secrets against Run's six — `AppConfig` reads
      `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` and nothing else, so the
      basemap and dev-account machinery has no equivalent here.
- [x] Generate `config/app_config.json` from secure vars in the workflow.
      **Also created `config/app_config.example.json`**, which `AppConfig`'s
      documentation claimed was committed — the directory did not exist.
- [ ] **Create the `mgk_fitness_lift_env` variable group in Codemagic** with
      those two values, marked Secure. The workflow names the group; the build
      fails at the first script without it, by design.
- [ ] **Check the iOS distribution profile exists for `com.mgkcodes.liftio`.**
      It should, inherited from the Expo build — but a profile is a snapshot of
      the App ID's capabilities when it was made, and Run's first build died at
      `xcode-project use-profiles` for exactly this. Regenerate if it fails.
- [ ] First TestFlight upload, installed on device.
- [ ] **Prove a real `lift_chat` turn against production.** Carried over from
      [roadmap.md](roadmap.md) and still unproven: everything says the plumbing
      is right, nothing yet says the coach answers. This build is what finally
      answers it.

## Phase 2 — Compliance the old app already paid for

Liftio's changelog is a list of rejections bought once. Do not buy them twice.

- [ ] **Terms and Privacy links.** Nothing in `apps/mgk_lift/lib` links to
      either. Required wherever an account can be created.
- [ ] **Auto-renew disclosure, verbatim.** Guideline 3.1.2(a) wants the full
      24-hour cancellation window at the point of purchase, not a summary.
      Liftio's accepted wording is in its 1.4.0 changelog entry.
- [ ] **Third-party AI disclosure.** Guideline 5.1.2(i). This is *more* acute
      than it was for Liftio, which sent numerical aggregates only: Lift sends
      the lifter's own words about their body and injuries to OpenRouter. Needs
      a visible surface — Liftio settled on an info affordance at the point of
      use, a Settings toggle, and a dedicated screen naming provider, what is
      sent and what is not.
- [ ] **Email confirmation back on in Supabase Auth.** Switched off 2026-08-10
      for the first TestFlight sign-in. With it off, anybody can register an
      address they do not own. `AuthRepository.signUp` already handles both
      paths, so this needs no code change — but the built-in mailer is
      rate-limited and explicitly for testing, so **configuring SMTP is the
      actual task** and the toggle is a stopgap.
- [ ] **Progress photos: sync them, or change the copy.** The screen currently
      promises nothing is uploaded. Tables and bucket exist. Whichever way this
      goes, the sentence and the behaviour change in the same commit.
- [ ] Update `getliftio.com` Terms — three files across `Liftio` and
      `getliftio.com` still contradict the licence decision, and Liftio has no
      credits screen. `mgk_lift`'s `credits_screen.dart` is the reference.

## Phase 3 — Payments, owned

`core.entitlements` already models the store lifecycle exactly — `product` in
`(free, paid, premium)`, `status` in `(active, expired, grace, refunded,
revoked)` — and already revokes write access from `authenticated`. The table is
shaped for this; what is missing is anything that writes to it.

- [ ] **Confirm the subscriber count is zero** in the RevenueCat dashboard
      before building on the assumption. Liftio's changelog refers to "every
      paid customer in production v1.3.0", so a handful may exist. If any do,
      they need a manual grant, not a redesign.
- [ ] Create store products on both stores: **£1 Coaching** → `product = 'paid'`,
      **£3 Premium** → `product = 'premium'`. This is a pricing change as well
      as a platform one — Liftio sold a single £1.99 tier.
- [ ] Client purchase flow with `in_app_purchase`: query, buy, restore, and a
      purchase stream that survives backgrounding.
- [ ] **iOS validator** — an Edge Function handling App Store Server
      Notifications V2. Apple POSTs signed JWS payloads for renewal, failed
      renewal, grace period, refund and revocation; the function verifies the
      signature chain against Apple's root CAs and writes `core.entitlements`
      with `service_role`.
- [ ] **Android validator** — Play Real-time Developer Notifications over
      Pub/Sub, reconciled through `purchases.subscriptionsv2.get`, writing the
      same row.
- [ ] **A manual grant path before either of them.** A SQL function usable from
      Supabase Studio to set somebody's entitlement. This is the support escape
      hatch, and Liftio needed exactly this repeatedly. Cheap now, invaluable
      the first time a purchase does not land.
- [ ] Sandbox-test both stores end to end: buy, renew, cancel, refund, restore
      on a second device.

**Admin dashboard — deliberately not release-blocking.** Wanted, and the reason
to own validation, but the manual grant path covers the same emergency at a
fraction of the cost. Build it once real purchases are flowing and it has real
data to show. Scope when started: users and their entitlements, grant and
revoke, and a log of store notifications received.

## Phase 4 — Android

Entirely new ground: ADR-0001 is iOS-first, `codemagic.yaml` says "No Android
workflow, deliberately", and Liftio never shipped to Play.

- [ ] **Release signing.** `build.gradle.kts` currently signs release builds
      with `signingConfigs.getByName("debug")`. Play rejects debug-signed
      uploads outright. Needs an upload keystore, `key.properties` (gitignored,
      already matched by the existing rules), and the release config wired up.
- [ ] Google Play Console: create the app, claim `com.mgkcodes.liftio`.
- [ ] Store listing, content rating, and the **Data safety form** — it must
      match reality, including the AI provider and health-adjacent data.
- [ ] Add an Android workflow to `codemagic.yaml`, and update the comment that
      says there deliberately isn't one.
- [ ] Internal testing track, installed on a real Android device.

## Phase 5 — Debt that touches the release

From [roadmap.md](roadmap.md)'s carried-over list, filtered to what a shipping
app cannot leave broken.

- [ ] **Delete Runio's `coach` and `delete-account` functions.**
      `C:\Projects\Runio\supabase\functions\` still defines both against this
      same project, and whichever repo deploys last wins. Runio's `surfaces.ts`
      has diverged — no `lift_chat`, no `app` field — so a deploy from there
      takes Lift's coach down in production. This is a live hazard, not tidying.
- [x] **Units are session state.** Fixed, but not the way this item described.
      Wiring the existing `SupabaseUnitPreferences` alone would have persisted
      units *only for signed-in lifters*, and tracking is free and needs no
      account — so the common case would still have lost the choice on every
      launch. Now device-first with the account authoritative when it answers,
      which is what `UnitPreferencesStore`'s documentation already promised
      ("falls back to the last known choice") and could not keep with nowhere
      local to fall back to. Also reloads on auth change: `initState` runs
      before Supabase restores a session, so the shared value was previously
      only picked up on the launch *after* signing in.
- [ ] **Pose selection is session state.** `core.user_settings.progress_pose_set`
      is the column and nothing writes it. The units work above establishes the
      pattern to copy — a device store, an account store, one composing
      repository — so this is now a smaller job than it was.
- [ ] **Rest-timer buzz is foreground-only.** Needs a local-notification plugin
      and a runtime permission — and on Android, a permission that must be
      requested, not just declared.
- [ ] **`daily-ai-summary` still calls `api.anthropic.com` directly** and is the
      only place holding an `ANTHROPIC_API_KEY`. Move it behind a coach surface.
- [ ] Unset `DAILY_GLOBAL_LIMIT` on production — a legacy Liftio secret nothing
      in this repo reads, which looks load-bearing to whoever reads the list.
- [ ] Resumable coach transcript on open. Currently the memory survives and the
      screen does not, which reads as amnesia even though it isn't.

## Phase 6 — Submission

- [ ] Screenshots for both stores at current required sizes. Liftio's
      `v1.4.0 app screenshots` folder shows the previous set.
- [ ] App Store metadata: description, keywords, what's new for 2.0.0. Say
      plainly that this is a rewrite.
- [ ] Privacy nutrition labels (iOS) consistent with the Data safety form
      (Android) and with what the app actually sends.
- [ ] Submit iOS. Submit Android internal → production.

---

## Not in this release

Named so they are decisions rather than omissions:

- The admin dashboard (Phase 3 — manual grants cover the emergency).
- `eat` — the third app. The restructure migration deliberately did not create
  its schema; adding it later costs one migration.
- Retiring the Liftio Expo repo. It stays as reference until 2.0.0 is approved
  and installed, because its changelog is the record of what Apple has already
  rejected once.

## Open questions

- Does signing into 2.0.0 restore a user's cloud history from `lift.*`, or does
  the app only write there? The tables hold real data; whether the Flutter app
  reads it back on a fresh install is unverified and decides whether the two
  known users lose anything.
- What App Store Connect actually shows for 1.4.0 today — build number, review
  state, and whether anything was submitted after 2026-04-30.
