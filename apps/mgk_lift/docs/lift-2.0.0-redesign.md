# Lift 2.0.0 — the redesign

The plan that follows Matthew's design review of 30 September 2026,
[design-review-2026-09-30.md](design-review-2026-09-30.md): nineteen findings
over the [Lift Screen Board](https://claude.ai/artifact/UZKDFbA8qht1Nj9TQ3dQB1)
(version 11), and the thirteen decisions settled with him the same day. It
changes screens and flows and, for signing in, both apps and the server.

Same discipline as [lift-2.0.0-logging-rework.md](lift-2.0.0-logging-rework.md):
tick items as they land, and when something is settled differently from how it
is written here, **change the item and say why**. The order of the phases is the
order of work.

> **What this replaces in the logging rework.** D1 (a saved workout learns at
> Finish automatically, with Undo) and Phase 3's "The template learns"; the
> builder; the saved-workout preview; the ready-made library as a way to start;
> "Add exercise" as the dock's resting state; and the photograph behind a
> workout (Phase 5). Phase 0 below edits those items to point here.

---

## Read this first

**`main` moved.** `origin/main` gained 57 commits of Run's build-26 work after
the review (`8db4ee5`, 2026-09-30), and three parts of this plan build on that
work rather than on the branch's copy of it: Run's sign-in and account safety,
Run's Settings, and Run's purchase screen. So Phase 0 starts with the merge the
[handover](handover-2026-09-30.md) describes. `main` touches nothing under
`apps/mgk_lift` or `packages/`, so Lift's line numbers below (from `b239035`)
hold after it.

**Two things need Matthew outside the code, and both take calendar time.** The
Apple, Google Cloud and Supabase configuration for signing in, with a new
provisioning profile for each app; and a working Replicate connection for the new
photographs (it failed to connect in the planning session). Phase 0 starts both,
so they are ready when the code is.

**Run has to ship too.** Signing in is shared by both apps (R10), so a Run build
carrying it must reach the store no later than Lift 2.0.0. Run's releases come
from `main`, which puts the merge of this branch back into `main` — waiting on
Matthew — on the way to submission.

**TestFlight build 32 predates all of this**, and the store screenshots wait for
it ([submission-week.md](submission-week.md), workstream F).

Codes (`W6`, `P7`, …) are the board's: the letter is the act, the number the
plate.

## What the review found

| # | Finding | Screens | Phase |
|---|---|---|---|
| 1 | Sign in needs a photograph, and Sign in with Apple and Google | S1, S2 | 1 |
| 2 | Track doesn't work: space, imagery, big numbers, and Start as the point | T1–T7 | 2 |
| 3 | No photograph behind a workout | W1 | 3 |
| 4 | Your workouts: glass, and Start on each | W3 | 2 |
| 5 | Ready-made workouts confuse; the coach should offer workouts | W4 | 2 (the cut); 2.0.x (the coach) |
| 6 | The builder makes no sense beside the session screen | W5, W17 | 2 |
| 7 | The preview is one step too many | W15, W16 | 2 |
| 8 | The session's heading wants glass; Add is not the main button | W6 | 3 |
| 9 | Rest timer: no change | W10, W18 | — |
| 10 | The C on the session screen, with Run's minimising bubble | W6 on | 3 |
| 11 | Search is too strict; filter by muscle and equipment | W7, W19 | 7 |
| 12 | Summary: glass, louder totals, a clearer exit, saving asked at Finish | W11 | 4 |
| 13 | Summary: the bubble instead of the coach button and New bests; the C opens a chat | W11, W12, W21 | 4 |
| 14 | Backup: a pill at the top that says why when it fails | W22, W23 | 4 |
| 15 | A real sales screen, behind the C for anyone unsubscribed | P7 | 5 |
| 16 | Plan, paid, no plan yet: say what happens next | P2 | 5 |
| 17 | Today's session moves to Track; Plan becomes the calendar | P5, P6 | 2, 5 |
| 18 | Profile: glass stats, bests out, previous workouts in their own space | G1, G2 | 6 |
| 19 | Settings: account first, less text, Run's units | A1–A10 | 6 |

## Decisions

### Settled 2026-09-30

With Matthew, in the planning session. Numbered R to keep them apart from the
logging rework's D1–D6.

1. **R1. Greyscale stays.** The references give structure, not palette: big
   numbers, glass, one obvious action. Where a screen leads with a photograph
   (Track, Sign in), the photograph gets strong enough to carry the top of the
   screen. That changes ADR-0009's signature treatment — a photograph at
   ~25–34% under a scrim — which Run shares, so it is written as a platform
   decision (Phase 0), not a Lift edit.
2. **R2. 2.0.0 is the screens and the flows.** Search (11) and exercise stats go
   in if time allows, otherwise 2.0.1. A coach that offers workouts from chat is
   2.0.x.
3. **R3. Saving to a workout is a question, and it replaces the automatic
   learning (D1).** Asked when a session from a saved workout added, removed or
   swapped movements; one line lists the changes (*"+ Dips, − Cable Fly"*); yes
   by default. Sets, reps and order never ask, and a session never changes them.
   The lesson with Undo goes.
4. **R4. It is asked in the Finish sheet.** Nothing is left pending on the
   summary, so its button becomes **Done** and the C there only opens the chat.
   A session started blank gets *Save as a workout* in the same place, off by
   default.
5. **R5. The builder goes; the editor stays** for existing workouts, behind a
   "…" on each row. It is also the way back from a wrong yes.
6. **R6. Nothing on the coach is free.** For anyone unsubscribed, signed out
   included, the C opens one full-screen sales screen; Plan and Photos keep a
   short explanation whose button opens the same screen. The account is asked
   for when a tier is chosen, not before the offer is seen.
7. **R7. The bubble says new bests to everyone.** Bests are tracking, and
   tracking is never gated. Only the tap differs: the chat if you pay, the sales
   screen if you don't.
8. **R8. Plan never starts a workout.** Today's session starts from Track.
   Another day offers *Do it today*, which puts that session on Track for today.
9. **R9. Bests stay on Profile**, in a contained card, until the exercise stats
   screen ships.
10. **R10. Sign in with Apple and Google ship in 2.0.0, in both apps**, built
    once from this lane as shared code. Run's build carrying it reaches the
    store no later than Lift 2.0.0.
11. **R11. About three starter workouts survive** — Full Body, Upper / Lower,
    PPL — shown only where one is needed: an empty library, a first run. No
    browsing sheet.
12. **R12. Track's big number is sessions this week** ("2", or "2 of 4" with a
    plan). Streak and volume stay on Profile.
13. **R13. A workout sits on a dark gradient with a soft light**, drawn in code,
    so the glass heading has something to blur. New greyscale photographs are
    generated for Track and Sign in.

### What they replace

| Settled before | Where | Now |
|---|---|---|
| D1: learn at Finish automatically, with Undo | logging rework, Phase 3 | R3, R4 |
| The builder (W5) | logging rework, Phase 3 | R5 |
| The preview (W15, W16) | logging rework, Phase 3 | Start on each row (Phase 2) |
| Ready-made as a way to start (W4) | logging rework, Phase 3 | R11 |
| *Add exercise* as the dock's resting state | logging rework, Phase 5 | *+ Add* in the top bar (Phase 3) |
| A grounded photograph behind the session | logging rework, Phase 5 | R13 |
| The C sends the unsubscribed to Plan, and the signed-out to sign in | `lift_shell.dart` `_openCoach` | R6 |
| The paywall as Plan's and Photos' empty state | `plan_surface.dart`, `photos_surface.dart` | R6: doors to one sales screen |
| Planned sessions start from Plan | `standing_plan_surface.dart` | R8 |

The brain's Draft decision *"Lift templates are the coach's grounding layer, not
a user-facing library"* (2026-08-07, never built) is settled by R11: the
catalogue stays whole as the coach's raw material, and three starters are shown.

### Found while planning

Not in the review. All read from the code; none yet seen on a screen.

- **Plans live only on the server.** `SupabaseStandingPlanStore` keeps no local
  copy, and a failed load leaves the plan null (`lift_shell.dart` 894–906). Once
  today's session starts from Track (17), no signal at the gym means no planned
  session. Phase 2 keeps a local copy.
- **Nothing can move a planned session.** A plan's days are derived (`weekdays`
  beside `dayOrder`), not stored as dated sessions, and the coach's move-a-day
  instructions (`LIFT_ADAPT_INSTRUCTIONS`) are not registered as a surface. So
  *Do it today* is a local, one-day choice (Phase 2). Plan's pitch promises it
  anyway — *"Shoulder is sore, can we move Thursday? It proposes the change; you
  approve it."* — and the sales screen must not repeat that (Phase 5).
- **The C is on the tabs only.** The session screen, the summary and every other
  pushed route cover it. Lift has no `CoachNote` or `CoachReveal`, and
  `hasCoachNote` is never passed outside the preview harness.
- **A second account on the phone inherits the first one's training.** Run fixed
  this on `main` (`ab02080`: `AnotherAccountScreen`, `LocalDataGuard`); Lift has
  nothing like it. Apple and Google make a second account far more likely — an
  Apple sign-in that hides the address is a new account — so the guard comes
  with signing in (Phase 1).
- **Sign in with Apple needs its tokens revoked when the account is deleted**
  ([TN3194](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple)).
  Supabase does not do it. `delete-account` removes the login only when neither
  app has data left (`auth_user_deletable`), which is where the revoke belongs.
- **Photos does not see a purchase made from it.** `isEntitled` is fixed when the
  route is pushed (`lift_shell.dart` 866–880), so the offer stays up after
  buying. The sales screen returns a result, and Photos reads it (Phase 5).
- **The Finish sheet is not on the board**, though the save question moves into
  it. Phase 0 adds its plates.
- **The store wording exists twice.** `storeName`, `storeAccountName` and
  `renewalWording` are in both apps (Lift's `purchase_sheet.dart` 452–479, Run's
  `purchase_screen.dart`). Principle 9: they move into `mgk_ui` with the sales
  screen.

### Open — recommendation first

The plan is written against these; change the item if the answer differs.

- **O1. Apple and Google are asked for an email address only**, not a name or a
  photograph. Lift's policy line *"Account data — email / auth identifier"*
  stays true, and the store's privacy answers only gain the providers' names.
- **O2. The same person, two accounts.** Supabase joins a Google sign-in to an
  email account with the same verified address; an Apple sign-in that hides the
  address makes a new one. The sign-in screen says so under the Apple button,
  and the other-account guard stops training crossing over. Joining the two in
  Settings is 2.0.x.
- **O3. Mid-workout, the bubble says new bests only.** Anything else it could say
  waits until bests have been seen working at a rack.
- **O4. *Do it today* lasts until that session is finished or the day ends**, and
  Track shows it as today's session, "moved from Thursday".
- **O5. The explanation under *Start today's session*** (17) is the day's
  movements with last time's numbers, which is what Plan's day detail shows now.
  The plan's reasoning stays on Plan.
- **O6. How strong the photograph gets, and where it fades**, is set by eye
  against the board, then written into the ADR amendment.

---

## Phase 0 — groundwork

**Why first:** three of this plan's pieces are Run's code on `main`; the shared
components come before the screens that use them; and the two things that need
Matthew take calendar time.

- [x] **Merge `main` into the branch**, as the handover's *Merging with `main`*
      says: `main`'s side in `supabase/functions` and its migration names, both
      sides in `web/`. Then Lift's, Run's and `mgk_ui`'s suites, both Deno
      suites, `npm run legal` and `next build`. *Done 2026-09-30 (`4816570`):
      two conflicts, both `main`'s side, and one seam the merge could not show
      (a new Run test importing the coach mark from where it used to live). Run
      1,752 tests, Deno 214 + 21 + 7, `mgk_ui` 59, `mgk_units` 47, web build.
      Lift 759 of 760: `in_workout_test`'s reordering test fails identically on
      the commit before the merge, so it predates it and is fixed on its own.*
- [ ] **Amend ADR-0009** for the photograph (R1, O6): where a screen leads with
      one, it may carry the top of the screen, with the scrim light under the
      headline; elsewhere the faint texture stands. Written as a platform
      decision beside ADR-0009 — the ADR itself says a change like this is never
      a one-app edit — and principle 8 in `docs/design.md` points to it.
- [ ] **Shared pieces into `mgk_ui`**, Run's suite after each:
      - Run's `HomeTile`, `HomeStatTile` and `HomeTileRow` (`home_tiles.dart`),
        as they are — they import nothing from Run — plus a wide stat tile for
        R12.
      - Run's `CoachReveal`, and the data half of `CoachNote` (`headline`,
        `detail`, `kind`). The locked line becomes a parameter;
        `CoachNote.forRuns` stays in Run.
      - `storeName`, `storeAccountName`, `renewalWording`, and Lift's
        `RestorePurchasesButton`.
      - The soft-light backdrop (R13), beside `PhotoBackdrop`.
- [ ] **The board catches up** with plates for the Finish sheet — with unticked
      sets, and for a session from a saved workout — so the screen that takes the
      save question is photographed before it changes.
- [ ] **Point the old plans here.** The logging rework's items that R3–R8 and
      R13 replace are edited to say so, and the design review links here.
- [ ] **Photographs** (R1, R13): new greyscale heroes for Track and Sign in, made
      as the current ones were (Replicate, per ADR-0009) and composed for a
      headline over the top. Today's Track hero is a 35 KB file made to sit at
      30%. *Needs the Replicate connection; the screens use placeholders until
      then.*
- [x] **The sign-in dashboards** *(Matthew)*, added to
      [store-setup.md](store-setup.md) with owners:
      - Apple: Sign in with Apple on both App IDs (`com.mgkcodes.liftio`,
        `com.mgkcodes.fitness.run`), grouped under one primary App ID; a
        Services ID and a key, for Android's web flow and for revoking tokens.
      - Provisioning: both App Store profiles regenerated, since a profile is a
        snapshot of the App ID's capabilities. Lift's is uploaded to Codemagic
        by hand (*Lift MGKFitness App Store*); Run's is fetched, once regenerated
        in the portal.
      - Google Cloud: a web client (the one Supabase checks), an iOS client per
        app, and an Android client per app with the SHA-1 of both the upload key
        and Play's app-signing key.
      - Supabase, the hosted project: Apple and Google switched on, with every
        client id, and the redirect for Android's Apple flow.

      *Apple's half done 2026-09-30, and it found something: Apple regenerated
      Lift's profile on Frunt's distribution certificate, Run's already used
      it, and both apps published through Frunt's App Store Connect key. By
      Matthew's rule that nothing MGKFitness ships depends on Frunt, both apps
      now sign with MGKFitness's own certificate and publish with its own key
      ([store-setup.md](store-setup.md) 7b; `codemagic.yaml`).*

      *All done the same day, walked through screen by screen. Google's clients
      live in the existing `mgk-fitness` Cloud project; Lift's Play app was
      created and given a draft first upload so Play would generate the
      fingerprint Google needed; and Supabase already had both providers on
      from Liftio 1.x, with ten Apple accounts that keep working because Lift
      is the primary App ID. Every value is in store-setup.md 7a–7d.*

**Done when:** the branch contains `main` and every suite passes; the shared
pieces are in `mgk_ui` and Run looks the same; the ADR amendment is written; the
dashboards are in `store-setup.md`.

---

## Phase 1 — signing in, both apps

**Why here:** it has the longest lead time, it is the only phase Run has to ship
too, and the sales screen (Phase 5) asks for an account at the moment somebody
chooses a tier — which is only as good as signing in is.

### Shared

- [ ] **One way of signing in, used by both apps**: Apple natively on iOS
      (`sign_in_with_apple`, then `signInWithIdToken` with a nonce), Apple's web
      flow on Android, Google natively on both (`google_sign_in`, then
      `signInWithIdToken`). Email and password stay. Where it lives — a small
      workspace package, since it is not UI — is settled when it is written; the
      buttons go in `mgk_ui`.
- [ ] **Email only** (O1).
- [ ] **The other-account guard, shared.** Run's `LocalDataGuard` and
      `AnotherAccountScreen` move where both apps can use them: an account
      signing in on a phone whose training belongs to another either erases it
      and starts clean, or signs out and leaves it. Each app supplies its own
      erase.
- [ ] **Links back into the app.** Neither app has a URL scheme or an intent
      filter today; Google on iOS needs its reversed client id, and Apple's
      Android flow needs a way back (`<package>://login-callback`, already in
      Supabase's redirect list).
- [ ] **A password reset that finishes.** *Found during the dashboards,
      2026-09-30.* "Forgot your password?" sends an email whose link can only
      land on the Site URL, and no page there lets anybody choose a new
      password, so a reset has never been able to complete in either app. A
      small page on `mgkfitness.mgkcodes.com` does it (`web/`), and both apps'
      `sendPasswordReset` pass it as `redirectTo`. Apple and Google accounts
      have no password to forget.

### Lift

- [ ] **The sign-in screen** (1, S1, S2) on the new photograph (R1): *Continue
      with Apple* and *Continue with Google* above email and password, and the O2
      line under Apple. Guideline 4.8: Google is offered only beside Apple.
- [ ] Lift's first entitlements file (Sign in with Apple). `codemagic.yaml`'s
      note that Lift "declares no entitlements" changes with it.
- [ ] `SupabaseAuth` and `FakeAuth` gain the two providers behind `AuthService`.

### Run

- [ ] Run's sign-in screen gains the same two buttons, in Run's layout, and Run's
      entitlements gain Sign in with Apple beside HealthKit. Run's suite.

### Deleting an account

- [ ] **Apple's tokens are revoked** when the login is actually deleted. For an
      account with an Apple identity, the app asks the person to confirm with
      Apple before deleting and sends the fresh authorization code with the
      request; `delete-account` exchanges it and calls Apple's revoke endpoint
      only if it deletes the login (`auth_user_deletable`). A failed revoke never
      blocks the deletion, which Apple requires be fulfilled regardless. Deno
      tests against a fake Apple endpoint.

### The policies

- [ ] Both apps' privacy policies name Apple and Google as ways to sign in, and
      what they pass on: an email address and an identifier. Lift:
      `legal_copy.dart`, `docs/privacy-policy.md`, and the web page from
      `tool/build_legal_pages.py`. Run: the same three plus its legal site,
      pinned by Run's *what we collect* test. The store answers in
      `store-listing.md` and Run's store docs.

**Done when:** on a release build of each app, on each platform, a new person can
sign up with Apple and with Google, sign into the other app as the same account,
meet the guard as a second account on the same phone, and delete the account
with Apple's tokens revoked.

---

## Phase 2 — starting a workout

### Track (2, 17, R12)

- [ ] **Rebuilt from the shared tiles.** The photograph carries the top of the
      screen with the headline set on it; one wide tile, sessions this week; your
      workouts, each with **Start**; one main button anchored low, with the C
      beside it in the same row.
- [ ] **The button's words still come from the state**, as `_headline` and
      `_StartButton` decide them now: *Start a session*; *Start today's session:
      Upper*, with the day's movements and last time's numbers in a glass card
      above it (O5); *Resume session*, with the interrupted card. On a planned
      day, starting something else is a quiet link under the button.
- [ ] **Out:** the three-number strip (`_RecentStrip`) and *Next up*, whose jobs
      the tile and the planned card take over.
- [ ] **A local copy of the active plan**, refreshed whenever it loads, so
      today's session shows with no signal.
- [ ] **Do it today** (R8, O4): a day chosen on Plan becomes Track's session for
      today, "moved from Thursday". A choice on this phone, not a plan edit.

### Your workouts (4, 6, 7, R5)

- [ ] **Glass rows over the photograph.** Each has **Start** and a "…" (Edit,
      Duplicate, Delete). Tapping the row opens it in place to the full list,
      sets × reps — what the preview showed, without the extra screen.
- [ ] **The preview sheet goes** (W15, W16). Its rule moves to Start: with a
      session open, Start asks *"Push is still open. Resume it, or discard it and
      start Pull?"*. The backstops stay: `TrackController.openWorkout` resumes,
      and the recorder throws `SessionInProgress`.
- [ ] **Build one goes**, from the bar and from the empty state. The editor
      opens from "…" → Edit only.
- [ ] Track's workout cards get the same Start and the same rule.

### Starters (5, R11)

- [ ] **The ready-made sheet goes.** Three starters — Full Body, Upper / Lower,
      PPL: the offered splits less *Upper / Lower + PPL* — appear in the empty
      library and in Track's empty *Your workouts*, each added with one tap and
      an Undo.
- [ ] The catalogue (15 sessions, 8 splits) stays in `workout_templates.dart` as
      the coach's raw material, and `premadeId` still records where a copy came
      from.

**Done when:** from a first open, a starter is a started session in two taps; a
saved workout starts in one tap from Track and from the library; and with a
session open, Start asks before anything else begins.

---

## Phase 3 — during a workout (3, 8, 9, 10)

- [ ] **The soft-light backdrop** (R13) replaces `hero_home.webp` behind the
      session (`active_session_screen.dart` 1106–1111).
- [ ] **The heading on glass** (8): title, clock, volume, sets and movements
      (`_LargeTitle`) in a glass panel, over the soft light. The folding bar
      stays.
- [ ] **+ Add beside Finish** in the top bar (`_TopBar`). `_AddRow` goes, and the
      dock exists only while resting: it rises from the bottom edge with the
      timer, which is otherwise unchanged (9).
- [ ] **The C on the session screen**, bottom right as on the tabs, and above the
      dock while it is up. The chat when subscribed, the sales screen when not.
- [ ] **The bubble** (10, R7, O3). When a ticked set beats that movement's best
      estimated one-rep max — Epley, 12 reps or fewer, strictly greater, as
      `SessionSummary.of` counts it — the C opens with the best, holds, and
      closes. The bests are worked out once per session from the log the screen
      already has (`widget.log`) and checked on each tick: no network, no model,
      free for everyone.
- [ ] *Save to your workouts* at the foot of the list goes (R4).

**Done when:** a session looks and behaves as above on the emulator; a new best
plays the bubble once; and a best matched rather than beaten plays nothing.

---

## Phase 4 — ending a workout (12, 13, 14)

### The Finish sheet (R3, R4)

- [ ] **The update is worked out before the sheet, not after.** Today
      `TemplateUpdate.between` runs once the sheet has returned
      (`active_session_screen.dart` 972–976); it moves ahead of it, and the sheet
      takes the result.
- [ ] **The question**, when a session from a saved workout added or removed
      movements (a swap already reads as both): *"Save to Push for next time?
      + Dips, − Cable Fly"*, on. A new set count or a new order alone never asks.
- [ ] **Yes changes only the movements.** Removed ones go and added ones land at
      their position; set counts, rep targets and order stay as the workout had
      them. `TemplateUpdate.after` carries resizes and order today, so this
      needs its own result.
- [ ] **The two conflicts move into the sheet.** Edited on another phone while
      training: the line says so, off, and on overwrites it (today's *Update*).
      Deleted meanwhile: *"Save today's session as a new workout?"*, off.
- [ ] **A session started blank:** *Save as a workout*, off; switched on, a name
      field holding the session's name.
- [ ] Editing a past session (`_doneEditing`) never asks. It has no test today;
      it gets one.

### The summary (12, 13, 14)

- [ ] **The totals on glass, and louder.**
- [ ] ***Back to Track* becomes *Done*.**
- [ ] **Out:** *Talk it over with your coach*, the new-bests section (`_Bests`),
      the lesson (`_LessonCard`, `_Lesson`, `_learn`) and *Save to your
      workouts*.
- [ ] **The C, and the bubble** (13, R7): the session's new bests, then it
      closes. A tap opens the chat about this session when subscribed — the
      session is its first turn — and the sales screen when not. It no longer
      needs to count as Finish (R4).
- [ ] **The backup pill at the top** (14): *Backing up…*, then gone when it
      succeeds; on failure, the reason and a way to Settings, where *Sync now*
      is. Signed out: *Saved on this phone.* and nothing more — the account
      card's rule that it reports and does not sell. The states are
      `sessionBackupMessage`'s; `_BackupLine` goes.

**Done when:** every row of the logging rework's Phase 3 learning table has a test
against R3 — whether it asks, and what yes changes — and the summary has one
exit.

---

## Phase 5 — the coach and paying (15, 16, 17)

### The sales screen (15, R6)

- [ ] **A full-screen route replaces the purchase sheet.** A photograph and one
      headline; each tier a card with its benefits as bullets, and its store
      price and period. **Choosing a tier is the purchase**, as Run's screen
      already works. Restore, the store's renewal wording and the terms and
      privacy links stay: every assertion in `purchase_ui_test.dart` carries over
      (guidelines 3.1.1 and 3.1.2(a)).
- [ ] **It promises only what ships.** Each bullet names the code behind it, and
      the move-Thursday promise goes (*Found while planning*).
- [ ] **Signed out, the offer shows in full**; choosing a tier asks for the
      account — Apple, Google or email — then goes on to the store. The three
      guards stay: the screen, `_identified`, and the identity sync.
- [ ] **Its doors:** the C wherever it is, and Plan's and Photos' buttons.
      `_openCoach` stops sending the unsubscribed to Plan and the signed-out to
      sign in.
- [ ] **Photos reads the result**, and shows the library after a purchase.

### Plan (16, 17, R8)

- [ ] **Unsubscribed:** what Plan is for, briefly, and one button to the sales
      screen.
- [ ] **Subscribed, no plan yet** (16): what happens next, in three steps — tell
      the coach your goal and your days, it builds the block, today's session
      appears on Track — and one button, *Build a plan*.
- [ ] **A live plan, led by the calendar** (17): how the week is going, the week
      and the whole block, the goals, and why this split. Today says what today
      is and links to Track; **nothing starts here.** Every other day offers *Do
      it today*.

**Done when:** an unsubscribed person reaches the same sales screen from the C on
every screen, from Plan and from Photos; buying from any of them unlocks the
screen they came from; and Plan has no Start.

---

## Phase 6 — Profile and Settings (18, 19)

### Profile (18, R9)

- [ ] **The six numbers on glass**, as tiles.
- [ ] **Previous workouts first:** a contained card of the last five — name,
      date, duration, volume, sets — with *See all* to the history.
- [ ] **Bests in a contained card** until the exercise stats screen (R9).
- [ ] The year grid, consistency, most trained and the photos card are kept and
      tightened, not removed.

### Settings (19)

- [ ] **The account first:** Run's profile card shape — initials, email, plan —
      opening an account screen with sign out, restore and delete. Lift keeps no
      photograph of anybody (O1).
- [ ] **Units as rows**, the value on the right, each opening a small sheet with
      its explanation: Run's `SettingsRow` and unit sheet. Distance and weight
      are shared MGKFitness settings, so the rows and the sheet move into
      `mgk_ui` and Run uses them from there.
- [ ] **Explanations behind a tap:** the rest-alert, coach and backup paragraphs
      become one-line rows, with the paragraph behind an info tap or on the
      detail screen.
- [ ] **Spacing rethought** around groups, as Run's are, with the version in a
      footer.

**Done when:** on a 375 pt phone the account and the units are on screen without
scrolling, and Run's Settings looks the same after its rows move.

---

## Phase 7 — if time: search and exercise stats (11, R2, R9)

### Search (11)

- [ ] **Words, not the whole query.** Today `search()` looks for the whole string
      inside a name, muscle group or equipment (`exercise_lookup.dart` 52–73).
      Each word matches on its own, in any order.
- [ ] **Other names:** *one arm* and *single arm*, *db* and *dumbbell*, *bb* and
      *barbell*, *pulldown* and *pull down*, *tricep* and *triceps* — a small
      table, pinned by tests.
- [ ] **One typo per word** over four letters.
- [ ] **Filters:** muscle group (9) and equipment (12, the rare ones folded into
      *Other*) as chips above the list, with search or without.

### Exercise stats (R9)

- [ ] A screen for one movement: the best set, estimated one-rep max over time,
      recent sessions, and its illustrations. Reached by tapping a movement's
      name in a session, the summary, the history and Profile.
- [ ] When it ships, bests leave Profile.

---

## The test pass

### Automated

**Rewritten**, because what they pin changes:

- `workout_library_surface_test.dart`: the lesson (L212–363) becomes the Finish
  sheet's question; *saving a session to the library* (L395–580) becomes the
  blank session's row; *adding a premade* (L582–704) becomes the starters.
- `track_workouts_test.dart`: the preview becomes Start on the card; blocked
  becomes resume-or-discard.
- `session_summary_screen_test.dart`: the save offer goes; *Back to Track*
  becomes *Done*; bests come from the bubble.
- `workout_editor_test.dart`: builder mode goes.
- `purchase_ui_test.dart`: every assertion kept, against the sales screen.

**Kept:** the `TemplateUpdate.between` unit tests (`workout_library_test.dart`
L407–573) — the function stays — and `workout_templates_test.dart`, since the
catalogue stays.

**New:**

- The Finish sheet asks on added, removed and swapped; never on sets or order;
  yes changes only movements; both conflicts; the blank row starts off; the edit
  variant.
- A beaten best plays the bubble; a matched one does not; over 12 reps never
  does; all of it offline.
- Unsubscribed, the C opens the sales screen on every surface; signed out, the
  account is asked for at the tier.
- Signing in with each provider; the other-account guard; a deletion that
  revokes (Deno).
- Track in airplane mode shows today's session from the local plan; *Do it
  today* shows, and is gone once finished.

**Suites:** Lift, Run (the shared pieces and signing in), `mgk_ui`, Deno
(`delete-account`), and both apps' legal-copy tests.

### On the device

- Apple and Google, both apps, both platforms; one account across the two;
  deletion with the revoke.
- The photograph on Track and Sign in; the soft light behind the glass at the
  rack.
- The bubble mid-set: readable, out of the way, still under reduced motion.
- The Finish sheet's question in a real session.
- Airplane mode with a plan: today's session on Track.

### The board

**New or changed:** the Finish sheet (unticked sets, the question, the blank row,
both conflicts), the summary (Done, the bubble, the pill), Track (unplanned,
planned, resume, first run, *Do it today*), the library (Start, the open row, the
starters), resume-or-discard, the session (backdrop, heading, *+ Add*, the C, the
bubble, resting), the sales screen (signed in, signed out, nothing to sell), Plan
(unsubscribed, no plan, live), Profile, Settings and its unit sheet, Sign in, and
the other-account screen.

**Gone:** `workout-preview`, `workout-preview-blocked`, `premade-library`,
`workout-builder`, `session-summary-lesson`, `save-workout`, `purchase-sheet`.

---

## Builds

Each one Matthew's go, because each is outward-facing, and **each is both
platforms**: iOS to TestFlight and Android to Play's internal testing, since
signing in, the photographs and the glass all behave differently on each.

1. **After Phase 1: signing in.** A Lift build from this branch, and a Run build
   carrying the same sign-in — from `main` once this branch is merged back, or
   from this branch with a build number agreed with Run's lane. It proves the
   provider configuration on real phones, which nothing on this machine can.
2. **After Phases 2–4: the workout.** The one to use at the gym.
3. **After Phases 5–6, and 7 if it made it: the submission candidate.** The store
   screenshots are captured from it.

## Not in this plan

- **A coach that offers a workout from chat.** `lift_chat` returns a reply and
  nothing else; offering a workout needs a structured intent like Run's chat
  has. 2.0.x.
- **Joining an Apple account to an email account** in Settings (O2). 2.0.x.
- **Moving a planned day in the plan itself.** The coach's adapt surface is not
  registered.
- **Run adopting the sales screen or the stronger photograph.** Run's lane; the
  shared pieces and the ADR amendment allow it.
- Everything in [submission-week.md](submission-week.md) and
  [store-setup.md](store-setup.md) that is not design: the `lift.save_workout`
  migration, the merge back to `main`, the store dashboards, SMTP, the listing.
