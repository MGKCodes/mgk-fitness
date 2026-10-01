# Run 1.0.0: what is left before both stores

The plan for submitting Run 1.0.0 to the App Store and Google Play, from one
commit with one build number
([ADR-0039](decisions/0039-one-commit-two-stores-and-the-pubspec-owns-the-build-number.md)).

**This page carries the state, and nothing else.** One table and one ordered
checklist. It was 1,168 lines on 1 October 2026, with three builds of history
around about fifteen live items, and it had started to contradict itself. The
gates, the reasoning and the history are in
[history/app-store-1.0.0-record.md](history/app-store-1.0.0-record.md), frozen.

Three rules keep it short:

- **Tick items as they land.** Where something is settled differently from how
  it is written, change the item and say why in one line.
- **Answers live in the runbooks.** Every store field is in
  [store-setup.md](store-setup.md) (Apple) or [play-setup.md](play-setup.md)
  (Google), and the copy is in [app-store-listing.md](app-store-listing.md) and
  [play-listing.md](play-listing.md). This page points at them and does not
  repeat them.
- **No history here.** A finished section is deleted, not kept ticked. Git and
  the record hold what happened.

The file name says App Store because that was the only store when it was first
written. It stays because a dozen documents link to it.

---

## Where we are

Updated 2026-10-01.

| | |
|---|---|
| **On testers' phones** | 1.0.0 (27): TestFlight from `b0384be`, Play internal from `080d760`, which differs from it in `codemagic.yaml` only. Not tagged yet. The iOS build was signed with `mgkfitness_distribution`, the first on MGKFitness's own certificate |
| **Release candidate** | **Build 28, not cut.** Its code is written and the pubspec still reads `1.0.0+27` |
| **Built from** | `develop`. `main` is what has shipped ([CONTRIBUTING.md](../../../CONTRIBUTING.md), Branching) |
| **Backend in production** | `coach` v31, `revenuecat` v10, `delete-account` v18 (with Apple's token revocation), migrations through `20260929183008`. Read off the project on 2026-10-01 |
| **Accounts** | Email confirmation is on, mail goes through SMTP2GO, and Apple and Google sign-in are configured for the suite ([store-setup.md](store-setup.md) §11) |
| **Suite** | 1,920 tests pass and the analyzer is clean with build 28's code, with the three `live` tests excluded. Lift's 860 and the shared package's 90 pass against the changed nav bar. This is the only place the count is written |
| **Screens** | [The board](https://claude.ai/code/artifact/9ddfd186-11ad-4260-bde9-ef8b7a5d9190), version 25, is build 27's. Build 28's plates are drawn and captioned (138, seven of them new) and are published once its code is committed, because a plate is stamped with the commit it was drawn at |
| **On a phone** | No full test sitting since build 13. Two purchases are recorded, Coach on Android (11 Sep) and one on TestFlight (30 Sep); sections G and P of the sheet have never been run through |

---

## What is left, in order

### 1. Before the cut

Build 27 was built, reached both stores, and was opened. Six things came out of
that first look, and they are build 28: a launch animation (the icon's mark
dashes across and leaves the name behind it), tabs that slide and fade instead
of cutting, deleting a run,
a treadmill run from Home, *Adjust this week* moved to the Plan tab, and race
week as a week of its own with race day drawn on the plan
([ADR-0044](decisions/0044-race-week-is-a-week-of-its-own.md)). The code is
written and tested. What is left here is not code.

- [ ] **Lift gets the nav bar's moving selection too.** It is in the shared
      package, so Lift's next build has it and Lift's board is stale on every
      plate that shows the bar. Lift's suite passes against it. Say so in
      Lift's lane before its next cut.
- [ ] **The published policy goes live with the build, not before.** The pages
      under `web/public/run/` name Esri now. They reach the site when `web/`
      next goes to `main`.

### 2. Cut build 28

- [ ] `apps/mgk_run/pubspec.yaml` to `1.0.0+28`, in a commit of its own.
- [x] [The test sheet](testflight-1.0.0-test-sheet.md) is carried to 28, with
      rows for the launch (A7 to A11), the treadmill run (C27), race week (D4,
      D19, D20) and deleting a run (E18 to E20). Its header still says "not cut
      yet": write the two commits in when the builds exist.
- [ ] Both workflows fired from the same commit on `develop`:
      `scripts/codemagic-build.sh run-ios-release develop` and
      `scripts/codemagic-build.sh run-android-release develop`.
- [ ] Tag `run/build-27` on `080d760` and `run/build-28` on the commit
      Codemagic checks out, each with both build records in the message. 27 is
      tagged although nobody sat down with it: it is what testers hold today.

### 3. The sitting

- [ ] **One sitting on build 28, on both phones**, from the test sheet. It has
      to include the purchase on each store (sections G and P), the Android
      foreground-service video (V) and the listing screenshots (H).
- [ ] Judged on the phone while there: Esri's label size and sharpness (the
      tiles are drawn at one pixel per point, so expect them softer than
      MapTiler's were), `kBasemapOpacity` (0.85 was set against MapTiler), and
      the credit: *Powered by Esri* above the in-run panel, opening the sources
      on a tap.
- [ ] **The map with no signal**, which only a phone can show. Open the app
      with a signal, wait a few seconds, switch to aeroplane mode, then press
      Start: the map around you should already be drawn. Then run a street the
      map has shown before, still offline: it should draw from the phone's
      copy. A street it has never shown stays a plain ground, which is right.
- [ ] Proved for the first time on a phone, because no test can: Google on the
      iPhone (it needs *Skip nonce checks* on in Supabase; Lift's
      `store-setup.md`, step 7), and Apple on Android coming back from the
      browser into the app.

### 4. The store forms

No build needed, so these can run alongside 1 to 3.

- [ ] **App Store Connect:** Premium's description
      ([store-setup.md](store-setup.md) §2), the two review accounts (§9), and
      every submission form (§10).
- [ ] **Play Console:** every App content declaration
      ([play-setup.md](play-setup.md) §4), the subscriptions' descriptions and
      benefits (§5), and the listing ([play-listing.md](play-listing.md)).

### 5. The graphics

Taken from build 28 on a real phone. The plates draw no map tiles, and the
stand-ins in `store-assets/` show heart rate, calories and elevation that a
recorded run never has, so neither may be submitted.

- [ ] **App Store:** the 6.9" screenshots
      ([app-store-listing.md](app-store-listing.md) § Screenshots).
- [ ] **Play:** the feature graphic (1024 × 500, missing and mandatory), the
      phone screenshots, and the 512 icon re-saved with alpha if Play refuses
      it ([play-listing.md](play-listing.md) § Graphics).

### 6. Submit

- [ ] **App Store:** build 28 with both subscriptions attached, demo account A
      in Sign-in, the review notes, and manual release.
- [ ] **Play:** build 28 promoted from internal to production, with managed
      publishing on ([play-setup.md](play-setup.md) §11).
- [ ] Release both when both are approved, then promote `develop` to `main` as
      [CONTRIBUTING.md](../../../CONTRIBUTING.md) describes.

---

## Rules that hold until it is live

Each of these was got wrong once. The reasoning is in the record or the ADR.

- **`REVENUECAT_ACCEPT_SANDBOX` stays on.** App Review buys in the sandbox
  ([ADR-0037](decisions/0037-the-sandbox-stays-open-in-production.md)).
- **The build number is the `+N` in the pubspec**, bumped by a commit before a
  build is fired, and both stores read it from there (ADR-0039).
- **Edge Functions are deployed by name**, and never `daily-ai-summary`.
- **Production migrations and moving a published tag are the owner's to run.**
  Claude Code's auto mode refuses both.
- **`NSHealthUpdateUsageDescription` stays in `Info.plist`**, although the app
  writes nothing to Health. App Store Connect refuses the upload without it
  (error 90683).
- **Nothing from MGKFitness is signed, sent or billed through Frunt's
  accounts.**

## Open, and not blocking

- **OpenRouter's reply** on the processor agreement, sent 1 September
  ([openrouter-processor-agreement.md](openrouter-processor-agreement.md)), and
  the same agreement with RevenueCat. Both are obligations running alongside
  the release, not gates on it.
- **Everything the 29 September review deferred**, each with a date to look
  again: [after-1.0.0.md](after-1.0.0.md).
- **Three dates that stop things working if missed:** Supabase's Apple secret
  (regenerate by 2027-03-20), the Esri key (expires 2027-09-29; ship its
  second key by the end of August 2027) and the signing certificate
  (2027-09-30).
