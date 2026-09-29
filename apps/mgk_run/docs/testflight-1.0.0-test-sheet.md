# MGKFitness: Run 1.0.0 — test sheet, build 26

**Build 26, both stores: TestFlight on the iPhone, Play internal testing on
Android.** The file name is older than Android; the sheet covers both.

**Tests `1.0.0+26` built from `<BUILD-26-COMMIT>`.** Fill that in from the
Codemagic build records once 26 is cut (both workflows must name the same
commit), and tag it `run/build-26` there, not on the branch tip
([ADR-0039](decisions/0039-one-commit-two-stores-and-the-pubspec-owns-the-build-number.md)).
A tester holding a different build is testing something else.

Read this on the phone with the build in your hand, and **dictate what you find
into a note** rather than ticking as you go — see *How to capture what you find*
below. A failed row with two words of context is worth more than a green sheet.

**Only what you actually saw counts.** An untested row is useful; an assumed
pass is not. Silence on a row is read as untested, never as passed.

**Rewritten 2026-09-29 for build 26.** This is the one sitting before
submission; testing build 25 was dropped. The earlier sheets are not kept
beside this one: build 12's is at `02a9214`, build 13's at `0930105`, and the
build 14 sheet, last touched for build 25, at `f46f3f1`, if the raw record is
ever wanted.

## What build 26 is

Everything build 25 had, plus three lanes of fixes and the consent the privacy
policy has promised since 2026-09-01. The list of what 26 adds is in
[app-store-1.0.0.md](app-store-1.0.0.md); every item on it has a row here
marked **NEW**.

**Three facts shape this sheet.**

**First, the purchase has never been walked end to end on either platform.**
Section G (iPhone) failed to run on four builds, and Premium on Android (section
P) has never been bought. They are the two things a submission needs that
nothing else can prove.

**Second, the new flows were only ever seen in widget tests**: the consent
sheet, reporting a reply, the another-account screen, the erase switches, the
billing warning on Delete account, the recovered run. A test cannot tell you
whether the sheet reads as a question or as a wall, or whether "Erase" sounds as
permanent as it is.

**Third, deleting now erases the phone by default.** Do the deletion rows on a
throwaway account, never the one with your real runs.

---

## How to capture what you find

**Do not tick this file on the phone.** Dictate into one note per phone, called
`run build 26 iphone` and `run build 26 android`, holding the **microphone key
on the keyboard** — not Voice Memos, which gives an audio file somebody has to
transcribe.

**Or use the scribe.** From `apps/mgk_run`:

```
python tool/field_sheet.py docs/testflight-1.0.0-test-sheet.md <out.md> 26
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
| H | Whether there is enough history for shot 6 (a year of running) |

---

## Before you start

**1. Three backend items change what this sitting can prove.** They are on the
owner list in [app-store-1.0.0.md](app-store-1.0.0.md):

| If this is not done yet | What it does to this sitting |
|---|---|
| The migration creating `coach.reports` | R2 and R3 cannot pass: every report fails to send |
| The migration's `core.user_settings` defaults | The distance unit never reaches the account; it stays on the phone |
| The coach function redeployed from `main` | The server does not enforce the subscription for Run (the app's own gate still shows), Premium's allowance is Coach's, and three Run fixes from 4 September are missing. Note anything odd in D rather than chasing it |

Run the sitting anyway if one is missing, and say which rows it blocked.

**2. `REVENUECAT_ACCEPT_SANDBOX` is `true`, and stays `true`**
([ADR-0037](decisions/0037-the-sandbox-stays-open-in-production.md)). Sections
G and P do not work without it, and App Review needs it too. Nothing to do
unless somebody switched it off.

**3. The accounts, each with one job.**

| Account | Phone | Used for | Never |
|---|---|---|---|
| **Yours** — the one with your real runs | iPhone | A3, E5, E11, E12, I, D, R, G | deleted, or backup switched off |
| **Test 2** — new, no Run row | Android | P (the Play purchase), the first half of E15 | used on the iPhone |
| **Test 3** — throwaway | Android | E15 onwards: E10, E14, E16, E17, E13, E8 | holding anything you want |
| **Demo A and B** | neither | App Review only | used here: the reviewer has to meet the consent sheet on them |

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
- **iPhone only on iOS.** It runs on an iPad in compatibility mode.
- **Android never asks for the notification permission** (Android 13+), so the
  "Recording your run" notification only appears if notifications are on for
  Run in the phone's settings. Recording works either way.
- **Manual laps are not kept after Finish.**
- **A runner at 0 km a week cannot build a plan.**
- **Plan dates shift a day if the phone moves west across time zones.** Do not
  test on a plane.
- **Adjusting a week from inside the Plan tab's week view** is not yet covered
  by the race-day rule. Use Home ▸ Adjust this week for D17.

The last five are in [after-1.0.0.md](after-1.0.0.md), each with a date to
revisit.

---

## The running order

1. **iPhone, fresh install: A1, A2, A5, A6, then B's iPhone rows.** Delete the
   app first. If the phone holds runs that are not backed up, turn backup on
   under build 25 before you delete it; A3 is about getting them back. **Do B
   once and pay attention**: permission dialogs do not come back without a
   reinstall.
2. **Android, fresh install from the internal testing link: A1, A2, A5, A6,
   then B's Android rows.** Not a sideloaded APK: it cannot buy anything (P2).
3. **E1 to E4, E7 and E7a** on the iPhone, still no account.
4. **E9, then E5, A3 and A4** — the offline check first, then your own account,
   for real, on the iPhone. **Leave E8, E13 and E16's erase alone.**
5. **I, with no row and no agreement yet.** The consent sheet has to come
   before any price, so this is the one time the order of a section matters.
6. **Grant your row** (SQL above), then **D1 to D4, D16 to D18, D6 to D8, D12,
   D13**, and **R**.
7. **Delete the row**, then **D9 to D11, D14, D15** and **C11**.
8. **G on the iPhone** — the purchase, indoors, row still deleted. Sign into
   the app *first*, sign out of the sandbox account *first*, and read the
   function log rather than the screen.
9. **P on Android**, as Test 2.
10. **Outside: C** (C21 to C25 included), **F**, then **V** on Android.
11. **H** — the screenshots, both phones. They need the data the earlier steps
    made.
12. **E11 and E12** on the iPhone, as yourself.
13. **On Android, as Test 2 then Test 3: E15, E10 with E14, E16, E17, E13, and
    E8 last.** E15 leaves Test 3 on the phone, and everything after it is
    Test 3's.

**Six ways to waste the afternoon:**

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

## B. Permissions — a fresh install on each phone

| # | Step | Expected | ✓ |
|---|---|---|---|
| B1 | iPhone: location prompt | *"Record your run's route, distance, and pace."* Allow Once / **Allow While Using App** / Don't Allow. **No "Always"** — the app never asks for it | ☐ |
| B2 | iPhone: the Health sheet | **NEW.** Asks to read **Steps**, and nothing else: no Workouts, nothing to write | ☐ |
| B3 | iPhone: Settings ▸ Run ▸ Location | Listed as **Run**, set to While Using the App. The app's Settings ▸ Permissions says *On while the app is open* | ☐ |
| B4 | Android: location prompt | While using the app / Only this time / Don't allow, with a precise toggle. **No "Allow all the time"** | ☐ |
| B5 | Android: the intro | **No Health step at all** | ☐ |
| B6 | Deny location, then read the banner | Names **that phone's** settings path | ☐ |

## C. Recording

| # | Step | Expected | ✓ |
|---|---|---|---|
| C13 | Tap **Record a run** | A start screen, not a running clock. Today's session named, and the map **pans** | ☐ |
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

## D. The coach and the plan

Every row above D9 needs the granted row. D9 and everything below it need the
row **deleted**.

| # | Step | Expected | ✓ |
|---|---|---|---|
| D1 | Ask for a plan (Plan ▸ Build a plan) | The intake opens — consent and disclaimer were settled in I | ☐ |
| D2 | Work through the intake | **One question per turn**, and it reflects back what it heard | ☐ |
| D3 | Read the generated plan | Whole numbers — never `4.1 km` | ☐ |
| D4 | **Check race week** | Race day carries **no training session**. It is the event | ☐ |
| D16 | Build it on a day that is not Monday | Week 1 starts on the **coming** Monday (ADR-0034). Say whether that reads as sensible or as a delay | ☐ |
| D17 | **In race week, Home ▸ Adjust this week**, pick a reason, accept | **NEW.** The revised week still leaves race day empty | ☐ |
| D18 | **Build a plan for a race less than six weeks after the coming Monday** | **NEW.** Refused before anything is built: *"A plan needs at least 6 weeks before race day. Pick a later race, or build a plan without one."* | ☐ |
| D6 | Ask the coach about your last run | Read against the session you were set | ☐ |
| D7 | Ask about a run over a week ago | Gets the **date right** | ☐ |
| D8 | Force-quit, reopen, ask something | A new session; no verbatim replay | ☐ |
| D12 | Run on a rest day, then ask the coach to adjust the week | It counts the run and refits what is left. **A session you already ran must not move** | ☐ |
| D13 | Ask it to move a session still ahead | Allowed. Only the past is pinned | ☐ |
| D9 | **Delete the row, relaunch** | The coach locks again | ☐ |
| D10 | With the row deleted, ask for a plan | The gate sheet with a way to the prices, never *"the coach hit a problem"* | ☐ |
| D11 | With the row deleted, tap the coach mark | The **gate sheet**; its button reaches the paywall | ☐ |
| D14 | **With the row deleted, try every other way in** | *Ask about this* on Profile and on a finished run, the missed-session card, Adjust this week, the Plan tab. **All of them meet the gate**, never an error | ☐ |
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
| I5 | **With permission withdrawn, try each way in**: the mark, Plan ▸ Build a plan, *Ask about this* on Profile and on a finished run, the missed-session card, Home ▸ Adjust this week | Every one shows the consent sheet first. **Not now** on each; nothing opens. Agree on the last one | ☐ |
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
| E3 | Turn on backup with no account | Raises sign-up | ☐ |
| E4 | Abandon that sign-up | Nothing written | ☐ |
| E9 | **In airplane mode, try to create an account** | Fails within about 20 s naming the connection | ☐ |
| E5 | Create or sign into your account online, turn backup on | Existing runs upload **then**. Check `run.runs` | ☐ |
| E7 | **Settings with no account** (Profile ▸ gear) | The card at the top: your name or *Create an account*, and *"Everything is on this phone only. An account backs up your training and lets you ask for a plan."* Behind it, **Create an account** and no Sign out or Delete account | ☐ |
| E7a | Still signed out: Settings ▸ Privacy & legal | **Delete account** is still listed there. Tap it, type DELETE, and say what it tells you: there is no account to delete | ☐ |
| E11 | **Read Settings as a whole**, signed in | **CHANGED.** A profile card (face, name, address, plan), then **Preferences** (Distance), **Your data** (Back up my data, Permissions), **About** (Support, Privacy & legal), the version at the foot. Say whether backup is easy to find | ☐ |
| E12 | **Profile, signed in with backup on** | A line saying where the training is: "Backing up…", a last-backed-up time, or a failure that says the phone still has it | ☐ |
| E15 | **Android: Test 2 signed in with a run on the phone. Sign out (switch off), sign in as Test 3** | **NEW.** *"This phone has another account's training on it"*, with **Erase this phone's training and continue as** Test 3's address, and **Sign out**. Sign out leaves Test 2's run. Sign in as Test 3 again ▸ Erase: the app opens empty, as Test 3 | ☐ |
| E10 | **Test 3: add a run (by hand is fine), turn backup on, then off** | It says what was deleted, **and the rows go** — check `run.runs` for Test 3 | ☐ |
| E14 | In the same switch-off, the `e14-seed` Lift conversation | That row **is still there**: `select id, app from coach.conversations where id = 'e14-seed';` | ☐ |
| E16 | **Sign out** (Settings ▸ the card ▸ Sign out) | **NEW.** *"Sign out?"* with a switch, **Also remove my data from this phone**, **off**. Off: *"Your runs stay on this device…"* and they do. On: the text changes to *"…removed from this phone. Anything you have not backed up is gone for good."* and they go | ☐ |
| E17 | **Test 3, with a granted `google` row: Delete account** (Settings ▸ Privacy & legal ▸ Delete account) | **NEW.** A box headed *About your subscription*: "Deleting your account does not cancel your subscription. Cancel it in Google Play, or it will keep renewing." with **Manage subscription**. **Also erase this phone's copy** is **on**. Typing DELETE arms the button | ☐ |
| E13 | **Carry on: delete Test 3, with the `e13-seed` Lift workout stored** | **Your data is deleted**, then *"…removed from our servers. Your login is still active because Lift is using it — email hello@mgkcodes.com if you want that removed too."* and *"This phone's copy has been erased too."* The Lift row and the login both survive (SQL below). The server answered `other_app_data`, which is the only thing that produces that sentence | ☐ |
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

**Never completed, on any build.** Runbook detail and every ignore-reason is in
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
| G6 | **Both tiers show a price, and Premium's line** | Premium reads *"Three times the coaching each month."* If it still says *"A better model…"*, App Store Connect has not been changed (store-setup.md §2). *"Not available to buy yet"* means the offering is not CURRENT | ☐ |
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
| P4 | Read the paywall | £0.99 and £2.99 a month; Premium reads *"Three times the coaching each month."*; the disclosure names the **Google Play account**, not an Apple ID; **Terms of use** opens `/run/terms` | ☐ |
| P5 | **Buy Premium Coach first** | The coach unlocks. `core.entitlements`: `premium` / `active` / `google`, with `expires_at` and `event_ms`. **No row?** Read `unmapped_product: <id>` in the function log, add that id (play-setup.md §10), buy again | ☐ |
| P6 | Reinstall from the link, sign in, **Restore purchases** | The coach comes back | ☐ |
| P7 | Account ▸ Coaching ▸ **Manage subscription** | Play's subscription page for Run | ☐ |
| P8 | **Cancel in Play** | The row stays `active` until the period ends, then `expired` | ☐ |

## V. The foreground-service video — Android, NEW

Play's foreground-service declaration needs this video (play-setup.md §4).

| # | Step | Expected | ✓ |
|---|---|---|---|
| V0 | Settings ▸ Apps ▸ Run ▸ **Notifications on** | The app never asks for it, and the notification is what the video shows | ☐ |
| V1 | **Record the screen**: Start a run ▸ lock ▸ wake and show **"Recording your run"** ▸ walk a minute or two ▸ unlock and show the **distance went up** ▸ Finish ▸ the notification **is gone** | One continuous video, uploaded unlisted and linked in the declaration | ☐ |

## H. The listing screenshots

**The list is in [app-store-listing.md](app-store-listing.md) § Screenshots**,
and nowhere else; open it on the phone. They cannot come from Windows: the plate
harness draws no basemap tiles.

| # | Step | Expected | ✓ |
|---|---|---|---|
| H1 | **iPhone:** the six shots, on the phone's own capture | 6.9" sizes (1260×2736, 1290×2796 or 1320×2868). Drop them in `store-assets/captured/` as `listing-*.png`, then `python tool/export_store_assets.py --check` from `apps/mgk_run` | ☐ |
| H2 | **Android:** the same six | **Long side at most twice the short side** — 1080×1920 is safe. An iPhone capture is refused by Play. Method in [play-listing.md](play-listing.md) § Graphics | ☐ |

**No app icon to capture.** App Store Connect takes the icon from the build.
`store-assets/captured/icon-1024.png` is the **old** mark; do not upload it.

---

## What to send back

**The two notes, and nothing else.** The rows needing a spoken answer are
listed once, above.

What each note needs beyond those:

1. **Which build** each phone has. TestFlight and Play's app page show the
   build number; the app's own Settings shows only 1.0.0. It must be 26.
2. **Which accounts** you used, and for A3 which address.
3. **How far you got.** Stopping is a fine outcome; a sheet that claims G ran
   when it did not is the failure that made rewrites necessary.
4. **Which backend items were not done yet**, and so which rows they blocked.
5. **Anything that felt wrong but still passed.** The only findings this sheet
   has no row for, by definition.

Then paste them in and say they are the build 26 notes.
