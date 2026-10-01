# Lift 2.0.0: what is left before both submissions

The one current list of what stands between `apps/mgk_lift` and two store
submissions, App Store and Google Play.

**Checked 1 October 2026** against `develop` at `db88a4f`, the production
Supabase project, the live site and Codemagic's build list. Each line under
*Where it stands* says how it is known.

This file replaces `release-2.0.0.md`, the 30 September handover, the August
punch list and this file's own earlier draft. All four described a branch, a
payments plan and a set of blockers that no longer exist. They are frozen in
[history/](history/README.md), as they were at `db88a4f`.

Tick items as they land. When something is settled differently from how it is
written here, change the item and say why.

---

## Where it stands

| | State | Known by |
|---|---|---|
| The app | The redesign is finished: 68 of 68 items in [lift-2.0.0-redesign.md](lift-2.0.0-redesign.md), merged into `develop` beside Run | `flutter analyze` clean and 860 tests passing, run 1 October |
| The screens | 86 plates on the [Lift Screen Board](https://claude.ai/artifact/UZKDFbA8qht1Nj9TQ3dQB1), version 16 | Rendered from `develop` at `db88a4f`. Every plate matches version 15's, so the merge changed nothing on screen |
| Edge Functions | `coach` v31, `revenuecat` v10, `delete-account` v19 | Listed from production, 1 October |
| Database | `20260929120000_lift_save_workout.sql` is **not applied**. The ledger ends at `release_hardening`; the photo-deletion routine was applied by hand on 1 October and is not in it | Listed from production, 1 October. The app falls back to four requests per workout, so nothing is broken |
| The site | `/lift/privacy`, `/lift/terms`, `/lift/ai-disclosure`, `/lift/support`, `/lift/delete-account` and `/reset-password` all answer 200, and the policy names SMTP2GO | Fetched 1 October |
| Email and sign-in | SMTP2GO, email confirmation on, Apple and Google configured | Recorded done on 30 September in [store-setup.md](store-setup.md) steps 6 and 7. Not checked again today |
| Builds | The last Lift builds are from 29 September, commit `4d12c46`: iOS 2.0.0 (32) on TestFlight, and an `.aab` uploaded to Play's internal testing as a draft | Codemagic's build list, 1 October |
| The stores | No Lift product is recorded as created in App Store Connect, Play or RevenueCat, nor the Codemagic group `mgk_fitness_lift_env` | No dashboard box in store-setup.md steps 0, 1, 3, 4 or 5 is ticked, and the group is commented out in both Lift workflows. Not checked in the dashboards themselves |

**Built on 1 October, on the branch `docs/lift-release-checklist`, and not yet
merged into `develop`:** "Delete my Lift data" taking the progress photos (the
function, a migration, the app's wording, the policy and the web page), and
the support address `lift@mgkfitness.mgkcodes.com` everywhere Lift names one.
Both are deployed and live (step 1 below): the function, the migration and the
web pages. The app's half ships with the next build. Analyzer clean, 860 Lift
tests and 16 function tests passing. The pgTAP cases for the migration have
not run, because this machine has no Docker; the routine was proved against
production on a throwaway account instead.

Two things follow from that table.

**Nothing a phone has run is the app that will ship.** Build 32 predates the
whole redesign and Sign in with Apple and Google. The first build of the
finished app is the release candidate.

**A build cut today could not sell.** Without the RevenueCat keys in Codemagic
the app passes no store at all, and says subscriptions are not open.

**After a fresh checkout, run `dart run build_runner build
--delete-conflicting-outputs` in `apps/mgk_lift` before the tests.** The
generated database code is not in git. With a stale copy the analyzer reports
49 issues and 18 tests fail, which is what this checkout did on 1 October until
it was regenerated.

---

## The decisions this rests on

Settled 2 September 2026. The numbers are kept because other files cite them.

1. **Payments ship in 2.0.0**, through RevenueCat.
2. **Both stores.** iOS is an update to Liftio's listing, bundle id
   `com.mgkcodes.liftio` ([ADR-0001](decisions/0001-liftio-is-replaced-not-relaunched.md)).
   Android is a first release.
3. **The legal documents ship without legal review**, at
   `mgkfitness.mgkcodes.com/lift`.
4. **No annual tier.** Two monthly tiers. Liftio's legacy products keep
   renewing for whoever holds one
   ([store-setup.md](store-setup.md) step 0).
5. **The web pages live in this repository**, under `web/`, generated from
   `apps/mgk_lift/docs/*.md` by `tool/build_legal_pages.py`.
6. **The tiers are named, never priced.** *Coach* and *Premium Coach*. No price
   is written into the app; it comes from the store.

Since then: Sign in with Apple and Google ship in 2.0.0, in both apps (the
redesign's R10), so guideline 4.8 now applies and is met by offering Apple
beside Google.

---

## What is left, in order

Owner is *Matthew* where it needs an account or a decision, *Claude* where it
is code or a command, and *both* where it needs a phone and a dashboard at once.

### 1. Dashboards and the database *(Matthew, with Claude)*

None of this waits on anything else, and the release candidate waits on most
of it. The three decisions that sat here were made on 1 October and are
recorded as ticked items.

- [ ] **[store-setup.md](store-setup.md) steps 0 to 5**, in its order: count
      Liftio's subscribers; the two App Store products; Play's subscriptions,
      service-account access and declarations; RevenueCat's two Lift apps,
      products and offering; the Codemagic group; `REVENUECAT_PRODUCTS`.
- [ ] **Apply `lift_save_workout`.** Claude Code's auto mode refuses production
      migrations even with a go-ahead, so either run the file in the Supabase
      SQL editor or allow `mcp__supabase__apply_migration` in
      `.claude/settings.local.json`. Then rename the file to the version the
      ledger records.
- [x] **Price: £0.99 Coach, £2.99 Premium Coach.** Decided 1 October. The
      coach's limits are sized per tier against those prices.
- [x] **"Delete my Lift data" deletes progress photos too.** Decided 1 October
      and built the same day: the photos are Lift's, though the table sits in
      `core`. Rolling it out is the next item.
- [x] **Photo deletion is rolled out.** All four steps on 1 October, in the
      order that keeps picture files from being orphaned.
      1. `delete-account` version 19, from `96c4f4c`. Production's version 18
         and its `core.delete_account` were checked first and were byte for
         byte what the repository holds.
      2. `20261001120000_lift_deletion_takes_progress_photos.sql`, run by
         Matthew in the Supabase SQL editor. The connector declined it twice
         with no prompt shown, even with the permission rule added. The routine
         in production then matched the file byte for byte, and only
         `service_role` can call it. **Applied by hand, so the migrations
         ledger has no row for it** and the file keeps its own timestamp.
      3. Proved on a throwaway account with one run, one photo row and one
         picture file. *Delete my Lift data* answered 200 with the login kept
         for Run, and left 1 run, 0 photo rows and 0 files. A full deletion
         then removed the run, the profile and the login.
      4. The web pages went to `main` (`69f39e3`, `24f81dc`) and are live:
         the deletion page lists the photos under Lift's data and the policy
         is dated 1 October.
- [x] **The support address is `lift@mgkfitness.mgkcodes.com`.** Decided 1
      October; the mailbox exists. Changed in the app (`kSupportEmail`), the
      three legal documents and their footer, the listing draft and the web
      pages, and live on the site. Two addresses on the site are still
      `hello@mgkcodes.com` and were left alone because both apps share them:
      the footer of every page (`web/app/layout.tsx`) and the reset-password
      page.
- [ ] **Merge this branch into `develop`**, which also brings `develop` level
      with what `main` now serves. `develop` has moved on since the branch was
      cut, and another session is working in that checkout, so the merge is
      for when that work is committed.
- [ ] **Google's sign-in branding** still links to Run's pages (store-setup.md
      7c). Point it at pages that cover both apps.
- [ ] **Liftio 1.x's listing.** The `/lift` pages now describe 2.0.0 while 1.x
      is the version in the store. Check which privacy URL the live listing
      uses.

### 2. The release candidate *(Claude, on Matthew's go)*

- [ ] **Track's UI first.** Matthew wants to go through elements of the Track
      tab before any build (1 October). No build is cut until that pass is
      done and its plates are back on the board.
- [ ] Uncomment `mgk_fitness_lift_env` in both Lift workflows in
      `codemagic.yaml`, once the group exists (store-setup.md step 4).
- [ ] Uncomment `publishing:` in `lift-android-release`, once the service
      account has access to Lift's Play app (step 2).
- [ ] Build both platforms from `develop` with
      `scripts/codemagic-build.sh lift-ios-release develop` and
      `lift-android-release`. Lift's build number is Codemagic's project
      counter, so it is above 32 without a pubspec change.

A "Publishing failed" from Codemagic can be a successful upload: Apple answered
500 mid-upload on build 31 and the IPA arrived anyway. Read the step log before
building again.

### 3. On a phone *(both)*

The sheet is [testflight-2.0.0-test-sheet.md](testflight-2.0.0-test-sheet.md).
What has never run anywhere but a test or an emulator, and so decides the
release:

- [ ] **The upgrade.** A phone with Liftio 1.4.0 takes 2.0.0 as an update and
      signs in. Whether that lifter's history arrives has never been seen.
      ADR-0001 rests on it.
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

### 4. The store pages *(after the release candidate)*

- [ ] **Screenshots for both stores** *(Claude)*. Unblocked: they waited for
      the redesign. The capture script's viewport is fixed at 390×844; run it
      at 430×932 and DPR 3 for 1290×2796, which is Apple's 6.9-inch size and
      within Play's.
- [ ] **One review screenshot per subscription** *(Claude)*: the sales screen,
      plate P8, at the same size.
- [ ] Play's feature graphic (1024×500) and icon (512×512) *(Claude designs,
      Matthew approves)*. Decided 1 October: the store assets are Claude's to
      design, after Track's UI is settled.
- [ ] Listing copy, pasted from [store-listing.md](store-listing.md)
      *(Matthew)*.
- [ ] Privacy labels and the Data safety form, from the same file *(Matthew)*.
      One check first: RevenueCat's own privacy manifest.
- [ ] Age rating, content rating, target audience, ads declaration
      *(Matthew)*. The answers are drafted in store-listing.md.
- [ ] **A demo account for review** *(both)*: confirmed, which now needs a
      real mailbox, and entitled with `core.grant_entitlement()`.

### 5. Submit

- [ ] iOS: 2.0.0 with both subscriptions attached to the version. The listing
      is renamed from *Liftio* to *MGKFitness: Lift* in the same submission.
- [ ] Android: internal testing, then production.
- [ ] When both apps have shipped: promote `develop` to `main`
      ([CONTRIBUTING.md](../../../CONTRIBUTING.md), Branching).

---

## The two stores, line by line

### App Store

| Item | State |
|---|---|
| A build of the shipping app, uploaded and processed | Open: the release candidate |
| 6.9-inch iPhone screenshots | Open |
| Description, keywords, promotional text, what's new | Drafted in store-listing.md |
| Privacy policy URL and support URL | Live |
| App privacy labels | Drafted; RevenueCat's manifest to check |
| Age rating | Open; answers drafted |
| Subscriptions submitted with the version, a review screenshot each | Open: store-setup.md step 1 |
| Renewal terms at the point of purchase and in the terms | In the code: the sales screen and the terms |
| Restore purchases | In the code: the sales screen and the account screen |
| Sign in with Apple beside Google (4.8) | In the code; never run on a phone |
| In-app account deletion, Apple's tokens revoked | In the code on iOS; `delete-account` v18 deployed |
| Demo account, confirmed and entitled | Open |
| Export compliance, camera and photo-library strings | Done |
| iPhone only | Set; unconfirmed on a build |

### Google Play

| Item | State |
|---|---|
| Console app, `com.mgkcodes.liftio` claimed | Done 30 September |
| Upload key | Done: the suite's `mgkfitness_upload` |
| First `.aab` uploaded by hand | Done, as a draft on internal testing. It is a build from before the redesign |
| `INTERNET` in the release manifest | Done |
| Subscriptions as base plans | Open: store-setup.md step 2 |
| Service-account access, then `publishing:` in the workflow | Open |
| Phone screenshots, feature graphic, 512×512 icon | Open |
| Short and full description | Drafted in store-listing.md |
| Content rating, target audience, ads declaration | Open; answers drafted |
| Data safety form | Drafted |
| Privacy policy URL, account deletion URL | Live |
| Support email | `lift@mgkfitness.mgkcodes.com` |
| A release build on a real phone | Open |

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
- **No legal review** (decision 3). Two questions are still open with
  OpenRouter: a processor agreement covering special-category data, and
  whether the three documents should now say that inputs are not trained on.
  The account has enforced Zero Data Retention on every provider since 30
  September; the documents still claim neither way.

For 2.0.x: a coach that offers a workout from chat, and joining an Apple
account to an email account in Settings.

## Not Lift's, and able to hurt it

Nothing in this section is Lift's work, and none of it needs another app's
plans or checklists read. It is here so a surprise from outside is recognised.

- **Both apps sign into one account.** An account made with Apple or Google in
  Lift can only sign into Run from a Run build that has those buttons. The code
  for both is already on `develop`.
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
