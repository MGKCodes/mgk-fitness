# Run 1.0.0: what is left before both stores

The plan for submitting Run 1.0.0 to the App Store and Google Play, from one
commit with one build number
([ADR-0039](decisions/0039-one-commit-two-stores-and-the-pubspec-owns-the-build-number.md)).

> **Done, 19 October 2026: Run is on both stores.** 1.0.1 (build 31) is on
> sale on the App Store and Google Play. Apple rejected 1.0.0 (build 29) on
> 16 October and 1.0.1 replaced it
> ([ADR-0046](decisions/0046-a-version-is-submitted-once.md)). What is still
> unticked below is phone work and one note for Lift; none of it stands
> between Run and a store any more.

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

Updated 2026-10-19 for the stores, the builds and the branches. A row that
gives its own date was read on that date.

| | |
|---|---|
| **On sale** | **App Store: 1.0.1 (31) since 19 October 2026.** Approved in submission `7156a611` (sent 16 October with four items: the version, the `Run Coach` group and both subscriptions) and released by itself at 19:45 UTC, since it was set to release on approval. 1.0.0 (29) was rejected there on 16 October (guideline 4) and never released. **Google Play: 1.0.1 (31) since 16 October**, on full rollout; 1.0.0 (29) was live by 5 October. `scripts/store/stores.py status run` and `links run` read both |
| **On testers' phones** | **1.0.1 (31) on both**: TestFlight and Play internal, built by Codemagic on 16 October. Tagged `run/build-31` on `1acf955`; Android's was rebuilt from `main` after its first publish failed ([`.store-release.md`](../../../.store-release.md)). 1.0.0 is `run/build-29` |
| **Built from** | **`main` holds Run 1.0.1** (`30c2160`, promoted on 16 October with everything but `apps/mgk_lift`); `develop` is 1.0.2 ([ADR-0046](decisions/0046-a-version-is-submitted-once.md)) |
| **Backend in production** | `coach` v31, `revenuecat` v10, `delete-account` v18 (with Apple's token revocation), migrations through `20260929183008`. Read off the project on 2026-10-01 |
| **Accounts** | Email confirmation is on, mail goes through SMTP2GO, and Apple and Google sign-in are configured for the suite ([store-setup.md](store-setup.md) §11) |
| **Suite** | 1,948 tests pass and the analyzer is clean at `6e20a70`, with the three `live` tests excluded. Lift's 860 and the shared package's 93 pass against the changed coach reveal. This is the only place the count is written |
| **Screens** | [The board](https://claude.ai/code/artifact/9ddfd186-11ad-4260-bde9-ef8b7a5d9190): version 27, every plate drawn at `6e20a70`, was 1.0.0's. Since 5 October it shows 1.0.1 (version 33): 72 plates drawn at `170ab2d`, the rest on their 1 October pictures, H4, H5, Y8 and Y9 among them until a weekday other than Monday (`test/plates/board.state.json` says which is which). The lock-screen readout is on no plate |
| **For the forms** | [The submission sheet](https://claude.ai/artifact/Y2zLyeNxVuTrJTfHUn7tqM): every field of both consoles, ready to paste. [The store shots](https://claude.ai/artifact/KmRop4oC1KrHb2UdHykJbU): the listing pictures |
| **On a phone** | No full test sitting since build 13. Two purchases are recorded, Coach on Android (11 Sep) and one on TestFlight (30 Sep); sections G and P of the sheet have never been run through |

---

## What is left, in order

### 1. Before the cut

Build 28 went to TestFlight and the owner looked at it that evening. Four
things came back, and they are build 29:

- **The coach's line could not be read.** It played behind the launch
  animation, so only its last second was seen. It waits for the launch now,
  opens out of the mark, is held about five seconds and closes back.
- ***Add a treadmill run* was a lone button under Start.** It is a full-width
  row at the foot of the *This week* tile.
- **The start screen said too little and did not show where you are.** It has
  a dot at your position that follows you, a GPS line, and a panel with the
  session's pace, about how long, effort and how it should feel.
- **The map was soft.** Esri's tiles are drawn at two pixels a point; their
  street names are half the size
  ([ADR-0043](decisions/0043-the-map-keeps-what-it-has-shown.md), amended).

And one more, asked for with them and built the same evening: **a run's
distance, time and pace on the lock screen** while it records. A Live Activity
on the iPhone and a notification on Android
([ADR-0045](decisions/0045-the-runs-figures-on-the-lock-screen.md)). The
Android half was run on an emulator. The iPhone half is a second target in the
Xcode project, written without a Mac: Codemagic is the first thing to compile
it.

- [x] **The Live Activity extension's App ID and profile** are in Codemagic
      ([store-setup.md](store-setup.md) §11), and the iPhone build signed with
      them.
- [ ] **Lift gets two shared changes.** The nav bar's moving selection (build
      28) and the coach's line opening out of its mark (build 29) are in the
      shared package. Lift's suite passes against both and its board is stale
      where either shows. Say so in Lift's lane before its next cut.
- [x] **The published policy names Esri.** `web/public/run/privacy-policy.html`
      went to `main` on 2 October (`ee5cfe6`) and the live page was read back.
      Only the page went: the document and the in-app copy on `main` stay as
      they were until `develop` is promoted, so `main`'s own legal test expects
      the old name until then. `main` has not been merged back into `develop`,
      which already has the page; do that with the next push of `develop`.

### 2. Cut build 29

- [x] `apps/mgk_run/pubspec.yaml` is `1.0.0+29` (`6e20a70`).
- [x] [The test sheet](testflight-1.0.0-test-sheet.md) is carried to 29, with
      rows for the coach's line (A12), the start screen (C13, C28, C29), the
      treadmill row (C27) and the map's sharpness (M1). Its header names the
      commit and both build records.
- [x] **Android:** built and on Play internal (Codemagic
      `6abed24d6ae690405c3a70d8`).
- [x] **The iPhone app compiles**, both targets, unsigned (Codemagic
      `6abed24e6d9c8b2e33d5c126`). It was the first thing to build the
      extension.
- [x] **The iPhone build:** signed and on TestFlight (Codemagic
      `6abed6a85aeae4113434d463`), from the same commit as Android.
- [x] Tagged, 2 October: `run/build-27` on `080d760` and `run/build-29` on
      `9204036`, each with its build records in the message.

### 3. The sitting

- [x] **The owner used build 29 on the iPhone** on 2 October and is happy to
      submit it. The lock-screen readout was seen working there (C30 to C33).
- [ ] **What that did not cover, and a store will.** A purchase on each store
      on this build (sections G and P): App Review buys in the sandbox as its
      first act. And build 29 on an Android phone at all: it has only been
      run on an emulator, which is also where its foreground-service video was
      recorded.
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

No build needed, so these can run alongside 1 to 3. **Paste from
[the submission sheet](https://claude.ai/artifact/Y2zLyeNxVuTrJTfHUn7tqM)**, which reads every field out of the listing docs
and unwraps the descriptions; build it again after any change to them
(`python tool/build_submission_sheet.py`).

- [x] **App Store Connect:** every form filled on 2 October, from the
      submission sheet: the version page, App Information, App Privacy (ten
      data types, published), Pricing, both subscriptions and the review
      accounts, whose passwords were reset that day.
- [x] **Play Console:** every form filled on 2 October, from the submission
      sheet: the listing, store settings, both subscriptions, and every App
      content declaration. One optional Data safety question is left
      unanswered until the site has a page for it
      ([play-setup.md](play-setup.md) §4).
- [x] **App Store Server Notifications** point at RevenueCat, both URLs, set
      on 2 October ([store-setup.md](store-setup.md) §3).
- [x] **Play's real-time developer notifications** reach RevenueCat, set up
      and tested on 2 October ([play-setup.md](play-setup.md) §6).
- [x] **The regulated medical device declaration** in App Information:
      declared not one, 2 October.
- [x] **The subscriptions' review screenshot and Premium's review notes** were
      September's, and said Premium's plans came from a better model. Both
      replaced on 2 October: the screenshot is the current paywall, and the
      notes say replies and allowance, as ADR-0041 has it.
- [x] **Both descriptions mention the run's figures**, one line under WHAT IS
      FREE, added on 2 October. The App Store says *on your lock screen*, where
      the owner saw it. **Play says *in a notification*:** on Android 16 the
      readout is not on the lock screen by default
      ([after-1.0.0.md](after-1.0.0.md)). Play's first wording said lock
      screen and was saved in the console that way; **paste the corrected
      description again before sending Play for review.**
- [x] **The foreground-service video** is on the site (`06a57d4`), recorded on
      an emulator ([play-setup.md](play-setup.md) §4).

### 5. The graphics

Drawn, not captured: the app's own code draws the six screens with the real
map, and a frame and the words are added afterwards
([app-store-listing.md](app-store-listing.md) § Screenshots). Every file below
passes `python tool/export_store_assets.py --check`.

- [x] **The six screens**, for each phone, with a runner who has only what the
      app records.
- [x] **Play's feature graphic** (1024 × 500) and **its 512 icon with alpha**.
- [x] **The design is Still**, chosen by the owner on 2 October from
      [the gallery](https://claude.ai/artifact/KmRop4oC1KrHb2UdHykJbU).
- [x] **Upload:** `ios-still` to App Store Connect; `play-still`, the feature
      graphic and the icon to Play Console. *Done through
      `stores.py screenshots run`: the App Store's redrawn without "Free" on
      7 October, and both stores' drawn again from 1.0.1 on 16 October.*

### 6. Submit

- [x] **App Store: submitted on 2 October 2026**, four items in one
      submission: iOS App 1.0.0 (29), the `Run Coach` group and both
      subscriptions. Waiting for Review. Submitted on manual release; *since
      5 October it releases itself on approval*, switched mid-review with
      `scripts/store/stores.py release-type run --automatic --yes`.
- [x] **Play: submitted on 2 October 2026**, eleven changes in one
      submission: build 29 promoted from internal to production
      ([play-setup.md](play-setup.md) §11), its countries, the listing and the
      declarations. **Managed publishing is off, the
      owner's choice on 2 October:** the app goes live on Play as soon as
      Google approves it, with no button to press, and so possibly before the
      App Store does.
- [x] **`develop` promoted to `main`** on the day of the submission, and
      `develop` moved to `1.0.1+30`
      ([ADR-0046](decisions/0046-a-version-is-submitted-once.md)).
- [x] **If either store rejects it:** a form, a picture or a description is
      fixed in the console and resubmitted with build 29. Anything that needs a
      new binary goes out as `1.0.1`, from `develop`. *Apple rejected 1.0.0 on
      16 October (guideline 4: the coach asked for a name after Sign in with
      Apple). The fix was code, so 1.0.1 (31) went from `develop` the same
      day, resubmitted in the same submission, which kept the subscriptions.*
- [x] **When Apple approves**, press release in App Store Connect. Play
      publishes itself. *Nothing to press: the version released itself on
      approval, 19 October, and Play published 1.0.1 on 16 October.*

---

## Rules that hold for every release

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
