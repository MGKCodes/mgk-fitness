# Privacy Policy — MGKFitness: Run

> **Not legally reviewed, and shipping anyway — a decision taken 2026-09-01.**
> Formal review is out of reach for now, so this goes out as the most accurate
> description we can write. What protects it is that the data flows below were
> read off the running system rather than written from intent: the risk that
> actually bites is a policy that says something untrue about what happens to
> somebody's data, and that is the part this document is careful about. What is
> unreviewed is its legal *form* — rights language, how the lawful basis is
> phrased, whether the retention justification would satisfy a regulator.
> Revisit when there is budget; it is revisable, and a dated update is normal.
>
> Still open, and different in kind from the above:
>
> 1. **A processor agreement with OpenRouter** covering special-category data.
>    **This one is not about wording.** The policy names OpenRouter as a
>    processor, which asserts that an Article 28 arrangement exists. Publishing
>    before it does means stating something that is not yet true — so it is a
>    factual precondition rather than a review, and it wants a decision of its
>    own. See
>    [openrouter-processor-agreement.md](openrouter-processor-agreement.md).
> 2. **Whether the configured `COACH_MODEL`'s provider trains on inference
>    inputs.** A per-model property, so changing the model can change the answer
>    — see [compliance.md](compliance.md). `data_collection: "deny"` is set on
>    every request, which is the control; what is unconfirmed is what it
>    guarantees contractually.
> 3. The publication date below.

**Last updated:** [date] · **Controller:** MGKCodes Ltd · **Contact:**
hello@mgkcodes.com

## Summary

MGKFitness: Run is a running coach. Your runs and plans live on your phone; backing
up to our servers is optional and off until you ask. To coach you it sends your
training context, and what you say in the conversation, to an AI provider. We do
not sell your data. You can delete everything at any time.

> The in-app copy of this policy lives in
> `lib/src/features/legal/domain/legal_copy.dart`. **Change both together** — a
> regression test (`test/legal/legal_copy_test.dart`) fails if they drift.

## What we collect

- **Account data** — email / auth identifier.
- **Profile data** — date of birth, weight, unit preference, and running profile
  (current volume, longest run, available days, a recent race/time trial,
  optional injury notes).
- **Activity data** — runs you record or that sync from Apple Health: route
  points, distance, duration, pace, elevation, heart rate, cadence, and
  estimated calories.
- **Training data** — generated plans, sessions, check-ins, and RPE, including
  the plans you have finished with, so your coach knows what you have already
  tried.
- **What you say to your coach** — your messages, the coach's replies, and a
  short rolling summary of what matters across conversations. This is free text
  you wrote, so it may contain anything you chose to tell it, including how you
  feel and where you hurt. Treat it as the most personal thing here, because it
  is.
- **Usage records** — for each AI request, which part of the coach it came from,
  how many tokens it used and what it cost. Needed to enforce fair-use limits
  and keep the service affordable; it holds no training or message content.

We collect only what the coaching product needs (data minimisation).

## Health data

Activity, heart-rate, and profile data are **health data — special-category
data under UK GDPR**. We process it to provide the coaching service you request
(the lawful basis is your consent, which you can withdraw by deleting your
data).

Apple **HealthKit** data is read (and written back as workouts) only with your
explicit permission, and is used solely to power your training. HealthKit data
is never used for advertising and is not shared with third parties for their own
purposes.

## Who we share it with (sub-processors)

- **Supabase** — hosts our database, authentication, and server functions.
- **OpenRouter** — routes our AI requests to the model provider that serves the
  model we have selected. Requests are made by our server, not your device, so
  the provider never sees your IP address or device.

  What we send depends on what the coach is doing:

  - To **generate or adapt a plan**: your training profile and the plan itself —
    goals, volumes, available days, session history, and your injury notes if
    you gave any.
  - To **hold a conversation**: a written summary of your training *and up to
    your last twenty messages, as you wrote them*. If you told your coach about
    an injury, a symptom or how you are feeling, that text is sent.

  We never send your **name, email, or account identifier**, and we never send
  **raw GPS traces**. But we will not pretend the rest is anonymous: taken
  together it is health information about one person, and if you would rather it
  did not leave the app, do not use the coach.

  **What we control, and what we do not.** Every request we make asks OpenRouter
  to route only to providers that do not keep or train on what we send. That
  setting is on for all of them, and it is the strongest control available to
  us. What we cannot do is audit the provider that ultimately serves a request,
  so treat that as a control we apply rather than a promise we can make for
  them. We will say so here if that ever changes.
- **RevenueCat** — handles subscription purchases and tells our server whether
  yours is active. It receives your account identifier and your purchase
  history, and nothing else: no runs, no training data, and nothing you said to
  your coach.
- **MapTiler** — serves the basemap tiles behind your route; receives
  approximate map viewport coordinates. Configured per build
  (`MAP_TILE_URL_TEMPLATE`); a build with no tile provider draws routes with no
  basemap and contacts no one.

We do not sell personal data, and we do not use it for third-party advertising.

## Where data is stored

Your runs, plans and conversations live **on your device**, which is the copy
the app actually works from — it records, reads and plans with no network at
all. Data in transit is encrypted (HTTPS/TLS).

## Backing up is optional, and off until you ask

Nothing above leaves your phone for our servers unless you turn on **Back up my
data** in Settings. It starts off. With it off, your phone is the only copy, and
an uninstall loses everything — which is the trade we let you make rather than
make for you, because this is health information.

With it on:

- Your runs, routes, heart rate, plans and coach conversations are copied to our
  Supabase project in **eu-west-1 (Ireland)**.
- Signing in on a new phone pulls them back down, so a lost or replaced device
  does not lose your training. The restore only ever **adds** — it will not
  overwrite anything already on the new phone.
- **Turning it back off deletes what we have stored.** Your phone keeps its own
  copy.

The AI requests described above are a separate thing and happen either way: the
coach cannot answer without sending your training context, so using the coach
sends it whether or not backup is on.

Our Supabase project is shared with our lifting app **MGKFitness: Lift** (see
Your rights below). This app's own data lives in its own schema, separated per
user by row-level security.

## Your rights

Under UK GDPR you can access, correct, export, or delete your data, and withdraw
consent. There are two in-app controls, and they do different things:

- **Back up my data → off** withdraws consent to storing your data on our
  servers and deletes what is already there. Your phone keeps its copy.
- **Delete account** removes **every** record we hold for you — runs,
  route points, splits, plans, sessions, your runner profile, your coach
  conversations and your usage records. It is written to sweep every table keyed
  to your account rather than a list someone has to remember to update, so a
  feature added later is covered by that design rather than by our diligence.

To exercise any right, use those controls or contact hello@mgkcodes.com.

Your login is your **MGKFitness profile**, shared with our lifting app
**MGKFitness: Lift**. If the profile holds no data from Lift, deletion removes
the profile itself. If it does, we delete everything this app holds and keep only
the profile, so your data in Lift survives — email hello@mgkcodes.com to remove
the profile as well.

## Retention

We keep your data while your account is active, and deletion removes it
immediately, except where we must retain limited records to meet legal
obligations. Two things expire on their own without you asking:

- **Usage records** are pruned after 31 days — long enough for the monthly
  fair-use window and no longer.
- **Coach conversations** are kept so your coach remembers you between sessions,
  then pruned after 180 days, or sooner once there are more than 1,000 messages.
  The short rolling summary is what survives.

## Children

The app is not directed at children under 16 and we do not knowingly collect
data.

## Changes

We'll update this policy as the product evolves and note the date above.

## Contact

MGKCodes Ltd — hello@mgkcodes.com.
