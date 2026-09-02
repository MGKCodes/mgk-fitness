# App Store listing — 1.0.0

The copy that goes in the boxes. [app-store-1.0.0.md](app-store-1.0.0.md)'s
Gate 4 says which boxes exist and what their limits are; this is what goes in
them, so the checklist stays a checklist and the writing lives somewhere it can
be edited as writing.

Written 2026-09-02 against `f5599c3`. **Nothing here has been reviewed by
anybody but its author.** Every character count is verified by
`tool/check_listing.py`, which fails on an overrun — Apple truncates silently in
some fields and rejects in others, and neither is a thing to discover on
submission day.

**Every claim below was checked against the code, not against the product
spec** — [product-spec.md](product-spec.md) still says "Runio", still says
"Pre-alpha (design)", and still promises HealthKit writes the app does not do.
It is a design document that stopped tracking the build.

---

## What the app may not claim

Written first, because a listing is where an aspiration quietly becomes a lie.

- **It does not write to Health.** `health_read_types.dart` requests
  `HealthDataAccess.READ` for `WORKOUT` and `STEPS` and nothing else. No line of
  the description may say runs are saved back to Health, or Apple will test it.
- **It does not record elevation.** The tiles exist and permanently read "not
  recorded" ([ADR-0024](decisions/0024-elevation-is-barometric-or-absent.md)).
  Elevation is not a feature until it is.
- **No heart rate, no cadence, no active energy.** Stopped on purpose in
  [release-1.0.0.md](release-1.0.0.md).
- **No audio cues** — [ADR-0006](decisions/0006-in-run-audio-deferred.md).
- **No Strava, in any direction**
  ([ADR-0002](decisions/0002-no-strava-integration.md)). Do not name it in
  keywords either; a competitor's name in a keyword field is a rejection.
- **No watch app.** Watch runs arrive through Health. "Works with Apple Watch"
  would be read as a companion app and is not true.

---

## App information

| Field | Value | Count |
|---|---|---|
| Name | `MGKFitness: Run` | 15 / 30 |
| Primary category | Health & Fitness | |
| Secondary category | Sports | |
| Copyright | `2026 MGKCodes Ltd` | |
| Primary language | English (U.K.) | |

The home-screen label stays `Run` and that is deliberate: iOS truncates at
roughly twelve characters, so `MGKFitness: Run` and `MGKFitness: Lift` would
both render as `MGKFitness:…` on the same phone. The store carries the platform
name, the phone carries the app name.

## Subtitle — 30 characters

**Settled 2026-09-02: option 1.** The other two are kept because a subtitle is
cheap to change and the reasoning should outlive the choice.

All three lead with tracking, because the free half is most of the app and the
gate copy already makes that promise — a listing that leads with the
subscription and a gate that leads with what is free are two different products.

1. **`Track runs. Get a real plan.`** — 28. **Chosen.** Two sentences, two
   halves, in the order a runner meets them.
2. `Run tracking, and a coach` — 25. Quieter, and says less about the plan.
3. `Your runs, and a plan for them` — 30. Warmest, and at the limit exactly.

## Promotional text — 170 characters

Changeable without review, which makes it the right place for anything that
will move. At launch it should carry the thing the description buries:

> Recording is free forever, with no account and no trial countdown. The coach
> is the part you pay for, and it builds a plan around the running you actually
> do.

158 characters, which leaves room for a launch line later.

## Keywords — 100 characters

Comma-separated, no space after the comma — the spaces count. Nothing here
repeats a word already in the name or subtitle; Apple indexes those separately
and a repeat wastes the field.

```
marathon,5k,10k,half,training,gps,pace,splits,tempo,intervals,race,jogging,tracker,workout
```

90 characters.

## Description — 4000 characters

```
Record a run the moment you open the app. No account, no sign-up, no trial
counting down. Press start and it tracks your route, your splits and your pace,
and keeps them on your phone.

That half is free, and always will be.


WHAT IS FREE

- GPS tracking with a live map, splits and pace
- Keeps recording with the screen locked and the phone in a pocket
- Records without a signal. The run is written to your phone as it happens,
  not to a server
- Treadmill and manual entry, for the runs your phone did not see
- Your whole log: every run, its route, its splits, your records, and your
  year at a glance
- Runs from a watch arrive through Apple Health, so the log is the whole
  picture rather than the part you started here
- Kilometres or miles, your choice, from the first screen


THE COACH

A subscription. It writes your training plan and keeps it honest week to week.

- A conversation, not a form. It asks what you are training for and works the
  shape out from your answers.
- A plan has a shape. A dated race build, an open-ended ramp toward a distance
  you have never run, or a rhythm to hold. Not everything is a sixteen-week
  block, and the app does not pretend otherwise.
- Sessions arrive about a week ahead, so the plan reflects the running you
  actually did rather than the running you intended in January.
- Every run is read against the session it answered: what was asked, and what
  you ran.
- When life gets in the way, say so. The week bends around it, and nothing
  changes until you say yes.
- It is you against you. The coach never ranks you against another runner,
  because there is no other runner in here.


WHAT IT IS NOT

No feed, no followers, no leaderboards, no kudos. It is a training tool, not a
social network, and it never becomes one.


YOUR DATA

Your runs live on your phone. Backing them up is a choice you make rather than
a default, and if you never make it, nothing leaves the device.

The coach is a language model, so what you tell it and the training context
behind it are sent away to be answered. The privacy policy names every company
involved and exactly what each one receives. You can delete everything you have
ever recorded, permanently, from inside the app.


BEFORE YOU START

This is not medical advice. It does not know your medical history and cannot
see how you feel today. Speak to a doctor before you start or change a training
programme, and stop if something hurts.

iPhone only. Recording keeps the GPS running in the background, which uses more
battery than an app that is closed.


SUBSCRIPTION

The coach is an auto-renewing monthly subscription. The price is shown in the
app, in your own currency, before you buy anything.

- Payment is charged to your Apple ID at confirmation of purchase.
- It renews automatically unless auto-renew is switched off at least 24 hours
  before the end of the current period.
- Your account is charged for renewal within 24 hours before the period ends.
- Manage or cancel it in your Apple ID account settings after purchase.

Privacy policy: https://mgkfitness.mgkcodes.com/run/privacy
Terms of use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

**The terms link is Apple's standard EULA, settled 2026-09-02.** Nothing to
write, Apple hosts it, and it satisfies Guideline 3.1.2 today.
[ADR-0005](decisions/0005-license-agpl.md) already establishes why AGPL is
compatible with distributing through the App Store: that was always a
multi-copyright-holder problem, and MGKCodes is the sole holder — which is the
same reason Signal ships under AGPL.

**The privacy policy URL above is provisional.** See
[app-store-1.0.0.md](app-store-1.0.0.md)'s Gate 2: the page is going into the
MGKCodes site, whose existing app-legal routes are `/privacy/liftio` rather than
a subdomain. Settle the route shape before this string goes anywhere near App
Store Connect.

## Subscription products

One group, because the tiers are alternatives and a runner should be able to
move between them without a second purchase.

| | Coach | Premium Coach |
|---|---|---|
| Entitlement | `paid` | `premium` |
| Model tier | `standard` | `sharp` |
| Price | £0.99 / month | £2.99 / month |
| Display name | Coach | Premium Coach |
| Duration | 1 month | 1 month |

**Description** (each needs one, and each needs a review screenshot):

- **Coach** — "A training plan built around your running, and a coach that
  adjusts it every week."
- **Premium Coach** — "The same coach, thinking harder about your week. A
  better model behind every plan and every answer."

Prices are [ADR-0029](decisions/0029-what-a-tier-costs-and-buys.md)'s, and
`supabase/functions/coach/limits.ts` sizes every spend ceiling against them. Let
Apple's matrix set the other storefronts. **No free trial and no introductory
offer** at 1.0.0: a trial on a £1 product costs more in support than it earns.

## Review notes

```
WHAT THIS APP IS
A running tracker with an optional AI coaching subscription.

NO ACCOUNT IS NEEDED TO USE MOST OF IT
The app opens straight onto a working tracker. You can record, review and
delete a run without signing up. An account is asked for at exactly two
moments: when you ask for a training plan, and when you turn on backup.

TO REVIEW THE PAID HALF
Sign in with the demo account below. It has an active subscription entitlement
attached, so the coach and the plan builder are reachable without a purchase.

  Email:    [DEMO EMAIL]
  Password: [DEMO PASSWORD]

Tap the round mark in the bottom-right corner of any tab to open the coach.
The Plan tab builds a training plan from a short conversation.

BACKGROUND LOCATION
Requested so a run keeps recording with the screen locked and the phone in a
pocket, which is how running apps are used. The permission is asked for during
onboarding with that reason on screen, and the app is fully usable if it is
refused: the run records while the app is in the foreground.

HEALTH DATA
The app READS workouts and step count from HealthKit, so runs recorded on a
watch or in another app appear in the training log. It does not write to
HealthKit. Health data is never used for advertising and is never sold.

WHAT LEAVES THE DEVICE, AND WHEN
Runs are stored on the phone. They are only uploaded if the user turns backup
on, which is off by default. Coaching messages and the training context behind
them are sent to an LLM gateway (OpenRouter) to be answered; the configured
model runs with data collection denied. The privacy policy lists every
sub-processor.

SUBSCRIPTION
Two monthly tiers behind one subscription group. Purchases are handled by
RevenueCat; entitlements are written server-side and read by the backend, so
the client never decides what it is entitled to.
```

## Still to produce

- [ ] **Screenshots.** 6.9" set, off a real device on TestFlight — not from the
      plate harness, which draws no basemap tiles. Six shots, chosen off
      [the board](https://claude.ai/code/artifact/9ddfd186-11ad-4260-bde9-ef8b7a5d9190):
      `H1`, `R4` or `R5`, `F1`, `P2`, `C3`, `S4`. The first two are what shows
      in search, so they carry the argument alone.
- [ ] **The 1024×1024 marketing icon** in App Store Connect — no alpha channel,
      no rounded corners.
- [ ] **A review screenshot per subscription product.**
- [ ] **The demo account**, and an `active` row in `core.entitlements` for it.
- [ ] **The two URLs above must resolve** before submission. Neither does yet.
