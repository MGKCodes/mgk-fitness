# Google Play listing — 1.0.0

The copy that goes in Play Console's boxes, and the graphics checklist. The
App Store copy is in [app-store-listing.md](app-store-listing.md); both are
counted by `tool/check_listing.py`, which fails on an overrun, on a claim the
code does not support, and here also on anything Apple-only reaching the
Android listing.

Written 2026-09-29 for build 26. **This is source, like the Apple file**: edit
the copy here, run the checker, then paste. Where a field is set is in
[play-setup.md](play-setup.md); this file only says what goes in it.

---

## What this listing may not say

Everything in [app-store-listing.md](app-store-listing.md)'s list, plus four
things that are Android's own:

- **No Apple anything.** No Apple ID, no App Store, no iPhone, no Apple Health.
  Payment is charged to the Google Play account.
- **No health data at all.** On Android the app asks for no health permission
  and reads nothing from Health Connect or anywhere else. Steps and cadence are
  an iPhone feature, so this listing does not mention them.
- **Not "iPhone only".** Obviously, and it was in the first draft.
- **Not "on your lock screen".** The run's distance, time and pace are on a
  notification ([ADR-0045](decisions/0045-the-runs-figures-on-the-lock-screen.md)),
  and for most of 2 October 2026 this listing said they were on the lock
  screen. They are not, by default, on Android 16: the notification is a quiet
  one, and Android 16 keeps quiet notifications off the lock screen unless the
  runner turns them on in Settings. Seen on an emulator that afternoon, with a
  lock screen, while recording the foreground-service video; the earlier check
  had been made in the notification shade with no lock screen set. So the
  description says *in a notification*, with its condition, *if you allow
  notifications*, and says separately and without condition that the run keeps
  recording. The App Store listing keeps "lock screen": a Live Activity is on
  it, and the owner has seen it there.

**Google requires one paragraph verbatim**, because the app is in the Health &
Fitness category and gives training advice (Health Content and Services
policy). It is the first paragraph under BEFORE YOU START, and the checker
fails if a character of it changes.

---

## Title — 30 characters

```
MGKFitness: Run
```

The same name as the App Store listing, so the two stores name one product one
way ([naming.md](../../../docs/naming.md)).

## Short description — 80 characters

```
Free GPS run tracking. An optional AI coach builds and adjusts your plan.
```

## Full description — 4000 characters

```
Record a run the moment you open the app. No account, no sign-up, no trial
counting down. Press start and it tracks your route, your splits and your pace,
and keeps them on your phone.

That half is free, and always will be.


WHAT IS FREE

- GPS tracking with a live map, splits and pace
- Keeps recording with the screen locked and the phone in a pocket
- Distance, time and pace in a notification while you run, if you allow
  notifications
- Records without a signal. The run is written to your phone as it happens,
  not to a server
- Treadmill and manual entry, for the runs your phone did not see
- Your whole log: every run, its route, its splits, your records, and your
  year at a glance
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

An AI can be wrong. If a reply is wrong, unsafe or offensive, press and hold it
to report it from inside the app, and we will review it.


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
inside the app, or from our website if you no longer have the app.


BEFORE YOU START

MGKFitness: Run is not a medical device and does not diagnose, treat, cure, or
prevent any medical condition. Consult a healthcare professional for medical
advice, diagnosis, or treatment.

Its plans are not medical advice. It does not know your medical history and
cannot see how you feel today. Speak to a doctor before you start or change a
training programme, and stop if something hurts.

Recording keeps the GPS running while the screen is off, which uses more
battery than an app that is closed.


SUBSCRIPTION

The coach is an auto-renewing monthly subscription in two tiers: Coach, and
Premium Coach, which answers with a better AI model and has a bigger monthly
allowance. The price is shown in the app, in your own currency, before you buy
anything.

- Payment is charged to your Google Play account at confirmation of purchase.
- It renews every month unless auto-renew is switched off at least 24 hours
  before the end of the current period.
- Manage or cancel it in the Play Store, under Payments and subscriptions.

Privacy policy: https://mgkfitness.mgkcodes.com/run/privacy
Terms of use: https://mgkfitness.mgkcodes.com/run/terms
```

The billing sentences say the same four facts as the paywall's Google Play
disclosure (`purchase_screen.dart`, `_googleRenewal`), in the same store's
words.

## Subscriptions

Monetise › Subscriptions › each subscription › Edit subscription details.
The ids are fixed (`run.coach.monthly`, `run.coach.premium.monthly`); only the
listing text below changes.

**The description is shown to runners, whatever Play Console says.** Google
describes a subscription's description as internal and not shown on Google
Play. The app reads it anyway: the paywall prints `storeProduct.description`,
which RevenueCat takes from Play's product details. So it carries the same line
as the App Store, and the checker fails if the two differ.

**Benefits** are up to four per subscription, 40 characters each, and may not
mention a price or a free trial. Play shows them where a subscriber manages the
subscription.

### Coach

```
name: Coach
description: A training plan, adjusted every week.
benefit: A training plan from a conversation
benefit: Adjusted each week to what you ran
benefit: Ask the coach about any run
```

### Premium Coach

```
name: Premium Coach
description: A better AI model and a bigger allowance.
benefit: Everything in Coach
benefit: A better AI model for coach replies
benefit: A bigger monthly allowance
```

**Premium's text changed on 2026-09-30** ([ADR-0041](decisions/0041-premium-is-a-better-model-and-a-bigger-allowance.md)): a better AI model for
replies and a bigger allowance, stated as intent, with no model or number named.
Change it in Play Console by hand; nothing in the build carries it.

## Graphics

Main store listing › Graphics. None of these is in the app bundle, so no build
carries them.

- [ ] **App icon — 512 × 512, 32-bit PNG with alpha, at most 1 MB.** The art
      is `apps/mgk_run/design/store/play-listing-icon-512.png`, saved as 24-bit
      with no alpha channel. `python tool/export_store_assets.py` re-saves it
      with one as `store-assets/derived/play-icon-512.png`. Upload that file;
      nothing about the picture changes.
- [ ] **Feature graphic — 1024 × 500, JPEG or 24-bit PNG, no alpha.** Drawn:
      `store-assets/derived/play-feature-graphic.png`, the launch animation's
      last frame (`RUN »`) with the App Store subtitle under it, from
      `design/store-shots`. Play crops and overlays it in places, so nothing
      that matters is within about 80 px of an edge.
- [ ] **Phone screenshots — 2 to 8, JPEG or 24-bit PNG, no alpha.** Drawn: six,
      at 1080 × 1920, in `store-assets/derived/listing/play-still/`. Which six, in what order and with what words is in
      [app-store-listing.md](app-store-listing.md) § Screenshots. Each side
      has to be between 320 and 3840 px, with **the long side at most twice the
      short side**, and four or more at 1080 px or wider is what Play asks for
      before it will feature an app.

      **They are drawn as an Android phone, not resized from the iPhone set.**
      An iPhone picture is 2.17 : 1, over the limit, and it would show steps
      and cadence that Android does not have.

All three are checked by `python tool/export_store_assets.py --check`, from
`apps/mgk_run`.

## Release notes — 500 characters

Asked for when a release is created (Test and release ▸ Production ▸ Create
new release), between the `<en-GB>` tags the box arrives with. Shown on the
listing as *What's new*.

```
The first release of MGKFitness: Run. Free GPS run tracking with a live map, splits and pace, and an optional AI coach that builds your training plan and adjusts it every week.
```

## Store settings

| Field | Value |
|---|---|
| App category | Health & Fitness |
| Tags | Optional; up to five from Play's own list |
| Contact email | run@mgkfitness.mgkcodes.com |
| Website | https://mgkfitness.mgkcodes.com |
| Privacy policy | https://mgkfitness.mgkcodes.com/run/privacy |
