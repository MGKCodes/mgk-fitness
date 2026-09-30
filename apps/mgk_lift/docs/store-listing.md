# Store listing for Lift 2.0.0: what goes in each field

Drafts for App Store Connect and Play Console, written 2026-09-29 from the code
and from [privacy-policy.md](privacy-policy.md), so filling the forms is
transcription rather than judgement. Character counts are in brackets. No price
appears anywhere: prices live in the stores (submission-week decision 6).

What the code does, which every answer below rests on:

- **No account is needed to track.** With no account nothing leaves the phone.
  Signing in (Apple, Google, or email and password; Supabase, EU) backs
  workouts up. Apple and Google pass an email address and an identifier, and
  nothing else (O1).
- **Paid half:** the AI coach, training plans and progress photos, as Coach or
  Premium Coach. Photos go to a private Supabase bucket. Coach text goes to
  OpenRouter, sent by our server, never with name, email or account id.
- **RevenueCat** gets the Supabase user id and the store's purchase record.
- **No ads, no analytics SDK, no crash reporter, no tracking.** Checked in
  `pubspec.yaml` and the lockfile on 2026-09-29.

---

## App Store Connect

### App information

| Field | Value |
|---|---|
| Name | `MGKFitness: Lift` [16] |
| Subtitle | `Workout log with an AI coach` [28] |
| Primary category | Health & Fitness |
| Secondary category | Sports |
| Privacy policy URL | `https://mgkfitness.mgkcodes.com/lift/privacy` |
| License agreement | Custom: the text at `https://mgkfitness.mgkcodes.com/lift/terms` |
| Copyright | `2026 MGKCodes Ltd` |

### Version 2.0.0

**Promotional text** [151]

> Log a set in one tap, with last time's numbers already in. A rest timer that
> buzzes with your phone locked. Works with no signal, and needs no account.

**Keywords** [91]

```
gym,workout log,weightlifting,strength,tracker,sets,reps,rest timer,progress photos,routine
```

**Support URL** `https://mgkfitness.mgkcodes.com/lift/support`
**Marketing URL** `https://mgkfitness.mgkcodes.com`

**Description**

> Lift is a strength-training log built for the minute between sets.
>
> LOGGING
> - Start from one of your saved workouts and every set is already filled in:
>   the reps you aim for, and the weight you lifted last time.
> - Tick a set and the rest timer starts. It buzzes when rest is over, even
>   with your phone locked, and counts on past zero so you know how long you
>   actually rested.
> - Each movement remembers its own rest length.
> - Mark warm-up sets, swap a movement when the machine is taken, reorder,
>   and remove anything with Undo.
> - Every set is saved on your phone the moment you tick it. No signal needed.
>
> YOUR WORKOUTS
> - Save a session as a workout and start it again in one tap.
> - A saved workout learns from how you train: remove a movement and it stays
>   removed next time.
> - Every session is there to open, fix or delete, grouped by week.
>
> BACKUP
> - Tracking needs no account. Sign in and your workouts are backed up, and the
>   app tells you plainly whether each one has been.
>
> THE COACH (SUBSCRIPTION)
> - A training plan built around your goal and the days you can train, which
>   adjusts as you go.
> - A coach you can talk to about your training. It reads your log.
> - Progress photos, one a week per pose, played back in sequence.
> - Coach and Premium Coach hold the same features; Premium Coach gives the
>   coach far more room to talk.
>
> The coach is an AI model, not a person, and it is not medical advice. You can
> switch it off in Settings, and nothing is sent to it while it is off.
>
> Lift used to be called Liftio. This is a complete rebuild. Your account and
> your backed-up history carry over.
>
> Subscriptions renew monthly until cancelled, and can be managed in your Apple
> ID settings.
> Terms of use: https://mgkfitness.mgkcodes.com/lift/terms
> Privacy policy: https://mgkfitness.mgkcodes.com/lift/privacy

**What's New**

> Liftio is now MGKFitness: Lift, rebuilt from the ground up, so the icon and
> name on your home screen have changed. Your account and backed-up history
> carry over: sign in the same way you did before.
>
> New: saved workouts that start ready-filled and learn from your sessions, a
> rest timer that reaches your lock screen, every session editable, sign in
> with Google, and an optional AI coach with training plans and progress
> photos.

### App Review information

Leave the credentials for a **confirmed and entitled** demo account here
(`core.grant_entitlement()` makes it entitled; I can do it once you create the
account). Notes:

> Lift is a workout log. Tracking, saved workouts, history and stats are free
> and need no account: tap Start a session on the Track tab.
>
> The paid half (AI coach, training plans, progress photos) is sold as two
> monthly auto-renewing subscriptions, Coach and Premium Coach. The purchase
> screen opens from Start coaching on the Plan tab, from the C button at the
> bottom right of any tab, or from Unlock photos under Profile > Progress
> photos. It shows both tiers, the renewal terms, links to the terms and
> privacy policy, and Restore purchases. Restore is also under Settings > the
> account card.
>
> The demo account below is already subscribed, so the coach, plans and photos
> are open without purchasing.
>
> The AI coach sends the lifter's messages and a summary of their training to
> OpenRouter, from our server. It is disclosed at the point of use (the info
> mark in the coach sheet), in Settings > Use the AI coach (a switch that turns
> it off entirely), and in Privacy & legal.
>
> Signing in: Sign in with Apple, Sign in with Google, or an email and
> password, all on the one sign-in screen.
>
> Account deletion: Profile > Settings > Privacy & legal > Delete account. For
> an account made with Apple, the app asks Apple to confirm, and the server
> revokes the app's Apple tokens when the login is deleted.
>
> This version replaces Liftio 1.4.0 under the same bundle id; the app was
> renamed.

### App Privacy ("nutrition labels")

**Tracking: No.** No data is used to track across other companies' apps or
websites, and there is no advertising or data broker anywhere in the pipeline.

Every type below: **linked to the user** (once signed in, it sits under their
account), **not used for tracking**, purpose **App Functionality** only.

| Apple data type | Collected | What it is in Lift |
|---|---|---|
| Contact Info › Email Address | Yes | The account login: typed in, or passed on by Apple or Google at sign-in (with Hide My Email, Apple's relay address) |
| Identifiers › User ID | Yes | The Supabase user id, also passed to RevenueCat; and Apple's or Google's identifier for the lifter, when they sign in with one |
| Health & Fitness › Fitness | Yes | Logged workouts: movements, sets, reps, weights |
| Health & Fitness › Health | Yes | Injury notes typed into plan intake, and whatever a lifter tells the coach about their body |
| User Content › Photos or Videos | Yes | Progress photos (paid; private bucket) |
| User Content › Other User Content | Yes | Coach messages, session and exercise notes |
| Purchases › Purchase History | Yes | The subscription, via the store and RevenueCat |
| Usage Data › Other Usage Data | Yes | Per-request AI usage (tokens, cost), for fair-use limits |
| Location, Contacts, Browsing, Search, Diagnostics, Sensitive Info, Financial Info | No | |

One check before submitting: open the RevenueCat SDK's privacy manifest
(`PrivacyInfo.xcprivacy` in the built app, or RevenueCat's docs page on Apple
privacy labels). If it declares a type not in this table, add it. Run's
privacy-policy note 3 records the same open item.

### Age rating

Answer the questionnaire as the app is: no violence, sexual content, gambling,
profanity, alcohol or drugs; **medical or treatment information: none** (it gives
training guidance and says it is not medical advice); **unrestricted web
access: no**; **user-generated content shared with others: no** (photos and
messages are private to the account); and yes to any question about an **AI
chatbot or assistant**. The terms separately require 16+ to create an account.

### Subscriptions

See [store-setup.md](store-setup.md) step 1 for the product fields, levels and
review notes.

---

## Google Play Console

### Main store listing

| Field | Value |
|---|---|
| App name | `MGKFitness: Lift` [16] |
| Short description | `Log a set in one tap. Rest timer that buzzes when locked. An optional AI coach.` [79] |
| Full description | The App Store description above, with the last renewal line changed to: "Subscriptions renew monthly until cancelled, and can be managed in the Play Store under Payments and subscriptions." |
| App category | Health & Fitness |
| Contact email | `hello@mgkcodes.com` |
| Website | `https://mgkfitness.mgkcodes.com` |
| Privacy policy | `https://mgkfitness.mgkcodes.com/lift/privacy` |

### Data safety

- **Is data encrypted in transit?** Yes.
- **Can users request deletion?** Yes: in the app, and at
  `https://mgkfitness.mgkcodes.com/lift/delete-account`.
- **Is any data shared?** **No.** Supabase, OpenRouter (and the model provider
  it routes to) and RevenueCat process data on our behalf, which Play counts as
  service providers rather than sharing.

Collected, all for **App functionality**, none for advertising or analytics:

| Play category › type | Required or optional | Notes |
|---|---|---|
| Personal info › Email address | Optional | Only with an account |
| Personal info › User IDs | Optional | Only with an account |
| Health and fitness › Fitness info | Optional | Synced only when signed in |
| Health and fitness › Health info | Optional | Injury notes, coach messages |
| Photos and videos › Photos | Optional | Progress photos, paid |
| Messages › Other in-app messages | Optional | Coach conversations |
| App activity › Other user-generated content | Optional | Session and exercise notes |
| Financial info › Purchase history | Optional | Only if subscribed |
| App activity › Other actions | Optional | AI usage records for fair-use limits |

Signing in with Apple or Google adds no type to either table: they pass an
email address and an identifier, which are the two rows already there.

"Optional" is honest here: every one of them depends on the lifter choosing to
sign in, subscribe or use the coach. The core feature, logging, collects nothing
off the device.

### App content

- **Ads:** No ads.
- **App access:** Some functionality is restricted. Give the demo account and
  say: "The coach, plans and photos need a subscription; this account has one."
- **Content rating (IARC):** same answers as Apple's. Expect Everyone / PEGI 3.
- **Target audience:** 16–17 and 18+. Not 13–15, because the terms require 16
  for an account and the paid half is account-bound.
- **Health apps declaration:** Lift is a fitness tracker with coaching. It does
  not diagnose, treat or claim medical outcomes, so declare it as fitness, not
  as a medical or health-research app.
- **Account deletion:** the URL above.
- **Government, financial features, news:** none.

---

## Open questions

1. **RevenueCat's own collection:** confirm against its privacy manifest before
   filing the Apple labels (above).
2. **OpenRouter's processor terms for special-category data:** still open
   (privacy-policy note 1). It does not change any answer here, but it is the
   agreement those answers assume.
3. **Whether the configured model's provider trains on inputs:** still open
   (privacy-policy note 2). If it does, "not shared" needs revisiting.
