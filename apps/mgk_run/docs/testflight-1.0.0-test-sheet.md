# MGKFitness: Run 1.0.0 — TestFlight test sheet

Read this on the phone with the build in your hand, and **dictate what you find
into a note** rather than ticking as you go — see *How to capture what you find*
below. A failed row with two words of context is worth more than a green sheet.

**Only what you actually saw counts.** An untested row is useful; an assumed
pass is not. Silence on a row is read as untested, never as passed.

The boxes below get filled in afterwards, from your note, in the commit that
records the build — not by you, one-handed, outdoors.

**Rewritten 2026-09-04 for build 13.** Build 12's filled-in sheet is not kept
beside this one. Every finding it produced is either fixed and named in the row
that re-tests it, or recorded in [app-store-1.0.0.md](app-store-1.0.0.md); the
sheet itself is at commit `02a9214` if the raw record is ever wanted. Two sheets
carrying state about the same release is how one of them goes stale, and this
document is consumed rather than maintained.

## What build 13 is

Build 13 (`75a89df`) is **eighteen commits of fixes on top of build 12**, and
almost none of it has been on a phone. Build 12's sitting on 2026-09-04 answered
A to F and then ran out of afternoon.

**Two facts shape this sheet.** First, **sections G and H have never run** — the
purchase chain and the listing screenshots are the two things a submission
actually needs, and neither has been proven once. Second, everything marked
**FIXED** is a change made in response to build 12 and verified only in a test
suite; a suite cannot tell you whether a three-second count feels long, or
whether a refusal reads as an insult.

What build 12 did establish, and what is therefore not re-litigated: recording
works (C1–C10 all passed), the permission strings read correctly, the app opens
on a working tracker with no account, and account creation, decline and deletion
behave. Those rows are still here — a build that broke them would be worse than
one that fixed nothing — but they are the fast part.

---

## How to capture what you find

**Do not tick this file on the phone.** Editing an 86-row markdown table
one-handed outdoors is how findings get lost, and the ones most easily lost are
the ones only a phone can produce.

**Dictate into one note.** Open Notes, start a single note called
`run 1.0.0 build 13`, and hold the **microphone key on the keyboard** — not
Voice Memos, which gives an audio file that has to be transcribed before anybody
can read it.

**Or use the scribe.** From `apps/mgk_run`:

```
python tool/field_sheet.py docs/testflight-1.0.0-test-sheet.md <out.md> 13
```

That produces this sheet with a brief telling a Claude Desktop session how to
walk you through it by voice and hand back a structured block. The copy is
stamped with the commit it came from, because the last session worked from a
stale one and it bounded what got covered.

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
| A3 | Whether the 23 Aug run is in the log **after signing in**. Build 12 could not answer this because restore was broken |
| B4 | Whether Health re-prompted for Steps on an install that already had the app. **Still nobody knows** |
| B6 | Whether iOS ever asked for Health **write** access. Decides whether an `Info.plist` key gets dropped |
| C12 | How many haptics per kilometre, and whether signal loss buzzed once or repeatedly. **Never once felt** |
| C14 | Whether three seconds feels right — long enough to pocket a phone, short enough not to resent |
| D12 | Whether the refitted week reads as *thought about* or as *rearranged* |
| E10 | What the erase confirmation says, word for word |
| E11 | Whether Settings now reads as organised, and whether backup consent is easy to find |
| F2 | **The battery percentage used, and over how long.** Still the first measurement nobody has taken |
| G6, G8 | What the two prices read, and in which currency |
| G18 | The row: `product`, `status`, `platform`, and whether **`event_ms`** is filled |
| G's failure | **The ignore-reason string from the `revenuecat` function log** — not a description of the screen |
| Elevation | Whether "not recorded" reads as **deliberate or broken** on a real finished run |
| H6 | Whether there is enough history for a year-of-running shot at all |

---

## The running order

**One change since build 12, and it is that afternoon's lesson.** Section G
moved *before* the outdoor run. It is indoors, it takes twenty minutes, it is
the most submission-critical thing here, and it has never run — so it must not
sit behind the weather again.

1. **A, B** — indoors, fresh install, no account. **Do B first and do it once**:
   permissions are a first-launch question and the dialog does not come back
   without a reinstall.
2. **E1 to E4** — still no account.
3. **E9, then E5 to E7** — the offline check first, then create the account for
   real. **Leave E8 and E10 alone.**
4. **Grant the entitlement row** (SQL below), then **D1 to D8**, **D12**, **D13**.
5. **Delete the row**, then **D9 to D11**, **D14**, **D15** and **C11**.
6. **G — the purchase, indoors, row still deleted.** Sign into the app *first*,
   sign out of the sandbox account *first*, read the function log rather than
   the screen. **Do not skip this to get outside.**
7. **Outside: C, with C12 to C15.** Then **F**. C10 wants airplane mode, so give
   it its own short run.
8. **H** — the screenshots. They need the data the earlier steps made.
9. **E10, then E8, last and only last.** Deleting the account destroys what
   steps 4 to 8 stood on.

**Five ways to waste the afternoon:**

- **E8 early.** It takes the entitlement row, the purchase and the coach with
  it. The most expensive misstep on this sheet.
- **Buying before signing into the app.** Build 13 now *refuses* this rather
  than taking the money (G3a) — but you cannot test a purchase you were not
  allowed to make.
- **Leaving a granted row in place through G**, so a purchase and a grant are
  indistinguishable.
- **Signing into iCloud with the sandbox Apple ID** rather than letting iOS ask
  at the moment of purchase.
- **Answering B's dialogs before you are paying attention.**

---

## Before you start

**1. `REVENUECAT_ACCEPT_SANDBOX=true` is set in Supabase.** Section G does not
work without it. **Unset it before you submit** — left on in production, anybody
with a tester account grants themselves a coach.

**2. Grant yourself a row**, once, against production with your own email:

```sql
insert into core.entitlements (user_id, app, product, status, platform)
select id, 'run', 'paid', 'active', 'apple'
from auth.users where email = 'you@example.com'
on conflict (user_id, app) do update
  set product = 'paid', status = 'active';
```

Only `status = 'active'` grants anything. **Delete it again** before section G:

```sql
delete from core.entitlements
where app = 'run'
  and user_id = (select id from auth.users where email = 'you@example.com');
```

**3. Which account, and this matters for A3.** `run.runs` holds 11 runs
including **two on 23 August** under `mattkay02@gmail.com` — one character from
the other address on this project. Sign into that one, and say which you used.

**4. Go outside.** C, F and half of H need real GPS and roughly forty minutes of
moving.

---

## Known gaps — do not report these

- **Climb and high point read "not recorded".** No barometric source
  ([ADR-0024](decisions/0024-elevation-is-barometric-or-absent.md)). *Whether it
  reads as deliberate is a finding, not a gap — and it is now also two empty
  tiles in listing shot H3.*
- **Heart rate, cadence and active energy are absent by design.**
- **No in-run audio** ([ADR-0006](decisions/0006-in-run-audio-deferred.md)).
- **The app is iPhone-only.** It runs on an iPad in compatibility mode.
- **Week 1 of a plan can contain days already past.** A plan built on a Friday
  anchors to that Monday. Known, and an open decision rather than a bug: race
  day is fixed, this half changes what every plan looks like.

---

## A. Install and first launch

| # | Step | Expected | ✓ |
|---|---|---|---|
| A1 | Install from TestFlight | Home screen icon reads **Run** | ☐ |
| A2 | Launch with no account | A working app, not a sign-in wall | ☐ |
| A3 | **Sign in, then look for the 23 Aug run** | **FIXED.** Build 12 restored nothing: `_justSignedUp` was set by tapping *Get started* and never cleared, short-circuiting restore for the session. The history should arrive | ☐ |
| A4 | Watch what it says when it arrives | **NEW.** A message naming what was restored. Silence used to be indistinguishable from failure | ☐ |
| A5 | Portrait-first, nothing clipped | Notch and home indicator respected | ☐ |

## B. Permissions

| # | Step | Expected | ✓ |
|---|---|---|---|
| B1 | Location prompt | *"Record your run's route, distance, and pace."* No "Runio" | ☐ |
| B2 | Health prompt | Names **step count** as well as workouts | ☐ |
| B3 | Settings › Run › Location | Listed as **Run**; the in-app copy matches | ☐ |
| B4 | **On an install that already had the app**, does Health re-prompt for Steps? | Still unknown. Answer it either way | ☐ |
| B5 | Deny location, then read the banner | Names an **iOS** path | ☐ |
| B6 | Is Health *write* access ever requested? | It should not be. If iOS asks, that is Guideline 5.1.1 and a key gets dropped | ☐ |

## C. Recording, and the new way into it

| # | Step | Expected | ✓ |
|---|---|---|---|
| C13 | Tap **Record a run** | **NEW.** A start screen, not a running clock. Today's session named, and the map here **is pannable** | ☐ |
| C14 | Tap **Start** | **NEW.** A three-second count, then recording begins. Say how it feels | ☐ |
| C15 | Start the count, then tap **Stop** | **NEW.** Back to Start; nothing recorded | ☐ |
| C1 | Start a run, wait for a fix | Acquiring resolves; the route draws | ☐ |
| C2 | Run 2 km+ | Distance and pace track sanely | ☐ |
| C3 | Watch a kilometre split land | A sane time | ☐ |
| C4 | Take a manual lap | Recorded; splits undisturbed | ☐ |
| C5 | Pause, wait, resume | Clock stops and restarts; no distance jump | ☐ |
| C6 | **Lock the phone 10+ minutes while running** | Distance keeps climbing | ☐ |
| C7 | Raise and lower the stats panel | Two detents, no clipping, **and the drag still wins** — the in-run map takes no gestures on purpose | ☐ |
| C8 | Finish the run | Summary with route, splits and the stats grid | ☐ |
| C9 | Open the same run from the log | The same numbers | ☐ |
| C10 | Airplane mode, record a short run, finish | Records and saves with no network | ☐ |
| C11 | On a finished run, the locked stat card | Reads *"See what a coach adds"* and opens the gate sheet | ☐ |
| C12 | **Count the haptics across the whole run** | One per kilometre, **not** one per fix; one on signal loss, not one a second. **Never felt** | ☐ |

## D. The coach and the plan

D1–D8, D12, D13 need the entitlement row. D9–D11, D14, D15 need it **deleted**.

| # | Step | Expected | ✓ |
|---|---|---|---|
| D1 | Ask for a plan | Cost notice, then the intake | ☐ |
| D2 | Work through the intake | **FIXED.** **One question per turn**, not four in a bubble. It still reflects back what it heard | ☐ |
| D3 | Read the generated plan | Whole numbers — never `4.1 km` | ☐ |
| D4 | **Check the final week** | **FIXED.** Race day carries **no training session**. It is the event | ☐ |
| D5 | Check the current week's days | Known gap: week 1 may hold days already past. Note it; do not report it as new | ☐ |
| D6 | Ask the coach about your last run | Read against the session you were set | ☐ |
| D7 | Ask about a run over a week ago | Gets the **date right** | ☐ |
| D8 | Force-quit, reopen, ask something | A new session; no verbatim replay | ☐ |
| D12 | **Run on a rest day, then ask the coach to adjust the week** | **NEW.** It should notice the run happened, count it, and refit what is left — not reshuffle. **A session you already ran must not move** | ☐ |
| D13 | Ask it to move a session still ahead | Still allowed. Only the past is pinned | ☐ |
| D9 | **Delete the row, relaunch** | The coach locks again | ☐ |
| D10 | With the row deleted, ask for a plan | Refused as a door with a price, never *"the coach hit a problem"* | ☐ |
| D11 | With the row deleted, tap the coach mark | The **gate sheet**; its button reaches the paywall | ☐ |
| D14 | **With the row deleted, try every other way in** | **FIXED.** *Ask about this* on Profile and on a finished run, the missed-session card, adjust-this-week, the Plan tab. **All of them must meet the door**, never a 402 | ☐ |
| D15 | With the row deleted, look at Home's coach mark | **FIXED.** The mark is there — it is the door — but **no observation**. That reading is the paid product | ☐ |

## E. Account, backup, deletion

| # | Step | Expected | ✓ |
|---|---|---|---|
| E1 | Record two runs with no account | The backup prompt appears once, after the second | ☐ |
| E2 | Decline it | Nothing stored; not asked again | ☐ |
| E3 | Turn on backup with no account | Raises sign-up | ☐ |
| E4 | Abandon that sign-up | Nothing written | ☐ |
| E9 | **In airplane mode, try to create an account** | **FIXED.** Fails within ~20s naming the connection. It used to hang silently, then appear to work | ☐ |
| E5 | Create an account online, turn backup on | **FIXED.** Existing runs upload **then**, not on the next launch. Check `run.runs` | ☐ |
| E6 | Sign in on a second install | The history comes back | ☐ |
| E7 | Settings with no account | States the position; no Sign out or Delete account | ☐ |
| E11 | **Read Settings as a whole** | **CHANGED.** Four bands. Say whether it reads as organised, and whether backup consent is findable | ☐ |
| E10 | **Turn backup off** | **FIXED.** It says what was deleted, **and the rows actually go** — check `run.runs`. It previously deleted nothing while the privacy policy promised it did | ☐ |
| E8 | Delete account | Confirmation first, then the data goes | ☐ |

## F. The long one

| # | Step | Expected | ✓ |
|---|---|---|---|
| F1 | Distance against a known route | Within a few percent | ☐ |
| F2 | Battery drain over the run | **Note the figure.** Still never measured | ☐ |
| F3 | Any stutter in the map or the panel | Note where | ☐ |
| F4 | The run in the log next morning | **Still there** | ☐ |

## G. The purchase — the whole chain

**Never run. Not once.** Build 12's sitting stopped before it, and two
independent faults in this chain were found by reading code rather than by
testing it.

Runbook detail and every ignore-reason is in [store-setup.md](store-setup.md)
§8. **Read the function log before changing anything.**

| # | Step | Expected | ✓ |
|---|---|---|---|
| G1 | A sandbox Apple ID exists | Do **not** sign into iCloud with it | ☐ |
| G2 | Sign out of the sandbox account on the device | iOS asks at purchase | ☐ |
| G3 | Sign in to the **app** | The webhook keys the row on the Supabase UUID | ☐ |
| G3a | **Sign out of the app, then try to buy** | **NEW.** It must **refuse before the store**, say *sign in first*, and must not read as a failed payment. Build 12 took the money and granted nothing | ☐ |
| G4 | Delete any entitlement row you granted | Otherwise a purchase and a grant look the same | ☐ |
| G5 | Coach mark ▸ gate ▸ **See the plans** | `PurchaseScreen` opens | ☐ |
| G6 | **Both tiers show a price** | *"Not available to buy yet"* means the offering is not CURRENT — configuration, not the app | ☐ |
| G7 | Premium Coach is the higher tier | Level 1 is the higher | ☐ |
| G8 | The price is in **the storefront's** currency | Nothing compiles a figure in | ☐ |
| G9 | Tap **Terms of Use** | Apple's EULA opens and loads | ☐ |
| G10 | Tap **Privacy policy** | `mgkfitness.mgkcodes.com/run/privacy`, no login | ☐ |
| G11 | The auto-renew disclosure is on screen and legible | Guideline 3.1.2 | ☐ |
| G12 | **Restore purchases** is present | Required | ☐ |
| G13 | Nothing clips at the bottom | 320pt is the narrowest supported | ☐ |
| G14 | Start a purchase, **cancel at the sandbox sheet** | Reported as cancelled, never as a failure | ☐ |
| G15 | Buy the Coach tier | Sandbox sheet, then the polling message | ☐ |
| G16 | RevenueCat ▸ Customer history | Against your **Supabase UUID**, not an `RCAnonymousID:` | ☐ |
| G17 | RevenueCat ▸ Webhooks | A 200 | ☐ |
| G18 | `core.entitlements` | One row: `paid` / `active` / `apple`, **and `event_ms` not null**. That column was missing in production until 2026-09-04, and every real event 502'd on it | ☐ |
| G19 | The app | The coach unlocks. It polls at 0/1/2/3/5s | ☐ |
| G20 | **Without relaunching, sign out and back in** | **FIXED.** The tier re-reads on the auth change. Build 12 needed a full relaunch | ☐ |
| G21 | Move to the Premium tier | No second purchase — one group | ☐ |
| G22 | **Restore purchases** on a fresh install | The coach comes back | ☐ |
| G23 | Cancel from Apple ID settings | The row goes `expired` **when it lapses**, not immediately | ☐ |

**If nothing happens**, the reason is in the `revenuecat` function log and it
names the product id. `unmapped_product` means the secret and App Store Connect
disagree; `unknown_app_user_id` means you bought before signing in; `sandbox`
means the accept flag is unset.

## H. The six listing screenshots

**Never taken.** They cannot come from Windows: the plate harness answers every
network image with a 400, so there are no basemap tiles.

Use the device's own capture. Drop them in `store-assets/captured/` named
`listing-*.png`, then from `apps/mgk_run` run
`python tool/export_store_assets.py --check`.

| # | The screen | Board code | Plate id | ✓ |
|---|---|---|---|---|
| H1 | Home: a plan, and today's session | `H1` | `home-with-plan` | ☐ |
| H2 | A run in progress — **outdoors, map drawn** | `R4`/`R5` | `03-warmed` / `04-deep` | ☐ |
| H3 | A finished run: route, splits, stats | `F1` | `run-complete` | ☐ |
| H4 | A week of the plan, opened | `P2` | `week-detail` | ☐ |
| H5 | The coach answering | `C4` | `coach-answering` | ☐ |
| H6 | A year of running, on the profile | `S4` | `year-grid` | ☐ |

Board codes exist only inside
[the contact sheet](https://claude.ai/code/artifact/9ddfd186-11ad-4260-bde9-ef8b7a5d9190);
the plate ids are the repo's own names. **Shoot from the description** — the
codes are only there to find the reference.

⚠ **H3 will have two of six stat tiles empty.** Elevation gain and max elevation
both read "not recorded" on a real phone, while the plate shows them filled
because its fixture supplies altitude. Look at it and say whether that reads as
deliberate or broken. It is Gate 5's last open decision and cannot be judged
from a plate; if it reads as broken, H3 can be framed on the splits instead.

**The 1024×1024 marketing icon** does not come off the phone —
`store-assets/captured/icon-1024.png`, no alpha, square corners.

---

## What to send back

**The note, and nothing else.** The rows needing a spoken answer are listed once,
above.

What the note needs beyond those:

1. **Which half you tested** — free, paid, or both.
2. **Which account** you signed in as for A3.
3. **How far you got.** Stopping is a fine outcome; a sheet that claims G ran
   when it did not is the failure that made this rewrite necessary.
4. **Anything that felt wrong but still passed.** The only findings this sheet
   has no row for, by definition.

Then paste it in and say it is the build 13 sheet.
