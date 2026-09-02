# Getting Lift 2.0.0 submitted, on both stores

The goal is **two submissions sent** — App Store and Play — not two approvals.
Review outcome is a separate problem with a separate plan.

**Nothing is cut to protect a date.** An earlier draft of this file was
schedule-shaped and trimmed work to fit a Friday; that was the wrong instinct and
it is gone. What follows is everything that has to be true before either Submit
button is honest, ordered by what depends on what rather than by day. Pace is not
this document's business.

Same discipline as [release-2.0.0.md](release-2.0.0.md): tick items as they land,
and when something is settled differently from how it is written here, **change
the item and say why**.

This does not replace [release-2.0.0.md](release-2.0.0.md). That file holds the
reasoning for each phase. This one is the ordering, the exhaustive per-store
submission checklists, and **five blockers that appear on no phase of it**.

---

## The decisions this rests on

Settled 2026-09-02. Each alternative was put and declined; recorded so they read
as decisions rather than drift.

1. **Payments ship in 2.0.0.** Shipping free with payments in 2.1.0 was offered
   and declined. Phase 3 is on the critical path in full, and it brings the
   auto-renew disclosure with it.
2. **Both stores.** iOS-only was offered and declined.
3. **Legal documents ship best-effort, with no legal review.** They will live at
   `mgkfitness.mgkcodes.com/lift`; `getliftio.com` is retired rather than
   corrected, and the "draft, legally unreviewed" banners come out of the shipped
   copy.
4. **No annual tier.** Liftio sold £19.99/yr beside its monthly. 2.0.0 ships two
   monthly tiers only — £1 Coaching and £3 Premium. This is now settled rather
   than omitted; revisit when there is renewal data to price an annual against.

## The two submissions are not the same shape

Half the work below applies to one and not the other.

**iOS is an update to an existing listing.** ADR-0001 says Liftio is *replaced,
not relaunched*: the bundle id is `com.mgkcodes.liftio`, the App ID and
provisioning already exist, the App Store Connect record already exists, and
TestFlight was used on 2026-08-21. Nothing needs creating.

What needs care is what is already there. **Liftio is live on the App Store
today**, and 2.0.0 renames that listing to *MGKFitness: Lift*. So this is a
rename of a shipping product with real users on it, and everything below that
concerns legacy subscribers is a live concern rather than a precaution.

**Android is a first upload.** Liftio never shipped to Play. The Console record,
the package claim, the keystore, the listing, the content rating and the Data
safety form are all new. The account already has production access because frunt
is live on it, so the 14-day closed-testing gate for new personal accounts does
not apply.

---

## Five blockers, found by reading the code

None of these are on `release-2.0.0.md`. Ordered by what they cost if missed.

### 1. The Android release build has no network access

`android/app/src/main/AndroidManifest.xml` declares **no permissions at all**.
`INTERNET` appears only in `debug/AndroidManifest.xml` and
`profile/AndroidManifest.xml`, which is Flutter's default template and applies to
those build types only.

Confirmed against a merged release manifest already on disk
(`build/app/intermediates/merged_manifest/release/processReleaseMainManifest/`):
the only permission present is the auto-generated
`com.mgkcodes.liftio.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`.

So a **release** Android build cannot make a single network request. Sign-in,
sync, the coach, plan generation and photo upload all fail. It works perfectly
under `flutter run`, which is exactly why nothing has caught it — and Phase 4's
*"Internal testing track, installed on a real Android device"* has never been
ticked, so no release build has ever been run.

**Fixed 2026-09-02**, and proved rather than assumed. The permission is in the
main manifest with a comment saying why it cannot be tidied away, and a release
APK was built: the **packaged** manifest —
`build/app/intermediates/packaged_manifests/release/processReleaseManifestForPackage/` —
now carries `android.permission.INTERNET` where before it carried only the
auto-generated receiver permission.

**Still open, and the more important half:** install that release build on a real
device and sign in. The permission was one line; the finding was that no release
Android build had ever been executed, and a manifest fix proves nothing about the
rest of it. That item lives in workstream E.

### 2. Restore Purchases does not exist

A grep over `apps/mgk_lift/lib` finds no restore affordance of any kind.
Guideline 3.1.1 requires one in any app selling a subscription, and it is checked
mechanically — a rejection, not a risk.

It is not merely a compliance box: somebody reinstalling, or signing in on a
second device, has no other route back to what they paid for. Phase 3 mentions
"restore on a second device" only as a *sandbox test step*, which quietly assumes
a button nobody built.

**Work:** a Restore purchases affordance on both paywalls and in Settings,
calling RevenueCat's `restorePurchases()`, then re-reading `core.entitlements`.

### 3. `onSubscribe` is wired to nothing, in two places

`plan_surface.dart` and `photos_surface.dart` both take a nullable
`VoidCallback? onSubscribe`, and nothing passes one. There are **two** paywall
surfaces to wire, not one; the plan only ever discusses the Plan paywall.

`plan_surface.dart:257` already renders `Start coaching — £1/mo` above a £1/£3
tier table, and `photos_surface.dart` renders `Unlock photos`. Prices and offers
on screen with no purchase path behind them is Guideline 3.1.1, so both facts
have to change in the same build.

### 4. The app is built universal, and has never been an iPad app

`TARGETED_DEVICE_FAMILY = "1,2"` in all three build configurations. That declares
iPad support, so Apple requires **13-inch iPad screenshots** and reviews the app
on an iPad.

Nothing here was laid out for one. The capture harness says so in as many words —
*"A phone, because that is the only place this app runs"* — and every plate on the
screen board is a 390×844 portrait phone.

**Done 2026-09-02.** Set to `"1"` in all three build configurations. That
removes an entire screenshot set and an entire class of rejection — shipping a
universal binary nobody has opened on an iPad is how a release gets rejected for
something unrelated to it.

Not verifiable from here: the change is in `project.pbxproj` and only an actual
iOS build confirms Xcode agrees. It is on the next TestFlight cut.

### 5. Liftio's existing subscribers

**Liftio is confirmed live on the App Store as of 2026-09-02.** The listing
becomes *MGKFitness: Lift* with 2.0.0 — a rename of a shipping product, not a new
record. So this blocker is real rather than hypothetical, and it is the one item
here that can hurt people who have already paid.

Phase 3 lists "confirm the subscriber count is zero" as a checkbox. Because iOS
reuses that live listing, it is a migration rather than a check: Liftio sold a
**£1.99/mo** and a **£19.99/yr** tier, and its own changelog refers to *"every
paid customer in production v1.3.0"*.

The annual tier makes it sharper. Decision 4 says 2.0.0 sells monthly only, so
anybody on **£19.99/yr** holds a product with no successor in the new lineup.
They must keep what they paid for until their term ends — which means the legacy
annual product stays in the group, off sale, and mapped to `paid` like the rest.

Anyone still active holds a product id 2.0.0 does not recognise, and
`core.entitlements` has no row for them — so on the day this ships they open a
paid app and are asked to subscribe again.

**Work:** count them first. Then keep the legacy products in the **same
subscription group** as the new £1/£3 tiers and take them **off sale rather than
deleting them**, map the legacy product ids to `product = 'paid'` in the webhook,
and backfill entitlement rows for anyone still active.
`core.grant_entitlement()` covers whoever slips through.

---

## Workstreams

Ordered by dependency. **B blocks almost everything else**, which is why it is
first; A is already done and listed so the foundation is visible.

Owner is `you` where it needs an account I cannot reach, `me` where it is code,
and `both` where it needs a device and a dashboard at the same time.

### A. Identity and store records — done

- [x] Bundle id and `applicationId` are `com.mgkcodes.liftio`; App ID and
      provisioning reused from Liftio (Phase 0).
- [x] `version: 2.0.0+1`. Build numbers must strictly increase within the train.
- [x] Display names: `Lift` on the device, `MGKFitness: Lift` on the listing.
- [x] App Store Connect record exists; TestFlight used 2026-08-21.

### B. Payments — the mass of the remaining work

Nothing in F or G can be finished until a build can take money.

- [ ] **Count Liftio's live subscribers** *(you)* — blocker 5. Everything else in
      this section is shaped by the answer.
- [ ] Create store products *(you)*: **£1 Coaching** → `product = 'paid'`,
      **£3 Premium** → `product = 'premium'`, on both stores. On Apple they go in
      the existing subscription group beside the legacy tiers.
- [x] **Annual tier: no.** Settled 2026-09-02 as decision 4 — monthly only. The
      legacy £19.99/yr product still has to survive for whoever holds one, which
      is blocker 5's problem rather than a pricing one.
- [ ] RevenueCat project, both store integrations, public SDK keys *(you)*.
- [ ] Wire `purchases_flutter` *(me)*: configure with the public key, identify the
      customer as the Supabase user id so the two systems agree on who somebody is
      without a mapping table, and drive **both** paywalls from offerings rather
      than the hardcoded `_Tiers` — blocker 3.
- [ ] **Restore Purchases** *(me)* — blocker 2.
- [ ] **The webhook Edge Function → `core.entitlements`** *(me)*: one function,
      shared-secret check, writing under `service_role`. Renewal, expiry, grace,
      refund and revocation arrive as one event shape. Maps legacy Liftio product
      ids to `paid`.
- [ ] **The client never trusts the SDK for access** *(me)*. RevenueCat's cached
      customer info decides what the *paywall* shows; `core.entitlements` decides
      what the *server* serves, which is already how the coach function gates.
- [x] **A manual grant path.** `core.grant_entitlement()` and
      `core.revoke_entitlement()`, keyed by email, `service_role` only, written
      2026-09-02 as `20260902120000_manual_entitlement_grant.sql`.
- [x] **Applied to production 2026-09-02, and verified there.** Both functions
      are `security definer` with `search_path=""`; `authenticated` and `anon`
      cannot execute either and `service_role` can; and a grant for an unknown
      address raises with its hint rather than silently doing nothing. The one
      real entitlement row was not touched.
- [ ] **The auto-renew disclosure, in full** *(me)*, at both points of purchase
      and in the terms. Liftio's already-accepted wording: *"Subscription
      auto-renews unless cancelled at least 24 hours before the end of the current
      period. Manage in Settings."* Clear `legal_copy_test.dart` by writing the
      whole disclosure, not by deleting the test.

### C. Compliance and legal copy

- [x] Terms, privacy policy and AI disclosure exist, reachable from Settings ▸
      Privacy & legal and from the sign-in screen.
- [x] Account deletion, both scopes, proved against production 2026-09-01.
- [x] Third-party AI disclosure surfaces: the coach sheet mark, the Settings
      switch, the dedicated screen.
- [x] **Strip the "draft, legally unreviewed" banners.** Done 2026-09-02. They
      did not simply go: each carried real open items, and deleting the banner
      would have deleted those with it. They moved into **HTML comments**, which
      no markdown renderer emits — so the published page is clean while the note
      stays beside the claim it is about. The two that matter are tracked below
      rather than left in a comment.
- [x] **`getliftio.com` references: nothing to repoint.** Checked 2026-09-02, and
      the answer is better than the item assumed — **the shipped app contains no
      URLs at all**. The only domains in `legal_copy.dart` are
      `hello@mgkcodes.com` email addresses. Every remaining `getliftio.com` in the
      repo is ADR, README or roadmap narrative *about* the domain being retired,
      where naming it is correct. The user-facing repoint was already a no-op.
- [x] **Publication date set** to 2 September 2026 in all three documents,
      replacing `[date]`.
- [ ] **Publish the documents at `mgkfitness.mgkcodes.com/lift`** *(you)*. The
      privacy policy URL is a required field in **both** App Store Connect and
      Play's Data safety form, which makes a one-page site a submission blocker
      for both stores.
- [ ] **A processor agreement with OpenRouter** covering special-category data
      *(you)*. Carried out of the stripped banners; it was open before and is open
      still.
- [ ] **Confirm whether the configured `COACH_MODEL`'s provider trains on
      inference inputs** *(you)*. A per-model property, so changing the model can
      change the answer. All three documents deliberately claim neither way until
      it is settled, which is defensible but not permanent.
- [ ] **Name RevenueCat as a processor** in `docs/privacy-policy.md` *and*
      `legal_copy.dart`, in the same commit that wires it *(me)*.
      `legal_copy_test.dart` has a case — *"names every processor it sends data
      to"* — that fails when a processor reaches the pipeline without reaching the
      reader. It is the right tripwire and must be cleared by writing the policy,
      not by editing the list.

One worry checked and dismissed: Lift invokes only the `coach` function. It never
calls `daily-ai-summary`, so the Anthropic-direct debt in Phase 5 is not a hole in
this app's AI disclosure. OpenRouter is the only provider Lift's data reaches, and
that is what the disclosure says.

### D. Accounts and email

- [ ] **Configure SMTP** *(you)*. Confirmation is back on and there is no custom
      SMTP, so Auth falls back to Supabase's shared testing mailer, which is
      capped at a handful of messages an hour project-wide. Live check
      2026-09-02: **13 users, all confirmed, none created since 2026-08-10** —
      nobody has successfully signed up since the toggle went back on.
- [ ] Prove a real sign-up end to end afterwards *(both)*, on a real domain —
      Supabase Auth rejects `example.com` and `.invalid` outright.

### E. Builds and signing

- [x] iOS release signing and the `lift-ios-release` Codemagic workflow.
- [x] Android release signing wired; `lift-android-release` workflow exists.
- [x] **`INTERNET` in the main Android manifest** — blocker 1. Done and proved
      against a rebuilt packaged manifest 2026-09-02.
- [x] **`TARGETED_DEVICE_FAMILY` → `"1"`** — blocker 4. Done 2026-09-02; confirmed
      by an iOS build rather than a grep is still outstanding.
- [ ] **Create the upload keystore** *(you)*, back it up permanently, add to
      Codemagic as `liftio_upload`. An upload key Play has seen cannot be swapped
      without Google's intervention.
- [ ] Cut a fresh TestFlight build *(me)*. The current one predates coach v21 and
      gets `400 conversation required` on every coach request.
- [ ] **Install a release Android build on a real device and sign in** *(both)*.
      This is the step that would have caught blocker 1, and no substitute for it
      exists.

### F. Store assets and metadata

- [ ] **Screenshots for both stores** *(me)*. The preview harness already renders
      every screen; `capture_screens_web.mjs` hardcodes a 390×844 viewport, and
      making that configurable and running at 430×932 @ DPR 3 yields 1290×2796 —
      Apple's 6.9-inch requirement, and comfortably within Play's. One run covers
      both stores with real screens over seeded data.
- [ ] Feature graphic, 1024×500 *(you)* — Play only, and it needs designing
      rather than capturing.
- [ ] Store icon, 512×512 *(you)* — Play.
- [ ] Listing copy for both *(you)*: title, subtitle/short description, full
      description, keywords, what's new for 2.0.0.
- [ ] **Privacy nutrition labels (iOS)** and the **Data safety form (Play)**
      *(you, drafted by me)*. This app is the awkward case — progress
      photographs, health-adjacent training data, and free-text injury notes sent
      to a third-party AI provider. RevenueCat's own collection has to be
      declared too. I will draft both from the code so the step is transcription
      rather than judgement.
- [ ] Content rating questionnaire, target audience and ads declaration *(you)* —
      Play.
- [ ] Age rating *(you)* — iOS.
- [ ] Subscription review screenshot, one per product *(you)* — Apple requires
      one for each.
- [ ] Reviewer demo account *(both)*, on an address that is confirmed **and**
      entitled, since the paid half is otherwise invisible to a reviewer.

### G. Proving it works

Reinstated in full. An earlier draft cut most of this as "approval work rather
than submission work", which was a distinction that only made sense against a
deadline.

- [ ] **A sandbox purchase on each store** that reaches `core.entitlements`
      through the webhook *(both)*.
- [ ] **Renew, cancel, refund, revoke and restore** on each store *(both)*.
      Restore is blocker 2's feature and cannot ship unexercised; refund and
      revoke are the two paths that decide whether somebody keeps access they
      stopped paying for.
- [ ] **The progress-photo round trip on a device** *(both)*: shutter, upload,
      delete, and a restore onto a second install. The rules are unit-tested and
      the storage sweep is proved against production, but the round trip itself
      has never run — it needs a camera.
- [ ] **Exercise the resumable coach transcript** *(both)*. Built on 2026-08-19,
      and as of 2026-09-01 there had never been a single `app = 'lift'`
      conversation in production, so the resume path has never once run against
      real data.
- [ ] **A full pass of `testflight-2.0.0-test-sheet.md`** *(you)* on the new
      build, with an entitled account.

---

## Submission checklists

The exhaustive per-store lists, so "are we ready" is answerable without reading
the rest of this file.

### App Store

| | Item | State |
|---|---|---|
| ☐ | Build uploaded and processed | needs E |
| ☐ | 6.9-inch iPhone screenshots | needs F |
| ☐ | Description, keywords, promotional text, what's new | needs F |
| ☐ | Privacy policy URL, live | needs C |
| ☐ | App privacy (nutrition labels) | needs F |
| ☐ | Age rating | needs F |
| ☐ | Subscriptions submitted with the build, review screenshot each | needs B |
| ☐ | Auto-renew disclosure at point of purchase and in terms | needs B |
| ☐ | Restore Purchases present | blocker 2 |
| ☐ | Demo account, confirmed and entitled | needs D + B |
| ☑ | Encryption declaration (`ITSAppUsesNonExemptEncryption: false`) | done |
| ☑ | Camera and photo-library usage strings | done |
| ☑ | In-app account deletion | done |
| ☑ | Terms and privacy reachable in-app | done |

Guideline 4.8 does not apply: sign-in is email and password, with no third-party
or social login, so no Sign in with Apple equivalent is required.

### Google Play

| | Item | State |
|---|---|---|
| ☐ | Console app created, `com.mgkcodes.liftio` claimed | needs E |
| ☐ | Upload keystore created and backed up | needs E |
| ☐ | `INTERNET` permission in the release manifest | blocker 1 |
| ☐ | First `.aab` uploaded **by hand** | needs E |
| ☐ | Phone screenshots, feature graphic, 512×512 icon | needs F |
| ☐ | Short and full description | needs F |
| ☐ | Content rating, target audience, ads declaration | needs F |
| ☐ | Data safety form | needs F |
| ☐ | Privacy policy URL, live | needs C |
| ☐ | Subscriptions as base plans | needs B |
| ☐ | Release Android build proven on a real device | needs E + G |

The Play Developer API can add a release to an existing listing but cannot create
one, so the first bundle goes through the Console UI and the workflow's
`publishing:` block stays commented out until it has.

---

## Out of scope

Named so they are decisions rather than omissions, each with the reason it cannot
hinder a submission.

- **Pose selection is session state** (Phase 5). A bug in a paid feature's
  preferences, not a submission gate.
- **Rest-timer buzz is foreground-only** (Phase 5). Needs a local-notification
  plugin; the timer works, it is the buzz that does not survive backgrounding.
- **`daily-ai-summary` calls `api.anthropic.com` directly** (Phase 5). Lift never
  invokes it — checked. It is Run's and the platform's debt.
- **`DAILY_GLOBAL_LIMIT` unset on production** (Phase 5). A legacy Liftio secret
  nothing reads.
- **Run's unscoped deletion erases Lift's data.** A real and serious bug, in
  run's lane, not fixable from this branch, and not reachable by a reviewer.
- **The RevenueCat admin dashboard.** Already marked not release-blocking;
  `core.grant_entitlement()` covers the same emergency.
- **iPad support**, per blocker 4.
- **Legal review**, per decision 3.

## Risks

1. **The Android release build has never run.** Blocker 1 is one line, but it was
   found by reading a manifest rather than by a failure, which means nothing else
   about that build has been verified either. Treat the first release install as
   discovery, not confirmation.
2. **Sandbox purchases rarely work first time.** Liftio's own 1.4.0 notes record
   *"firefighting two RC SDK bugs (singleton race, sandbox-alias entitlement
   invisible)"* — the same integration, on the same account. The manual grant path
   exists so a broken sandbox does not also block testing the entitled half.
3. **Legacy subscribers are an unknown.** Until they are counted, blocker 5 is
   either nothing or a migration, and the work differs by more than a day.
4. **Data safety and nutrition labels are judgement calls on a hard case.**
   Photographs of bodies, health-adjacent data, and free text to a third-party AI
   provider. Drafting them from the code removes the guessing but not the review.
