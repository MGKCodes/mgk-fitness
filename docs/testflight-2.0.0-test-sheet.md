# MGKFitness: Lift 2.0.0 — TestFlight test sheet

Fill this in on the phone, with the build in your hand. Tick what passes, write
a line where it does not, and hand the whole thing back — a failed row with two
words of context is worth more than a green sheet.

**Tick only what you actually saw.** An untested row left blank is useful; an
assumed pass is not, and this build is the first time most of this has run
anywhere other than a simulator.

## Before you start

**1. Grant yourself the coach.** The plan and the coach sit behind a payment
gate, and payments do not exist yet — Phase 3 of
[release-2.0.0.md](release-2.0.0.md) is entirely unticked. Without a row you
will test the free half of the app and conclude the paid half is broken. Run
this once against production, with your own email:

```sql
insert into core.entitlements (user_id, app, product, status, platform)
select id, 'lift', 'paid', 'active', 'manual'
from auth.users where email = 'you@example.com'
on conflict (user_id, app) do update
  set product = 'paid', status = 'active';
```

Only `status = 'active'` grants anything, and an unknown `product` falls back to
the free tier rather than the dear one — so both fields have to be right.

**2. Know which install you are.** Two paths through this build, and they fail
differently:

- **Upgrade** — a device with Liftio 1.4.0 (the Expo app) already on it. This is
  the risky path and the one that matters, because the store will deliver 2.0.0
  to these people as an update.
- **Fresh** — a device that has never had Liftio.

Test the upgrade path if you have a device for it, and say which you did.

## Known gaps — do not report these

Real, known, and already written down. Reporting them costs you time and tells
me nothing:

- **A finished session does not feed back into the plan.** Per-slot results are
  not recorded yet, so a plan will not notice you got stronger. The plan screen
  is right; the loop behind it is unfinished.
- **A stalled main lift says nothing at all.** It is deliberate that no swap is
  offered — swapping a main lift hides the problem rather than fixing it — but
  it should say *something*, and currently does not.
- **Progress photos do not sync.** They are local to the device.
- **No Terms or Privacy links anywhere in the app.**
- **Sets and reps come from the coach; weights come from your log.** A movement
  you have never done shows advice instead of a number. That is the design, not
  a missing feature.

---

## A. Install and first run

| # | Step | Expected | ✓ |
|---|---|---|---|
| A1 | Install from TestFlight and open it | Opens without a crash | ☐ |
| A2 | *(Upgrade only)* Open on a device that had 1.4.0 | Opens, and does not behave like a fresh install | ☐ |
| A3 | *(Upgrade only)* Look for your old training history | **Unverified — this is the big one.** Whether 2.0.0 restores a 1.4.0 lifter's history on sign-in has never been proven either way. Write down exactly what you see. | ☐ |
| A4 | Check the name under the home-screen icon | Reads `Lift` — not `Mgk Lift`, and not the full `MGKFitness: Lift`, which iOS would truncate | ☐ |
| A5 | Force-quit and reopen | Returns to where you were | ☐ |

## B. Account

| # | Step | Expected | ✓ |
|---|---|---|---|
| B1 | Sign up with a new email | Account created; no confirmation email needed — confirmation is currently switched off | ☐ |
| B2 | Sign out, then sign back in | History is still there | ☐ |
| B3 | Sign in with a wrong password | A readable error, not a raw code | ☐ |
| B4 | Kill the app while signed in, reopen | Still signed in | ☐ |

## C. Track — the free half

Works without an entitlement. It is also what existing Liftio users already
paid for, so it has to be right.

| # | Step | Expected | ✓ |
|---|---|---|---|
| C1 | Start an empty session | Session opens, clock runs | ☐ |
| C2 | Add an exercise by search | Finds it — 266 movements are in the catalogue | ☐ |
| C3 | Log a set, weight and reps | Saves; the tick marks it done | ☐ |
| C4 | Add a set, then remove one | Set numbers stay sensible | ☐ |
| C5 | Leave the session running, lock the phone, come back | Clock is still right, nothing lost | ☐ |
| C6 | Let the elapsed clock pass an hour | Reads `1:02:14` and **does not clip** — a real bug, fixed by shrinking the number rather than truncating it | ☐ |
| C7 | Finish the session | Lands in history with the right volume | ☐ |
| C8 | Start another and discard it instead | Nothing is written | ☐ |
| C9 | Switch kg to lb in Settings | Every weight converts; nothing still shows a raw kg figure | ☐ |

## D. The plan — what this build is for

The standing plan replaced the twelve-week block model. There is **no end
date**: the plan does not expire, the week is derived from the weekday, and
movements rotate rather than the plan finishing.

| # | Step | Expected | ✓ |
|---|---|---|---|
| D1 | Open Plan without an entitlement | The payment gate, not an error | ☐ |
| D2 | With the entitlement, open Plan | The intake starts | ☐ |
| D3 | Walk the intake | One question at a time, wheels and premade answers, one progress bar across the whole thing | ☐ |
| D4 | Answer days, equipment, injuries, goal, age, height, weight | The wheels feel like iOS wheels — detented, with haptics | ☐ |
| D5 | Enter height and weight in imperial | Accepts ft/in and lb, and converts sanely | ☐ |
| D6 | Finish the intake | A plan is generated — **the first real `lift_plan` call against production** | ☐ |
| D7 | Read the plan | Has a name, and a sentence or two on *why this shape for you*, in the coach's words | ☐ |
| D8 | Count the training days | Matches the days you said you could train | ☐ |
| D9 | Tap into a day | Opens that day's movements — you should not be reading every exercise on one screen | ☐ |
| D10 | Find a movement you have never logged | Tells you to pick a weight you could do the top reps with comfortably — **no invented kilograms** | ☐ |
| D11 | Start today's workout from the plan | Session opens pre-filled with that day's movements, sets and reps | ☐ |
| D12 | Check nothing is pre-ticked | Every set is unlogged. The app must never log a session you did not do | ☐ |
| D13 | Regenerate the plan | Gives a different plan, and the old one does not linger | ☐ |
| D14 | Open the plan on a rest day | Says it is a rest day rather than inventing a session | ☐ |

## E. The coach

| # | Step | Expected | ✓ |
|---|---|---|---|
| E1 | Find the floating "C" mark | On Track, Plan and Profile; does not cover anything you need | ☐ |
| E2 | Drag it up | Slides up, glass styling, corners matching the bubbles | ☐ |
| E3 | Ask it a real question | **A real answer from production.** Never yet proven end to end | ☐ |
| E4 | Ask something the research covers — sets per week, how often to train a muscle | Answers in line with the 9 knowledge documents now in the database | ☐ |
| E5 | Mid-session, ask to swap a movement | Offers alternatives that actually exist in the catalogue | ☐ |
| E6 | Accept a swap | That movement changes; the rest of the session is untouched | ☐ |
| E7 | Ask about a **main** lift that has stalled | Should not offer a swap. *(Saying nothing at all is the known gap.)* | ☐ |
| E8 | Send several messages quickly | The rate limit explains itself in plain words, not an error code | ☐ |
| E9 | Sign out and look for the mark | Gone — the coach is not offered to a signed-out user | ☐ |

## F. Profile and photos

| # | Step | Expected | ✓ |
|---|---|---|---|
| F1 | Open Profile | Stats match what you actually logged | ☐ |
| F2 | Check Volume and Time on the narrowest phone you have | Both fit; neither is cut off | ☐ |
| F3 | Take a progress photo | The camera permission asks with a readable reason | ☐ |
| F4 | Open a photo series | Renders — this screen has previously hung on a spinner | ☐ |
| F5 | Check "last session" on Track | Reads `2 weeks ago` without clipping | ☐ |

## G. Sync, offline, deletion

| # | Step | Expected | ✓ |
|---|---|---|---|
| G1 | Aeroplane mode, log a session | Works — the tracker is local first | ☐ |
| G2 | Back online | Syncs without being asked twice | ☐ |
| G3 | Sign in on a second device | The same history arrives | ☐ |
| G4 | Delete your account | Everything goes: sessions, plan, plan slots, coach memory | ☐ |
| G5 | Sign in again afterwards | Treated as a new account | ☐ |

## H. Cross-app

| # | Step | Expected | ✓ |
|---|---|---|---|
| H1 | With MGKFitness: Run on the same account, compare the profile | Age, height and weight match — one person, two apps | ☐ |
| H2 | Change your weight here, then open MGKFitness: Run | It follows across | ☐ |

---

## What to send back

1. This sheet, ticked, with a line against anything that failed.
2. Which install path you tested — upgrade or fresh.
3. **The answer to A3** — whether a 1.4.0 lifter keeps their history. That one
   decides whether 2.0.0 can ship to the existing listing at all.
4. Anything that felt wrong but still passed. Those are the ones worth arguing
   about.
