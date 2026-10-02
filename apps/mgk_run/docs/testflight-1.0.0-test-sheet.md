# MGKFitness: Run 1.0.0 — test sheet, build 29

**Build 29, both stores: TestFlight on the iPhone, Play internal testing on
Android.** The file name is older than Android; the sheet covers both.

**Tests `1.0.0+29`, tagged `run/build-29`.** Both stores were built from
`9204036` on 1 October 2026, read off the Codemagic build records: Android
`6abed24d6ae690405c3a70d8`, the iPhone `6abed6a85aeae4113434d463`
([ADR-0039](decisions/0039-one-commit-two-stores-and-the-pubspec-owns-the-build-number.md)).
A tester holding a different build is testing something else.

Read this on the phone with the build in your hand, and **dictate what you find
into a note** rather than ticking as you go — see *How to capture what you find*
below. A failed row with two words of context is worth more than a green sheet.

**Only what you actually saw counts.** An untested row is useful; an assumed
pass is not. Silence on a row is read as untested, never as passed.

**Rewritten 2026-10-01 for build 27, and carried to builds 28 and 29 the same
day.** Build 28 went to TestFlight only (`7f84f2a`) and was looked at on the
iPhone that evening: four things came back, and they are build 29. Android
never had 28.

Build 27 reached both stores (TestFlight from `b0384be`, Play internal from
`080d760`) and was opened, not sat down with: six changes came out of opening
it, and they are build 28. Build 26's sitting never happened either, so this is
still the one sitting before submission. The earlier sheets are not kept beside
this one: build 12's is at `02a9214`, build 13's at `0930105`, the build 14
sheet, last touched for build 25, at `f46f3f1`, build 26's at `c0375bb` and
build 27's at `9d0a96a`, if the raw record is ever wanted.

## What build 29 is

Everything build 26 had, which no phone has been sat down with either. Plus
build 27's: signing in with Apple and Google, the email form as a second step,
a password reset that finishes on the web, a sign-up that waits for its
confirmation email, Apple's tokens revoked with the account, Esri's map with
its credit, and a map that keeps what it has been shown. Plus six things from
the first look at 27: a launch animation, tabs that slide instead of cutting,
deleting a run, a treadmill run from Home, *Adjust this week* on the Plan tab,
and a race week that is one, with race day on the plan. Plus four from the
look at 28: the coach's line waits for the launch and is held long enough to
read, *Add a treadmill run* is a row on the week tile, the start screen shows
where you are and what today's session asks for, and the map is drawn sharp.
And one more asked for with them: a run's distance, time and pace on the lock
screen while it records.
The list is in [app-store-1.0.0.md](app-store-1.0.0.md).

Rows marked **NEW** were new in 26 and have still never been walked. Rows
marked **NEW in 27**, **NEW in 28** and **NEW in 29** are those builds'.

**Five facts shape this sheet.**

**First, the purchase has never been walked end to end on either platform.**
Section G (iPhone) failed to run on four builds, and Premium on Android (section
P) has never been bought. One purchase has gone through on each store since
(Coach on Android on 11 September, one on TestFlight on 30 September), which
proves the chain exists and not that either section passes.

**Second, the flows new in 26 were only ever seen in widget tests**: the consent
sheet, reporting a reply, the another-account screen, the erase switches, the
billing warning on Delete account, the recovered run. A test cannot tell you
whether the sheet reads as a question or as a wall, or whether "Erase" sounds as
permanent as it is.

**Third, deleting now erases the phone by default.** Do the deletion rows on a
throwaway account, never the one with your real runs.

**Fourth, signing in with Apple and Google has never been on a phone in Run.**
It was built in Lift's lane and the consoles were set up once, for the suite;
Run's half is recorded from that runbook and was not re-checked. Section S is
where it is proved or not.

**Fifth, email confirmation is on.** Every account made with an email address
needs an address you can open, or it exists and cannot sign in.

---

## How to capture what you find

**Do not tick this file on the phone.** Dictate into one note per phone, called
`run build 29 iphone` and `run build 29 android`, holding the **microphone key
on the keyboard** — not Voice Memos, which gives an audio file somebody has to
transcribe.

**Or use the scribe.** From `apps/mgk_run`:

```
python tool/field_sheet.py docs/testflight-1.0.0-test-sheet.md <out.md> 29
```

That produces this sheet with a brief telling a Claude Desktop session how to
walk you through it by voice and hand back a structured block, stamped with the
commit it came from.

**Capture by exception.** Say the row id and what happened only when:

- it **failed**, or
- it passed but **felt wrong**, or
- it is on the *say these out loud* list below, where a tick throws the answer
  away.

Anything you do not mention is read as **untested, not passed** — which is the
safe direction and the reason this works.

### Say these out loud — a tick loses the answer

| Row | Say |
|---|---|
| A3 | Whether the 23 Aug run is in the log **after signing in** |
| A7 | Whether the launch animation reads as the app opening or as a wait |
| A12 | Whether you could read the coach's whole line before it closed |
| C30 | What the lock screen shows during a run, and how far behind the app it is |
| D19 | What the Race day row says, word for word |
| B2 | Exactly what the Health sheet lists |
| C12 | How many haptics per kilometre, and whether signal loss buzzed once or repeatedly |
| C14 | Whether three seconds feels right |
| C17 | Whether the panel stayed put while you panned |
| C21 | The note on the recovered run, word for word |
| D16 | Whether a plan starting next Monday reads as sensible or as a delay |
| I1 | Whether the consent sheet reads as a question or as a wall, and whether **Not now** is as easy to hit as **Agree** |
| R2 | What appears under the reply after sending |
| E10 | What the erase confirmation says, word for word |
| E11 | Whether Settings reads as organised, and whether backup is easy to find |
| E12 | What Profile's backup line says, word for word |
| E13 | The done screen's sentence about the login, word for word |
| F2 | **The battery percentage used, and over how long.** Still never measured |
| G6, P4 | What the two prices read, in which currency, and Premium's line under its price |
| G18, P5 | The row: `product`, `status`, `platform`, `expires_at`, `event_ms` |
| G's or P's failure | **The ignore-reason from the `revenuecat` function log**, not a description of the screen |
| H1, H2 | Which picture is not what the phone shows, and how it differs |
| H3 | **The coach's reply, word for word.** It goes on the listing |
| S3, S6 | What Apple's sheet or page asked for, and where you landed afterwards |
| S4 | Which account Google put you in: your own, with your runs, or an empty one |
| S10 | The confirmation email: who it says it is from, inbox or spam, and what the page says after the link |
| S11 | The same for the reset email, and what the page says once the password is changed |
| S12 | Whether Apple asked you to confirm, and whether Run is gone from your Apple ID's *Sign in with Apple* list afterwards |
| M1 | Whether the map is sharp now, and whether the street names are too small to read |
| M5 | Whether the route is still the loudest thing on the map |
| M6, M7, M8 | What the map showed with no signal: streets, or a plain ground |

---

## Before you start

**1. Nothing on the backend is waiting.** Read off the project on 1 October:
`coach` v31, `revenuecat` v10, `delete-account` v18 (with Apple's token
revocation), migrations through `20260929183008`. If R2, S12 or a purchase
fails, read the function log and say what it says; do not put it down to a
missing deploy.

**1a. The build must have been cut after Codemagic's map settings moved to
Esri.** M2 is the check: no *Powered by Esri* on the map means it was not, and
section M is then testing the wrong provider. Say so and skip M.

**2. `REVENUECAT_ACCEPT_SANDBOX` is `true`, and stays `true`**
([ADR-0037](decisions/0037-the-sandbox-stays-open-in-production.md)). Sections
G and P do not work without it, and App Review needs it too. Nothing to do
unless somebody switched it off.

**3. The accounts, each with one job.**

| Account | Phone | Used for | Never |
|---|---|---|---|
| **Yours** — the one with your real runs | iPhone | A3, E5, E11, E12, I, D, R, G | deleted, or backup switched off |
| **Test 2** — new, no Run row | Android | S9, S10 and S11 while making it, then P (the Play purchase) and the first half of E15 | used on the iPhone |
| **Test 3** — throwaway | Android | E15 onwards: E10, E14, E16, E17, E13, E8 | holding anything you want |
| **Apple, hidden** — *Continue with Apple*, choosing **Hide My Email** | iPhone | S3, S13, S12. A separate account from yours by design, so it holds nothing and is safe to delete | made with *Share My Email*, which signs into your real account |
| **Demo A and B** | neither | App Review only | used here: the reviewer has to meet the consent sheet on them |

**Confirmation is on.** Test 2 and Test 3 need addresses you can open. A
plus-address on your own mailbox works (`you+run2@…`, `you+run3@…`).

`run.runs` holds the 23 August runs under `mattkay02@gmail.com`, one character
from the other address on this project. Sign into that one for A3 and say which
you used.

**4. Grant yourself a row for sections D and R** (not I, which needs no row),
against production, with the right store for the phone (`'apple'` on the
iPhone, `'google'` on Android):

```sql
insert into core.entitlements
  (user_id, app, product, status, platform, expires_at, event_ms)
select id, 'run', 'paid', 'active', 'apple', null, null
from auth.users where email = 'you@example.com'
on conflict (user_id, app) do update
  set product = 'paid', status = 'active', platform = excluded.platform,
      expires_at = null, event_ms = null, updated_at = now();
```

Only `status = 'active'` grants anything, and **not beyond a day past
`expires_at`**. The update clears it because a row left by an earlier purchase
keeps that purchase's expiry, which has long passed, and would read as
**ended** however `active` it says it is. `event_ms` null means the first real
purchase overwrites the grant. Grant **Test 3** the same way, with `'google'`,
before E17, so the deletion screen has a subscription to warn about.

**Delete your own row again** before G:

```sql
delete from core.entitlements
where app = 'run'
  and user_id = (select id from auth.users where email = 'you@example.com');
```

**5. Seed Lift data for E13 and E14** (Test 3):

```sql
-- E13: a Lift workout, so deleting Run has to keep the login.
insert into lift.workouts (id, user_id, name, started_at)
select 'e13-seed', id, 'E13 seed', now()
from auth.users where email = '<TEST_3_EMAIL>';

-- E14: a Lift coach conversation, which Run's backup switch must not touch.
insert into coach.conversations (id, user_id, app)
select 'e14-seed', id, 'lift'
from auth.users where email = '<TEST_3_EMAIL>';
```

**6. Go outside for C, F and V.** They need real GPS and roughly forty minutes of
moving, and V needs the Android phone.

---

## Known gaps — do not report these

- **No elevation, heart rate or calorie tiles on a real run.** No barometric
  source ([ADR-0024](decisions/0024-elevation-is-barometric-or-absent.md)), and
  the recorder never sets heart rate or calories. The grid shows only what the
  run has. Heart rate and calories from Health are specified for 1.0.1 in
  [after-1.0.0.md](after-1.0.0.md).
- **No in-run audio** ([ADR-0006](decisions/0006-in-run-audio-deferred.md)).
- **A place the map has never shown, with no signal, is a plain ground** under
  the route. The phone keeps the tiles it has been shown and loads the ones
  around you when the app opens; it does not download an area
  ([ADR-0043](decisions/0043-the-map-keeps-what-it-has-shown.md)).
- **iPhone only on iOS.** It runs on an iPad in compatibility mode.
- **The lock screen's figures need iOS 16.2 or later**, and Live Activities
  left on for Run. On an older iPhone, or with them off, the run records and
  the lock screen shows nothing.
- **Android shows two notifications while a run records**: the figures, and the
  location service's own "Recording your run". The second is the one Android
  requires.
- **Android with approximate location only** still sits on "Acquiring GPS" and
  records nothing: Android does not tell the app, so C26's warning is iPhone
  only.
- **Manual laps are not kept after Finish.**
- **A runner at 0 km a week cannot build a plan.**
- **Plan dates shift a day if the phone moves west across time zones.** Do not
  test on a plane.
- **Adjusting a week from a week opened in the calendar** (Plan ▸ Calendar ▸
  a week ▸ the adjust button) is not yet covered by the race-day rule. Use
  Plan ▸ Adjust this week, under the week, for D17.
- **A race on a Monday or a Tuesday leaves race week empty** before it: there
  is no day in that week ahead of the day before the race.
- **The time on the Race day row is a prediction from the time trial**, by
  formula. It knows nothing of the course or of the training since.

The five from approximate location on Android to the adjust button are in
[after-1.0.0.md](after-1.0.0.md), each with a date to revisit.

---

## The running order

1. **iPhone, fresh install: A1, A2, A5 to A7, A9 to A12, then B's iPhone rows.** Delete the
   app first. If the phone holds runs that are not backed up, turn backup on
   under the build you have before you delete it; A3 is about getting them
   back. **Do B once and pay attention**: permission dialogs do not come back
   without a reinstall.
2. **Android, fresh install from the internal testing link: A1, A2, A5 to
   A12, then B's Android rows.** Not a sideloaded APK: it cannot buy anything (P2).
3. **E1 to E4, E7 and E7a** on the iPhone, still no account. Then **S1, S2 and
   S7**, which need no account either.
4. **S3, S13 and S12 on the iPhone**, in that order, on the hidden Apple
   account: sign in, back out of a deletion, then delete it. It holds nothing.
5. **E9, then E5, A3 and A4** — the offline check first, then your own account,
   for real, on the iPhone. **S4** here if your own address is a Google one.
   **Leave E8, E13 and E16's erase alone.**
6. **I, with no row and no agreement yet.** The consent sheet has to come
   before any price, so this is the one time the order of a section matters.
7. **Grant your row** (SQL above), then **D19 first, on the plan you already
   have**, then **D1 to D4, D20, D16 to D18, D6 to D8, D12, D13**, and **R**.
8. **Delete the row**, then **D9 to D11, D14, D15** and **C11**.
9. **G on the iPhone** — the purchase, indoors, row still deleted. Sign into
   the app *first*, sign out of the sandbox account *first*, and read the
   function log rather than the screen.
10. **Android: make Test 2 with an email address, which is S9 and S10.** Then
    **S5, S6 and S8**, signing out between them, and **S11** on Test 2.
11. **P on Android**, as Test 2.
12. **M6 on both phones before you leave the house**, then **outside: C** (C21
    to C26 included), **M1 to M5**, **F**, then **V** on Android. **M7 and M8**
    on the way back, in aeroplane mode.
13. **H** — the screenshots, both phones. They need the data the earlier steps
    made.
14. **E11, E12, then E18 to E20** on the iPhone, as yourself, and **C27**.
15. **On Android, as Test 2 then Test 3: E15, E10 with E14, E16, E17, E13, and
    E8 last.** E15 leaves Test 3 on the phone, and everything after it is
    Test 3's.

**Seven ways to waste the afternoon:**

- **Deleting your own account.** Deleting now erases the phone's copy by
  default, so E8 or E13 on your account takes the runs on the phone as well as
  the server's. Test 3 exists for this.
- **Buying before signing into the app.** It is refused now (G3a), so there is
  nothing to test.
- **Leaving a granted row in place through G or P**, so a purchase and a grant
  are indistinguishable.
- **Signing into iCloud with the sandbox Apple ID** rather than letting iOS ask
  at the moment of purchase.
- **Agreeing to the consent sheet on demo account A or B.** The answer is kept
  on the account, and the reviewer would never see the sheet the review notes
  describe.
- **Answering B's dialogs before you are paying attention.**
- **Making a test account on an address you cannot open.** Confirmation is on:
  the account exists and cannot sign in.

---

## A. Install and first launch — both phones

| # | Step | Expected | ✓ |
|---|---|---|---|
| A1 | The home screen | **NEW icon** on both phones — two chevrons on near-black, not the old loop — labelled **Run** | ☐ |
| A2 | Launch with no account | A working app, not a sign-in wall | ☐ |
| A3 | **Sign in, then look for the 23 Aug run** | The history arrives. Say whether that run is in it | ☐ |
| A4 | Watch what it says when it arrives | A message naming what was restored | ☐ |
| A5 | Portrait, nothing clipped | Notch, home indicator and Android gesture bar respected | ☐ |
| A6 | **The nav bar, on all three tabs** | A floating pill. Scroll each tab to its very bottom: **nothing may sit under it** | ☐ |
| A7 | **Force-quit, then open the app** | **NEW in 28.** The two chevrons from the icon draw back to the left, then dash to the right. **RUN** is uncovered behind them and thin lines streak past. It rests as **RUN »** with *MGKFITNESS* under it, then lifts to show the app, already loaded. About two seconds, and smooth: **say if it stutters, and whether it reads as the app opening or as a wait** | ☐ |
| A8 | **Android, phone in light mode: force-quit and open** | **NEW in 28.** Dark from the first instant. **No white flash** before the animation. On Android 12 or later the icon shows first, on the same dark ground | ☐ |
| A9 | **Open it from the background** (not force-quit) | **NEW in 28.** No animation: it only plays on a cold start | ☐ |
| A10 | **Tap between Home, Plan and Profile** | **NEW in 28.** The screen slides a short way and fades into the next; a soft plate slides along the nav bar to the tab you tapped. **Nothing snaps.** Scroll Profile down, leave and come back: it is where you left it | ☐ |
| A11 | **With Reduce Motion on** (iPhone: Accessibility ▸ Motion; Android: Remove animations), force-quit and open, then change tab | **NEW in 28.** No launch animation, and tabs change at once | ☐ |
| A12 | **Force-quit, open, and watch the coach's C above the nav bar** | **NEW in 29.** Nothing happens to it while the launch animation is up. Then the C **opens out into a bar** with a line on it, the line **stays about five seconds**, and the bar **closes back into the C**. **Say whether you could read the whole line** | ☐ |

## B. Permissions — a fresh install on each phone

| # | Step | Expected | ✓ |
|---|---|---|---|
| B1 | iPhone: location prompt | *"Record your run's route, distance, and pace."* Allow Once / **Allow While Using App** / Don't Allow. **No "Always"** — the app never asks for it | ☐ |
| B2 | iPhone: the Health sheet | **NEW.** Asks to read **Steps**, and nothing else: no Workouts, nothing to write | ☐ |
| B3 | iPhone: Settings ▸ Run ▸ Location | Listed as **Run**, set to While Using the App. The app's Settings ▸ Permissions says *On while the app is open* | ☐ |
| B4 | Android: location prompt | While using the app / Only this time / Don't allow, with a precise toggle. **No "Allow all the time"** | ☐ |
| B5 | Android: the intro | **No Health step at all** | ☐ |
| B6 | Deny location, then read the banner | Names **that phone's** settings path | ☐ |

## S. Signing in — NEW in 27

Never on a phone in Run before this build. The console settings behind it are
in [store-setup.md](store-setup.md) §11.

| # | Step | Expected | ✓ |
|---|---|---|---|
| S1 | **Welcome ▸ I already have an account**, on each phone | **NEW in 27.** *Continue with Apple*, *Continue with Google* and *Continue with email*, the same width, with *Choosing Hide My Email with Apple starts a separate account.* under them. **Nothing to scroll for**, and no email field yet | ☐ |
| S2 | Tap **Continue with email** | **NEW in 27.** Email, Password, **Sign in**, *Forgot your password?* and *Other ways to sign in*, all on the screen with the keyboard down. *Other ways to sign in* goes back to the three buttons | ☐ |
| S7 | Tap **Continue with Apple**, then close Apple's sheet. The same with Google | **NEW in 27.** Back on the screen with **no message**. Closing a sheet is not an error | ☐ |
| S3 | **iPhone: Continue with Apple, choosing Hide My Email** | **NEW in 27.** Apple's own sheet, asking for an email address and nothing else. Then the app, signed in, **as a new and empty account**: Settings shows a `privaterelay.appleid.com` address. Say what the sheet asked for | ☐ |
| S13 | **On that account: Delete account, type DELETE, confirm, then close Apple's sheet** | **NEW in 27.** *"Nothing was deleted. An account made with Apple asks Apple to confirm before it goes."* The account is still there | ☐ |
| S12 | **Delete it again and confirm with Apple** | **NEW in 27.** Apple asks to confirm, then the done screen. Afterwards, iPhone Settings ▸ your name ▸ Sign in with Apple **no longer lists Run**. The `delete-account` log line reads `"apple":"revoked"` | ☐ |
| S4 | **iPhone: Continue with Google** | **NEW in 27.** Google's sheet, then the app. If the Google address is your account's own, you are **in your account, with your runs**: one address is one account. Say which you landed in | ☐ |
| S9 | **Android: Create an account ▸ Continue with email, with a 7-character password** | **NEW in 27.** *"Use at least 8 characters."* and nothing is sent. Signing **in** with an older, shorter password still works | ☐ |
| S10 | **Make Test 2 with 8 or more** | **NEW in 27.** *"Check your email to confirm your account."* in grey, **not red**. The email is from **MGKFitness** `<noreply@mgkfitness.mgkcodes.com>`, in the inbox. Sign in **before** following the link: *"Check your email and follow the link, then sign in."*, also grey. Follow the link, then sign in: it works. Say what the page after the link says | ☐ |
| S5 | **Android: sign out, Continue with Google** | **NEW in 27.** Android's own account chooser, then the app, signed in | ☐ |
| S8 | **Sign out, Continue with Google again** | **NEW in 27.** It **asks which account**, and does not walk straight back into the last one | ☐ |
| S6 | **Android: sign out, Continue with Apple** | **NEW in 27.** The **browser** opens on Apple's page, and the app says *"Finish signing in with Apple in your browser."* Sign in there and the browser hands back to **Run, signed in**. Say where you landed | ☐ |
| S11 | **As Test 2, signed out: Continue with email ▸ Forgot your password?** | **NEW in 27.** With no address typed: *"Enter your email first."* With one: *"If that address has an account, a reset link is on its way."* The email's link opens `mgkfitness.mgkcodes.com/reset-password`. Fewer than 8 characters is refused there; a good one says **Your password is changed**. Sign in with it. Open the same link again: *"This link has expired or has already been used."* | ☐ |

**S12's log line** is in the Supabase dashboard ▸ Edge Functions ▸
`delete-account` ▸ Logs, on the line beginning `account deleted`.

## C. Recording

| # | Step | Expected | ✓ |
|---|---|---|---|
| C13 | Tap **Record a run** (or **Start** on a session) | **CHANGED in 29.** A start screen, not a running clock. A **dot where you are**, in the middle of the map, and the map **pans**. Under it: *GPS ready* with *within N m* (or *Finding GPS* for the first seconds), today's session with **pace, about how long, effort** and a line on how it should feel, and **Start** | ☐ |
| C28 | **Walk twenty metres with the start screen open** | **NEW in 29.** The dot moves with you, and the map follows. Pan the map away: a recentre button appears top right, and puts it back | ☐ |
| C29 | **Home ▸ Record a run on a rest day, or with no plan** | **NEW in 29.** The panel says *Free run*, *Run as you like*, and that nothing is counted down. No pace, no session | ☐ |
| C30 | **iPhone: start a run, then lock the phone** | **NEW in 29.** On the lock screen: **RUN**, and under it **distance, time and pace**. The time counts every second; the distance and pace catch up every few seconds as you move. On a phone with a Dynamic Island, the distance and the clock are in it while the app is in the background. **Say what it shows, and how far behind the app it is** | ☐ |
| C31 | **iPhone, still locked: pause from the app, lock again; then resume; then Finish** | **NEW in 29.** Paused: it says **RUN · PAUSED** and the clock stands still. Resumed: it counts again. Finished or discarded: it is **gone** from the lock screen | ☐ |
| C32 | **Android: tap Record a run for the first time** | **NEW in 29.** Android asks whether Run may send notifications, **once**, as the start screen opens. Allow it | ☐ |
| C33 | **Android: start a run, then lock the phone** | **NEW in 29.** A notification with **distance · pace** as its title and a clock counting up. No sound and no buzz when it updates. Paused, it says *Paused at …*. After Finish it is gone | ☐ |
| C14 | Tap **Start** | A three-second count, then recording. Say how it feels | ☐ |
| C15 | Start the count, then tap **Stop** | Back to Start; nothing recorded | ☐ |
| C1 | Start a run, wait for a fix | Acquiring resolves; the route draws | ☐ |
| C2 | Run 2 km+ | Distance and pace track sanely | ☐ |
| C3 | Watch a kilometre split land | A sane time | ☐ |
| C5 | Pause, wait, resume | Clock stops and restarts; no distance jump | ☐ |
| C6 | **Lock the phone 10+ minutes while running**, on each phone | Distance keeps climbing. On iPhone the blue location pill shows; on Android the notification, if notifications are on | ☐ |
| C7 | Raise and lower the stats panel | Detents land, no clipping | ☐ |
| C16 | Drag the panel down | A third resting place: distance and time only, map full screen | ☐ |
| C17 | **Drag the map with one finger** | It pans and a recentre control appears. **The panel must not move** | ☐ |
| C18 | Tap the recentre control | Snaps back to you and the control goes. It must *never* recentre on its own | ☐ |
| C19 | iPhone: pan near the screen edges | The map does not fight iOS's back swipe | ☐ |
| C8 | Finish the run | Summary with route, splits and the stats grid | ☐ |
| C9 | Open the same run from the log | The same numbers | ☐ |
| C20 | Read the stats grid | Time and pace; on iPhone with Health allowed, **Steps and Avg cadence** too. No elevation, heart rate or calories (known) | ☐ |
| C10 | Airplane mode, record a short run, finish | Records and saves with no network | ☐ |
| C11 | Home's last-run card, free runner | Reads *"See what a coach adds"* and opens the gate sheet | ☐ |
| C12 | **Count the haptics across a whole run** | One per kilometre, **not** one per fix; one on signal loss, not one a second | ☐ |
| C21 | **Start a run, record a few minutes, then swipe the app away** (app switcher / recents). Relaunch | **NEW.** The run is in the log, finished at the last fix, with the note *"Recovered automatically — recording stopped when the app closed, before you pressed Finish."* No 0.00 km entry | ☐ |
| C22 | **Android: press Back mid-run** | **NEW.** *"Discard this run?"* with Keep running / Discard. Keep running carries on recording, notification and all. Back must never leave a run recording out of sight | ☐ |
| C23 | **iPhone: edge-swipe back mid-run** | **NEW.** The same dialog; the run does not vanish behind the swipe | ☐ |
| C24 | **Double-tap Finish, fast** | **NEW.** One summary, one run in the log. Finish and Resume show a small spinner while it settles | ☐ |
| C25 | **iPhone: mid-run, set Settings ▸ Run ▸ Location to Never**, come back, pause, set it back to While Using, then tap **Allow location** (it may read **Continue**) | **NEW.** The **same** run carries on. After Finish there is **one** run in the log, with both halves of the distance | ☐ |
| C26 | **iPhone: Settings ▸ Run ▸ Location ▸ Precise Location off**, then start a run | **NEW.** A problem panel saying Run only has approximate location, with *Turn on Precise Location for Run in Settings* and a way to Settings — not a run stuck on "Acquiring GPS" that saves as 0 m. Turn Precise back on afterwards | ☐ |
| C27 | **Home ▸ This week ▸ Add a treadmill run**, the row at the foot of the tile | **CHANGED in 29.** A full-width row with a plus, **not** a button under Start. *Add a run* opens with **Treadmill** already chosen. Fill in distance and time, **Add run**: back on Home, and the run is in the log on Profile as a treadmill run | ☐ |

## M. The map — NEW in 27

The map's tiles are Esri's from this build, and the phone keeps the ones it has
been shown ([ADR-0043](decisions/0043-the-map-keeps-what-it-has-shown.md)).
No test can see any of this: tiles need a network and a screen.

| # | Step | Expected | ✓ |
|---|---|---|---|
| M6 | **Indoors, with a signal and location already allowed: open the app, wait ten seconds on Home, switch to aeroplane mode, then tap Record a run** | **NEW in 27.** The map around you is **already drawn**, streets and names. It was loaded when the app opened | ☐ |
| M2 | The start screen's bottom-right corner | **NEW in 27.** *Powered by Esri*, clear of the home indicator and of **Start**. Tap it: the data sources open above it. Tap again: they close | ☐ |
| M1 | **Outside: read the map on the start screen and mid-run** | **CHANGED in 29.** A dark grey map, **sharp**: street edges are crisp, not smeared. The street names are **small** (half the size they were in 28). **Say whether they are too small to be any use, and whether the map now looks as sharp as the rest of the screen** | ☐ |
| M3 | Mid-run: find the credit, raise and lower the panel, then pan the map | **NEW in 27.** *Powered by Esri* sits **just above the panel** and rides with it. With the recentre control showing it sits **beside** the control, not under it | ☐ |
| M4 | The finished run's map | **NEW in 27.** The credit in its bottom-right corner | ☐ |
| M5 | The map against the route | **NEW in 27.** The route is the loudest thing on it. Say if the map is too bright or too faint | ☐ |
| M7 | **Aeroplane mode, then open the run you just finished from the log** | **NEW in 27.** Its map draws, from the phone's copy | ☐ |
| M8 | **Still in aeroplane mode, pan the map somewhere it has never shown** | **NEW in 27.** A plain dark ground, no broken-image marks, the route still drawn. That is right (known gap) | ☐ |

## D. The coach and the plan

Every row above D9 needs the granted row. D9 and everything below it need the
row **deleted**.

| # | Step | Expected | ✓ |
|---|---|---|---|
| D1 | Ask for a plan (Plan ▸ Build a plan) | The intake opens — consent and disclaimer were settled in I | ☐ |
| D2 | Work through the intake | **One question per turn**, and it reflects back what it heard | ☐ |
| D3 | Read the generated plan | Whole numbers — never `4.1 km` | ☐ |
| D4 | **Check race week** (Plan ▸ Calendar, the last week; tap into it) | **CHANGED in 28.** The day reads **Race day**, with the race, its distance and *about* a time (only if you gave a time trial). The **day before is empty**, there is **no long run**, the runs before it are easy and **each shorter than the last**, and the week's line says *Race week*. In the calendar the day's cell says **Race** | ☐ |
| D19 | **Your own plan, built before this build, with a run on race day** | **NEW in 28.** Open Plan ▸ Calendar ▸ the last week. The run on race day is **gone** and the week is as D4 describes, without rebuilding the plan. **Say what the Race day row says, word for word** | ☐ |
| D20 | **Plan tab, under this week's seven days** | **NEW in 28.** **Adjust this week** is here, and **not on Home**. Tap it: the same reasons as before, and the answer arrives in the conversation | ☐ |
| D16 | Build it on a day that is not Monday | Week 1 starts on the **coming** Monday (ADR-0034). Say whether that reads as sensible or as a delay | ☐ |
| D17 | **In race week, Plan ▸ Adjust this week**, pick a reason, accept | **NEW.** The revised week still leaves race day empty | ☐ |
| D18 | **Build a plan for a race less than six weeks after the coming Monday** | **NEW.** Refused before anything is built: *"A plan needs at least 6 weeks before race day. Pick a later race, or build a plan without one."* | ☐ |
| D6 | Ask the coach about your last run | Read against the session you were set | ☐ |
| D7 | Ask about a run over a week ago | Gets the **date right** | ☐ |
| D8 | Force-quit, reopen, ask something | A new session; no verbatim replay | ☐ |
| D12 | Run on a rest day, then ask the coach to adjust the week | It counts the run and refits what is left. **A session you already ran must not move** | ☐ |
| D13 | Ask it to move a session still ahead | Allowed. Only the past is pinned | ☐ |
| D9 | **Delete the row, relaunch** | The coach locks again | ☐ |
| D10 | With the row deleted, ask for a plan | The gate sheet with a way to the prices, never *"the coach hit a problem"* | ☐ |
| D11 | With the row deleted, tap the coach mark | The **gate sheet**; its button reaches the paywall | ☐ |
| D14 | **With the row deleted, try every other way in** | *Ask about this* on Profile and on a finished run, the missed-session card, Plan ▸ Adjust this week, the Plan tab. **All of them meet the gate**, never an error | ☐ |
| D15 | With the row deleted, look at Home's coach mark | The mark is there, **with no observation**. That reading is the paid product | ☐ |

## I. The coach asks first — NEW

Your account, **no row, and never agreed** on this account. If you agreed on an
earlier build, withdraw first (I4).

| # | Step | Expected | ✓ |
|---|---|---|---|
| I1 | **Tap the coach mark** | **Before any price**: *"Before your coach answers"*. Says the coach is an AI model; names **OpenRouter**; lists what is sent (training profile, plans, recent runs' date, distance, time and pace, messages and a short summary) and what never is (name, email, account ID — *"a message goes as you wrote it"* — and GPS routes); the retention line ends *"a control we apply, not a promise we can make for them"*. **Agree** and **Not now**, neither chosen for you | ☐ |
| I2 | Tap **Not now** | Back where you were. The coach does not open and nothing is sent | ☐ |
| I3 | Tap the mark again, **Agree** | The medical disclaimer (if this phone has not seen it), **then** the gate sheet. Consent, then the price | ☐ |
| I4 | Settings ▸ Privacy & legal ▸ **Coach and AI** | Reads *"You agreed…Tap to withdraw."* Tap ▸ *"Stop the coach sending your training?"* ▸ Withdraw ▸ *"Withdrawn. Your coach will ask before it sends anything."* The row then reads *"Not agreed…"* | ☐ |
| I5 | **With permission withdrawn, try each way in**: the mark, Plan ▸ Build a plan, *Ask about this* on Profile and on a finished run, the missed-session card, Plan ▸ Adjust this week | Every one shows the consent sheet first. **Not now** on each; nothing opens. Agree on the last one | ☐ |
| I6 | **Signed out**, tap the coach mark | An account is asked for first — never the consent sheet or a price without one | ☐ |

## R. Reporting a reply — NEW

Needs the granted row and the `coach.reports` migration.

| # | Step | Expected | ✓ |
|---|---|---|---|
| R1 | **Press and hold one of the coach's replies** | *"Report this reply"*: four reasons — Harmful or unsafe / Wrong or misleading / Offensive / Something else — none chosen, and **Send report** does nothing until one is | ☐ |
| R2 | Choose a reason, type a note, **Send report** | The sheet closes and the reply says *"Reported. Thanks, we'll take a look."* under it | ☐ |
| R3 | Look in `coach.reports` | One row: `app` `run`, the reply, the reason code, your note, your user id | ☐ |
| R4 | Airplane mode, report another reply | *"That didn't send. Check your connection and try again; what you wrote is still here."* The reason and note stay | ☐ |
| R5 | Press and hold **your own** message; then a coach reply in the plan intake | Your own: nothing. The intake's: the same report sheet | ☐ |

```sql
select app, reason, note, left(reply, 60) as reply, created_at
from coach.reports order by created_at desc limit 3;
```

## E. Account, backup, deletion

| # | Step | Expected | ✓ |
|---|---|---|---|
| E1 | Record two runs with no account | The backup prompt appears once, after the second | ☐ |
| E2 | Decline it | Nothing stored; not asked again | ☐ |
| E3 | Turn on backup with no account | Raises the account screen: Apple, Google and *Continue with email*, with what an account is for above them | ☐ |
| E4 | Abandon that sign-up | Nothing written | ☐ |
| E9 | **In airplane mode, try to create an account** (Continue with email) | Fails within about 20 s naming the connection | ☐ |
| E5 | Create or sign into your account online, turn backup on | Existing runs upload **then**. Check `run.runs` | ☐ |
| E7 | **Settings with no account** (Profile ▸ gear) | The card at the top: your name or *Create an account*, and *"Everything is on this phone only. An account backs up your training and lets you ask for a plan."* Behind it, **Create an account** and no Sign out or Delete account | ☐ |
| E7a | Still signed out: Settings ▸ Privacy & legal ▸ Delete account, type DELETE, confirm | The row is listed even with no account. It must refuse without claiming anything was deleted — expect *"Please sign in again, then retry the deletion."* Say what it actually says | ☐ |
| E11 | **Read Settings as a whole**, signed in | **CHANGED.** A profile card (face, name, address, plan), then **Preferences** (Distance), **Your data** (Back up my data, Permissions), **About** (Support, Privacy & legal), the version at the foot. Say whether backup is easy to find | ☐ |
| E12 | **Profile, signed in with backup on** | A line saying where the training is: "Backing up…", a last-backed-up time, or a failure that says the phone still has it | ☐ |
| E18 | **Profile ▸ a run ▸ Edit ▸ the bin, top right**. Then **Keep it** | **NEW in 28.** *"Delete this run?"*, saying it goes from the phone and the backup and cannot be undone. Keep it: nothing changes | ☐ |
| E19 | **Delete it for real**, signed in with backup on. Use a run you do not want | **NEW in 28.** Back on Profile, **not** on the deleted run's screen. It is gone from the log and from the totals. Check `run.runs`: the row is gone. **Force-quit and reopen: it has not come back** | ☐ |
| E20 | **Aeroplane mode, signed in: delete another** | **NEW in 28.** *"Couldn't delete that run. Check your connection and try again."*, as a toast. The run is **still there**. Signed out, the same step simply deletes it | ☐ |
| E15 | **Android: Test 2 signed in with a run on the phone. Sign out (switch off), sign in as Test 3** | **NEW.** *"This phone has another account's training on it"*, with **Erase this phone's training and continue as** Test 3's address, and **Sign out**. Sign out leaves Test 2's run. Sign in as Test 3 again ▸ Erase: the app opens empty, as Test 3 | ☐ |
| E10 | **Test 3: add a run (by hand is fine), turn backup on, then off** | It says what was deleted, **and the rows go** — check `run.runs` for Test 3 | ☐ |
| E14 | In the same switch-off, the `e14-seed` Lift conversation | That row **is still there**: `select id, app from coach.conversations where id = 'e14-seed';` | ☐ |
| E16 | **Sign out** (Settings ▸ the card ▸ Sign out) | **NEW.** *"Sign out?"* with a switch, **Also remove my data from this phone**, **off**. Off: *"Your runs stay on this device…"* and they do. On: the text changes to *"…removed from this phone. Anything you have not backed up is gone for good."* and they go | ☐ |
| E17 | **Test 3, with a granted `google` row: Delete account** (Settings ▸ Privacy & legal ▸ Delete account) | **NEW.** A box headed *About your subscription*: "Deleting your account does not cancel your subscription. Cancel it in Google Play, or it will keep renewing." with **Manage subscription**. **Also erase this phone's copy** is **on**. Typing DELETE arms the button | ☐ |
| E13 | **Carry on: delete Test 3, with the `e13-seed` Lift workout stored** | **Your data is deleted**, then *"…removed from our servers. Your login is still active because Lift is using it — email run@mgkfitness.mgkcodes.com if you want that removed too."* and *"This phone's copy has been erased too."* The Lift row and the login both survive (SQL below). The server answered `other_app_data`, which is the only thing that produces that sentence | ☐ |
| E8 | **Remove the Lift seed, sign in as Test 3 again, delete again** | *"…removed from our servers, along with your login."* The login is gone | ☐ |

```sql
-- E13: the Lift row and the login survive a Run deletion.
select (select count(*) from lift.workouts where id = 'e13-seed') as lift_row,
       (select count(*) from auth.users where email = '<TEST_3_EMAIL>') as login;

-- Before E8: take the Lift seed away, so the next deletion takes the login.
delete from lift.workouts where id = 'e13-seed';
delete from coach.conversations where id = 'e14-seed';
```

**E13, E14 and E15 are the rows no test covers end to end.** They are
Supabase-boundary behaviour, where a unit test asserts against a fake, and each
was wrong once in a way that hurt somebody: two deleted Lift's data, and one
handed one runner's training to another account.

## F. The long one

| # | Step | Expected | ✓ |
|---|---|---|---|
| F1 | Distance against a known route | Within a few percent | ☐ |
| F2 | Battery drain over the run | **Note the figure.** Still never measured | ☐ |
| F3 | Any stutter in the map or the panel | Note where | ☐ |
| F4 | The run in the log next morning | **Still there** | ☐ |

## G. The purchase on the iPhone — the whole chain

**Never completed, on any build.** One TestFlight purchase wrote its row on
30 September; the section has not been walked. Runbook detail and every
ignore-reason is in
[store-setup.md](store-setup.md) §8. **Read the function log before changing
anything.**

| # | Step | Expected | ✓ |
|---|---|---|---|
| G1 | A sandbox Apple ID exists | Do **not** sign into iCloud with it | ☐ |
| G2 | Sign out of the sandbox account on the device | Settings ▸ App Store ▸ Sandbox Account. iOS asks at purchase | ☐ |
| G3a | **Signed out of the app**: Home's last-run card ▸ *See what a coach adds* ▸ See the plans ▸ Subscribe | Refused **before the store**: *"Sign in first, then try again… Nothing has been charged."* with a **Sign in** button under it | ☐ |
| G3b | Tap that **Sign in** and sign in | Back on the paywall, able to buy | ☐ |
| G4 | Your granted row is deleted | Otherwise a purchase and a grant look the same | ☐ |
| G5 | Coach mark ▸ gate ▸ **See the plans** | `PurchaseScreen` opens | ☐ |
| G6 | **Both tiers show a price, and Premium's line** | Premium reads *"A better AI model and a bigger allowance."* If it still says *"A better model…"*, App Store Connect has not been changed (store-setup.md §2). *"Not available to buy yet"* means the offering is not CURRENT | ☐ |
| G7 | Premium Coach is the higher tier | Level 1 is the higher | ☐ |
| G8 | The price is in **the storefront's** currency | Nothing compiles a figure in | ☐ |
| G9 | Tap **Terms of use** | **Our terms**, `mgkfitness.mgkcodes.com/run/terms`, open and load | ☐ |
| G10 | Tap **Privacy policy** | The policy opens in the app | ☐ |
| G11 | The auto-renew disclosure is on screen and names the **Apple ID** | Guideline 3.1.2 | ☐ |
| G12 | **Restore purchases** is present | Required | ☐ |
| G13 | Nothing clips at the bottom | 320 pt is the narrowest supported | ☐ |
| G14 | Start a purchase, **cancel at the sandbox sheet** | Nothing reported as a failure | ☐ |
| G14a | Airplane mode, tap Subscribe | *"No connection — try again when you're online."* | ☐ |
| G15 | Buy the Coach tier | Sandbox sheet, then the polling message | ☐ |
| G16 | RevenueCat ▸ Customer history | Against your **Supabase UUID**, not an `RCAnonymousID:` | ☐ |
| G17 | RevenueCat ▸ Webhooks | A 200 | ☐ |
| G18 | `core.entitlements` | One row: `paid` / `active` / `apple`, **`expires_at` a few minutes ahead** (sandbox months are short), and **`event_ms` filled** | ☐ |
| G19 | The app | The coach unlocks. It polls at 0/1/2/3/5 s | ☐ |
| G19a | Subscribe to Coach again | Apple's own "already subscribed" sheet, or *"This Apple ID already has a subscription. Tap Restore purchases."* Never a second charge | ☐ |
| G20 | **Without relaunching, sign out and back in** | The tier re-reads on the auth change | ☐ |
| G21 | Move to **Premium Coach** | No second purchase (one group), and the row turns **`premium`** | ☐ |
| G22 | **Restore purchases** on a fresh install | The coach comes back: it closes, or *"Restored. The coach can take a minute to unlock."* | ☐ |
| G22a | Signed out, tap **Restore purchases** | *"Sign in first, then restore…"* with a Sign in button | ☐ |
| G24 | Before cancelling: Profile ▸ Settings ▸ the card ▸ Coaching ▸ **Manage subscription** | **NEW.** Apple's subscription page, because the row says `apple` — the store that bills, not the phone's | ☐ |
| G23 | Cancel from Apple ID settings | The row stays `active` until it lapses, then goes `expired`; the app's Account says **Ended** | ☐ |

**If nothing happens**, the reason is in the `revenuecat` function log and it
names the product id. `unmapped_product` means the secret and App Store Connect
disagree; `unknown_app_user_id` means you bought before signing in; `sandbox`
means the accept flag is off.

## P. The purchase on Android — NEW

As **Test 2**, on a phone whose Play account is a licence tester. Runbook in
[play-setup.md](play-setup.md) §9 and §10.

| # | Step | Expected | ✓ |
|---|---|---|---|
| P1 | Play Console ▸ License testing lists this phone's Google account | Purchases are free and a month lasts minutes | ☐ |
| P2 | The app came from the **internal testing link** | A sideloaded APK cannot buy | ☐ |
| P3 | Sign in as Test 2 (no row) ▸ coach mark ▸ Agree ▸ disclaimer ▸ gate ▸ See the plans | The paywall | ☐ |
| P4 | Read the paywall | £0.99 and £2.99 a month; Premium reads *"A better AI model and a bigger allowance."*; the disclosure names the **Google Play account**, not an Apple ID; **Terms of use** opens `/run/terms` | ☐ |
| P5 | **Buy Premium Coach first** | The coach unlocks. `core.entitlements`: `premium` / `active` / `google`, with `expires_at` and `event_ms`. **No row?** Read `unmapped_product: <id>` in the function log, add that id (play-setup.md §10), buy again | ☐ |
| P6 | Reinstall from the link, sign in, **Restore purchases** | The coach comes back | ☐ |
| P7 | Account ▸ Coaching ▸ **Manage subscription** | Play's subscription page for Run | ☐ |
| P8 | **Cancel in Play** | The row stays `active` until the period ends, then `expired` | ☐ |

## V. The foreground-service video — Android, NEW

Play's foreground-service declaration needs this video (play-setup.md §4).

| # | Step | Expected | ✓ |
|---|---|---|---|
| V0 | Allow notifications when Run asks (C32), or Settings ▸ Apps ▸ Run ▸ **Notifications on** | **CHANGED in 29:** the app asks. The notification is what the video shows | ☐ |
| V1 | **Record the screen**: Start a run ▸ lock ▸ wake and show **"Recording your run"** ▸ walk a minute or two ▸ unlock and show the **distance went up** ▸ Finish ▸ the notification **is gone** | One continuous video, uploaded unlisted and linked in the declaration | ☐ |

## H. The listing screenshots

**The pictures are drawn, not captured**, since build 29: the app's own code
draws each screen with the real map, and a frame and the words are added
afterwards ([app-store-listing.md](app-store-listing.md) § Screenshots). So
this section no longer asks for captures. It asks whether each picture is true
to the build in your hand. The pictures are on
[the gallery](https://claude.ai/artifact/KmRop4oC1KrHb2UdHykJbU); open it beside the phone.

| # | Step | Expected | ✓ |
|---|---|---|---|
| H1 | **iPhone:** each of the six pictures against the same screen on the phone | The same layout and the same kinds of figure. The finished run shows time and pace, and steps and cadence if Health was allowed. Nothing is on a picture that the phone does not have | ☐ |
| H2 | **Android:** the same six | The same, and the finished run has **no** steps or cadence | ☐ |
| H3 | Signed in as a subscriber, ask the coach **"What could I run a half marathon in?"** and copy the reply out | A reply in the runner's own units. It replaces the scripted reply in picture 5 | ☐ |

**No app icon to capture.** App Store Connect takes the icon from the build.
`store-assets/captured/icon-1024.png` is the **old** mark; do not upload it.

---

## What to send back

**The two notes, and nothing else.** The rows needing a spoken answer are
listed once, above.

What each note needs beyond those:

1. **Which build** each phone has. TestFlight and Play's app page show the
   build number; the app's own Settings shows only 1.0.0. It must be 29.
2. **Which accounts** you used, and for A3 which address.
3. **How far you got.** Stopping is a fine outcome; a sheet that claims G ran
   when it did not is the failure that made rewrites necessary.
4. **Which backend items were not done yet**, and so which rows they blocked.
5. **Anything that felt wrong but still passed.** The only findings this sheet
   has no row for, by definition.

Then paste them in and say they are the build 29 notes.
