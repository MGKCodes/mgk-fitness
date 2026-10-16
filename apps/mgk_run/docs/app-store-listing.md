# App Store listing — 1.0.0

The copy that goes in the boxes. [store-setup.md](store-setup.md) §10 says
which boxes exist, field by field; this is what goes in them, so the runbook
stays a runbook and the writing lives somewhere it can be edited as writing. The Google Play copy is in
[play-listing.md](play-listing.md), checked by the same script.

Written 2026-09-02 against `f5599c3`. **Updated 2026-09-29 for build 26**: the
description stopped promising watch runs from Apple Health (the app reads step
count only), the terms link is our own terms (ADR-0040), Premium's description
says what Premium actually buys (ADR-0038, then ADR-0041 the next day), the
Play health disclaimer is in
here too, and the review notes are final apart from the demo credentials.

**To paste it, use [the submission sheet](https://claude.ai/artifact/Y2zLyeNxVuTrJTfHUn7tqM)**, not this file. The
descriptions are wrapped at eighty columns here, and pasted as they stand both
stores would break every sentence in the middle. `python
tool/build_submission_sheet.py` reads every field out of these docs, unwraps
it and puts a Copy button on it, in the order the consoles ask.

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
- **Premium's model is never named, and "better" has to stay true.** Premium
  replies come from `COACH_CHAT_MODEL_SHARP`, which must be a stronger model
  than Coach replies with; plans use one model for every tier, so nothing says
  Premium's *plans* are better ([ADR-0041](decisions/0041-premium-is-a-better-model-and-a-bigger-allowance.md)).

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
- Distance, time and pace on your lock screen while you run
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
Premium Coach, which answers with a better AI model and has a bigger monthly
allowance. The price is shown in the app, in your own currency, before you buy
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

**The lock screen line was added on 2 October 2026**, after the owner saw the
Live Activity working on build 29
([ADR-0045](decisions/0045-the-runs-figures-on-the-lock-screen.md)). A runner
can switch Live Activities off, so it is a feature and not a promise; the run
records either way, and the line above it says so.

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
| Premium Coach | `Premium Coach` (13) | `A better AI model and a bigger allowance.` (41) |

They read as a pair on purpose: the first says what the product is, the second
says only what is different about it. At 45 characters there is no room to say
both twice.

**Premium's description changed on 2026-09-30, and it has to be changed in App
Store Connect by hand** (Subscriptions › Premium Coach › Localization). It said
*"A better model behind every plan and answer."* No tier model was configured
then, and plans never use one. Since 2026-09-30 Premium's replies come from a
better model (`COACH_CHAT_MODEL_SHARP`, verified by a live call), and its
allowance is three times Coach's monthly spend. The description states that
intent and names no model or number, so changing the model is configuration,
not a store edit ([ADR-0041](decisions/0041-premium-is-a-better-model-and-a-bigger-allowance.md)).
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
A free GPS running tracker (no account needed) with an optional AI running coach, sold as an auto-renewable subscription: Coach and Premium Coach, monthly, in one subscription group. Premium answers with a better AI model and has a bigger monthly allowance.

DEMO ACCOUNTS
On the first screen, tap "I already have an account", then "Continue with email".
A - coach already unlocked. Please review the coach with this account, and please do not make a purchase on it:
[ADDRESS_A] / [PASSWORD_A]
B - no subscription. Please use this one to test the purchase with your sandbox Apple ID:
[ADDRESS_B] / [PASSWORD_B]
If you test account deletion, please use B, so that A stays available.

THE PAID HALF
Tap the round coach mark (bottom right, on every tab) or Plan tab > "Build a plan". The first time, the app asks permission to send training data to the AI provider (see below), then shows the medical disclaimer. On account B a sheet about the subscription follows, and "See the plans" opens the paywall. After a sandbox purchase the coach unlocks within about ten seconds.
The subscription is tied to the signed-in account because the coach runs on our server, is charged per request, stores the runner's plan and history, and has to follow them to a new phone. Recording runs never needs an account.

AI COACH AND DATA SHARING
The coach is a large language model. Before anything is sent, the app asks permission on a sheet titled "Before your coach answers". It names OpenRouter, the service that routes each request to the AI model provider, and lists what is sent (training profile, plan, recent runs' date, distance, time and pace, the runner's messages and a short summary) and what is never added (name, email, account ID, GPS routes). "Not now" sends nothing. Permission can be withdrawn in Profile > Settings > Privacy & legal > Coach and AI.
Any coach reply can be reported: press and hold the reply, choose a reason, and send.

BACKGROUND LOCATION
Used only while recording a run the user started, so recording continues with the screen locked (iOS shows the blue location indicator). The app requests "While Using" permission only, never "Always". When the app is opened it also reads the last known position, if location is already allowed, to load the map around the runner before a run. It never prompts for that and takes no location in the background.

HEALTHKIT
Read-only. The app reads step count for the time window of a run recorded in the app, to show steps and cadence on that run. It never writes to Health. Nothing read from HealthKit is sent to the AI or used for advertising, and it stays on the device unless the user turns on backup.

MEDICAL
Not a medical device. A medical disclaimer is shown before the first plan or conversation, and the description and terms say the same.

SIGNING IN
Sign in with Apple, Sign in with Google, or an email and password. The three are offered together, at equal size; "Continue with email" opens the email form. The demo accounts above use email and password. A new account made with an email address has to confirm it from an email before it can sign in; the demo accounts are already confirmed.

ACCOUNT DELETION
Profile tab > Settings (gear, top right) > Privacy & legal > Delete account. It is also on the account screen: tap the card at the top of Settings, then Delete account. Typing DELETE confirms, and the server data is deleted at once. For an account made with Apple, the app asks Apple to confirm, and the server revokes the app's Apple tokens when the login is deleted.

No ads, no analytics, no crash reporting and no tracking.
```

## Screenshots — the list

**This is the one list of which screens are on the listing.** It used to be in
three places (here, the release plan, and section H of the test sheet). The
release plan points here, and the test sheet asks for "the list in
app-store-listing.md" rather than carrying a copy.

Six pictures, in the order the stores show them. The first two are what shows
in search, so they carry the subtitle between them: tracking, then the plan.

| # | The screen | Tag | Headline | Screen file |
|---|---|---|---|---|
| 1 | A run in progress, **outdoors, map drawn** | none | Track every run. No account needed. | `2-run` |
| 2 | Home: a plan, and today's session | Coach · Subscription | Know what to run today. | `1-home` |
| 3 | A finished run: route, time, pace, splits | none | Every run, kept on your phone. | `3-finished` |
| 4 | The plan: the race, this week, *Adjust this week* | Coach · Subscription | A real plan, adjusted weekly. | `4-plan` |
| 5 | The coach answering | AI coach · Subscription | Ask the coach about any run. | `5-coach` |
| 6 | A year of running, on the profile | none | Your year, at a glance. | `6-year` |

**The words live in
[`design/store-shots/src/shots.ts`](../design/store-shots/src/shots.ts).** This
table is a copy for reading; that file is what is rendered.

**The three coach pictures are tagged as the subscription.** They show the
coach, and App Review guideline 2.3.2 asks a listing to make clear which of the
things it shows need a purchase. The other three carry no tag.

**No picture says "Free".** Apple counts it as a price, which guideline 2.3.7
keeps out of screenshots. Lift 2.0.0 was rejected for these same words on 7
October 2026, and Run 1.0.0, which had them too, was taken out of review the
same day and sent back with the pictures above (build 29 unchanged, screens
drawn from `3baf30c`, whose app code is build 29's). The description may still
say what is free.

**Changed on 2026-10-01, with build 29.** The run moved ahead of Home, so the
first two pictures follow the subtitle. Picture 4 was "a week of the plan,
opened" and is the Plan tab: it shows the race, the week and *Adjust this week*
in one screen, where the opened week showed one week's rows.

### They are drawn, not captured

**Until build 29 this section said to take them on a real phone**, because the
plate harness answers every network image with a 400 and so drew no map. That
reason is gone. `test/plates/store.dart` takes the stub off and waits for the
real tiles, at the exact size each store takes. It draws the shipped app's own
screens for a seeded runner, `design/store-shots` adds the frame, the status
bar and the words, and the whole set is redrawn in a few minutes after any
change to a screen ([README](../design/store-shots/README.md)).

A listing is read as a promise, so the runner in the pictures has only what the
app does:

- **Only what a recorded run has.** Time, pace and splits; steps and cadence on
  the iPhone picture only, because Android reads no step count. No elevation
  and no heart rate on either.
- **The coach's reply in picture 5 is scripted** (`StoreCoach` in
  `store.dart`), because nothing that draws the pictures can reach the real
  coach. It is in the runner's own units, and its half-marathon time is the one
  the pace model gives this runner. If the test sheet's H3 brings back what the
  real coach said to the same question, that replaces it word for word.
- **Home's greeting follows the clock** when the set is drawn. `store.dart`
  writes a status-bar time that agrees with it, and the mockups read it.

A capture off a phone is still acceptable, and still checked: drop it in
`store-assets/captured/` as `listing-*.png`.

**Still is on the listing.** Three designs were drawn (Still, Slipstream and
Plain; the README says what each is) and shown on [the gallery](https://claude.ai/artifact/KmRop4oC1KrHb2UdHykJbU). The owner
chose Still on 2 October 2026, and it is what `render.sh` draws.

| Store | Size | Count | Where they are |
|---|---|---|---|
| App Store | 6.9": **1260×2736, 1290×2796 or 1320×2868**, no alpha. Drawn at 1290×2796 | 1–10 per localisation | `store-assets/derived/listing/ios-still/` |
| Google Play | **long side at most 2× the short side**; JPEG or 24-bit PNG. Drawn at 1080×1920 | 2–8 | `store-assets/derived/listing/play-still/` |

From `apps/mgk_run`, `python tool/export_store_assets.py --check` checks every
set against these, and `--downloads` copies them out of the worktree to where a
browser can reach them.

The two stores' sets are drawn separately, each as its own platform's screen.
An iPhone picture is 2.17:1, which Play refuses, and the Android finished run
has no steps.

## Still to produce

- [ ] **The 6.9" screenshots.** Drawn, and Still chosen. Left: upload them.
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
