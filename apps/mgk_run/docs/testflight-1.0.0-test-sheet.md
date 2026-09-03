# MGKFitness: Run 1.0.0 — TestFlight test sheet

Fill this in on the phone, with the build in your hand. Tick what passes, write
a line where it does not, and hand the whole thing back — a failed row with two
words of context is worth more than a green sheet.

**Tick only what you actually saw.** An untested row left blank is useful; an
assumed pass is not.

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

| # | Plate | The screen | ✓ |
|---|---|---|---|
| H1 | `H1` | Home: a plan, and today's session | ☐ |
| H2 | `R4`/`R5` | A run in progress — **outdoors, map drawn** | ☐ |
| H3 | `F1` | A finished run: route, splits, stats | ☐ |
| H4 | `P2` | A week of the plan, opened | ☐ |
| H5 | `C3` | The coach answering — needs the entitlement | ☐ |
| H6 | `S4` | A year of running, on the profile | ☐ |

**H1 and H2 are what shows in search**, so they carry the argument alone. Shoot
them last, after sections C–G have put real data in the app: H1 and H4 need a
generated plan, H5 needs the coach unlocked, H3 needs a finished run.

**H6 is the one to think about.** A fresh install has no year of running, and a
profile showing an empty year is a worse shot than five good ones. If the data
is not there, say so and we pick a sixth from what is — between three and ten
screenshots are allowed, and six mediocre beats five strong plus one hollow.

**The 1024×1024 marketing icon** is separate and does not come off the phone —
`store-assets/captured/icon-1024.png`, no alpha, square corners.

---

## What to send back

1. This sheet, ticked, with a line against anything that failed.
2. Whether you tested free, paid, or both.
3. **The answer to A3** — whether the 23 Aug run came back. It is the last
   thing holding Phase 0 open.
4. **The answer to B4** — whether widening the Health request re-prompted.
   Nobody knows, and it affects every existing install.
5. **The answer to B6** — whether iOS ever asked for Health *write* access.
   It decides whether an `Info.plist` key gets dropped before submission.
6. **The F2 battery figure**, whatever it is. There is nothing to compare it to
   yet, which is exactly why the first number matters.
7. **Where section G broke, if it did** — and the ignore-reason from the
   function log rather than a description of the screen. That screen is calm
   and correct for several different causes.
8. **Whether "not recorded" reads as deliberate or broken** on a real finished
   run. That is Gate 5's last open decision and it cannot be judged from a
   plate.
9. Anything that felt wrong but still passed. Those are the ones worth arguing
   about.
