# Lift 2.0.0: what is left before both submissions

The one current list of what stands between `apps/mgk_lift` and two store
submissions, App Store and Google Play.

**Checked on the evening of 1 October 2026**, when the Lift branch
(`feat/lift-2.0.0-candidate`) was merged into `develop`, and **again on 2
October** against git, production and the site. Each line under *Where it
stands* says how it is known.

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
| The app | Finished as designed, and all of it on `develop`: the redesign (R1 to R13), Track as a front page with *Your workouts* reworked (TR1 to TR9), the launch, and tabs that move. On 2 October the screens Lift shares with Run were drawn as Run draws them (below, *Done on 2 October*) | `flutter analyze` clean and 898 Lift tests passing, 2 October |
| The screens | 91 plates on the [Lift Screen Board](https://claude.ai/artifact/UZKDFbA8qht1Nj9TQ3dQB1), version 19: sign-in, Settings and the account screen redrawn | Rendered 2 October, with the shared-screens change |
| Builds, iOS | **2.0.0 (41) is on TestFlight**, built from `e2a20d5`. Matthew used it on 1 October and is happy with it, the launch included. **It is no longer what `develop` builds**: the coach's line now opens out of its mark (`643c463`, shared with Run), and the sign-in, Settings and account screens changed on 2 October | Codemagic build `6abec3a503a04954ee43d4c7`, every step green; Matthew's phone. The difference: `git diff e2a20d5..develop`, 2 October |
| Builds, Android | The only `.aab` is from 29 September, before the redesign, sitting as a draft on Play's internal testing. **No Android build of the shipping app exists** | Codemagic's build list, 1 October |
| Edge Functions | `coach` v31, `revenuecat` v10, `delete-account` v19, none redeployed since | Listed from production, 1 October, and again on 2 October by their deploy times. The Supabase connector numbers the same deploys one higher (v32, v11, v20) |
| Database | `20260929120000_lift_save_workout.sql` is **not applied**: `lift.save_workout` does not exist in production. The photo-deletion routine was applied by hand on 1 October and is not in the ledger | Listed from production and the catalog read, 2 October. The app falls back to four requests per workout, so nothing is broken |
| The site | `/lift/privacy`, `/lift/terms`, `/lift/ai-disclosure`, `/lift/support`, `/lift/delete-account` and `/reset-password` all answer 200, and the policy names SMTP2GO | Fetched 1 October, and the six again on 2 October |
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
      find out now. *Very likely answered on 2 October:* the same developer
      account submitted Run 1.0.0 to production with no closed test. Not read
      off Lift's own Console page, which is the check that closes this.
- [x] **Apply `lift_save_workout`.** *Done 5 October:* the connector declined
      it twice, and Matthew ran the file in the SQL editor. Production has the
      function, as the caller, with `authenticated` able to run it and `anon`
      not (read back the same day). It is not in the migration ledger, since
      the editor writes none, so the file keeps its own version, as the photo
      deletion change kept its own. The app tries it first and falls back to
      four requests only where it is missing, so builds from now on send a
      workout in one request.
- [ ] **Google's sign-in branding** still links to Run's pages (store-setup.md
      7c). Point it at pages that cover both apps.
- [ ] **Liftio 1.x's listing.** The `/lift` pages now describe 2.0.0 while 1.x
      is the version in the store. Check which privacy URL the live listing
      uses.

### 2. Builds *(Claude, on Matthew's go)*

- [x] **iOS: 2.0.0 (41)**, on TestFlight since 1 October.
- [ ] **iOS again, from `develop`.** `develop` is no longer build 41's app
      (*Where it stands*), so a build from it is what both stores should ship
      from one commit, and what the phone pass should run on. Not before
      Matthew says builds may go. *Started 5 October* from `c0b7c0e`, the
      sweep's merge: Codemagic build `6ac3b8a95db35febf72b6d24`, publishing to
      TestFlight. Tick this when TestFlight offers it, and tag it.
- [x] **Android publishing is wired in**, since 1 October: the workflow names
      the `mgk_fitness_play` group and publishes to the internal track. Not
      yet exercised, because no build has run since.
- [ ] **Android.** Build `lift-android-release` from `develop`
      (`scripts/codemagic-build.sh lift-android-release develop`). *Started 5
      October* from `c0b7c0e`: Codemagic build `6ac3b8aea036e7e4d2ecdc68`.
      Two things to expect from the first one:
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
- [x] **Run the pgTAP cases for photo deletion** (`supabase/tests/delete_account.sql`,
      20 cases). *Done 5 October:* every database test passes (68, in five
      files) on a local database built from the migrations alone. The
      contract test was out of date, not the schema: it now names
      `core.waiting_list` beside `coach.usage` as deliberately unreachable.
      Production's `core.delete_account` deletes progress photos for a
      Lift-only deletion too (read on 5 October), though that change is not
      in the migration ledger: it went in by hand.

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

- [ ] **Screenshots for both stores** *(Claude draws, Matthew approves)*.
      Drawn on 4 October in Run's design, from Run's kit
      ([design/store-shots](../design/store-shots/README.md)): six pictures
      that follow Run's picture for picture, tagged free or subscription.
      `ios-still` is 1290×2796 (Apple's 6.9-inch size), `play-still` 1080×1920,
      both flattened, in `apps/mgk_lift/screenshots/store/listing/` (not in
      git). The screens come from the preview harness at Run's phone sizes and
      safe areas (`tool/capture_store_screens.mjs`). *Redrawn 5 October* on
      the final screens: Session complete with its title bar, the shared
      coach sheet, and the profile in Run's layout.
- [ ] **One review screenshot per subscription.** Rendered on 1 October: the
      sales screen at 1290×2796, in
      `apps/mgk_lift/screenshots/store/subscription-review-1290x2796.png`
      (not in git). *Matthew* uploads it to both App Store products, with the
      review notes in store-setup.md step 1. *Redrawn 5 October* as it
      ships: the coach's C, Coach labelled Recommended, one Subscribe button.
- [ ] Play's feature graphic (1024×500) *(Claude designs, Matthew approves)*.
      Drawn on 4 October with the screenshots: the mark at rest above `LIFT`,
      as the launch ends, then MGKFitness and "Log every set. Get a real
      plan.", in `apps/mgk_lift/screenshots/store/play-feature-graphic.png`.
      The 512×512 icon exists: `design/store/play-listing-icon-512.png`.
- [ ] Listing copy, pasted from [store-listing.md](store-listing.md)
      *(Matthew)*. The *What's New* text now says that Liftio's old
      subscription has ended; read it before pasting, it is a draft.
- [ ] Privacy labels and the Data safety form, from the same file *(Matthew)*.
      RevenueCat's own privacy manifest was checked on 2 October: it declares
      purchase history only, for app functionality, not linked and not
      tracking, which the table already has.
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
- [ ] When Lift goes for review, promote `develop` to `main`: `main` is what
      was submitted ([CONTRIBUTING.md](../../../CONTRIBUTING.md), Branching).
      Promoting all of `develop` deploys `web/`, so check what `web/` holds
      first. Then `develop` moves to 2.0.1 (CONTRIBUTING.md, Versions).

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

## Done on 2 October

- **The screens Lift shares with Run are drawn as Run draws them**, from one
  place in `mgk_ui` that Run's screens now use too (Run's 58 account, screen
  and arrival plates redraw byte for byte, and its 1,948 tests pass). The
  sign-in opens with Lift's icon and name and calls the login an *MGKFitness
  Account*, with Run's words and labels. Run's sign-in says the same, under
  Run's icon, from Run 1.0.1.
  Settings leads with the suite's profile card, carries Run's groups
  (Preferences, Your data, About, with a Support row) and its foot
  (*MGKFitness: Lift 2.0.0 · MGKCodes*), and says where backup stands in one
  row. The account screen is laid out as Run's: the person, backup with Sync
  now, the plan and Restore, then Sign out and Delete account. Track's
  *Review* opens it directly, since that is where refusals are listed. Back
  buttons Lift draws itself use the app bar's glyph, so an iPhone shows one
  kind of back everywhere.
- **The sign-in no longer says you do not need an account.** It is only
  opened to back up, from Settings, or to subscribe, from the sales screen,
  and on a screen somebody asked for the line read as a contradiction. From
  the sales screen its email form starts on *Create your account*, as Run's
  does when something needs an account; from Settings, on *Welcome back*.

## Done on 4 and 5 October

The sister-apps sweep: the two screen boards side by side, and every screen a
person meets in both apps made to look like one family's.

- **Profile is laid out as Run's**, section for section, after the two
  screen boards side by side showed two different apps. A *Profile* title bar
  over the photograph; the lifetime volume counting up in its own card over
  sessions, time and streak; the heaviest set and the biggest session as
  Run's two record tiles; the most-trained movements as Run's table; the year
  in the grid both apps now draw from `mgk_ui` (Run's five profile and year
  plates redraw byte for byte); and the last five sessions as Run's log, with
  *See all*. The six tiles, the consistency card, the "Nothing logged yet"
  card and its button went. Matthew's call: "I like the Run one".
- **Deleting says account, not profile**, on Privacy & legal and the account
  screen, as Run's does.
- **The session summary has a title bar**, as Run's finished run does:
  *Session complete* after Finish, *Session summary* from the log, with
  "Just now · Push" over the volume.
- **The coach is headed by Lift's icon and "Coach"**, and every wait for it
  is the breathing orb (`CoachOrb`) with *Thinking…*, not three dots. Run's
  coach has the same heading and orb from 1.0.1.
- **The coach sheet is the suite's** (`CoachSheetFrame`, `CoachTopBar`,
  `CoachComposer`, `CoachEmptyState` in `mgk_ui`): Lift's design, which Run's
  coach now draws too. Three changes a lifter will see: an empty coach offers
  three questions to tap, each starting a conversation of its own; the
  bubbles tuck in the corner nearest the speaker; and **the sheet rises above
  the keyboard**. It did not pad for it before, so on a phone the keyboard
  could come up over the field the sheet was opened to type into; check it
  on the TestFlight build. Also fixed: the previous-conversations labels
  counted days across a clock change wrongly ("Today" for yesterday, the day
  after the clocks move, 25 October next), as Run's did until 248d289.
- **The paywall is the suite's** (`CoachPaywall` in `mgk_ui`): one screen
  that fits a 390 × 844 phone without scrolling; the app's icon and name where
  the decision is made; four short benefit lines, each opening its detail on
  tap; the two tiers side by side with Coach chosen to start and Premium
  shown as "3× the coaching"; one *Subscribe* button that names the chosen
  price; the renewal terms in one line; Restore, Terms and Privacy at the
  foot. Matthew's brief: "those ticks must be read quicker and explanation
  can be found if you want". Run's paywall moves to the same screen in 1.0.1.
  Then, from his look at the board: Coach is labelled *Recommended* (advice,
  not "Most popular", which the research said not to claim without data);
  the coach's own C sits beside the app's name, so the paywall is plainly
  for the thing that button opens; and everything read to decide sits on
  charcoal rather than on the photograph. Every store word on it follows
  the phone: an Android phone reads Google Play, never an Apple ID (P10 on
  the board).
- **The coach asks for the medical disclaimer first** (Matthew's call: Run's
  full screen, not a line). Once on a phone, before the coach answers
  anything or a plan is built, and before the offer for anybody not
  subscribed, as Run's coach asks it (`MedicalDisclaimerScreen`,
  `LocalDisclaimerStore`). Every sentence is the terms' own "Not medical
  advice", held once in `legal_copy.dart` so the two cannot disagree, and it
  can be read again under Privacy & legal. Smart exercise swaps are not
  gated: they pick a machine, not a treatment.
- **The privacy policy says what Google may send.** "An email address and an
  identifier, and nothing else" was what we ask for, not what Google sends:
  Supabase can keep Google's name and picture link with the login. The
  policy now says so, and that the app does not use them (nothing in the
  app or the functions reads them). Run's policy says the same as Lift's
  used to, and changes after 1.0.0's review.
- **A subscription can be managed from the app.** Account › Coaching has
  *Manage subscription* for a subscriber, opening the App Store's
  subscriptions page or Lift's entry in Google Play's Subscription Center
  (`manage_subscription.dart`); Google Play's policy wants that way out in
  the app. Deleting the account says, before the tap and again after it,
  that deleting does not cancel the subscription, with the same link, in
  Run's words (`StillBillingNotice`), as Apple's account-deletion guidance
  asks. Known limit: the link is the phone's store, so a subscription bought
  on an iPhone and managed from an Android phone is sent to the wrong one,
  until the entitlement row says which store sold it.
- **Deleting asks how much, on the suite's screen** (`DeletionChoice`,
  `NoticePanel`, `PhoneCopySwitch`): the app's icon and name at the head;
  *Delete this app's data* or *Delete my whole MGKFitness account*; the note
  on what becomes of the login; and, new to Lift, a switch to erase this
  phone's copy as well, on by default. Erasing takes what
  `PhoneTrainingData.eraseAll` holds (sessions, saved workouts, the plan and
  the progress photos) and the shell reads its log, session and plan again.
  The outcome sentences are shared with Run's (`deletionOutcome`), and the
  title says *Deleted from our servers* when the phone kept its copy. Run
  offers the same choice from 1.0.1.

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
