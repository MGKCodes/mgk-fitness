# MGKFitness: Run 1.0.0 — TestFlight test sheet

Read this on the phone with the build in your hand, and **dictate what you find
into a note** rather than ticking as you go — see *How to capture what you find*
below. A failed row with two words of context is worth more than a green sheet.

**Only what you actually saw counts.** An untested row is useful; an assumed
pass is not. Silence on a row is read as untested, never as passed.

The boxes below get filled in afterwards, from your note, in the commit that
records the build — not by you, one-handed, outdoors.

**Rewritten 2026-09-03 for build 12.** The previous version was written before
the payment arc existed, and its *known gaps* list told you to ignore three
surfaces this build ships: the paywall, the gate's buy button, and the upgrade
card. It also carried two limitations that were fixed on 1 Sep. A sheet that
tells you to skip what you came to test is worse than no sheet, which is why
this is a rewrite rather than an edit.

## What build 12 is

Build 12 (2026-09-02) is the first build carrying the RevenueCat SDK,
`PurchaseScreen`, the wired `onUpgrade`, and the gate sheet's real surface.
**Nothing from 1 Sep onwards has been on a phone, the payment arc included** —
so sections G and H are a first look, not a re-check.

One row is **not** in build 12: E9, the Terms of Use link in Settings, was
written after the build was cut. Skip it.

---

## How to capture what you find

**Do not tick this file on the phone.** Editing a markdown table one-handed
outdoors is how findings get lost, and the ones most easily lost are the ones
only a phone can produce.

**Dictate into one note.** Open Notes, start a single note called
`run 1.0.0 build 12`, and hold the **microphone key on the keyboard** — not
Voice Memos, which gives you an audio file that has to be transcribed before
anybody can read it. Dictation gives you text immediately, editable, and it
pastes straight into a Claude Code session at the end.

**Capture by exception.** There are **74 rows** below (A4, B6, C12, D11, E9, F4,
G22, H6). Dictated as "pass" one at a time that is unreadable, and nobody checks
an unreadable list. Say the row id and what happened only when:

- it **failed**, or
- it passed but **felt wrong**, or
- it is on the *say these out loud* list below, where a tick throws the answer
  away.

Anything you do not mention is read as **untested, not passed** — which is the
safe direction and the reason this works. Say "A through C all clean" if they
were, and that is enough.

### Say these out loud — a tick loses the answer

Fourteen rows produce a *value* rather than a pass, and two judgements have no
row at all. These are the reason the afternoon is worth an afternoon:

| Row | Say |
|---|---|
| A3 | Whether the 23 Aug run is in the log. Yes or no, and if no, whether anything from that day is |
| B1, B2, B3 | The wording you actually saw, roughly. B2 must name **step count** |
| B4 | Whether Health re-prompted for Steps on an install that already had the app. **Nobody knows this** |
| B6 | Whether iOS ever asked for Health **write** access. Decides whether an `Info.plist` key gets dropped |
| C12 | How many haptics per kilometre, and whether signal loss buzzed once or repeatedly |
| F1 | The distance, against whatever you compared it to |
| F2 | **The battery percentage used, and over how long.** First measurement ever taken |
| F3 | Where it stuttered, if it did |
| G6, G8 | What the two prices read, and in which currency |
| G18 | The actual row: `product`, `status`, `platform` |
| G's failure | **The ignore-reason string from the `revenuecat` function log** — not a description of the screen. That screen is calm and correct for five different causes |
| Elevation | Whether "not recorded" reads as **deliberate or broken** on a real finished run. Gate 5's last open decision, and it cannot be judged from a plate |
| H6 | Whether there is enough history for a year-of-running shot at all |

### Where the note goes

Paste it into a Claude Code session in this repo and say it is the build 12
sheet. **The findings belong in this file, not beside it** — a second document
carrying the same state is how one of them goes wrong. This file gets filled in
and committed from your note; the note is scaffolding and can be deleted.

If it is long, drop it at
`apps/mgk_run/docs/.findings-build-12.txt` instead and say so — the dot prefix
keeps it out of the docs listing, and it gets deleted in the same commit that
fills in the sheet.

---

## The running order

**The sections are not in the order you do them.** The account has to be created
partway through and deleted at the very end, and the entitlement row has to move
twice. Followed section by section, this sheet has you deleting the account
before you buy anything with it.

1. **A, B** — indoors, fresh install, no account. **Do B first and do it once**:
   permissions are a first-launch question, and once answered you cannot get the
   dialog back without reinstalling.
2. **E1 to E4** — still no account. E1 needs two runs on the clock, so take two
   short ones round the block; they do not have to be the real C run.
3. **E5, E6, E7 — create the account.** This is the one path where consent
   causes a real upload, and everything after it needs the account to exist.
   **Leave E8 alone.**
4. **Grant the entitlement row** (SQL below), then **D1 to D8** — the coach and
   the plan on a granted row. A coach broken behind a grant is a coach problem;
   discovering that mid-purchase wastes the purchase.
5. **Delete the row**, then **D9, D10, D11** and **C11** — the gate, the
   refusal, and the locked card. These mean nothing with an entitlement in
   place.
6. **Go outside: C, with C12 alongside it.** Two kilometres minimum, a lock, a
   pause, a lap. Then **F**, forty minutes with the screen off — or fold C into
   the start of F if the weather is against you. **C10 wants airplane mode**, so
   do it as its own short run rather than mid-F.
7. **G, indoors, row still deleted.** Sign into the app *first*, sign out of the
   sandbox account *first*, read the function log rather than the screen.
8. **H** — the screenshots. Everything here needs data the earlier steps made:
   H1 and H4 the plan from step 4, H5 the coach unlocked by step 7, H3 a
   finished run, H6 whatever history exists.
9. **E8 last, and only last.** Deleting the account destroys what steps 4 to 8
   were standing on. It is the final act of the afternoon.

**Five ways to waste the afternoon**, each recoverable only by starting over:

- **E8 early.** Deleting the account takes the entitlement row, the purchase and
  the coach with it. It is the single most expensive misstep on this sheet, and
  reading the sections in order is what causes it.
- **Buying before signing into the app** — the webhook refuses an
  `RCAnonymousID:` and writes nothing (`unknown_app_user_id`).
- **Leaving a granted row in place through G**, so a purchase and a grant are
  indistinguishable.
- **Signing into iCloud with the sandbox Apple ID** rather than letting iOS ask
  for it at the moment of purchase.
- **Answering B's dialogs before you are paying attention.** There is no second
  showing without a reinstall, and B1 to B3 are about the wording.

---

## Before you start

**1. Decide which half you are testing, and say which.** Free and paid are
genuinely different products and they fail differently. Section C must work
with no account and no entitlement. Section D needs one. Section G *creates*
one by buying it.

**2. There are now two ways to hold the coach, and they prove different
things.**

- **Grant a row by hand.** Instant. Tests the gate and the coach, and nothing
  about payment.
- **Buy it in sandbox** — section G. Tests the whole chain: StoreKit,
  RevenueCat, the webhook, the row, and the app noticing.

**Do section D by hand first.** A coach that is broken behind a granted row is
a coach problem; discovering that mid-purchase wastes the purchase and muddles
which layer failed.

Grant yourself a row, once, against production with your own email:

```sql
insert into core.entitlements (user_id, app, product, status, platform)
select id, 'run', 'paid', 'active', 'apple'
from auth.users where email = 'you@example.com'
on conflict (user_id, app) do update
  set product = 'paid', status = 'active';
```

Only `status = 'active'` grants anything, and an unknown `product` falls back
to free rather than to the dear tier — so both fields have to be right.
**Delete the row again** to test the free half, and before section G:

```sql
delete from core.entitlements
where app = 'run'
  and user_id = (select id from auth.users where email = 'you@example.com');
```

**3. `REVENUECAT_ACCEPT_SANDBOX=true` is currently set in Supabase.** Section G
does not work without it — a sandbox purchase is a real event from a fake
payment, and the webhook otherwise ignores it with reason `sandbox`.
**Unset it before you submit.** Left on in production, anybody with a tester
account grants themselves a coach.

**4. Go outside.** Sections C, F and half of H need real GPS and roughly forty
minutes of moving. Nothing on a desk tells you anything about a recorder, and
the in-run screenshot is worthless without a drawn map.

---

## Known gaps — do not report these

Real, known, written down. Reporting them costs you time and tells me nothing:

- **Climb and high point always read "not recorded".** There is no barometric
  source ([ADR-0024](decisions/0024-elevation-is-barometric-or-absent.md)). The
  tiles are built end to end and correctly report absence rather than guessing
  from GPS altitude. Absent is the right answer today. *(Whether it should stay
  that way for 1.0.0 is the last open question on the release — if it reads as
  broken rather than deliberate on a real phone, say so. That is a finding, not
  a gap.)*
- **Heart rate, cadence and active energy are absent by design** — see
  *Deliberately not built* in [release-1.0.0.md](release-1.0.0.md).
- **No in-run audio** ([ADR-0006](decisions/0006-in-run-audio-deferred.md)).
- **The app is iPhone-only.** It runs on an iPad in compatibility mode and will
  look like it.

Four entries were removed from this list on 2026-09-03 because they had been
fixed and the sheet had not noticed: the upgrade card having nothing to tap,
the gate having no buy button, steps and high point not surviving a phone
change (both columns are mirrored now), and elevation reading metres in miles
mode (`Elevation` lives in `mgk_units` and converts at display).

---

## A. Install and first launch

| # | Step | Expected | ✓ |
|---|---|---|---|
| A1 | Install from TestFlight | Home screen icon reads **Run**, not MGKFitness | ☐ |
| A2 | Launch with no account | Lands on a working app, not a sign-in wall | ☐ |
| A3 | **Does the 23 Aug run appear in the log?** | The last open item in Phase 0. With the log reading Drift it should simply be there. If it is not, it never finalized — a new bug, not the one already fixed | ☐ |
| A4 | Check the app is portrait-first and nothing is clipped | Notch and home indicator both respected | ☐ |

## B. Permissions — the strings, on a device, for the first time

The purpose strings were rewritten in `1fdaf6f` and have never been seen on a
phone.

| # | Step | Expected | ✓ |
|---|---|---|---|
| B1 | Location prompt | Says *"Record your run's route, distance, and pace."* No mention of "Runio" | ☐ |
| B2 | Health prompt | Says *"Read your workouts and step count from Health…"* — **step count must be named** | ☐ |
| B3 | Settings › Run › Location | The app is listed as **Run**, and the in-app copy that sends you here matches what you find | ☐ |
| B4 | **On an install that already had the app**, does Health re-prompt for Steps? | Untested and genuinely unknown — answer it either way | ☐ |
| B5 | Deny location, then look at the banner | Names an **iOS** settings path, not an Android one | ☐ |
| B6 | Is Health *write* access ever requested? | It should not be. `Info.plist` still carries a write purpose string for a write the binary never performs — if iOS shows it, that is Guideline 5.1.1 and the key gets dropped before submission | ☐ |

## C. Recording — the free half

Must work with no account and no entitlement.

| # | Step | Expected | ✓ |
|---|---|---|---|
| C1 | Start a run, wait for a fix | Acquiring state resolves; route begins drawing | ☐ |
| C2 | Run 2 km+ | Distance and pace track sanely against a known route | ☐ |
| C3 | Watch a kilometre split land | Split appears with a sane time | ☐ |
| C4 | Take a manual lap | Lap recorded, does not disturb the splits | ☐ |
| C5 | Pause, wait, resume | Clock stops and restarts; distance does not jump | ☐ |
| C6 | **Lock the phone for 10+ minutes while running** | Distance keeps climbing. Confirmed working before — confirm it again on this build | ☐ |
| C7 | Raise and lower the stats panel | Two detents, no clipping at either | ☐ |
| C8 | Finish the run | Summary screen appears with route, splits and the stats grid | ☐ |
| C9 | Open the same run from the log | Same numbers as the summary showed | ☐ |
| C10 | Airplane mode, record a short run, finish | Records and saves with no network at all | ☐ |
| C11 | On the finished run, find the locked stat card | Reads *"See what a coach adds"* and **opens the gate sheet when tapped**. It shipped for a month telling people to upgrade with nothing to tap | ☐ |
| C12 | **Count the haptics across the whole run** | One per kilometre — **not one per GPS fix** — and one when the signal drops, not one a second. Nothing else fires unbidden. The tests assert which haptic fired and how many; **nothing has ever been felt**, which is the half a widget test cannot reach | ☐ |

## D. The coach and the plan — the paid half

Needs the entitlement row from *Before you start*. Do this before section G.

| # | Step | Expected | ✓ |
|---|---|---|---|
| D1 | Ask for a plan | Cost notice, then the intake conversation | ☐ |
| D2 | Complete the intake | It reflects back what it heard before building | ☐ |
| D3 | Read the generated plan | Whole numbers for prescribed distances — never `4.1 km` | ☐ |
| D4 | Check the plan's last week | Ends on race day, not an arbitrary Sunday | ☐ |
| D5 | Ask the coach about your last run | Reads it against the session you were set | ☐ |
| D6 | Ask about a run from over a week ago | Gets the **date right** — it should not place an old run as yesterday | ☐ |
| D7 | Force-quit, reopen, ask something | A new session; it does not replay the old conversation verbatim | ☐ |
| D8 | Open previous chats | Old sessions readable | ☐ |
| D9 | **Delete the entitlement row, relaunch** | The coach locks again. Access comes from the server, never a cached flag | ☐ |
| D10 | With the row deleted, ask for a plan | Refused as a door with a price, never as *"the coach hit a problem"* — and **no free fallback plan is generated** | ☐ |
| D11 | With the row deleted, tap the coach mark | The **gate sheet**, and its button reaches the paywall. Both destinations are new in this build | ☐ |

## E. Account, backup and deletion

| # | Step | Expected | ✓ |
|---|---|---|---|
| E1 | Record two runs with no account | After the second, the backup prompt appears once | ☐ |
| E2 | Decline it | Nothing is stored; you are not asked again | ☐ |
| E3 | Turn on *Back up my data* with no account | Raises sign-up rather than silently storing a yes | ☐ |
| E4 | Abandon that sign-up | Nothing written — you were interrupted, not asked and answered | ☐ |
| E5 | Create an account, turn backup on | Existing runs upload. **Never run outside fakes** — this is the one path where consent causes a real upload | ☐ |
| E6 | Turn backup off | Says what it deleted; the phone keeps its copy | ☐ |
| E7 | Settings with no account | States the position; **no Sign out or Delete account rows** | ☐ |
| E8 | Delete account | Confirmation first, then the data actually goes | ☐ |
| E9 | Settings ▸ Privacy & legal ▸ **Terms of use** | **NOT IN BUILD 12 — skip unless you are on a later build.** The row was written on 2026-09-03, after build 12 was cut. On build 12 the Terms of Use are reachable only from the paywall (G9). When it does ship: opens Apple's standard EULA in a browser, and actually loads | ☐ |

## F. The long one

One run of 40+ minutes, ideally with the screen off for most of it.

| # | Step | Expected | ✓ |
|---|---|---|---|
| F1 | Distance against a second device or a known route | Within a few percent | ☐ |
| F2 | Battery drain over the run | Note the figure — no target yet, this is the first measurement | ☐ |
| F3 | Any point where the map or panel stuttered | Note where | ☐ |
| F4 | The run in the log the next morning | **Still there.** This is the failure that started release-1.0.0.md | ☐ |

## G. The purchase — the whole chain

**New in build 12, and the last thing on the release that can fail quietly.**
Nothing below has run outside a unit test, and the paywall has only ever
rendered against `FakePurchases`.

Runbook detail, including every webhook ignore-reason and its cause, is in
[store-setup.md](store-setup.md) §8. **Read the function log before changing
anything** — the webhook never guesses, and it names the reason.

### Before you buy

| # | Step | Expected | ✓ |
|---|---|---|---|
| G1 | A sandbox Apple ID exists — ASC ▸ Users and Access ▸ Sandbox ▸ Testers | Do **not** sign into iCloud with it | ☐ |
| G2 | Sign out of the sandbox account on the device — Settings ▸ App Store ▸ Sandbox Account | iOS asks for it at the moment of purchase | ☐ |
| G3 | Sign in to the **app**, so there is a Supabase user | The webhook keys the row on the Supabase UUID and refuses an `RCAnonymousID:` | ☐ |
| G4 | Delete any entitlement row you granted yourself | Otherwise you cannot tell a purchase from a grant | ☐ |

### The paywall

| # | Step | Expected | ✓ |
|---|---|---|---|
| G5 | Coach mark ▸ gate sheet ▸ **See the plans** | `PurchaseScreen` opens | ☐ |
| G6 | **Both tiers show a price**, from the store | If it reads *"Not available to buy yet"* the offering is not CURRENT — stop, that is configuration, not the app | ☐ |
| G7 | Premium Coach reads as the higher tier | Ranked level 1, and level 1 is the higher | ☐ |
| G8 | The price is in **the storefront's** currency | Nothing compiles a figure into the binary; the test asserts the ADR-0029 pounds appear nowhere on screen | ☐ |
| G9 | Tap **Terms of Use** | Apple's standard EULA opens, and actually loads | ☐ |
| G10 | Tap **Privacy policy** | `mgkfitness.mgkcodes.com/run/privacy` opens, with no login | ☐ |
| G11 | The auto-renew disclosure is on screen and legible | One of four Guideline 3.1.2 requirements; the others are G6, G9/G10 and G12 | ☐ |
| G12 | **Restore purchases** is present | Required, and the only place the SDK's own view of ownership is read | ☐ |
| G13 | Nothing clips at the bottom | The legal links overflowed a 430pt phone by 29px before a test caught it; 320pt is the narrowest supported | ☐ |

### Buying

| # | Step | Expected | ✓ |
|---|---|---|---|
| G14 | Start a purchase, then **cancel at the sandbox sheet** | Reported as cancelled, **never as a failure** | ☐ |
| G15 | Buy the Coach tier | Sandbox sheet, then the app's polling message | ☐ |
| G16 | RevenueCat ▸ Customer history | The purchase, against your **Supabase UUID** — not an `RCAnonymousID:` | ☐ |
| G17 | RevenueCat ▸ Webhooks | A 200 | ☐ |
| G18 | `core.entitlements` | One row: `product` `paid`, `status` `active`, `platform` `apple` | ☐ |
| G19 | The app | The coach unlocks. It polls at 0/1/2/3/5s; if the row is late it says the payment went through and the unlock is coming — **that is the correct message, not an error** | ☐ |
| G20 | Move to the Premium tier | No second purchase — one group, and the tiers are alternatives | ☐ |
| G21 | **Restore purchases** on a fresh install | The coach comes back | ☐ |
| G22 | Cancel from Apple ID settings | The row goes `expired` **when it lapses**, not immediately. `CANCELLATION` means auto-renew is off and you keep what you paid for | ☐ |

**If nothing happens**, the reason is in the `revenuecat` function log and it
names the product id. `unmapped_product` means `REVENUECAT_PRODUCTS` and App
Store Connect disagree; `unknown_app_user_id` means you bought before signing
in; `sandbox` means the accept flag is not set.

## H. The six listing screenshots

Same device, same sitting. **These cannot be taken from Windows**: the plate
harness answers every network image with a 400, so there are no basemap tiles,
and the map is half of what makes the in-run shot worth showing.

Use the device's own capture (volume-up + side button) — a real screenshot is
already the right pixel size with no alpha channel. Drop them in
`store-assets/captured/` named `listing-*.png`, then from `apps/mgk_run` run
`python tool/export_store_assets.py --check`.

**Two naming systems, and only one of them is in this repository.** The board
codes (`H1`, `R4`, `C4`) exist **only inside the published contact sheet** —
`grep` for them across `test/plates/` returns nothing. The repo's own names are
the semantic plate ids in `test/plates/board.state.json`. Both are below, read
off the board itself on 2026-09-03 rather than guessed.

| # | The screen | Board code | Plate id in the repo | ✓ |
|---|---|---|---|---|
| H1 | Home: a plan, and today's session | `H1` | `home-with-plan` | ☐ |
| H2 | A run in progress — **outdoors, map drawn** | `R4` / `R5` | `03-warmed` / `04-deep` | ☐ |
| H3 | A finished run: route, splits, stats | `F1` | `run-complete` | ☐ |
| H4 | A week of the plan, opened | `P2` | `week-detail` | ☐ |
| H5 | The coach answering — needs the entitlement | `C4` | `coach-answering` | ☐ |
| H6 | A year of running, on the profile | `S4` | `year-grid` | ☐ |

Two of these were wrong when this table was first written from inference, and
both are worth knowing because the release plan still carries the old pair:

- **`P2` is `week-detail`, not `plan-week`.** `plan-week` is `P1`, "this week";
  `P2` is "a week opened", which is the shot wanted.
- **The coach answering is `C4`, not `C3`.** On the board `C3` is *the
  conversation* (`coach-conversation`) and `C4` is *answering*
  (`coach-answering`). All three copies of the shot list said `C3` — naming one
  plate and describing the other — and all three were corrected on 2026-09-03.
  **Shoot `C4`**: the coach replying to a suggestion chip is the picture that
  argues for a coach, where `C3` is the conversation merely opened.

**Shoot from the description, not the code.** The middle column is the shot; the
other two are only there to find the reference.

**H1 and H2 are what shows in search**, so they carry the argument alone. Shoot
them last, after sections C–G have put real data in the app: H1 and H4 need a
generated plan, H5 needs the coach unlocked, H3 needs a finished run.

⚠ **H3 will look worse on the phone than the plate does, and this is the first
time anybody has been able to see that.** The `run-complete` plate shows a
six-tile grid with **Elevation gain 167 m** and **Max elevation 111 m** filled
in, because its fixture supplies altitude. On a real device both read *"not
recorded"* — there is no barometric source (ADR-0024). So the shot you actually
take has **two of its six tiles empty**, a third of the grid, in a picture going
on the App Store.

**Look at it before you decide it is fine**, and say which it reads as. This is
the same judgement the *say these out loud* list asks for, arriving with a cost
attached: it is no longer only "does absence read as deliberate", it is "does a
third of the stat grid read as deliberate in a store screenshot". If the answer
is no, H3 can be shot from the splits instead, and Gate 5's elevation decision
stops being cosmetic.

**H6 is the one to think about.** A fresh install has no year of running, and a
profile showing an empty year is a worse shot than five good ones. If the data
is not there, say so and we pick a sixth from what is — between three and ten
screenshots are allowed, and six mediocre beats five strong plus one hollow.

**The 1024×1024 marketing icon** is separate and does not come off the phone —
`store-assets/captured/icon-1024.png`, no alpha, square corners.

---

## What to send back

**The note, and nothing else.** The fourteen rows that need a spoken answer are
listed once, in *Say these out loud* above; they are not repeated here, because
two lists of the same fourteen rows is how one of them loses an entry.

What the note needs beyond those:

1. **Which half you tested** — free, paid, or both. They are different products
   and they fail differently.
2. **Which build**, if it is not 12.
3. **How far you got.** Stopping at F is a fine outcome; a sheet that claims G
   ran when the weather ended the afternoon is not.
4. **Anything that felt wrong but still passed.** Those are the ones worth
   arguing about, and they are the only findings this sheet has no row for —
   by definition, since a row would have made them a pass or a fail.

Then paste it in and say it is the build 12 sheet. The boxes get filled in, the
findings get written against the rows they belong to, and the note gets deleted
in the same commit.
