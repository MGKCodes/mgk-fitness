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
> **Rewritten 2026-09-10 against the code, not against the previous draft.**
> An audit compared every claim here to what the app actually does and found
> eleven mismatches in both directions. The dangerous ones are fixed in code:
> the runner's name was being sent to the model provider while this document
> said it never was, and deleting a Run account erased the sibling app's data
> while this document promised it survived. The rest were corrected here —
> three things this policy claimed to collect and does not, three it collects
> and did not mention. Anything below that describes a column which exists but
> is never filled has been removed; a policy that over-declares is still a
> policy that is wrong, and it drags the app into a stricter review bracket for
> nothing.
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
> 3. **What the RevenueCat SDK collects on its own account.** We pass it an
>    account identifier and nothing else, which is the claim made below — but a
>    purchase SDK typically also collects an install identifier, a store country
>    and an OS version for itself. Check their privacy manifest before filing
>    the App Store's privacy labels.

**Last updated:** 10 September 2026 · **Controller:** MGKCodes Ltd · **Contact:**
hello@mgkcodes.com

## Summary

MGKFitness: Run is a running coach. Your runs and plans live on your phone;
backing up to our servers is optional and off until you ask. To coach you it
sends your training context, and what you say in the conversation, to an AI
provider. We do not sell your data. You can delete everything at any time.

> The in-app copy of this policy lives in
> `lib/src/features/legal/domain/legal_copy.dart`. **Change both together** — a
> regression test (`test/legal/legal_copy_test.dart`) fails if they drift.

## What we collect

- **Account data** — your email address, the account identifier it is keyed to,
  and **the name you give the coach**, if you give one. Only if you create an
  account; the app works without one.

  The name is optional and you can change or remove it at any time — clear the
  field and the coach stops using one. It is stored with your login rather than
  with your training, so it is what the app calls you and nothing more. It is
  **never sent to the AI provider**; see the sub-processors below.
- **Profile data** — your unit preference, and your running profile: current
  volume, longest run, available days, a recent race or time trial, and any
  injury notes you choose to give. We do **not** ask for your date of birth or
  your weight.
- **Activity data** — the runs you record, and any you add by hand: route
  points, distance, duration and pace. If you give Apple Health permission we
  also read your **step count** for the run. A heart rate is stored only if you
  type one in; we do not read heart rate from a watch or a chest strap.
- **Training data** — generated plans and sessions, whether each session was
  marked done or skipped, your rating of how hard it felt (RPE), and the plans
  you have finished with, so your coach knows what you have already tried.
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

Activity and profile data are **health data — special-category data under UK
GDPR**. We process it to provide the coaching service you request (the lawful
basis is your consent, which you can withdraw by deleting your data).

Apple **HealthKit** data is read only with your explicit permission, and **we
never write anything to Health**. We ask for two things: your workouts, which
we read to show you how many Health has recorded and then discard without
storing, and your **step count for a run**, which we do store alongside that
run. HealthKit data is never used for advertising and is not shared with third
parties for their own purposes.

On Android the app requests no health permissions at all.

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
  **raw GPS traces**. One honest qualification on the first of those: your
  messages go as you wrote them, so if you type your own name into the
  conversation, you have sent it. We do not add it.

  We will not pretend the rest is anonymous: taken together it is health
  information about one person, and if you would rather it did not leave the
  app, do not use the coach.

  **What we control, and what we do not.** Every request we make asks OpenRouter
  to route only to providers that do not keep or train on what we send. That
  setting is on for all of them, and it is the strongest control available to
  us. What we cannot do is audit the provider that ultimately serves a request,
  so treat that as a control we apply rather than a promise we can make for
  them. We will say so here if that ever changes.
- **RevenueCat** — handles subscription purchases and tells our server whether
  yours is active. **We** send it your account identifier and nothing else: no
  runs, no training data, and nothing you said to your coach. Like any purchase
  SDK it also collects technical information of its own about the install, such
  as a device-scoped identifier, your store country and your app version.
- **MapTiler** — serves the basemap tiles behind your route while you run;
  receives the map coordinates being displayed and, like any web request, your
  IP address. This happens whether or not you have an account. Configured per
  build; a build with no tile provider draws routes with no basemap and contacts
  no one.

We do not sell personal data, and we do not use it for third-party advertising.
The app contains **no analytics, no advertising SDK and no crash reporter**, and
reads no advertising identifier.

## Where data is stored

Your runs, plans and conversations live **on your device**, which is the copy
the app actually works from — it records, reads and plans with no network at
all. Data in transit is encrypted (HTTPS/TLS).

## Backing up is optional, and off until you ask

**Nothing about your training** leaves your phone for our servers unless you
turn on **Back up my data** in Settings. It starts off. With it off, your phone
is the only copy, and an uninstall loses everything — which is the trade we let
you make rather than make for you, because this is health information.

Two things are not covered by that switch, because they are what an account
*is* rather than something it stores: your **email address**, which we need to
sign you in, and your **unit preference**, which follows you to a new phone so
the app opens in miles if that is how you left it. Both are written when you
sign in and change, whatever the backup switch says. Neither is training data.

With backup on:

- Your runs, routes, plans and coach conversations are copied to our Supabase
  project in **eu-west-1 (Ireland)**.
- Signing in on a new phone pulls them back down, so a lost or replaced device
  does not lose your training. The restore only ever **adds** — it will not
  overwrite anything already on the new phone.
- **Turning it back off deletes your training data from our servers.** Your
  phone keeps its own copy. Your account itself, and the usage records described
  under Retention, are not part of that — use **Delete account** for those.

The AI requests described above are a separate thing and happen either way: the
coach cannot answer without sending your training context, so using the coach
sends it whether or not backup is on.

## Sharing with our lifting app

Our Supabase project is shared with our lifting app **MGKFitness: Lift**, and
one login serves both. Each app's own data lives in its own area, separated per
user by row-level security, and neither app can read the other's.

One thing does cross, and it is worth naming: when a run is backed up, a short
summary of it — the date, how long it lasted, how far it went, and how hard it
felt — is copied into a **shared activity feed** on your account, alongside your
lifting sessions. It exists so that one app can show you a complete picture of a
week's training. It is readable only by you, holds no route and no conversation,
and is deleted with the run it came from.

## Your rights

Under UK GDPR you can access, correct, export, or delete your data, and withdraw
consent. There are two in-app controls, and they do different things:

- **Back up my data → off** withdraws consent to storing your training on our
  servers and deletes what is already there. Your phone keeps its copy.
- **Delete account** removes every record this app holds for you — runs, route
  points, splits, plans, sessions, your runner profile, and your coach
  conversations and their summary. It sweeps every table keyed to your account
  rather than a list someone has to remember to update, so a feature added later
  is covered by that design rather than by our diligence.

  Two deliberate exceptions. Your **usage records** survive, because they are
  the meter that enforces fair-use limits and erasing them would let a deletion
  reset a spend cap; they hold no training data and nothing you wrote, and they
  are pruned after 31 days regardless. And your **login** survives if our
  lifting app still holds data on it — see below.

To exercise any right, use those controls or contact hello@mgkcodes.com. If
you have already uninstalled the app, ask us at
https://mgkfitness.mgkcodes.com/run/delete-account — the in-app control is
faster and complete, but it is no use to you once the app is gone.

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
