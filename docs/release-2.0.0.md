# Release 2.0.0 — Lift, rewritten

The plan to put `apps/mgk_lift` on the App Store and Google Play as
**MGKFitness: Lift** 2.0.0, replacing the shipped Expo build at 1.4.0.

Written 2026-08-17. Tick items as they land; when something is settled
differently from how it is written here, change the item and say why — the
reasoning is worth more than the checkbox, which is the lesson
[roadmap.md](roadmap.md) records about itself.

**The UI work found by testing lives next door.** The first build on a phone
turned up a list of interaction and layout gaps that are not phases of this
plan; they are in
[lift-2.0.0-punch-list.md](lift-2.0.0-punch-list.md). Two items overlap and are
tracked there rather than duplicated: the resumable coach transcript in Phase 5,
and the template picker's fate, which is item 3 of [roadmap.md](roadmap.md).

---

## The decisions this plan rests on

**The name Liftio is retired, but the app record is not.** Since this plan was
written, Liftio and Runio were dropped as user-facing names (2026-08-21) — the
app ships as **MGKFitness: Lift**, labelled `Lift` on the home screen, with
`MGKFitness` a placeholder for a consumer name that does not exist yet. See
[naming.md](naming.md). Everywhere below, "Liftio" now means the shipped 1.4.0
Expo app and the store record it left behind, never the thing being released.

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
- [x] Display names: `CFBundleDisplayName` and `android:label` were the dev
      placeholders `Mgk Lift` and `mgk_lift`. This plan said both become
      **Liftio**; they became **`Lift`** instead, because the name was retired
      before the item landed. The store listing carries the full
      `MGKFitness: Lift` and the phone carries only `Lift` — iOS truncates an
      icon label at about twelve characters, so both apps in the suite would
      have rendered as `MGKFitness:…` and become indistinguishable side by
      side. `kAppName` in `lib/src/core/brand.dart` must stay identical to
      both, since copy sends people to *Settings › Lift*.
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
- [x] **Create the `mgk_fitness_supabase` variable group in Codemagic** with
      `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`, marked Secure, and move
      those two out of `mgk_fitness_run_env`. One project (ADR-0008) means one
      group: a copy per app makes a key rotation half-land, with one product
      fixed, the other pointed at a dead key, and no build failure to say so.
      The workflows name the group; the build fails at the first script without
      it, by design.

      **Ordering matters.** Run's workflow now reads this group too, so it must
      exist before this branch merges — otherwise Run's next build fails at its
      config step with "SUPABASE_URL is empty". Lift has no group of its own;
      an empty one would just be somewhere for a future secret to land without
      anyone deciding it should.

      **Ticked 2026-09-01, on evidence rather than on a memory of doing it.**
      The group lives in Codemagic, not in this repository, so the proof is
      indirect: the workflow names the group, the config step fails at the
      first script without it, and a build off that workflow was installed on
      a phone on 2026-08-24. It exists.
- [x] **Create an App Store distribution provisioning profile for
      `com.mgkcodes.liftio`.** This was briefly ticked on the understanding that
      an inherited App ID brought one with it. The first build (2026-08-18,
      `7d758a2`) proved otherwise, failing with "No matching profiles found for
      bundle identifier com.mgkcodes.liftio and distribution type app_store" —
      the same message Run's first build produced. An App Store record, an App
      ID and a distribution certificate are three separate things, and none of
      them is a provisioning profile; EAS managed Liftio's signing and left
      nothing this pipeline can fetch.

      developer.apple.com ▸ Certificates, Identifiers & Profiles ▸ Profiles ▸ +
      ▸ Distribution ▸ App Store Connect ▸ pick the App ID and the existing
      Apple Distribution certificate. Nothing to download. Lift needs no
      capabilities, so it will not need regenerating.

      **Settled differently from how it is written above.** Creating the
      profile was necessary and not sufficient. Codemagic's *fetch* of it never
      once succeeded — five builds, every one with `startedAt` null, so no
      machine ever started and nothing about the build itself was reached — and
      the cause is still genuinely unexplained after the obvious theories were
      ruled out with evidence. What ships instead is **manual signing**: the
      profile and certificate uploaded once to Codemagic ▸ Teams ▸ Code signing
      identities and named in `ios_signing` as "Lift MGKFitness App Store" and
      "Lift MGKFitness Distribution", where Run still uses the automatic
      `distribution_type` + `bundle_identifier` form. Lift is the exception on
      purpose. `codemagic.yaml` carries the full account of what was ruled out;
      read it before "simplifying" the two apps back into agreement.
- [x] First TestFlight upload, installed on device. Built 2026-08-21
      (`a5d2d3e`, `10d1552`), held and worked through on 2026-08-24 against
      [testflight-2.0.0-test-sheet.md](testflight-2.0.0-test-sheet.md). What
      that session turned up became
      [lift-2.0.0-punch-list.md](lift-2.0.0-punch-list.md) — a plan of its own
      rather than a line here.
- [ ] **Prove a real `lift_chat` turn against production.** Carried over from
      [roadmap.md](roadmap.md) and still unproven. The reason is now known, and
      it was never the plumbing.

      `core.entitlements` is **empty** — zero rows, for anybody — and the
      deployed coach function gates on it. So every Lift coach request in
      production has been refused, and the 2026-08-24 session was a test of the
      free half of the app. `coach.turns` holds exactly one conversation and it
      is `app = 'run'`; there has never been a `lift:` turn.

      What this needs is the one-row `insert into core.entitlements` from the
      test sheet's "Before you start", and then a re-test. Not a code change.
      Until that row exists, every observation of Lift's paid half is an
      observation of a gated app.

## Phase 2 — Compliance the old app already paid for

Liftio's changelog is a list of rejections bought once. Do not buy them twice.

- [x] **Terms and Privacy links.** Nothing in `apps/mgk_lift/lib` linked to
      either. Required wherever an account can be created.

      Landed 2026-09-01 as a `legal` feature copied from run's rather than
      designed twice — `LegalDocument`, a renderer, a hub, and a staleness test
      pinning the in-app copy to `docs/`. Three documents, all written from the
      code: [privacy-policy.md](../apps/mgk_lift/docs/privacy-policy.md),
      [terms-of-use.md](../apps/mgk_lift/docs/terms-of-use.md) and
      [ai-disclosure.md](../apps/mgk_lift/docs/ai-disclosure.md). Each carries a
      "draft, legally unreviewed" banner naming what is still open, and **legal
      review of all three is a real open item** rather than a formality.

      Reachable from Settings ▸ Privacy & legal, and from the sign-in screen,
      which is the only place in this app an account can be created.
- [ ] **Auto-renew disclosure, verbatim.** Guideline 3.1.2(a) wants the full
      24-hour cancellation window at the point of purchase, not a summary.
      Liftio's accepted wording is in its 1.4.0 changelog entry.

      **Blocked on Phase 3, and deliberately not started.** There is no point of
      purchase to put it at, and 3.1.2(a) wants the disclosure in full or not at
      all. The terms carry one sentence — "Everything the app does today is
      available without paying" — and a test asserts the words *auto-renew*,
      *automatically renews*, *per month* and *free trial* appear nowhere, so
      the first person to write half the disclosure trips it. `docs/terms-of-use.md`
      holds the marker for what has to be written when payments land.
- [x] **Third-party AI disclosure.** Guideline 5.1.2(i). This is *more* acute
      than it was for Liftio, which sent numerical aggregates only: Lift sends
      the lifter's own words about their body and injuries to OpenRouter. Needs
      a visible surface — Liftio settled on an info affordance at the point of
      use, a Settings toggle, and a dedicated screen naming provider, what is
      sent and what is not.

      Landed 2026-09-01, all three. The affordance is in the coach sheet's top
      bar and is shown mid-intake as well as in conversation, because the
      questionnaire is where the injury notes are typed. The switch is
      device-local rather than in `core.user_settings` — it is consent, not a
      display choice, and an account row is something a restore could quietly
      flip back on. **Off means the mark is absent, not inert**, matching the
      call `main.dart` already makes when there is no server.

      Two things the wiring turned up. Building a plan is an AI request too, so
      the switch had to reach `_canPlan` or Plan would have gone on sending the
      intake answers — injury notes included — with the coach switched off. And
      the note under the then-disabled button said *"Your coach needs a
      connection"*, which had become a confident lie about a choice somebody
      made on purpose; `PlanSurface` now takes the reason and says which it is.
- [ ] **Email confirmation back on in Supabase Auth.** Switched off 2026-08-10
      for the first TestFlight sign-in. With it off, anybody can register an
      address they do not own. `AuthRepository.signUp` already handles both
      paths, so this needs no code change — but the built-in mailer is
      rate-limited and explicitly for testing, so **configuring SMTP is the
      actual task** and the toggle is a stopgap.

      **Half of this is already done, and the other half is now demonstrated
      rather than predicted.** Checked against the live project 2026-09-01: the
      toggle is back ON — a sign-up attempt returns `email rate limit
      exceeded`, which is the built-in mailer refusing to send a confirmation,
      not a validation error. So the stopgap is in place and **SMTP is the only
      thing left**, exactly as this item warned. Until it is configured, sign-up
      is effectively broken for anybody new: the mailer's limit is a handful of
      messages an hour across the whole project.

      Worth knowing while testing: Supabase Auth also rejects `example.com` and
      `.invalid` addresses outright, so a throwaway test account needs a real
      domain.
- [ ] **Progress photos: sync them, or change the copy.** The screen currently
      promises nothing is uploaded. Tables and bucket exist. Whichever way this
      goes, the sentence and the behaviour change in the same commit.

      **Settled 2026-09-01, and the answer changed the question.** Photos are
      not a free feature that might sync — the whole feature is paid, gated on
      the same entitlement as the coach and the plan. Storing photographs of
      somebody's body costs real money in a way text rows do not, which is the
      one place in this app where a storage gate is an economic fact rather
      than a paywall looking for a home. It is also the cleanest answer under
      data minimisation: we do not hold body photos for people who get nothing
      back from them.

      Landed so far: the gate, the offer, and the lapse behaviour. **A lapse
      takes the camera, not the photos** — everything already shot stays
      readable, playable and deletable, which is the rule `main.dart` already
      applies to coach memory and which matters more here, because a progress
      photo is the one thing in this app that cannot be recreated from anything
      else.

      **Sync landed 2026-09-01**, and the screen's promise changed in the same
      commit as the behaviour, which is what the note on that string was for.
      Photos now go to the `progress-photos` bucket under `<user id>/`, come
      back on a new phone, and a delete propagates as a tombstone rather than
      the photo reappearing on the next pull.

      Three things it turned up, all of them the kind that only show up in the
      wiring:

      - **`core.progress_photos` had one timestamp and Lift needs two.**
        `date` is when the shutter went; the week a photo is filed under is its
        *identity*, and deriving it server-side is impossible — Monday depends
        on the timezone the lifter was standing in. Hence a nullable
        `week_start`, no backfill, and the client deriving it for the 2024-25
        Liftio rows.
      - **A retake pushes two rows for one slot** — a tombstone and its
        replacement — and the new partial unique index rejects the replacement
        while the original is still live. Deletions now push first. The wrong
        order fails in a way that reads as a server problem.
      - **Deleting an account did not delete the pictures.**
        `core.delete_account` removes rows; the JPEGs live in storage and no
        `delete from` reaches them. Photographs of somebody's body, retained
        after they asked to be erased, invisible to every query anybody would
        think to run. The Edge Function now sweeps the bucket prefix, keyed off
        the same `shared_deleted` flag the row sweep uses.

      **The storage sweep is now verified against production**, end to end: a
      probe account was created with three photo rows and three objects, signed
      in, and put through the real `delete-account` function. Rows gone,
      **objects gone**, and the two real accounts' 30 rows and 37 objects
      untouched. That is the bug proved fixed rather than reasoned about.

      Rewritten to use `supabase-js` in the process. The sweep was hand-written
      REST — `POST /storage/v1/object/list/{bucket}`, `DELETE` with `prefixes` —
      and the docs confirm the client methods but not those bodies. A wrong body
      fails *silently* as "nothing to delete", and the residue is photographs of
      somebody's body kept after they asked to be erased. That is not a shape to
      guess at, so the library owns it now.

      **Still unverified:** the upload and download themselves, which need a
      device with a camera. The rules deciding which photos go and where they
      land are unit-tested; the round trip is for the next build.

      **Also open:** a lift-only deletion keeps the photos, because they live in
      `core` and are shared with the account rather than owned by this app. That
      is defensible while Run has no photo feature and is worth revisiting when
      it does.

      **Settled 2026-09-01:** photos are part of the paid tier, which means
      £1 and up. The two paid tiers hold the same features and differ only in
      how much the coach will talk to you, so there was never a photos-shaped
      question about which one — `isEntitled` is the whole gate. The paywall
      copy now names photos in the Coaching row and says Premium is the same
      feature for feature, with a test holding both.
- [ ] ~~Update `getliftio.com` Terms~~ — **superseded 2026-09-01.**
      `getliftio.com` is being retired rather than corrected. The web presence
      folds into the MGKCodes site as something like
      `mgkfitness.mgkcodes.com`, one place for the suite instead of a domain
      per app, which is the same consolidation the bundle names and the shared
      profile already made.

      So there is nothing to fix in three files across two repositories: what
      is left is to publish the two documents this app now carries — the
      [privacy policy](../apps/mgk_lift/docs/privacy-policy.md) and the
      [terms](../apps/mgk_lift/docs/terms-of-use.md) — at the new address, and
      point App Store Connect at it.

      **A later segment, and not a blocker for TestFlight.** It is a blocker
      for submission: App Store Connect requires a reachable privacy-policy
      URL, and `getliftio.com` should not be that URL if it is going away.

## Found while working Phase 2, and not on it

Two gaps this plan does not list, one of them a hard rejection.

- [x] **There is no way to delete an account.** Nothing in `apps/mgk_lift/lib`
      referenced deletion at all — no screen, no service, no mention. The
      `delete-account` Edge Function exists and is already app-aware
      (`{"app": "lift"}` erases `lift.*` and keeps the shared login when Run
      still holds data), and run has a full `DeleteAccountScreen` and
      `AccountDeletionService` to copy. **Guideline 5.1.1(v) requires in-app
      deletion for any app that supports account creation**, so this was a
      rejection rather than a nice-to-have.

      Landed 2026-09-01, and **it asks which deletion you mean.** One login
      serves the whole suite (ADR-0008), so "delete my account" names two
      different requests, and the function has always modelled both while no
      client had offered the choice:

      - *Delete my Lift data* — `{"app": "lift"}`. Erases `lift.*` and this
        app's coach data; the profile survives so Run keeps working.
      - *Delete my whole MGKFitness profile* — no `app`. Everything, in every
        app, and the login.

      It opens on the narrower one: a destructive screen should not arrive with
      the widest option already chosen. The gate is a typed `DELETE`, and the
      outcome screen says what actually happened — including the case where the
      narrow choice still took the login because Run held nothing, which is
      said before the tap as well as after it.

- [ ] **Run's deletion is unscoped, and erases Lift's data.** Not this app's
      bug and not fixable from this branch, but found here and worth writing
      down. `AccountDeletionService` invokes `delete-account` with **no body**;
      the function reads an absent `app` as "erase everything, everywhere, and
      the login", and `core.delete_account(user, null)` targets both schemas.
      So deleting a Run account today also erases the lifter's sessions —
      while run's own privacy copy promises *"we delete everything this app
      holds and keep only the profile, so your data in Lift survives"*.

      The corroboration is in run's own code: `AccountDeletionResult` models
      `retainedReason == 'sibling_app_data'`, which the server can only ever
      return for a scoped call. That branch is unreachable today. The fix is
      one argument — `body: {'app': 'run'}` — in run's lane.

## Phase 3 — Payments, through RevenueCat

`core.entitlements` already models the store lifecycle exactly — `product` in
`(free, paid, premium)`, `status` in `(active, expired, grace, refunded,
revoked)` — and already revokes write access from `authenticated`. The table is
shaped for this; what is missing is anything that writes to it.

**Rewritten 2026-09-01: RevenueCat, not our own validators.** This phase was
called *Payments, owned* and specified two Edge Functions — one verifying
Apple's JWS signature chain against their root CAs, one reconciling Play
Real-time Developer Notifications over Pub/Sub. That is a genuine amount of
security-sensitive code to own for a product with no subscribers yet, and both
halves are exactly what RevenueCat exists to do. The reasoning for owning it is
kept below rather than deleted, because it is the argument to revisit if
RevenueCat ever becomes the constraint.

`core.entitlements` does not change. It stays the app's single source of truth
and stays unwritable by `authenticated`; RevenueCat's webhook becomes the thing
that writes it, in place of the two validators. Nothing client-side reads an
entitlement from anywhere else.

### What the tiers actually are

**Both paid tiers hold the same features.** £3 buys more room to talk to the
coach and nothing else — no extra screen, no extra capability. Photos are part
of the paid tier alongside the coach and the plan (see the photos item in Phase
2), so the split is:

| | Free | £1 Coaching | £3 Premium |
|---|---|---|---|
| Tracking, templates, history, stats | yes | yes | yes |
| Plan, coach, progress photos | no | yes | yes |
| Coach message allowance | — | standard | far higher |

The paywall copy in `plan_surface.dart` says exactly this, and a test holds it
there — a feature that changes side has to change that block too.

### The work

- [ ] **Confirm the subscriber count is zero** in the RevenueCat dashboard
      before building on the assumption. Liftio's changelog refers to "every
      paid customer in production v1.3.0", so a handful may exist. If any do,
      they need a manual grant, not a redesign.
- [ ] Create store products on both stores: **£1 Coaching** → `product = 'paid'`,
      **£3 Premium** → `product = 'premium'`. This is a pricing change as well
      as a platform one — Liftio sold a single £1.99 tier.
- [ ] **Wire RevenueCat into the app** (`purchases_flutter`): configure with the
      public SDK key, identify the customer as the Supabase user id so the two
      systems agree on who somebody is without a mapping table, and drive the
      paywall from its offerings rather than from prices hardcoded in
      `_Tiers`.
- [ ] **A RevenueCat webhook → `core.entitlements`.** One Edge Function, with
      the shared-secret check RevenueCat signs its calls with, writing the row
      under `service_role`. This replaces both validators: renewal, expiry,
      grace, refund and revocation all arrive as the same event shape rather
      than as two vendors' formats.
- [ ] **The client never trusts the SDK for access.** RevenueCat's cached
      customer info decides what the *paywall* shows; `core.entitlements`
      decides what the *server* serves, which is already how the coach function
      gates. Two sources for "has this person paid" is how the wrong one gets
      reached for, and the server's is the one that cannot be edited from a
      jailbroken phone.
- [ ] **A manual grant path before any of it.** A SQL function usable from
      Supabase Studio to set somebody's entitlement. This is the support escape
      hatch, and Liftio needed exactly this repeatedly. Cheap now, invaluable
      the first time a purchase does not land — and it is what the TestFlight
      test sheet already depends on to exercise the paid half at all.
- [ ] **Auto-renew disclosure, verbatim** — Phase 2's blocked item lands here,
      because this is when there is a point of purchase to put it at. Guideline
      3.1.2(a) wants the full 24-hour cancellation window in the terms *and* at
      the point of purchase. `docs/terms-of-use.md` carries the marker, and a
      test in `legal_copy_test.dart` currently fails if anybody writes half of
      it — clear that test by writing the whole thing, not by deleting it.
- [ ] Sandbox-test both stores end to end: buy, renew, cancel, refund, restore
      on a second device.

### Kept, because it is the argument to revisit

The case for owning validation was: no dependency on a third party for the thing
that decides who has paid, no per-transaction cut, and a webhook we can replay.
It also came with an admin dashboard — **deliberately not release-blocking**,
because the manual grant path covers the same emergency at a fraction of the
cost.

If RevenueCat's pricing, uptime or data handling ever becomes the problem, the
migration is bounded by design: `core.entitlements` is already the only thing
the app reads, so replacing the webhook with the two validators above is a
server-side change with no client release. Scope for the dashboard when it is
wanted: users and their entitlements, grant and revoke, and a log of store
events received.

## Phase 4 — Android

Entirely new ground: ADR-0001 is iOS-first, `codemagic.yaml` says "No Android
workflow, deliberately", and Liftio never shipped to Play.

- [x] **Release signing wired.** `build.gradle.kts` now reads Codemagic's
      `CM_KEYSTORE_*` variables first and a local gitignored `key.properties`
      second. It **refuses to fall back to the debug key on a CI machine** and
      fails the build instead, because Play accepts a debug-signed upload and
      rejects it afterwards — a failure that looks like success. Locally the
      fallback stays so `flutter run --release` works without the upload key,
      behind a banner rather than a `logger.warn`, which Flutter's Gradle output
      filtering swallows. `key.properties.example` documents the four values and
      carries the `keytool` invocation.
- [x] Add an Android workflow to `codemagic.yaml` (`lift-android-release`), and
      correct the header that said there deliberately wasn't one — that decision
      is Run's and does not extend to Lift. Runs on `linux_x2`: nothing about an
      Android build needs Xcode, and macOS costs several times more per minute.
- [ ] **Create the upload keystore** and add it to Codemagic as
      `liftio_upload`. Nothing in this repo generates one — an upload key Play
      has seen cannot be swapped without Google's intervention.
- [ ] Google Play Console: create the app, claim `com.mgkcodes.liftio`. Nothing
      claims it today; Liftio declared the package in `app.json` but never
      shipped to Play, so this is a clean first upload with no migration.
- [ ] Store listing, content rating, and the **Data safety form** — it must
      match reality, including the AI provider and health-adjacent data.
- [ ] **Upload the first `.aab` by hand.** The Play Developer API can add a
      release to an existing listing but cannot create one, so the first bundle
      goes through the Console UI. The workflow's `publishing:` block is
      commented out until then — enabling it earlier turns a working build into
      a failing one at the last step.
- [ ] Google Play service account (Release manager), JSON pasted into
      `GCLOUD_SERVICE_ACCOUNT_CREDENTIALS`, then uncomment `publishing:`.
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
      plainly that this is a rewrite. The listing name changes from `Liftio` to
      `MGKFitness: Lift` in the same submission — existing users see the icon
      label change, so the release notes should say so rather than let it look
      like a different app installed itself.
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
