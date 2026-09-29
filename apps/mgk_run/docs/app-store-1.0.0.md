# Run 1.0.0 — everything between a green build and a live listing, on both stores

[release-1.0.0.md](history/release-1.0.0.md) took the app from "records a run" to
"somebody can hold it". This document picks up where it stops, because the two
are different problems: that one is about whether the app is good, this one is
about whether it can be **submitted, reviewed, and approved**. An app can be
finished and unsubmittable, and most of what follows is not code.

Written 2026-09-01 against `478eef5`. **Rewritten 2026-09-02 against
`31b7ce3`**, which is where the first version had already gone stale — the
payment half landed, the price was settled, and the listing material had never
been written down at all. **Brought up to date on 2026-09-29 for build 26 and
both stores.** The file name says App Store because that was the only store
when it was written; Google Play has been a target since ADR-0021 and ships in
1.0.0 ([ADR-0039](decisions/0039-one-commit-two-stores-and-the-pubspec-owns-the-build-number.md)),
and the name stays because a dozen documents link to it.

Tick items as they land. Where something is settled differently from how it is
written here, change the item and say why — same rule as the release plan, for
the same reason.

---

## Where we actually are

**Updated 2026-09-29, for build 26 and both stores.** Written from a full
pre-release review that day. Everything below this section is the reasoning
and the record; **this section carries the state**, and the list in it is the
order to work in.

| | |
|---|---|
| **TestFlight** | **1.0.0 (26)**, from `431db9c` (Codemagic `6abc0515…4bc49`), 2026-09-29. 25 before it, from `12d74d8` |
| **Play internal** | **1.0.0 (26)**, from `54e7487` (Codemagic `6abc0a58…4ad63`), 2026-09-29. 25 before it, from `12d74d8` |
| **Release candidate** | **1.0.0 (26), cut**, tagged `run/build-26`. Two commits, one app: `54e7487` changes only two test files from `431db9c` (the first Android build failed CI on them); `lib/`, `ios/`, `android/`, `pubspec.yaml` and `packages/` are identical |
| **Backend under it** | coach v28, revenuecat v7, migrations through `20260929183008` (item 2) |
| **Testing** | One sitting, on build 26, on both phones: [the test sheet](testflight-1.0.0-test-sheet.md). Testing build 25 was dropped |
| **Tag `run/build-25`** | On `12d74d8`, the commit that shipped (moved from `a6eb6e1` on 2026-09-29) |

Run 1.0.0 ships on **both** stores, from one commit with one build number
([ADR-0039](decisions/0039-one-commit-two-stores-and-the-pubspec-owns-the-build-number.md)).
This document is the checklist for both; the runbooks are
[store-setup.md](store-setup.md) (Apple) and [play-setup.md](play-setup.md)
(Google), and the copy is in [app-store-listing.md](app-store-listing.md) and
[play-listing.md](play-listing.md).

### What is left, in order

Most urgent first. Items 2, 4 and 5 touch production or rewrite a published
tag, which Claude Code's auto mode refuses to do, so they are yours to approve
and run.

1. - [x] **Android developer verification — done.** `com.mgkcodes.fitness.run`
      was registered on 2026-09-10 (3 keys), confirmed in Play Console on
      2026-09-29. The 2026-09-30 deadline is met; nothing to do.
2. **The backend changes — done 2026-09-29**, approved by the owner and each
   verified after it ran.
   - [x] **`coach` redeployed** (version 28, `cc876f7`): main plus Lift's
         `b6fb99b` (sessions), the expiry fix, the `lift_chat`-only
         conversation check, a 256 KiB request cap, errors logged by code only,
         the runner's local date, and Run's attribution and persona. Every
         deployed file compared byte-for-byte with the branch; an unsigned
         call answers 401. Run's coach is paid server-side from here (ADR-0030
         is live), Premium's allowance is real (ADR-0038), and Lift's planning
         surfaces stop answering 400.
   - [x] **`revenuecat` redeployed** (version 7): the refund fix (`20c46e5`,
         cherry-picked from `13fb60e`) and a scheduled pause that no longer
         ends paid-for time (`431db9c`). Compared with the branch; an unsigned
         call answers 401.
   - [x] **The migration**, `20260929183008_release_hardening`: the usage
         functions revoked from `public`, `anon` and `authenticated`;
         `core.user_settings` timestamps defaulted; `coach.reports` created,
         insert-only under RLS; `core.touch_updated_at`'s search path pinned.
         Checked in the catalog afterwards, privilege by privilege.
   - [x] **The missing backup columns**, `20260929114055_run_elevation_max_and_steps`,
         applied the same day and the file renamed to the ledger's version.

   Deploy rule, unchanged: functions **by name**, and **never `delete-account`
   or `daily-ai-summary` from `main`** — production's `delete-account` is
   Lift's copy, with the progress-photo sweep. `supabase/config.toml` now
   declares `verify_jwt = false` for the three functions that need it.

   **Watch for:** both functions were two versions ahead of what this session
   deployed, so something else deployed them today too. A later deploy of
   `coach` from `lift/release-2.0.0` would drop the expiry fix and the request
   guards (that branch merged main before them).
3. - [ ] **OpenRouter: turn on account-wide Zero Data Retention, and set a hard
      credit limit on the API key.** Five minutes. The first makes the
      policy's "providers that do not keep or train on what we send" a setting
      rather than a per-request hope, and settles publication blocker 3 in
      Gate 2. The second caps what a leaked key or a runaway surface can
      spend.
4. **Ship `main` and cut build 26.**
   - [x] `run/release-26` pushed to `main` as `431db9c` (fast-forward, 53
         commits), 2026-09-29. Vercel deploys `web/` from it.
   - [x] Fired from `main`: `run-ios-release` (`6abc05155fdcbdf7b604bc49`,
         from `431db9c`) **succeeded** and published to TestFlight.
         `run-android-release` from `431db9c` **failed its Test step** on two
         tests that only passed on a UK-timezone Windows machine (a migration
         read by its old version; a DST guard on the zone *name*); fixed in
         `54e7487`, re-fired (`6abc0a58690944ca0c34ad63`), **succeeded** and
         published to the Play internal track.
   - [x] Tagged `run/build-26` on `54e7487`, both build records in its
         message, and the test sheet stamped.
5. - [x] **`run/build-25` moved to `12d74d8`**, the commit both stores' build
      25 came from, 2026-09-29 (annotated, with the build records in the
      message).

6. **Console settings and one decision.**
   - [ ] **MapTiler: confirm a paid plan.** The Free plan is non-commercial
         only, and the App Store's Content Rights answer (store-setup.md §10)
         says we hold the rights to the tiles.
   - [ ] **RevenueCat: exactly one webhook**, at `…/functions/v1/revenuecat`,
         Authorization value verbatim with no `Bearer` (store-setup.md §5).
   - [ ] **Supabase Auth: email confirmation is off. Decide** whether to turn
         it on, with custom SMTP, before public launch. It changes the sign-up
         flow, so it is a product decision, not a setting to flip.
   - [ ] **`dev@runio.app`** is a production account on a domain MGKCodes may
         not own. Confirm the domain is ours, or change that account's email:
         whoever holds the domain can reset its password.
7. **The store forms.** No build needed; start now.
   - [ ] App Store Connect: Premium's description (store-setup.md §2), the two
         review accounts (§9), and every submission form (§10).
   - [ ] Play Console: every App content declaration (play-setup.md §4), the
         subscriptions' descriptions and benefits (§5), and the listing
         ([play-listing.md](play-listing.md)).
8. **The graphics.**
   - [ ] App Store: 6.9" screenshots, from a phone
         ([app-store-listing.md](app-store-listing.md) § Screenshots).
   - [ ] Play: the **feature graphic** (1024 × 500, missing and mandatory),
         **phone screenshots** at 2:1 or narrower (missing), and the 512 icon
         re-saved with alpha if Play refuses it
         ([play-listing.md](play-listing.md) § Graphics).
9. - [ ] **The build 26 sitting**, on both phones: [the test
      sheet](testflight-1.0.0-test-sheet.md), including the Android
      foreground-service video (section V) and the screenshots (section H).
10. **Submit.**
    - [ ] App Store: build 26 with **both subscriptions attached**, demo
          account A in Sign-in, the review notes, **manual release**.
    - [ ] Play: build 26 promoted from internal to production, **managed
          publishing on** (play-setup.md §11).
    - [ ] Release both when both are approved.

**Not on this list, on purpose:** `REVENUECAT_ACCEPT_SANDBOX` **stays on**.
Every earlier version of this document said to unset it before submitting,
which would have failed review: App Review buys in the sandbox
([ADR-0037](decisions/0037-the-sandbox-stays-open-in-production.md)).

### What build 26 adds over 25

Build 25 is `12d74d8`. This list replaces the sentence that stood here until
2026-09-29, *"Nothing else differs between 25 and 26"*, which stopped being true
the same day. The test sheet's rows marked **NEW** cover everything here that a
phone can show.

- **The in-app privacy policy caught up** with the published one (`628c3a3`):
  it omitted the name the app collects and the profile photo. That was why 25
  could not be promoted.
- **The coach asks before it sends** ([ADR-0036](decisions/0036-the-coach-asks-before-it-sends.md)):
  a sheet naming OpenRouter, what is sent and what never is, before any price
  and on every way into the coach; withdrawable in Settings ▸ Privacy & legal ▸
  Coach and AI. The conversation shows the medical disclaimer now too.
- **A coach reply can be reported** with a long press, into `coach.reports`.
- **The phone's training belongs to one account**
  ([ADR-0035](decisions/0035-the-phones-training-belongs-to-one-account.md)):
  a second account signing in is asked to erase the phone's training or sign
  out, and no longer receives the first one's.
- **Leaving is safer**: signing out can remove the phone's data (off by
  default) and detaches RevenueCat; deleting the account erases the phone's
  copy (on by default), resets backup consent, says the subscription keeps
  renewing, and says when the login was kept for Lift.
- **Manage subscription** opens the store that bills the subscription, and
  **the paywall** says what actually happened: pending, no connection, already
  owned, restored, or sign in first.
- **A subscription past its expiry stops granting** a day later, server and
  app, and reads as *Ended*.
- **Health is asked for steps only.** `WORKOUT` came off the read list; the
  purpose strings, the intro and the policy say so.
- **Truer copy** on the photo (never sent to us), the backup switch (the coach
  is separate), and the privacy manifest (declares what the app sends).
- **Coach memory** prune and restore stay inside Run's rows, and every coach
  request carries the runner's local date.
- **The recording lane** (seven commits, merged at `f8edac2`): a run
  interrupted by a kill or a crash is recovered at launch, with a note saying
  so; a killed schema upgrade is safe to retry (the local database goes from
  schema 10 to 11); Back and the iOS edge swipe mid-run ask instead of hiding a
  live recording; a double tap on Finish makes one run; re-allowing location
  mid-run resumes the same run; race day stays clear on every plan path; day
  counts survive a clock change; a race under six weeks away is refused; and on
  iPhone, approximate location says *Turn on Precise Location for Run in
  Settings* instead of recording nothing.

### Production, as found on 2026-09-29

What the review found running, so nobody assumes the repository is what is
deployed:

- **`run.runs` was missing `elevation_max_m` and `steps`**, so every Run backup
  upload failed. The migration was applied on 2026-09-29; the ledger stamped
  its own version, and the repo file keeps the old one until item 2's rename.
- **The `coach` function is the Lift branch's copy**, deployed 2026-09-01.
  What that means is under item 2.
- **The `revenuecat` function lacks the refund fix**, so a refunded subscriber
  keeps the coach until the period runs out.
- **Any signed-in user can call `coach.record_usage`**, and so fill another
  user's spend window.
- **`core.user_settings` has no defaults** on its timestamps, so Run's unit
  sync fails.
- **`coach.reports` does not exist**, so every report fails to send.
- **`REVENUECAT_ACCEPT_SANDBOX` is `true`**, which is correct and stays.

---

## Build 25, as recorded on 2026-09-12

Kept for what landed and why; its checklists are superseded by the list above.
Build 25 went to both test tracks on 2026-09-11 and its sitting never happened.

### What landed on 2026-09-10 to 09-12

The Play half of the product, and a design pass that was overdue:

- **Google Play, end to end.** Upload keystore (`mgkfitness_upload`, shared
  across the suite), the listing, a merchant account, two subscriptions priced
  **ex-VAT** so Android and iOS charge the same, the RevenueCat Google app, and
  `run-android-release` publishing itself. Build 24 was the first fully
  automated Play release from a commit.
- **The first working purchase on Android**, which took finding that
  `REVENUECAT_PRODUCTS` had no Play id — Play reports
  `run.coach.monthly:monthly` where the map held `run.coach.monthly`. Setting
  it then banded on a Windows PowerShell that strips quotes from native
  arguments, which silently unmapped **both** stores for thirteen minutes.
  `productMap` now says so out loud.
- **`/run/delete-account`**, which Play requires for any app offering account
  creation and which did not exist. `/run/support` was Apple-only prose and now
  names both stores.
- **Settings rebuilt**: an index with values on the right rather than two and a
  half screens of explanation, a profile header with an avatar, an Account
  screen, and a Support row pointing at a page that had been live and unlinked
  the whole time.
- **Real app icons**, generated for both apps from `tool/build_app_icons.py`.
  Both were shipping Flutter's template logo on Android with no adaptive icon;
  Lift had none anywhere.
- **Three privacy defects fixed**: the runner's name reaching the model
  provider, account deletion reaching into Lift's data, and backup-off erasing
  Lift's coach conversations.

## Where we were, build 13 (kept for the reasoning)

Written 2026-09-08. The counts and build numbers here are history; the section
above is the state. One claim in it was wrong and is corrected in place.

Green, and worth stating so the list below is read as short rather than long:

- **1,501 tests pass, analyzer and format clean** — verified 2026-09-08 at
  `6f71c3c`, after the build 13 field-test fixes (3 skipped by design,
  `@Tags(['live'])`, they hit the real backend). 199 Deno tests pass alongside
  them, and since the nav bar became shared: 293 in `apps/mgk_lift` and 49 in
  `packages/mgk_ui`, with the analyzer clean across the whole workspace rather
  than this app alone.

  **The count is not evidence about the defects that afternoon found.** All of
  them were caught by reading, by a device, or by somebody saying so — never by
  the suite, because four of them were an argument nobody passed, and a widget
  test cannot see the argument its caller declined to supply. Including
  `naming_test.dart`, which fails the build if a retired product name reaches a
  string a runner reads.

  **Builds 12 and 13 are both superseded, and build 14 is not yet cut.** Build
  13 went to a phone on 2026-09-07 and the sitting stopped at section G's setup,
  so **G and H have now failed to run three builds running**. It returned five
  defects and seven UI requests; all are fixed or built, at `6f71c3c`, and none
  of it has been on a device.

  **What is different this time is that the gesture and layout work was
  verified on hardware anyway** — an Android emulator resized to the 6.7"
  iPhone's geometry. The peek detent lands, a pan parks the camera without
  disturbing the sheet, the recentre control restores follow, and Profile
  scrolled fully clears the floating pill. That last one is IMG_4700's exact
  failure. A widget test at a fixed surface could not have answered any of it,
  which is why [ADR-0033](decisions/0033-the-bottom-chrome-floats.md) says so.

  What is written below as done on hardware was done on *build 12*, except
  where it names the emulator.
  [The test sheet](testflight-1.0.0-test-sheet.md) is rewritten for build 13:
  86 rows, with section G moved **before** the outdoor run because it is the
  most submission-critical thing on it and has never once run — last time it sat
  behind the weather and the afternoon ended first.

  **This is the only place the figure is written down.** It said 1186 in
  `apps/mgk_run/CLAUDE.md` while the suite passed 1352, so that second copy was
  deleted rather than corrected — a number kept in two places is a number that
  drifts, and the same failure had two release checklists disagreeing about the
  RevenueCat offering.
- **The iOS pipeline has run end to end.** `Run — iOS TestFlight` in
  `codemagic.yaml`, signing via the team's `frunt_asc` App Store Connect key,
  publishing with `submit_to_testflight: true`. **Build 12 succeeded on
  2026-09-02**, every step green including Publishing — the first build carrying
  the RevenueCat SDK, the paywall, the wired `onUpgrade`, the gate sheet's
  surface and the `appl_` key. Triggered through Codemagic's REST API rather
  than the UI.

  ~~Build numbers come from `$PROJECT_BUILD_NUMBER`, so `1.0.0+1` in the
  pubspec never needs bumping.~~ **Wrong, and reversed on 2026-09-09**
  (`0c36ec0`, `5e4a7ce`): Codemagic's counter is project-wide and drifted from
  the TestFlight number, so "build 12" here was binary 19. The build number is
  the `+N` in `apps/mgk_run/pubspec.yaml`, bumped by a commit before a build is
  fired, and both stores read it from there
  ([ADR-0039](decisions/0039-one-commit-two-stores-and-the-pubspec-owns-the-build-number.md)).
- **An App Store Connect record exists** for `com.mgkcodes.fitness.run` —
  proven rather than assumed: the upload step fails after a successful build
  when no listing exists, and it did not.
- **The deletion path is built and correctly scoped.** `core.delete_account`
  walks `array['lift', 'run']` plus `coach`, enumerating tables from the
  catalogue rather than a hard-coded list.
- **The legal documents are written and rendered** — privacy policy, medical
  disclaimer and a delete-account screen, all from `lib/src/features/legal/`,
  with the web versions generated from the same source by
  `tool/build_legal_pages.py`.
- **`ITSAppUsesNonExemptEncryption` is answered** in `Info.plist`, so no build
  lands as "Missing Compliance" waiting on a hand answer.
- **The purchase back end is built** — `core.entitlements`, the coach's
  server-side read, the client tier model, the gate sheet, and the `revenuecat`
  Edge Function that is the only thing that writes a row.
- **Every screen is on a board** —
  [the contact sheet](https://claude.ai/code/artifact/9ddfd186-11ad-4260-bde9-ef8b7a5d9190),
  rendered 2026-09-02 at `31b7ce3`.

  **Two counts, both true, and they are not the same thing.** The board shows
  **73** plates (33 of them driven through the real app). `board.state.json`
  records **77** captures. The four it holds that the board does not show are
  `account-gate`, `keep-runs-safe`, `settings-no-account` and `hero_weights`.
  This page said 73, was changed to 77 on 2026-09-03, and is now precise
  instead — a single number here could only ever have been wrong about one of
  the two.

  **Neither count includes the paywall.** `flows.dart` generates `paywall` and
  `paywall-store`; `board.state.json` carries neither, because the board
  predates them. The board's own *Not on the board yet* table still lists the
  purchase screen as missing "because RevenueCat is chosen and unbuilt", which
  has been untrue since 2026-09-02.

  **And `board.state.json` is maintained by hand.** `plate()` writes PNGs into
  the git-ignored `plates/` and never touches the state file, so the stamps are
  a human promise rather than a record. Every one still reads `31b7ce3` while
  `flows.dart` has moved three times since (`406aab4`, `7f0692a`, `34b5439`).
  It should be written by the harness. Not a phone job, and not a blocker.

**What has never happened is a submission.** Day-to-day development is on
Windows against an Android emulator, which is why every device question below is
answered on TestFlight rather than here.

---

## Gate 1 — What only a device can answer

Build 11 settled four unknowns: `TARGETED_DEVICE_FAMILY = "1"` compiles, code
signing resolves for the bundle id, the artefact globs match, and an App Store
Connect record exists.

**Every open item here is a row on the build 26 test sheet**, on both phones,
and that sitting is item 9 of the list at the top. Until then none of them has
been answered on hardware for the payment arc or anything after it.

- [x] **A backgrounded run survives with the screen locked.** Confirmed on a
      live TestFlight build. iOS carries `UIBackgroundModes: location` with
      `allowBackgroundLocationUpdates: true` and
      `pauseLocationUpdatesAutomatically: false`. Android keeps it going with a
      foreground service (ADR-0021); test sheet C6 checks both.
- [x] **The test sheet is written** —
      [testflight-1.0.0-test-sheet.md](testflight-1.0.0-test-sheet.md),
      rewritten for build 26 on 2026-09-29.
- [ ] **The 23 Aug run is recoverable** — test sheet A3. The last open item in
      [release-1.0.0.md](history/release-1.0.0.md)'s Phase 0. With the log
      reading Drift, the run should simply appear. If it does not, it never
      finalized, and that is a new bug rather than the one already fixed.
- [x] ~~**Widening the Health request does not re-prompt badly.**~~ **Moot
      since `b3ac0a4`** (2026-09-29): the app asks Health for step count only,
      so nothing widens. `WORKOUT` came off the read list because nothing ever
      imported a workout. Test sheet B2 checks what a fresh install is asked.
- [ ] **The permission dialogs read correctly** — B1, B3, B4. Location is asked
      **While Using** only, on both platforms; the app never asks for Always.
- [ ] **A run records end to end on real hardware** — section C, including the
      recording lane's new rows (C21 to C26).
- [ ] **The coach gate opens, and the coach opens behind it** — sections I and
      D. Since build 26 the order is account, then the AI consent sheet, then
      the price.
- [ ] **A purchase on each store** — section G on the iPhone, section P on
      Android. Both products are Ready to Submit, the offering is CURRENT, and
      `REVENUECAT_ACCEPT_SANDBOX=true` is set, and **stays set**
      ([ADR-0037](decisions/0037-the-sandbox-stays-open-in-production.md)):
      App Review buys in the sandbox too. This item said to unset it before
      submitting until 2026-09-29.

---

## Gate 2 — Submission blockers

App Store Connect will not accept a submission without these, and Play Console
has its own equivalents in [play-setup.md](play-setup.md) §4. None are code.

- [x] **A published privacy policy URL** — **`https://mgkfitness.mgkcodes.com/run/privacy`**,
      live 2026-09-03.

      Verified rather than assumed: 200 with a valid certificate, reachable with
      no cookies and no login (App Review has no account), `/nope` correctly
      404s, and `/run/privacy-policy.html` 308s to the clean URL so each document
      answers at exactly one address.

      **And it is serving the generated artefact.** The live page still carries
      the `GENERATED by tool/build_legal_pages.py` banner, which is the exact
      string `legal_copy_test.dart` asserts on — so the word-for-word parity a
      reviewer checks between the page and the app is enforced by CI rather than
      by discipline. That is the whole reason `web/` lives in this repository.

      **The site is live**, a Vercel project with root directory `web` on
      `mgkfitness.mgkcodes.com`, serving `/run/privacy`, `/run/terms`,
      `/run/medical-disclaimer`, `/run/support` and `/run/delete-account`. It
      deploys from `main`, so anything merged since the last push is not live
      until `main` is pushed (item 4 at the top). This paragraph said a Vercel
      project and a CNAME were still to do until 2026-09-29. What remains is
      pasting the URL into each store's field
      ([store-setup.md](store-setup.md) §10, [play-setup.md](play-setup.md) §4).

      **Where it goes is settled: `mgkfitness.mgkcodes.com/run`.** A suite
      subdomain with a path per app, which is the shape the naming already
      implies — the platform owns the domain and each app owns a path, exactly
      as `kPlatformName` owns the bundle id and each app owns the suffix. Lift's
      pages land beside it at `/lift` without a second decision.

      **Settled 2026-09-02, then re-settled the same day: it lives in `web/`,
      here.** The first answer was the MGKCodes studio site, and reading that
      repo changed it.

      **Two things about that site change the job, and neither was known when
      the subdomain was chosen.** It already hosts app legal pages, and the
      pattern is not what we assumed:

      1. **The routes are paths, not a subdomain** — `mgkcodes.com/privacy/liftio`,
         `/terms/liftio`, `/support/liftio`. A subdomain needs middleware host
         rewriting, a DNS record and a Vercel domain, *and* leaves the two apps
         with different URL shapes for the same kind of page.
      2. **The prose is hand-typed into JSX.** `app/privacy/liftio/page.tsx` is
         671 lines and `app/terms/liftio/page.tsx` is 743, with the policy text
         inline and **nothing testing it against the app**. Copying that pattern
         for Run makes a *fourth* hand-maintained rendering of a text a reviewer
         compares word for word — which is the exact failure
         `tool/build_legal_pages.py` was written to stop, reintroduced in a repo
         where no test can catch it.

      Both problems disappear by putting the site in this repository. The
      generator now writes to `web/public/run/` as well as `docs/legal-site/`,
      the pages are served **verbatim** rather than reproduced by a component,
      and `legal_copy_test.dart` reads the served bytes directly — so the third
      rendering finally joins the two that were already pinned to each other.
      Confirmed by breaking it: renaming a sub-processor on the served page
      alone fails the suite. That check is why the site is here and not in a
      repository of its own.

      The studio site's own Liftio pages were retired the same day, redirected
      to `getliftio.com` rather than deleted, because a shipped listing carries
      whatever URL it was submitted with.

      It is generated rather than written because
      [naming.md](../../../docs/naming.md) names the trap: **the in-app copy
      mirrors the published page word for word, and a reviewer does check.**
      Three renderings of one text — the doc, `legal_copy.dart`, and the web
      page — and hand-maintaining the third is how they drift. Verified at
      generation: 58 of 58 source blocks appear verbatim.
- [x] **The medical disclaimer page**, generated the same way.
- [x] **Terms of Use — ours, at `https://mgkfitness.mgkcodes.com/run/terms`**
      ([ADR-0040](decisions/0040-our-terms-and-apples-eula.md)).

      Guideline 3.1.2 requires an auto-renewable subscription's purchase surface
      to carry **functional links to both the Terms of Use and the privacy
      policy**. On 2026-09-02 this item settled on Apple's standard EULA and
      said there was "no terms document anywhere in this repo". Both stopped
      being true on 2026-09-10, when `8ac1181` wrote terms of our own
      (`docs/terms-of-use.md`): the app gives training advice, which Apple's
      document does not cover, and Google Play has no Apple EULA to fall back
      on. The paywall and Settings › Privacy & legal link `/run/terms`,
      pinned by `purchase_screen_test.dart` and `legal_screen_test.dart`.

      **Two fields, two answers.** The listings' descriptions link our terms
      ([app-store-listing.md](app-store-listing.md),
      [play-listing.md](play-listing.md)). App Store Connect's **License
      Agreement** stays **Apple's Standard EULA**: that field takes plain text,
      not a URL, and our terms say Apple's EULA governs App Store purchases and
      wins where the two conflict.
- [x] **A support URL** — **`https://mgkfitness.mgkcodes.com/run/support`**,
      live 2026-09-03 and verified alongside the policy. It answers the three things a
      runner actually writes in about, and says plainly which two we cannot fix:
      the store takes the payment, so the store cancels and the store refunds.
      It names both stores since 2026-09-11.
- [ ] **Clear the remaining publication blocker.** The generator's
      `BLOCKERS` list is **empty**, so nothing stops the pages being generated
      and served; of the four blockers it once carried, three are closed and
      one is a setting (item 3 at the top):
      1. ~~**Legal review.**~~ **Dropped 2026-09-01** — out of reach for now,
         recorded as an accepted risk rather than a forgotten step. What protects
         it is that the data flows were read off the running system; what is
         unreviewed is legal *form*, not factual accuracy.
      2. ~~**A processor agreement with OpenRouter.**~~ Off the blocker list.
         Naming a recipient is an **Article 13** transparency duty and does not
         assert that a contract exists. The **Article 28** contract is a real and
         separate obligation running in parallel; the email went to
         `support@openrouter.ai` on 2026-09-01 and is tracked in
         [openrouter-processor-agreement.md](openrouter-processor-agreement.md).
      3. **Whether the configured `COACH_MODEL`'s provider trains on inference
         inputs.** A per-model property. Answer from the deployed secret;
         [compliance.md](compliance.md) is explicit that guessing from the repo
         is wrong. `data_collection: "deny"` is the control and it is set; what
         is unconfirmed is what it guarantees contractually. **The only item that
         can still change what the policy has to say** — and less than it could
         have, since the wording no longer implies providers never retain.
         **Turning on OpenRouter's account-wide Zero Data Retention closes most
         of it**: it makes the policy's "providers that do not keep or train on
         what we send" an account setting rather than a per-request flag.
      4. ~~**The publication date**~~ — cleared. The policy has carried a real
         date since 2026-09-10 (29 September 2026 since tonight's revision), so
         there was no token left to replace; the generator's banner saying so
         came off on 2026-09-29.
- [ ] **App Privacy ("nutrition labels").** The answers, type by type, are in
      [store-setup.md](store-setup.md) §10, checked against build 26's code on
      2026-09-29, and they live only there. In short: data is collected;
      **no tracking** for any type; Email, Name, **Health (HealthKit step count
      only)**, Fitness, Precise Location, Other User Content, User ID, Purchase
      History and Product Interaction are linked to the user; Coarse Location
      (MapTiler's tile requests) is not. They must match the sub-processor
      table in [compliance.md](compliance.md): Supabase, OpenRouter,
      RevenueCat, MapTiler.

      This item used to carry its own table, which said location was collected
      "in use **and** in background" (the app asks While Using only) and left
      Coarse Location out. One table, in the runbook, is the fix.

      `ios/Runner/PrivacyInfo.xcprivacy` declares the same types apart from
      Coarse Location, and `the_privacy_manifest_declares_what_is_sent_test.dart`
      pins the list. Backup consent makes several of them conditional and the
      form has no way to say so: **declare what is collected with backup on.**
- [ ] **Age rating questionnaire** — Apple's 2025 version, answered in
      [store-setup.md](store-setup.md) §10. Expect **13+**. The two judgement
      calls: Health or Wellness Topics is **Frequent**, and Medical or
      Treatment Information **Infrequent** (None is defensible). The coach is
      not user-generated content and not messaging: it is a model, and no
      runner can reach another. The reasoning that stood here predated the
      2025 questionnaire, which asks about health topics directly.
- [ ] **App Review notes** — final, in
      [app-store-listing.md](app-store-listing.md) § Review notes, counted
      against the 4,000-character field by `tool/check_listing.py`. They cover
      the two demo accounts, where the AI consent is asked, reporting a reply,
      background location (**While Using only**), HealthKit (**step count
      only**, never written), the medical disclaimer and the deletion path.
      Paste them with the four credentials filled in.
- [ ] **Two demo accounts**, set up by [store-setup.md](store-setup.md) §9.
      The app opens on a working tracker with no account
      ([ADR-0019](decisions/0019-onboarding-is-two-moments.md)), which answers
      for the free half — but the coach and plans sit behind an account and an
      entitlement ([ADR-0030](decisions/0030-the-coach-is-the-paid-half.md)).
      **A** has a `premium` row that never lapses and that no store event can
      overwrite, for reviewing the coach; **B** has none, for the sandbox
      purchase. One account cannot do both jobs: a reviewer who buys on an
      entitled account proves nothing, and one who cannot reach the coach
      rejects for incomplete functionality. Play's reviewer gets A as well.

---

## Gate 3 — RevenueCat, end to end

**Settled: 1.0.0 ships paid.** The coach costs real money per request through
OpenRouter, so it is the paid half and the gate stays.
[ADR-0028](decisions/0028-revenuecat-is-the-purchase-path.md) records the
purchase path, [ADR-0029](decisions/0029-what-a-tier-costs-and-buys.md) the
prices, [ADR-0030](decisions/0030-the-coach-is-the-paid-half.md) what is gated.

### Built already

- [x] **`core.entitlements`** — one row per (user, app); `product` in
      free/paid/premium, `status` in active/expired/grace/refunded/revoked, plus
      platform, expiry, `source_txn_id` and `event_ms`. **Client-read-only by
      design**: no INSERT/UPDATE/DELETE policy and no grant to `authenticated`,
      because the repo is public and a write path that exists is a write path
      somebody uses. Only `service_role` writes.
- [x] **The server read path** — `supabase/functions/coach/entitlements.ts`,
      `tierFor` mapping a product to a model tier, covered by
      `entitlements_test.ts`. Only `active` grants anything.
- [x] **The client tier model** — `CoachAccess`, defaulting to `free`, every
      unknown answer resolving to `free`, and deliberately *not* read from a
      stored flag: a value a client can write is a value a client can forge.
- [x] **The refusal is a door** — `CoachGateSheet`, plate `C5` on the board.
      Before it, the app offered the coach to everybody and let the Edge Function
      refuse, which surfaced as *"The coach hit a problem. Please try again."*:
      untrue, and an invitation to retry something guaranteed to fail.
- [x] **The dead end is closed.** `HomeShell` now passes `onUpgrade`, so the
      locked last-run card's *"See what a coach adds"* renders and opens that
      sheet. It shipped for a month saying "Upgrade to see this stat" with
      nothing to tap — Guideline 2.1 on its own, whatever is decided about
      payments. `test/home/upgrade_door_test.dart` pins it.
- [x] **The gate copy quotes no price.** A figure compiled into the binary is
      right in one storefront and wrong in every other, and Apple expects the
      localised one StoreKit hands back. `kCoachPrice` / `kSharpCoachPrice`
      remain as the record `limits.ts` is sized against; they are not shown.
- [x] **The webhook Edge Function is built** — `supabase/functions/revenuecat`,
      the only writer of `core.entitlements`. Its mapping is pure and unit-tested
      (16 tests, no store and no database). Ordering needed a migration:
      `source_txn_id` is not a watermark, so `event_ms` was added and an event
      must be strictly newer to win. A replay is a no-op, a late expiry cannot
      revert a live renewal, and a row inserted by hand loses to the first real
      event rather than blocking it.
- [x] **RevenueCat declared as a sub-processor** in all four places that have to
      agree: `docs/privacy-policy.md`, `legal_copy.dart`, `compliance.md`'s
      table, and the generated pages. `legal_copy_test.dart` pins all four
      processors.

### The wiring, in the order it has to happen

The order is load-bearing: since ADR-0030 the coach is refused without a row,
and no row can exist until the webhook is deployed. **Nothing about the paid
half works until this list is finished.**

#### Steps 1–5: the two dashboards

Apple's agreements, tax and banking; the subscription group and its two
products; the RevenueCat project with its entitlements and a CURRENT offering;
the deployed webhook and its secrets; and the webhook registration.

- [x] **All of it, confirmed 2026-09-03.** **The checklist lives in
      [store-setup.md](store-setup.md) §1–7 and nowhere else** — every field,
      the five strings that must match exactly, and a table mapping each of the
      webhook's own ignore reasons to its cause.

      **It used to be listed here as well, with its own tick boxes, and the two
      copies disagreed.** This page said the RevenueCat setup was complete while
      the runbook still had the offering unticked — and no CURRENT offering is
      the single misconfiguration that produces a calm, correct and entirely
      misleading paywall reading *"Not available to buy yet"*. A sandbox failure
      would have been hunted in the app.

      Two checklists for one job is how one of them goes stale, which Gate 6
      already recorded about `roadmap.md` and which this page then did anyway.
      The runbook is finer-grained and is read with a dashboard open, so it
      keeps the boxes. This stays the plan.

#### Steps 6–12: code in this repository, and what proves it

- [x] **6. The SDK in the client.** `purchases_flutter ^10.10.1`, behind a
      `PurchaseClient` interface with a `RevenueCatPurchases` implementation and
      a `FakePurchases` that lets the whole thing be driven from Windows. The
      public key rides in `app_config.json` as `REVENUECAT_PUBLIC_KEY`;
      `codemagic.yaml` writes it, warns loudly when it is unset, and **fails the
      build if it is not an `appl_` key** — a Google key here would configure
      the SDK against the wrong store and fail at the moment of purchase.
      `HomeShell` calls `identify` with the Supabase user id whenever there is a
      session, because the webhook keys the row on it and refuses an
      `RCAnonymousID:` rather than writing to nobody.
- [x] **7. The purchase screen `C5` opens onto** — `PurchaseScreen`, driven all
      the way from the coach mark so the route is evidence rather than the
      render alone.

      **It is not on the board**, and this said "plate `paywall` on the board"
      until 2026-09-03. `flows.dart` generates `paywall` and `paywall-store`,
      but the board was captured at `31b7ce3` before either existed and
      `board.state.json` carries neither. The store-sized one is exported to
      `store-assets/derived/run-iap-review-screenshot.png` and is what satisfies
      the per-product review screenshot in [store-setup.md](store-setup.md) §2.

      Two naming systems collided in that sentence, which is why it went
      unnoticed: `C5` is a **board code**, and board codes exist only inside the
      published contact sheet — nowhere in `test/plates/`. `paywall` is a
      **harness plate id**. They are not the same namespace. Prices come from
      `Offerings`; `purchase_screen_test.dart` prices a fixture in dollars and
      asserts the pounds ADR-0029 settled appear nowhere. It carries both tiers,
      **Restore purchases**, functional links to the **Terms of Use** (ours,
      at `/run/terms`, since 2026-09-10; Apple's EULA before that) and the
      **privacy policy**, and the auto-renew disclosure — four Guideline 3.1.2
      requirements, each with a test named after it.

      Two things the tests caught rather than review: the legal links were a
      `Row` that **overflowed a 430pt phone by 29 pixels**, which on the
      narrowest supported 320pt would have clipped a link Apple requires to be
      functional; and a cancelled purchase was about to be reported as a
      failure, which it is not.
- [x] **8. `CoachAccess` still comes from the server.** `PurchaseClient` has no
      `isSubscribed` and will not get one. The screen reports success only once
      `core.entitlements` agrees, and **polls for it** — zero, one, two, three
      and five seconds — because RevenueCat tells the Edge Function
      server-to-server while the store's sheet is still dismissing, so the first
      read after a payment usually says `free`.

      When the row never arrives it says *"Payment went through. The coach can
      take a minute to unlock"* rather than reporting an error: the money moved,
      and inviting a second purchase is the one outcome worse than waiting. The
      single place the SDK's own view is read is `restore`, and it decides which
      sentence to show rather than what anybody owns.
- [ ] **9. A purchase on a device, on each store** — Gate 1, test sheet
      sections G and P. The Android Coach purchase went through on 2026-09-11;
      Premium on Android and anything on iOS never has.
- [ ] **10. A processor agreement with RevenueCat**, alongside the OpenRouter
      one.
- [ ] **11. App Privacy: Purchases and the identifier** — Gate 2, and Play's
      Data safety form (play-setup.md §4).
- [ ] **12. Premium's description** says *"Three times the coaching each
      month."* in both stores
      ([ADR-0038](decisions/0038-premium-buys-more-coaching-not-a-different-model.md)).
      The paywall prints the store's text, so this is in-app copy as well as a
      store field. store-setup.md §2, play-setup.md §5.

---

## Gate 4 — The listing itself

**The copy is written, in
[app-store-listing.md](app-store-listing.md) and
[play-listing.md](play-listing.md)** — so this stays a checklist and the writing
lives somewhere it can be edited as writing. Every character count there is
verified by `tool/check_listing.py`, which also refuses a description claiming
something the code does not do, and anything Apple-only in the Play copy. The
field-by-field answers for App Store Connect are in
[store-setup.md](store-setup.md) §10, and Play's in
[play-setup.md](play-setup.md) §4. What is left here is the art, and the
choices only you can make.

### App information — set once, not per version

- [ ] **Name** (30) — `MGKFitness: Run`, per
      [naming.md](../../../docs/naming.md). Already check by eye that the
      existing App Store Connect record says this: the record existing says
      nothing about what it is called. The **home screen** label stays `Run`
      (`CFBundleDisplayName`), which is deliberate — iOS truncates at roughly
      twelve characters and `MGKFitness: Run` and `MGKFitness: Lift` would both
      render as `MGKFitness:…` on the same phone.
- [x] **Subtitle** (30) — **`Track runs. Get a real plan.`** (28). It sits under
      the name in every search result and is the second thing anybody reads.

      **This said "three drafted, one to pick" until 2026-09-07, and it had been
      settled for five days.** [app-store-listing.md](app-store-listing.md)
      chose option 1 on 2026-09-02 and says so; this page went on carrying it as
      open, and "The order" below counted it as the unfinished half of step 6.
      A third copy of a decision, disagreeing with the document this page itself
      names as where the writing lives — the same failure recorded about the
      RevenueCat offering and about the six screenshots, found a third time by
      reading the two pages side by side rather than by anything going wrong.
      The listing document owns the copy; this page ticks the box.
- [x] **Primary category** Health & Fitness, **secondary** Sports.
- [ ] **Content rights** — **yes**, it contains third-party content: the
      MapTiler / OpenStreetMap basemap. The in-app map shows the attribution
      (`MAP_ATTRIBUTION`; `codemagic.yaml` fails a build that sets tiles
      without it). Holding the rights needs MapTiler's paid plan, not the Free
      one, which is non-commercial only — item 6 at the top.
- [ ] **License Agreement** — **Apple's Standard EULA**, per
      [ADR-0040](decisions/0040-our-terms-and-apples-eula.md). The field takes
      plain text, not a URL; our terms are linked from the description.
- [ ] **Age rating** — Gate 2.

### Version information — 1.0.0

- [x] **Promotional text** (170) — drafted at 158, which leaves room for a
      launch line. Changeable without review, so it is the right place for
      anything that will move.
- [x] **Description** (4000) — at 3,693 since the 2026-09-29 revision
      (the Health sentence, the AI coach and reporting, the consent, the
      health disclaimer Play requires). What it had to do, and does:
      - lead with the free half, because it is most of the app and because the
        gate copy already makes that promise — a listing that leads with the
        subscription and a gate that leads with what is free are two different
        products
      - say plainly that the coach is a subscription, and name what it does
      - carry the **medical disclaimer in short form**. The app gates onboarding
        on it; a listing that omits it is claiming something the app refuses to.
      - **auto-renewable subscription disclosure**: title, length, price, and
        that payment is charged to the Apple ID — Apple wants this in the
        description as well as on the paywall
- [x] **Keywords** (100) — drafted at 90. Comma-separated with no space after
      the comma, because the spaces count; nothing repeated from the name, which
      Apple indexes separately; and no competitor named, which is a rejection.
      `check_listing.py` asserts all three.
- [ ] **Support URL** — Gate 2. Required.
- [ ] **Marketing URL** — optional; `mgkcodes.com` if there is a page worth
      landing on.
- [x] **Copyright** — `2026 MGKCodes Ltd`.
- [ ] **Screenshots** — **owned by
      [app-store-listing.md](app-store-listing.md) § Screenshots**: which six,
      the board codes and plate ids they map to, and the sizes for both
      stores. Take them from a real phone, not the plate harness, which draws
      no basemap tiles.

      This item used to carry its own copy of the list, and recorded that the
      list lived in three places without choosing an owner. It chose one on
      2026-09-29: the listing document, because the screenshots are listing
      copy. This page ticks the box and the test sheet's section H points
      there.
- [ ] **App preview video** — optional, and genuinely optional. Skip for 1.0.0.
- [x] **App icon — nothing to upload.** App Store Connect takes the
      1024×1024 icon from the build's asset catalogue (the new mark since
      2026-09-11; RGB, no alpha). `store-assets/captured/icon-1024.png` is the
      **old** loop mark and must not be uploaded anywhere. Play's 512 icon is
      a separate upload ([play-listing.md](play-listing.md) § Graphics).
- [ ] **"What's New"** — not required for a first version.
- [ ] **Sign-in required?** **Yes**, with demo account A. The app opens on a
      working tracker with no account, but the coach — the half being sold —
      needs one, and the field is where App Review looks for credentials. The
      review notes add account B for the purchase. This said "no" until
      2026-09-29.
- [ ] **Contact information** for review — name, phone, email.

### Before hitting Submit

- [ ] **Export compliance** — already answered in `Info.plist`, so this should
      not appear. If it does, something changed.
- [ ] **Advertising identifier (IDFA)** — **no**. Nothing in the app advertises
      or attributes.
- [ ] **Both subscriptions attached to the version.** A first subscription is
      only ever reviewed with an app version.
- [ ] **Version release option** — manual release, for a first version. Automatic
      means it goes live the moment review passes, at whatever hour that is.
      Play's equivalent is managed publishing (play-setup.md §11).
- [ ] **Phased release** — irrelevant for 1.0.0 (it only applies to updates).

---

## Gate 5 — Would pass the form and fail the review

- [x] **`TARGETED_DEVICE_FAMILY` set to `"1"` — iPhone only**, and **proven by
      build 11**. It was `"1,2"`, Flutter's default, which nobody chose: Apple
      would have required an iPad screenshot set and **reviewed the app on an
      iPad**, and nothing here has ever been laid out for one — the widest
      surface the board tests is 430pt. iPhone-only is the honest description of
      what was built and matches [ADR-0001](decisions/0001-flutter-ios-only.md).
- [x] **`steps` and `elevation_max_m` are mirrored.** `run.runs` gained both
      columns and both sides of the seam read and write them.
      `mirror_round_trip_test.dart` pins the invariant that broke: every column
      the mirror writes must be one the restore reads.
- [x] **Elevation converts at display.** `Elevation` lives in `mgk_units`
      alongside `Distance`, `Pace` and `Mass`, following the **distance** system
      rather than having a unit of its own — kilometres with pounds is an
      ordinary combination, miles with metres of climb is not.
- [x] **`NSHealthUpdateUsageDescription` is in the binary, and says the app
      writes nothing.** The history matters, because the obvious fix is the
      wrong one:

      1. **Dropped 2026-09-08 at `6f71c3c`**, on the reasoning that the app only
         ever requests `HealthDataAccess.READ`, so a purpose string for writing
         was noise at best and Guideline 5.1.1 at worst.
      2. **Restored 2026-09-09 at `a54e77d`**, because App Store Connect refused
         the upload of 1.0.0 (21) with error 90683. The trigger is the HealthKit
         entitlement and the `health` plugin's linked write methods, not our
         Dart: *"While your app might not use these APIs, a purpose string is
         still required."* No test can catch this; only a real upload does.
      3. **Reworded 2026-09-29** to say what is true: *"Run does not save
         anything to Health. This is listed only because the Health library it
         uses can write, which Run never asks to do."* It is never shown,
         because the prompt only appears for a write request and there is none.

      The read side narrowed the same day: `health_read_types.dart` requests
      `STEPS` alone (`WORKOUT` came off, `b3ac0a4`), and the share string says
      step count for runs recorded in Run. **Do not remove the update key**
      without a real release build proving the upload still passes; the
      comment in `Info.plist` says the same.


- [x] **Elevation at launch: none.** Decided 2026-09-08. There is no
      barometric source at all — not on the emulator, and not on an iPhone
      either ([ADR-0024](decisions/0024-elevation-is-barometric-or-absent.md)).
      The hardware barometer is not the blocker; no code reads it. Building
      `CMAltimeter` was declined for 1.0.0: iOS-only, so unverifiable from
      Windows, and it would have reached a device untested.

      **Corrected 2026-09-29: the tiles do not "stay, and stay empty".** This
      item recorded a decision that the elevation tiles would always show and
      read "not recorded". The code does not do that: the finished-run grid
      adds a tile only when the run has a value (`run_summary_screen.dart`:
      absent, "never a zero"), so a real run shows no elevation tile at all,
      and the string "not recorded" appears nowhere on screen. The question this
      page kept open for the phone — does an empty tile read as deliberate or
      broken — therefore has nothing to look at, and is closed. If a tile that
      explains its absence is wanted, it is a 1.0.1 change.

      **The stand-in shots fill them, and must not be submitted** — recorded
      here because the release plan is where a choice like this has to be
      findable. `_demoSummary()` supplies elevation, and also heart rate and
      calories, which a recorded run fills for none of the three.
      `store-assets/README.md` states it against the stand-ins; the listing
      screenshots come off a real phone. The Health read is specified for
      1.0.1 in [after-1.0.0.md](after-1.0.0.md).


---

## Gate 6 — Documents that were wrong

Cleared 2026-09-01, again on 2026-09-02, and again on 2026-09-07. Recorded
rather than deleted, because this is the kind of staleness that is invisible
until somebody acts on it.

- [x] **`compliance.md` described a function that no longer existed** —
      `runio_delete_account` sweeping "every table in the `runio` schema", a
      month after that schema was renamed to `run`. **The code was right and the
      document defending it to a regulator was not**, which is the worse way
      round.
- [x] **The same file's deletion table was wrong in four places, and the fix
      above is why nobody looked.** Corrected 2026-09-07, found by reading the
      file rather than by anything failing. Thirty lines below the paragraph
      recording that `runio` had been corrected, the table describing the *same
      function* still said `runio.*`, still put the shared rows in `public`
      rather than `core`, and was silent on the coach data that
      `20260807140000_delete_account_scopes_the_coach.sql` made erasable per app.

      **The fourth is the one that matters, and it points the wrong way.** The
      table said `dob` and `weight_kg` were **always cleared**;
      `20260806130300_account_deletion.sql` had deliberately stopped clearing
      them on a partial deletion a month earlier — *"a real change in meaning,
      not an oversight"*. So the document defending erasure to a regulator
      **claimed more erasure than the function performs**, which is the same
      shape as the backup-consent defect build 12 found on a phone: the policy
      promised deletion and the code did none.

      A correction applied to the prose and not to the table beside it is how
      one document disagrees with itself. Both halves are now checked against
      the migrations rather than against each other, and the live prose no
      longer says "Runio" — the three remaining uses are quotations of the
      error, which is what [naming.md](../../../docs/naming.md) keeps on
      purpose.
- [x] **`codemagic.yaml`'s header contradicted its own workflow list.**
- [x] **`roadmap.md`** retitled and reconciled with this document rather than
      maintained beside it — two checklists being how one goes stale.
- [x] **Lift's test sheet granted an entitlement that could not exist** —
      `platform = 'manual'` against a `check (platform in ('apple','google'))`,
      so anyone who ran it tested the free half of Lift believing it was the paid
      one.
- [x] **This document was 18 commits stale**, which is what prompted the rewrite.
- [ ] **`product-spec.md` stopped tracking the build.** It is titled "Runio",
      is marked **"Pre-alpha (design)"**, and its decisions table promises
      HealthKit writes the app does not do. It is named as the source-of-truth
      product definition and is the document a listing would naturally be written
      from — which is why the listing copy was written against the code instead,
      and why this is worse than it looks.
- [ ] **`release-1.0.0.md` is still ~12 commits stale.** Its phases are ticked
      but the account-removal work and everything after it is missing. Lower
      priority than the rest, because it misleads about *history* rather than
      about how the system behaves now.

---

## Explicitly not blocking

Recorded so nobody re-opens them under deadline:

- **Heart rate, cadence, active energy.** Stopped on purpose, with reasons, in
  [release-1.0.0.md](history/release-1.0.0.md)'s "Deliberately not built".
- **In-run audio** — [ADR-0006](decisions/0006-in-run-audio-deferred.md).
- ~~**The Android release pipeline.**~~ **Wrong, and removed from this list on
  2026-09-29.** It said nothing ships to Play for Run at 1.0.0, citing
  ADR-0021, which says the opposite. Run 1.0.0 ships on Google Play from the
  same commit as the App Store
  ([ADR-0039](decisions/0039-one-commit-two-stores-and-the-pubspec-owns-the-build-number.md)),
  and `run-android-release` has published to the internal track by itself
  since build 24.
- **Going open source.** `roadmap.md` lists a git-history secret scrub as part of
  "v1 shippable". It is a prerequisite for making the repo *public*, not for
  shipping the app, and conflating them adds a hard job to the critical path for
  no store benefit.
- ~~**Bests, and the coach's memory surface.**~~ Named on the board as missing
  screens, and both are built: bests are Profile's *Records* section, and
  past conversations are readable from the history button in the
  conversation. The board predates them.
- **What 2026-09-29's review deferred** — each with a date to revisit, in
  [after-1.0.0.md](after-1.0.0.md). None of them is a submission blocker; all
  of them are real.

---

## The order

**Superseded on 2026-09-29 by *What is left, in order* at the top of this
page**, which is now the only ordered list here. Two ordered lists on one page
would be the failure this repository keeps recording, so this one is kept only
as the record of how the release got here.

Struck through is finished.

1. ~~**Apple's paid-applications agreement, tax and banking.**~~ Active, and
   held by the team rather than the app.
2. **The OpenRouter reply** — sent 2026-09-01, tracked in
   [openrouter-processor-agreement.md](openrouter-processor-agreement.md).
   **Still outstanding, and the only thing waiting on somebody else.** Not a
   submission blocker: naming a processor is an Article 13 duty (Gate 2).
3. ~~**Stand up `mgkfitness.mgkcodes.com`, settle the terms and the support
   URL.**~~ Live 2026-09-03. The terms were settled on Apple's EULA that day
   and on our own on 2026-09-10 (ADR-0040).
4. ~~**Run a TestFlight build.**~~ Build 12, 2026-09-02, every step green.
5. ~~**Gate 3, the wiring**~~ — the two dashboards, the webhook, the SDK, the
   purchase screen. Everything except a purchase on a device.
6. ~~**Write Gate 4's copy.**~~ Both listings, machine-checked by
   `tool/check_listing.py`; brought up to build 26 on 2026-09-29.
7. **One sitting on the phone.** Attempted on build 12 (2026-09-04, stopped at
   section F) and build 13 (2026-09-07, stopped at section G's setup), and
   never on 14 or 25. Each attempt found real defects, all fixed since — the
   purchase chain granting nothing, six ungated doors into the coach, sync
   doing nothing, plans training on race day, a backup switch that promised
   erasure and performed none, and an auth stream that said something
   happened rather than who
   ([ADR-0032](decisions/0032-identity-is-an-event-and-the-tier-is-re-read.md)).
   **Now item 9 at the top, on build 26, on both phones.**
8. **Fill in the forms** — now item 7 at the top, answered field by field in
   the two runbooks.
9. ~~**Decide Gate 5's elevation question.**~~ Closed: a real run shows no
   elevation tile, so there is no empty tile to judge (Gate 5).

~~A new open item, from the 2026-09-07 sitting: **plans anchor week 1 to
`mondayOf(now)`**.~~ **Closed 2026-09-08**: a plan starts on the coming Monday
([ADR-0034](decisions/0034-a-plan-starts-on-the-coming-monday.md)). Counting the
block backwards from race day remains the better fix and the larger one; it is
recorded in that ADR as the answer if this one reads as a delay on a phone.
