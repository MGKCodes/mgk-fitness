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
things that are true on an iPhone and false on Android:

- **No Apple anything.** No Apple ID, no App Store, no iPhone, no Apple Health.
  Payment is charged to the Google Play account.
- **No health data at all.** On Android the app asks for no health permission
  and reads nothing from Health Connect or anywhere else. Steps and cadence are
  an iPhone feature, so this listing does not mention them.
- **Not "iPhone only".** Obviously, and it was in the first draft.
- **Recording with the screen off is a notification, not a hidden process.**
  Android keeps a run going through a foreground service that shows "Recording
  your run" until Finish. The listing says so rather than implying the app
  tracks in the background on its own.

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
- Keeps recording with the screen locked and the phone in a pocket. While a run
  records, a notification says so, and it goes when you finish
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
Premium Coach, which is the same coach with three times the coaching each
month. The price is shown in the app, in your own currency, before you buy
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
description: Three times the coaching each month.
benefit: Everything in Coach
benefit: Three times the coaching each month
```

**Premium's text changed on 2026-09-29**
([ADR-0038](decisions/0038-premium-buys-more-coaching-not-a-different-model.md)):
Premium is the same coach with three times Coach's monthly allowance, not a
better model. Change it in Play Console by hand; nothing in the build carries
it.

## Graphics

Main store listing › Graphics. None of these is in the app bundle, so no build
carries them.

- [ ] **App icon — 512 × 512, 32-bit PNG with alpha, at most 1 MB.**
      `apps/mgk_run/design/store/play-listing-icon-512.png` is the right art but
      is saved as 24-bit RGB with no alpha channel. If Play refuses it, re-save
      it with one; nothing about the picture changes:

      ```
      python -c "from PIL import Image; Image.open('apps/mgk_run/design/store/play-listing-icon-512.png').convert('RGBA').save('play-icon-512-rgba.png')"
      ```

- [ ] **Feature graphic — 1024 × 500, JPEG or 24-bit PNG, no alpha.**
      **Missing, and Play will not publish without it.** Keep it plain: the
      mark on the app's near-black, and the name. Play crops and overlays it in
      places, so nothing important within about 80 px of the edges.
- [ ] **Phone screenshots — 2 to 8, JPEG or 24-bit PNG, no alpha.** **Missing.**
      Each side between 320 and 3840 px, and **the long side at most twice the
      short side**. 1080 × 1920 is the safe size: it passes that rule, and four
      or more at 1080 px or wider is what Play asks for before it will feature
      an app. Shoot the six in
      [app-store-listing.md](app-store-listing.md) § Screenshots, on an Android
      phone or an emulator set to that size (`adb shell wm size 1080x1920`).

      **An iPhone capture is refused.** 1290 × 2796 is 2.17 : 1, over the
      limit, and most modern Android phones capture at 20 : 9, which is over it
      too. Set the size, or crop, before capturing rather than after.

## Store settings

| Field | Value |
|---|---|
| App category | Health & Fitness |
| Tags | Optional; up to five from Play's own list |
| Contact email | hello@mgkcodes.com |
| Website | https://mgkfitness.mgkcodes.com |
| Privacy policy | https://mgkfitness.mgkcodes.com/run/privacy |
