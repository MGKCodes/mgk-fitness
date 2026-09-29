# App Store listing — 1.0.0

The copy that goes in the boxes. [app-store-1.0.0.md](app-store-1.0.0.md)'s
Gate 4 says which boxes exist and what their limits are; this is what goes in
them, so the checklist stays a checklist and the writing lives somewhere it can
be edited as writing. The Google Play copy is in
[play-listing.md](play-listing.md), checked by the same script.

Written 2026-09-02 against `f5599c3`. **Updated 2026-09-29 for build 26**: the
description stopped promising watch runs from Apple Health (the app reads step
count only), the terms link is our own terms (ADR-0040), Premium's description
says what Premium actually buys (ADR-0038), the Play health disclaimer is in
here too, and the review notes are final apart from the demo credentials.

**Nothing here has been reviewed by anybody but its author.** Every character
count is verified by `tool/check_listing.py`, which fails on an overrun — Apple
truncates silently in some fields and rejects in others, and neither is a thing
to discover on submission day.

**Every claim below was checked against the code, not against the product
spec** — [product-spec.md](history/product-spec.md) still says "Runio", still says
"Pre-alpha (design)", and still promises HealthKit writes the app does not do.
It is a design document that stopped tracking the build.

---

## What the app may not claim

Written first, because a listing is where an aspiration quietly becomes a lie.

- **It does not write to Health.** `health_read_types.dart` requests
  `HealthDataAccess.READ` for `STEPS` and nothing else. No line of the
  description may say runs are saved back to Health, or Apple will test it.
- **It does not import workouts.** `WORKOUT` came off the read list on
  2026-09-29 because nothing ever imported one. A run recorded on a watch does
  not appear in the log, so the listing may not say it does.
- **It does not record elevation.** The tiles exist and never appear on a real
  run, because there is no barometric source
  ([ADR-0024](decisions/0024-elevation-is-barometric-or-absent.md)).
  Elevation is not a feature until it is.
- **No heart rate, no active energy.** Stopped on purpose in
  [release-1.0.0.md](history/release-1.0.0.md). Cadence does appear on iPhone,
  derived from Health steps, but the description does not lean on it.
- **No audio cues** — [ADR-0006](decisions/0006-in-run-audio-deferred.md).
- **No Strava, in any direction**
  ([ADR-0002](decisions/0002-no-strava-integration.md)). Do not name it in
  keywords either; a competitor's name in a keyword field is a rejection.
- **No watch app, and no watch import.** "Works with Apple Watch" would be read
  as a companion app, and nothing from a watch reaches the log.
- **Premium is not a better model.** Same coach, three times the monthly
  allowance ([ADR-0038](decisions/0038-premium-buys-more-coaching-not-a-different-model.md)).

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
- Your step count for each run you record here, read from Apple Health if you
  allow it. Run only reads, and never writes anything to Health
- Kilometres or miles, your choice


THE COACH

A subscription. The coach is an AI model. It writes your training plan and
keeps it honest week to week.

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
- If a reply is wrong or unsafe, press and hold it to report it.


WHAT IT IS NOT

No feed, no followers, no leaderboards, no kudos. It is a training tool, not a
social network, and it never becomes one.


YOUR DATA

Your runs live on your phone. Backing them up to our servers is a choice you
make in Settings, and it is off until you turn it on.

The coach asks before it sends anything. It says what goes to OpenRouter, the
service that passes each request to the AI model provider that writes the
reply, and what it never adds: your name, your email or your GPS routes. You
can take that permission back in Settings.

The privacy policy names every company involved and exactly what each one
receives. You can delete everything you have ever recorded, permanently, from
inside the app.


BEFORE YOU START

MGKFitness: Run is not a medical device and does not diagnose, treat, cure, or
prevent any medical condition. Consult a healthcare professional for medical
advice, diagnosis, or treatment.

Its plans are not medical advice. It does not know your medical history and
cannot see how you feel today. Speak to a doctor before you start or change a
training programme, and stop if something hurts.

iPhone only. Recording keeps the GPS running in the background, which uses more
battery than an app that is closed.


SUBSCRIPTION

The coach is an auto-renewing monthly subscription in two tiers: Coach, and
Premium Coach, which is the same coach with three times the coaching each
month. The price is shown in the app, in your own currency, before you buy
anything.

- Payment is charged to your Apple ID at confirmation of purchase.
- It renews automatically unless auto-renew is switched off at least 24 hours
  before the end of the current period.
- Your account is charged for renewal within 24 hours before the period ends.
- Manage or cancel it in your Apple ID account settings after purchase.

Privacy policy: https://mgkfitness.mgkcodes.com/run/privacy
Terms of use: https://mgkfitness.mgkcodes.com/run/terms
```

**The terms link is our own terms** (`docs/terms-of-use.md`, served at
`/run/terms`), per [ADR-0040](decisions/0040-our-terms-and-apples-eula.md). It
said Apple's standard EULA until 2026-09-29, a decision 8ac1181 had already
reversed in the app on 2026-09-10. App Store Connect's **License Agreement**
field is a different thing and stays Apple's Standard EULA: it takes plain text,
not a URL, and our terms already say Apple's EULA applies to App Store purchases
and wins where the two disagree.

**Apple Health is named on purpose.** Guideline 2.5.1 asks an app using
HealthKit to say so in its description. The sentence says exactly what is
read, and that nothing is written.

**The first sentence under BEFORE YOU START is Google Play's required health
disclaimer**, word for word. Apple does not require it; it is here too so the
two listings say the same thing about the same product.

## Subscription products

One group, because the tiers are alternatives and a runner should be able to
move between them without a second purchase.

| | Coach | Premium Coach |
|---|---|---|
| Entitlement | `paid` | `premium` |
| Server tier (sets the allowance) | `standard` | `sharp` |
| Price | £0.99 / month | £2.99 / month |
| Duration | 1 month | 1 month |

**Display name** is capped at 30 characters and **description at 45** — far
tighter than the listing's own fields, and tight enough that the first draft of
both descriptions came in at 82 and 99. `check_listing.py` counts them now.

| | Display name | Description |
|---|---|---|
| Coach | `Coach` (5) | `A training plan, adjusted every week.` (37) |
| Premium Coach | `Premium Coach` (13) | `Three times the coaching each month.` (36) |

They read as a pair on purpose: the first says what the product is, the second
says only what is different about it. At 45 characters there is no room to say
both twice.

**Premium's description changed on 2026-09-29, and it has to be changed in App
Store Connect by hand** (Subscriptions › Premium Coach › Localization). It said
*"A better model behind every plan and answer."*, which production has never
done: planning runs on one model for every tier by design, and no tier chat
model is configured, so both tiers talk to the same one. What Premium does buy
is three times Coach's monthly allowance, enforced by the coach function once
it carries `c708e3e`
([ADR-0038](decisions/0038-premium-buys-more-coaching-not-a-different-model.md)).
**The paywall prints this field verbatim** on both platforms — it comes from
the store through RevenueCat, not from the app — so the old text would have
made the claim inside the app as well.

Each also needs a **review screenshot**, and one file serves both. Run
`python tool/export_store_assets.py`; it lands in
`store-assets/derived/run-iap-review-screenshot.png` at **1290x2796**. An IAP
review screenshot only has to show the reviewer where the purchase happens, so
unlike the *listing* screenshots the plate is usable and no device is needed.

That script exists because App Store Connect rejects the file twice over
otherwise. **It refuses an alpha channel**, and every Flutter render carries
one. **And it refuses arbitrary dimensions**: Apple's older "640x920 minimum"
is not what the form takes, and a 786x1704 export that cleared that minimum was
rejected. The plate is rendered at 430x932 logical by 3 for this reason.

Prices are [ADR-0029](decisions/0029-what-a-tier-costs-and-buys.md)'s, and
`supabase/functions/coach/limits.ts` sizes every spend ceiling against them. Let
Apple's matrix set the other storefronts. **No free trial and no introductory
offer** at 1.0.0: a trial on a £1 product costs more in support than it earns.

## Review notes

Pasted into App Store Connect › the version › App Review Information › Notes,
which takes 4,000 characters. Replace the four bracketed values with the demo
accounts from [store-setup.md](store-setup.md) §9 and nothing else.

```
WHAT THIS IS
A free GPS running tracker (no account needed) with an optional AI running coach, sold as an auto-renewable subscription: Coach and Premium Coach, monthly, in one subscription group. Premium is the same coach with three times the monthly allowance.

DEMO ACCOUNTS
On the first screen, tap "I already have an account".
A - coach already unlocked. Please review the coach with this account, and please do not make a purchase on it:
[DEMO_A_EMAIL] / [DEMO_A_PASSWORD]
B - no subscription. Please use this one to test the purchase with your sandbox Apple ID:
[DEMO_B_EMAIL] / [DEMO_B_PASSWORD]
If you test account deletion, please use B, so that A stays available.

THE PAID HALF
Tap the round coach mark (bottom right, on every tab) or Plan tab > "Build a plan". The first time, the app asks permission to send training data to the AI provider (see below), then shows the medical disclaimer. On account B a sheet about the subscription follows, and "See the plans" opens the paywall. After a sandbox purchase the coach unlocks within about ten seconds.
The subscription is tied to the signed-in account because the coach runs on our server, is charged per request, stores the runner's plan and history, and has to follow them to a new phone. Recording runs never needs an account.

AI COACH AND DATA SHARING
The coach is a large language model. Before anything is sent, the app asks permission on a sheet titled "Before your coach answers". It names OpenRouter, the service that routes each request to the AI model provider, and lists what is sent (training profile, plan, recent runs' date, distance, time and pace, the runner's messages and a short summary) and what is never added (name, email, account ID, GPS routes). "Not now" sends nothing. Permission can be withdrawn in Profile > Settings > Privacy & legal > Coach and AI.
Any coach reply can be reported: press and hold the reply, choose a reason, and send.

BACKGROUND LOCATION
Used only while recording a run the user started, so recording continues with the screen locked (iOS shows the blue location indicator). The app requests "While Using" permission only, never "Always".

HEALTHKIT
Read-only. The app reads step count for the time window of a run recorded in the app, to show steps and cadence on that run. It never writes to Health. Nothing read from HealthKit is sent to the AI or used for advertising, and it stays on the device unless the user turns on backup.

MEDICAL
Not a medical device. A medical disclaimer is shown before the first plan or conversation, and the description and terms say the same.

ACCOUNT DELETION
Profile tab > Settings (gear, top right) > Privacy & legal > Delete account. It is also on the account screen: tap the card at the top of Settings, then Delete account. Typing DELETE confirms, and the server data is deleted at once.

No ads, no analytics, no crash reporting and no tracking.
```

## Screenshots — the list

**This is the one list of which screens to shoot.** It used to be in three
places (here, the release plan, and section H of the test sheet), which the
release plan recorded as a problem twice without fixing. The release plan now
points here, and the test sheet asks for "the list in app-store-listing.md"
rather than carrying a copy.

Six shots, chosen off
[the board](https://claude.ai/code/artifact/9ddfd186-11ad-4260-bde9-ef8b7a5d9190).
The first two are what shows in search, so they carry the argument alone.

| # | The screen | Board code | Plate id |
|---|---|---|---|
| 1 | Home: a plan, and today's session | `H1` | `home-with-plan` |
| 2 | A run in progress — **outdoors, map drawn** | `R4`/`R5` | `03-warmed` / `04-deep` |
| 3 | A finished run: route, splits, stats | `F1` | `run-complete` |
| 4 | A week of the plan, opened | `P2` | `week-detail` |
| 5 | The coach answering | `C4` | `coach-answering` |
| 6 | A year of running, on the profile | `S4` | `year-grid` |

Board codes exist only inside the contact sheet; the plate ids are the repo's
own names. **Shoot from the description** — the codes are only there to find
the reference.

**Take them on a real phone, not from the plate harness.** The harness answers
every network image with a 400, so there are no basemap tiles, and the map is
half of what makes shot 2 worth showing. The stand-ins in
`store-assets/derived/stand-ins/` are an Android render with demo fixtures and
are not submittable ([store-assets/README.md](../../../store-assets/README.md)).

Shot 3 will show only the tiles a real run has: time, pace, and steps and
cadence if Health allowed them. No elevation, no heart rate — that is the
product, not a fault in the shot.

| Store | Size | Count | Where they go |
|---|---|---|---|
| App Store | 6.9": **1260×2736, 1290×2796 or 1320×2868**, no alpha | 1–10 per localisation | `store-assets/captured/listing-*.png`, then `python tool/export_store_assets.py --check` |
| Google Play | **long side at most 2× the short side**, e.g. 1080×1920; JPEG or 24-bit PNG | 2–8 | see [play-listing.md](play-listing.md) |

An iPhone capture (1290×2796 is 2.17:1) is refused by Play, so the Android set
is shot separately rather than resized from the iPhone one.

## Still to produce

- [ ] **The 6.9" screenshots**, from the list above.
- [x] **App icon — nothing to upload.** App Store Connect takes the 1024 icon
      from the build's asset catalogue. `store-assets/captured/icon-1024.png`
      is the **old** loop mark from before the 2026-09-11 icon change; do not
      use it for anything.
- [x] **A review screenshot per subscription product** — exported, and one file
      covers both.
- [ ] **Premium's description** changed in App Store Connect, per the table
      above.
- [ ] **The demo accounts** — A with an `active` row that no store event can
      overwrite, B with none. SQL in [store-setup.md](store-setup.md) §9.
- [x] **The two URLs above resolve.** `/run/privacy` verified live 2026-09-03
      (200, valid certificate, no login). `/run/terms` has been served by the
      same site since 2026-09-11; open it once before pasting it anywhere.
