# Privacy Policy — MGKFitness: Lift

> **Draft — legally unreviewed.** The data flows below are accurate as built and
> were checked against the code and the schema, not written from intent. What is
> still open before submission is not wording:
>
> 1. **Legal review** of this document.
> 2. **A processor agreement with OpenRouter** covering special-category data.
> 3. **Whether the configured `COACH_MODEL`'s provider trains on inference
>    inputs.** A per-model property, so changing the model can change the answer.
> 4. The publication date below.
>
> Items 2 and 3 are the ones that could change what this policy has to say.

**Last updated:** [date] · **Controller:** MGKCodes Ltd · **Contact:**
hello@mgkcodes.com

## Summary

MGKFitness: Lift is a strength-training log with an optional AI coach. Your
sessions live on your phone and tracking works with no account at all. Signing
in stores them on our servers. To coach you it sends your training context, and what you say
in the conversation, to an AI provider. We do not sell your data. You can delete
everything at any time.

> The in-app copy of this policy lives in
> `lib/src/features/legal/domain/legal_copy.dart`. **Change both together** — a
> regression test (`test/legal/legal_copy_test.dart`) fails if they drift.

## What we collect

- **Account data** — email / auth identifier.
- **Training data** — the sessions you log: exercise names, sets, reps, weight,
  set type, and for cardio work its duration and distance. Session and exercise
  notes are free text you wrote, so they hold whatever you chose to put there.
- **Progress photos** — the photos you take, the week and pose you filed them
  under, and any note against them. These stay on your phone; see *Progress
  photos* below.
- **Plan data** — the answers you give when you ask for a plan: your goal, how
  many weeks and days a week you can train, which days those are, the equipment
  you have, and your injury notes if you gave any.
- **What you say to your coach** — your messages, the coach's replies, and a
  short rolling summary of what matters across a conversation. This is free text
  you wrote, so it may contain anything you chose to tell it, including how you
  feel and where you hurt. Treat it as the most personal thing here, because it
  is.
- **Usage records** — for each AI request, which part of the coach it came from,
  how many tokens it used and what it cost. Needed to enforce fair-use limits and
  keep the service affordable; it holds no training or message content.

We collect only what the training product needs (data minimisation).

## Health data

Your training, your injury notes, and what you tell your coach about your body
are health data — special-category data under UK GDPR. We process it to provide
the logging and coaching service you request (the lawful basis is your consent,
which you can withdraw by deleting your data).

## Who we share it with

- **Supabase** — hosts our database, authentication, and server functions.
- **OpenRouter** — routes our AI requests to the model provider that serves the
  model we have selected. Requests are made by our server, not your device, so
  the provider never sees your IP address or device. To build or adapt a plan we
  send your plan answers: goal, weeks, days available, equipment, and your injury
  notes if you gave any. To hold a conversation we send a written summary of your
  recent training and the messages in that conversation, as you wrote them — so
  if you told your coach about an injury, a symptom or how you are feeling, that
  text is sent. We never send your name, email, or account identifier, and we
  never send your progress photos. But we will not pretend the rest is anonymous:
  taken together it is health information about one person, and if you would
  rather it did not leave the app, turn the coach off in Settings or do not use
  it.

We do not sell personal data, and we do not use it for third-party advertising.

## The coach is optional and can be turned off

The coach is the only part of the app that sends anything to an AI provider.
Turning off **Use the AI coach** in Settings stops that entirely: no message, no
training summary and no plan answer leaves the app for OpenRouter. Logging,
plans you already have, photos and syncing all keep working. Nothing you have
already said is un-sent by turning it off, but you can erase what the coach
remembers from the same screen.

## Progress photos

Progress photos stay on this device. They are not uploaded, and backing up your
training does not include them. That means this phone is the only copy and
uninstalling the app loses them — the trade we let you make rather than make for
you, because a photo of your body is the most personal thing this app holds.

## Where data is stored

Your sessions live on your device, which is the copy the app actually works
from — it logs, reads and plans with no network at all. Signing in copies your
sessions to our Supabase project in eu-west-1 (Ireland). Data in transit is
encrypted with HTTPS/TLS.

## Your account

You do not need an account to track your training, and with no account nothing
leaves your phone at all. Signing in stores your sessions on our servers under
your MGKFitness account, which is the same account MGKFitness: Run uses. There is
no separate switch — **signing in is the switch.**

## Your rights

Under UK GDPR you can access, correct, export, or delete your data, and withdraw
consent. Delete account removes every record we hold for you — your sessions,
exercises and sets, your plans, your coach conversations and your usage records.
Your phone keeps its own copy until you uninstall.

**Deletion asks how much**, because your login is your MGKFitness account and it
is shared with MGKFitness: Run. Delete this app only, and we erase everything
this app holds; your account survives so Run keeps working. Delete your whole
account, and everything Run holds goes too, along with the login itself.

One thing the narrow choice cannot promise: if Run holds no data, there is
nothing left for the account to be for, so it is removed as well. We tell you
which happened rather than leaving you to find out.

## Retention

We keep your data while your account is active, and deletion removes it
immediately, except where we must retain limited records to meet legal
obligations. Two things expire on their own without you asking: usage records are
pruned after 31 days, long enough for the monthly fair-use window and no longer;
and coach conversations are kept so your coach remembers you between sessions,
then pruned after 180 days. The short rolling summary is what survives.

## Children

The app is not directed at children under 16 and we do not knowingly collect
their data.

## Contact

MGKCodes Ltd — hello@mgkcodes.com.

Controller: MGKCodes Ltd. We note the date this policy changes.
