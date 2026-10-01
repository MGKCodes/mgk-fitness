# Lift 2.0.0: what is left before both submissions

The one current list of what stands between `apps/mgk_lift` and two store
submissions, App Store and Google Play.

**Checked on the evening of 1 October 2026**, when the Lift branch
(`feat/lift-2.0.0-candidate`) was merged into `develop`. Each line under *Where
it stands* says how it is known.

This file replaces `release-2.0.0.md`, the 30 September handover, the August
punch list and this file's own earlier draft, which are frozen in
[history/](history/README.md). *What is left* holds open items only. What was
finished on 1 October is recorded once, under *Done on 1 October*.

Tick items as they land. When something is settled differently from how it is
written here, change the item and say why.

---

## Where it stands

| | State | Known by |
|---|---|---|
| The app | Finished as designed, and all of it on `develop`: the redesign (R1 to R13), Track as a front page with *Your workouts* reworked (TR1 to TR9), the launch, and tabs that move | `flutter analyze` clean and 894 Lift tests passing, run 1 October after the merge |
| The screens | 91 plates on the [Lift Screen Board](https://claude.ai/artifact/UZKDFbA8qht1Nj9TQ3dQB1), version 18 | Rendered at `e2a20d5`, the commit build 41 was made from |
| Builds, iOS | **2.0.0 (41) is on TestFlight**, built from `e2a20d5`. Matthew used it on 1 October and is happy with it, the launch included. It is the release candidate unless the phone pass turns something up | Codemagic build `6abec3a503a04954ee43d4c7`, every step green; Matthew's phone |
| Builds, Android | The only `.aab` is from 29 September, before the redesign, sitting as a draft on Play's internal testing. **No Android build of the shipping app exists** | Codemagic's build list, 1 October |
| Edge Functions | `coach` v31, `revenuecat` v10, `delete-account` v19 | Listed from production, 1 October |
| Database | `20260929120000_lift_save_workout.sql` is **not applied**. The ledger ends at `release_hardening`; the photo-deletion routine was applied by hand on 1 October and is not in it | Listed from production, 1 October. The app falls back to four requests per workout, so nothing is broken |
| The site | `/lift/privacy`, `/lift/terms`, `/lift/ai-disclosure`, `/lift/support`, `/lift/delete-account` and `/reset-password` all answer 200, and the policy names SMTP2GO | Fetched 1 October |
| Email and sign-in | SMTP2GO, email confirmation on, Apple and Google configured | Recorded done on 30 September in [store-setup.md](store-setup.md) steps 6 and 7. Not checked again since |
| The stores | Lift's two subscriptions exist on both stores, RevenueCat has both Lift apps with their products in the current offering, Codemagic holds Lift's keys, and `REVENUECAT_PRODUCTS` maps Lift's four ids. Liftio's two legacy products are off sale. The App Store record is still named *Liftio*, which is the name TestFlight shows | Walked through with Matthew on 1 October, from his screenshots. [store-setup.md](store-setup.md) says what is still open |

Three things follow from that table.

**The iOS app that will ship has now run on one phone, once.** Build 41 is the
first build of the finished app. One evening's use is not the test sheet:
nothing in section 3 below has been ticked.

**Android has nothing to test.** Every Android item below waits for a build of
the shipping app.

**Build 41 can sell.** It carries Lift's own RevenueCat key, and the product
mapping has been set since 1 October. A sandbox purchase has not been tried.

**After a fresh checkout, run `dart run build_runner build
--delete-conflicting-outputs` in `apps/mgk_lift` before the tests.** The
generated database code is not in git. With a stale copy the analyzer reports
49 issues and 18 tests fail.

---

## The decisions this rests on

Settled 2 September 2026. The numbers are kept because other files cite them.

1. **Payments ship in 2.0.0**, through RevenueCat.
2. **Both stores.** iOS is an update to Liftio's listing, bundle id
   `com.mgkcodes.liftio` ([ADR-0001](decisions/0001-liftio-is-replaced-not-relaunched.md)).
   Android is a first release.
3. **The legal documents ship without legal review**, at
   `mgkfitness.mgkcodes.com/lift`.
4. **No annual tier.** Two monthly tiers. *Changed 1 October:* Liftio's legacy
   subscriptions end rather than carry over. Nothing maps them and nobody is
   granted access for holding one
   ([store-setup.md](store-setup.md) step 0).
5. **The web pages live in this repository**, under `web/`, generated from
   `apps/mgk_lift/docs/*.md` by `tool/build_legal_pages.py`.
6. **The tiers are named, never priced.** *Coach* and *Premium Coach*. No price
   is written into the app; it comes from the store.

Since then:

- Sign in with Apple and Google ship in 2.0.0, in both apps (the redesign's
  R10), so guideline 4.8 applies and is met by offering Apple beside Google.
- 1 October: £0.99 Coach and £2.99 Premium Coach; "Delete my Lift data" takes
  the progress photos; the support address is `lift@mgkfitness.mgkcodes.com`;
  Track is a front page on the layout Run's Home uses
  ([lift-2.0.0-track.md](lift-2.0.0-track.md)).

---

## What is left, in order

Owner is *Matthew* where it needs an account or a decision, *Claude* where it
is code or a command, and *both* where it needs a phone and a dashboard at once.

### 1. Dashboards and the database *(Matthew)*

None of this waits on anything else.

- [ ] **What the dashboard sweep left unconfirmed:**
      - neither new App Store product still shows the red banner;
      - each Play base plan is `monthly`, at £0.99 and £2.99;
      - Play Console › License testing has your Google account, for test
        purchases;
      - the Play service account (`mgk-fitness-play-publisher`) holds release
        permissions, which the Android workflow's `publishing:` needs;
      - the odd combined row seen in the App Store subscription group's list
        is gone after a refresh.
- [ ] **Decide whether Liftio's two paying subscribers are owed anything.**
      Their subscriptions end rather than carry over (decision 4). RevenueCat's
      old Liftio project showed four active customers on 1 October, two paying
      monthly and two who never paid. An older plan says Liftio 1.4.0 has not
      worked since 7 August, when its tables moved; that was not checked. If
      it is true, those two have been paying for an app that does not run. A
      refund, or nothing, is Matthew's call, and Apple issues it either way.
- [ ] **Confirm Play will let this account publish to production.** Google
      asks developer accounts registered as personal after November 2023 to
      run a closed test with 12 testers for 14 days first. If MGKCodes'
      account is one of those, Android's date moves by at least two weeks, so
      find out now. Not checked: it needs the Console.
- [ ] **Apply `lift_save_workout`.** Claude Code's auto mode refuses production
      migrations even with a go-ahead, so run the file in the Supabase SQL
      editor. Then rename the file to the version the ledger records. Until
      then the app uses four requests per workout, which works.
- [ ] **Google's sign-in branding** still links to Run's pages (store-setup.md
      7c). Point it at pages that cover both apps.
- [ ] **Liftio 1.x's listing.** The `/lift` pages now describe 2.0.0 while 1.x
      is the version in the store. Check which privacy URL the live listing
      uses.

### 2. Builds *(Claude, on Matthew's go)*

- [x] **iOS: 2.0.0 (41)**, on TestFlight since 1 October. `develop` now holds
      the same app code, so it does not need building again unless something
      changes.
- [x] **Android publishing is wired in**, since 1 October: the workflow names
      the `mgk_fitness_play` group and publishes to the internal track. Not
      yet exercised, because no build has run since.
- [ ] **Android.** Build `lift-android-release` from `develop`
      (`scripts/codemagic-build.sh lift-android-release develop`). Two things
      to expect from the first one:
      - **It publishes as a draft**, because Lift's app has no rolled-out
        release yet and Play refuses anything else for such an app. Testers
        see nothing until the draft is rolled out by hand: Play Console ›
        Testing › Internal testing. After that first rollout, change
        `submit_as_draft` to `false` in `codemagic.yaml`, as Run's is, so
        later builds reach testers on their own.
      - **If the publishing step fails on a green build**, the likeliest cause
        is the service account lacking release permission on Lift's app
        (step 1). The `.aab` is still in the build's artifacts and can be
        uploaded by hand.
- [ ] **RevenueCat's check on Play purchases** ("package name was not found")
      clears once that build is on internal testing. Look again then.
- [ ] **Tag what is built.** The suite's rule is that what shipped is a tag,
      and only Run has any (`run/build-6` to `run/build-26`). Build 41 was
      made from `e2a20d5`, which is on `develop`; `lift/build-41` belongs
      there if it becomes the release candidate, and every Lift build after
      it gets its own.
- [ ] **Run the pgTAP cases for photo deletion** (`supabase/tests/delete_account.sql`,
      20 cases). Written on 1 October and never run, because that machine has
      no Docker. The routine itself was proved against production by hand.

A "Publishing failed" from Codemagic can be a successful upload: Apple answered
500 mid-upload on build 31 and the IPA arrived anyway. Read the step log before
building again.

### 3. On a phone *(both)*

The sheet is [testflight-2.0.0-test-sheet.md](testflight-2.0.0-test-sheet.md),
written for build 41. Matthew's first evening with build 41 covered the look,
the launch and Track; none of the list below.

What has never run anywhere but a test or an emulator, and so decides the
release:

- [ ] **The upgrade.** A phone with Liftio 1.4.0 takes 2.0.0 as an update and
      signs in. Whether that lifter's history arrives has never been seen.
      ADR-0001 rests on it, and the listing copy promises it.
- [ ] **Signing in**, three ways, on both platforms: Apple, Google, email with
      a confirmation link. An existing Liftio Apple account gets back in. A
      second account on the same phone meets the guard.
- [ ] **A sandbox purchase on each store** that reaches `core.entitlements`
      through the webhook and unlocks the screen it was bought from. Then
      renew, cancel, refund and restore.
- [ ] **Deleting an account** made with Apple, on an iPhone: Apple asks, and
      the tokens are revoked.
- [ ] **A release Android build on a real phone.** Only the emulator has run
      one.
- [ ] **Progress photos, round trip:** shutter, upload, delete, restore on a
      second install.
- [ ] **The coach reopened** on a conversation it already had.
- [ ] **The rest alert on a locked iPhone.** Proved on an Android emulator
      only.
- [ ] **Larger text.** Only the new and reworked screens are pinned at 1.3×
      and 2×.
- [ ] **A profile build on an iPhone:** no dropped frames scrolling a
      six-movement session under the glass.
- [ ] **TestFlight offers it for iPhone only.** `TARGETED_DEVICE_FAMILY` is
      `1`; no build has been checked for it.

### 4. The store pages

- [ ] **Screenshots for both stores** *(Claude)*. Unblocked now that the
      screens are settled. The capture script's viewport is fixed at 390×844;
      run it at 430×932 and DPR 3 for 1290×2796, which is Apple's 6.9-inch
      size and within Play's.
- [ ] **One review screenshot per subscription.** Rendered on 1 October: the
      sales screen at 1290×2796, in
      `apps/mgk_lift/screenshots/store/subscription-review-1290x2796.png`
      (not in git). *Matthew* uploads it to both App Store products, with the
      review notes in store-setup.md step 1.
- [ ] Play's feature graphic (1024×500) *(Claude designs, Matthew approves)*.
      The 512×512 icon exists: `design/store/play-listing-icon-512.png`.
- [ ] Listing copy, pasted from [store-listing.md](store-listing.md)
      *(Matthew)*. The *What's New* text now says that Liftio's old
      subscription has ended; read it before pasting, it is a draft.
- [ ] Privacy labels and the Data safety form, from the same file *(Matthew)*.
      One check first: RevenueCat's own privacy manifest.
- [ ] Age rating, content rating, target audience, ads declaration, and Play's
      account deletion URL *(Matthew)*. The answers are drafted in
      store-listing.md and store-setup.md step 2.
- [ ] **A demo account for review** *(both)*: confirmed, which now needs a
      real mailbox, and entitled with `core.grant_entitlement()`.

### 5. Submit

- [ ] iOS: 2.0.0 with both subscriptions attached to the version. The listing
      is renamed from *Liftio* to *MGKFitness: Lift* in the same submission
      (App Store Connect › App Information › Name). TestFlight shows *Liftio*
      until then.
- [ ] Android: internal testing, then production.
- [ ] When both apps have shipped: promote `develop` to `main`
      ([CONTRIBUTING.md](../../../CONTRIBUTING.md), Branching).

---

## The two stores, line by line

### App Store

| Item | State |
|---|---|
| A build of the shipping app, uploaded and processed | Done: 2.0.0 (41) |
| 6.9-inch iPhone screenshots | Open |
| Description, keywords, promotional text, what's new | Drafted in store-listing.md |
| Privacy policy URL and support URL | Live |
| App privacy labels | Drafted; RevenueCat's manifest to check |
| Age rating | Open; answers drafted |
| Subscriptions submitted with the version, a review screenshot each | Products exist; the screenshot is rendered and not uploaded |
| Renewal terms at the point of purchase and in the terms | In the code: the sales screen and the terms |
| Restore purchases | In the code: the sales screen and the account screen |
| Sign in with Apple beside Google (4.8) | In build 41; not yet tried on a phone |
| In-app account deletion, Apple's tokens revoked | In the code on iOS; `delete-account` v19 deployed |
| Demo account, confirmed and entitled | Open |
| Export compliance, camera and photo-library strings | Done |
| iPhone only | Set; unconfirmed on a build |
| The listing's name | Still *Liftio*; changes with the submission |

### Google Play

| Item | State |
|---|---|
| Console app, `com.mgkcodes.liftio` claimed | Done 30 September |
| Upload key | Done: the suite's `mgkfitness_upload` |
| First `.aab` uploaded by hand | Done, as a draft on internal testing. It is a build from before the redesign |
| A build of the shipping app on internal testing | Open: step 2 |
| `INTERNET` in the release manifest | Done |
| Subscriptions as base plans | Done 1 October; prices to confirm (step 1) |
| Service-account access, then `publishing:` in the workflow | Access granted 1 October; release permissions unconfirmed. `publishing:` is live, as a draft to the internal track; no build has used it yet |
| Phone screenshots, feature graphic, 512×512 icon | Icon done; the rest open |
| Short and full description | Drafted in store-listing.md |
| Content rating, target audience, ads declaration | Open; answers drafted |
| Data safety form | Drafted |
| Privacy policy URL, account deletion URL | Live; the deletion URL is not yet entered in the Console |
| Support email | `lift@mgkfitness.mgkcodes.com` |
| A release build on a real phone | Open |

---

## Done on 1 October

Kept short, as the record of how each was settled. The commits hold the rest.

- **The dashboards** ([store-setup.md](store-setup.md) steps 0 to 5), with
  Matthew. The two App Store products and their levels, Play's two
  subscriptions, RevenueCat's two Lift apps with products, entitlements and
  offering, Apple's server notifications, and the Codemagic group
  `mgk_fitness_lift_env`, named in both Lift workflows.
- **Liftio's subscriptions end rather than carry over.** Both legacy products
  are off sale and out of RevenueCat, nothing maps them, and the app no longer
  counts them as Lift's. `REVENUECAT_PRODUCTS` maps Lift's four ids beside
  Run's four, set by Matthew and checked by digest.
- **Price:** £0.99 Coach, £2.99 Premium Coach. The coach's limits are sized
  per tier against those prices.
- **"Delete my Lift data" deletes progress photos too**, rolled out in the
  order that keeps picture files from being orphaned: `delete-account` v19;
  then `20261001120000_lift_deletion_takes_progress_photos.sql`, run by
  Matthew in the SQL editor because the connector declined it (**so the
  migrations ledger has no row for it**); then proved on a throwaway account
  (a Lift-only deletion kept the login and the run, and left no photo rows or
  files); then the web pages, live from `main` (`69f39e3`, `24f81dc`). The
  pgTAP cases have not run: this machine has no Docker.
- **The support address is `lift@mgkfitness.mgkcodes.com`**, in the app, the
  three legal documents, the listing draft and the web pages. Two addresses on
  the site are still `hello@mgkcodes.com` and were left alone because both
  apps share them: the footer of every page and the reset-password page.
- **Track is a front page, and *Your workouts* is where a session starts**
  ([lift-2.0.0-track.md](lift-2.0.0-track.md)), with Run's shared tab motion
  and a launch of Lift's own.
- **Build 41**, from the Lift branch, and Matthew's go on it.
- **The branch is merged into `develop`**, together with `main`'s two web
  commits, so `develop` holds everything `main` serves. The branch and its
  worktree are removed.

---

## Shipping with these, knowingly

Each is a gap in 2.0.0 that somebody decided on or accepted. Say so in review
notes where a reviewer could meet it.

- **An account deleted on Android keeps its Apple tokens.** Android sends no
  authorization code; getting one needs Apple's web flow, a callback route on
  the site and that route on the Services ID. The policies claim revocation
  for iPhone only.
- **The summary's C opens the coach as it does anywhere**, not on the session
  just finished.
- **Plan's "how the week is going"** shows the plan's own counts, not sessions
  done against it.
- **A planned day cannot be moved in the plan itself.** *Do it today* is a
  choice on one phone for one day.
- **The chosen photo poses are not saved to the account.**
  `core.user_settings.progress_pose_set` exists and nothing writes it.
- **The rest alert is inexact on Android 14 and later**, by about 13 seconds,
  and is not Time Sensitive on iOS, so a Focus mode can hold it.
- **Starting a saved workout is two taps from Track**, where it was one
  (TR2). Accepted for a front page that reads at a glance.
- **No legal review** (decision 3). Two questions are still open with
  OpenRouter: a processor agreement covering special-category data, and
  whether the three documents should now say that inputs are not trained on.
  The account has enforced Zero Data Retention on every provider since 30
  September; the documents still claim neither way.

For 2.0.x: a coach that offers a workout from chat, and joining an Apple
account to an email account in Settings.

Tidying that can wait until after the stores, carried here from
[lift-2.0.0-track.md](lift-2.0.0-track.md) so it is not lost in a closed file:

- The three split photographs in `assets/images/splits/` are no longer drawn
  anywhere and still ship in the bundle.
- `ActionPill` and `HeroStatTile` in `mgk_ui` are used by neither app now.
  Removing them is a change to the shared package, so it needs both lanes.
- Lift's start button and its launch curtain are copies of Run's. If both
  apps keep them, they belong in `mgk_ui`.

## Not Lift's, and able to hurt it

Nothing in this section is Lift's work, and none of it needs another app's
plans or checklists read. It is here so a surprise from outside is recognised.

- **Both apps sign into one account.** An account made with Apple or Google in
  Lift can only sign into Run from a Run build that has those buttons. The code
  for both is already on `develop`.
- **One RevenueCat customer holds both apps' purchases.** Lift's Restore
  counts only Lift's products. Run's counts any active subscription, so a
  Lift-only subscriber pressing Restore in Run is told "restored" in front of
  a screen that stays locked. Found from Lift's side on 1 October; Run's to
  fix.
- **`C:\Projects\Runio\supabase\functions` still defines `coach` and
  `delete-account` against this Supabase project** (present on this machine, 1
  October). A deploy from that repository overwrites production's copies with
  ones that know nothing of Lift.
- **The OpenRouter key is one key with one monthly cap for both apps.**
  Reaching it stops the coach in Run and Lift until the month resets.
- **`daily-ai-summary` is still deployed** and calls Anthropic directly. Lift
  never invokes it.
- **Dates.** Supabase's Apple secret expires about 30 March 2027: regenerate
  it by 20 March or Android's Apple sign-in stops. The distribution
  certificate expires 30 September 2027.

## If RevenueCat becomes the constraint

Kept because `purchases.dart` points here for it. The case for owning receipt
validation was no third party deciding who has paid, no cut per transaction,
and a webhook that can be replayed. It was set aside on 1 September because
verifying Apple's signature chain and reconciling Play's notifications is a
lot of security-sensitive code for a product with no subscribers.

The way back is bounded by design. `core.entitlements` is the only thing the
app reads, so replacing the `revenuecat` webhook with two validators is a
server change with no client release.
