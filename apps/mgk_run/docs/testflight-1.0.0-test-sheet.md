# MGKFitness: Run 1.0.0 — TestFlight test sheet

Fill this in on the phone, with the build in your hand. Tick what passes, write
a line where it does not, and hand the whole thing back — a failed row with two
words of context is worth more than a green sheet.

**Tick only what you actually saw.** An untested row left blank is useful; an
assumed pass is not. This build is the first one compiled since
`TARGETED_DEVICE_FAMILY` changed, and most of what follows has only ever run on
an Android emulator on Windows.

## Before you start

**1. Grant yourself the coach — this is now mandatory, not a convenience.**
Since [ADR-0030](decisions/0030-the-coach-is-the-paid-half.md) the coach is the
paid half on Run too, so **without a row you get no model access at all**: the
coach mark opens a sheet naming the price instead of a conversation. That is the
correct behaviour and not a bug. The purchase flow does not exist yet
([ADR-0028](decisions/0028-revenuecat-is-the-purchase-path.md) chooses
RevenueCat; none of it is built). Without a row you will test the free half and
conclude the paid half is broken. Run this once against production, with your
own email:

```sql
insert into core.entitlements (user_id, app, product, status, platform)
select id, 'run', 'paid', 'active', 'apple'
from auth.users where email = 'you@example.com'
on conflict (user_id, app) do update
  set product = 'paid', status = 'active';
```

Only `status = 'active'` grants anything, and an unknown `product` falls back to
free rather than to the dear tier — so both fields have to be right. **Delete
the row again** to test the free half:

```sql
delete from core.entitlements
where app = 'run'
  and user_id = (select id from auth.users where email = 'you@example.com');
```

**2. Decide which half you are testing, and say which.** Free and paid are
genuinely different products here and they fail differently. Section D needs the
row; section C must work without it.

**3. Go outside.** Sections E and F need real GPS and roughly forty minutes of
moving. Nothing on a desk tells you anything about a recorder.

## Known gaps — do not report these

Real, known, written down. Reporting them costs you time and tells me nothing:

- **"Upgrade to see this stat" has nothing to tap.** The button is wired only in
  the test suite, so a free runner is told to upgrade with no way to do it. It
  is the first thing the payment work fixes, and it is a submission blocker —
  but it is known.
- **The coach gate has no buy button either**, and deliberately not a fake one:
  RevenueCat is chosen and unbuilt, and a button that cannot take money fails at
  the moment somebody has decided to pay.
- **Climb and high point always read "not recorded".** There is no barometric
  source ([ADR-0024](decisions/0024-elevation-is-barometric-or-absent.md)). The
  tiles are built end to end and correctly report absence rather than guessing
  from GPS altitude. Absent is the right answer today.
- **Heart rate, cadence and active energy are absent by design** — see
  *Deliberately not built* in [release-1.0.0.md](release-1.0.0.md).
- **Steps and high point do not survive a phone change.** `run.runs` has neither
  column, so a restore brings the run back without them.
- **Elevation is in metres even in miles mode.** `mgk_units` has no `Elevation`
  type yet.
- **No in-run audio** ([ADR-0006](decisions/0006-in-run-audio-deferred.md)).
- **The app is iPhone-only.** It runs on an iPad in compatibility mode and will
  look like it.

---

## A. Install and first launch

| # | Step | Expected | ✓ |
|---|---|---|---|
| A1 | Install from TestFlight | Home screen icon reads **Run**, not MGKFitness | ☐ |
| A2 | Launch with no account | Lands on a working app, not a sign-in wall | ☐ |
| A3 | **Does the 23 Aug run appear in the log?** | The last open item in Phase 0. With the log reading Drift it should simply be there | ☐ |
| A4 | Check the app is portrait-first and nothing is clipped | Notch and home indicator both respected | ☐ |

## B. Permissions — the strings, on a device, for the first time

The purpose strings were rewritten in `1fdaf6f` and have never been seen on a
phone.

| # | Step | Expected | ✓ |
|---|---|---|---|
| B1 | Location prompt | Says *"Record your run's route, distance, and pace."* No mention of "Runio" | ☐ |
| B2 | Health prompt | Says *"Read your workouts and step count from Health…"* — **step count must be named** | ☐ |
| B3 | Settings › Run › Location | The app is listed as **Run**, and the copy in-app that sends you here matches | ☐ |
| B4 | **On an install that already had the app**, does Health re-prompt for Steps? | Untested and genuinely unknown — answer it either way | ☐ |
| B5 | Deny location, then look at the banner | Names an **iOS** settings path, not an Android one | ☐ |

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

## D. The coach and the plan — the paid half

Needs the entitlement row from *Before you start*.

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
| D9 | **Delete the entitlement row, relaunch** | The coach locks again and the mark opens the price sheet. Access comes from the server, never a cached flag | ☐ |
| D10 | With the row deleted, ask for a plan | Refused as a door with a price, never as "the coach hit a problem" — and **no free fallback plan is generated** | ☐ |

## E. Account, backup and deletion

| # | Step | Expected | ✓ |
|---|---|---|---|
| E1 | Record two runs with no account | After the second, the backup prompt appears once | ☐ |
| E2 | Decline it | Nothing is stored; you are not asked again | ☐ |
| E3 | Turn on *Back up my data* with no account | Raises sign-up rather than silently storing a yes | ☐ |
| E4 | Abandon that sign-up | Nothing written — you were interrupted, not asked and answered | ☐ |
| E5 | Create an account, turn backup on | Existing runs upload | ☐ |
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

---

## What to send back

1. This sheet, ticked, with a line against anything that failed.
2. Whether you tested free, paid, or both.
3. **The answer to A3** — whether the 23 Aug run came back. It is the last thing
   holding Phase 0 open.
4. **The answer to B4** — whether widening the Health request re-prompted.
   Nobody knows, and it affects every existing install.
5. **The F2 battery figure**, whatever it is. There is nothing to compare it to
   yet, which is exactly why the first number matters.
6. Anything that felt wrong but still passed. Those are the ones worth arguing
   about.
