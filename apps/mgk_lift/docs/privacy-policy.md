# Privacy Policy — MGKFitness: Lift

<!-- NOT FOR PUBLICATION — repo notes. HTML comments do not render, so this
     block is safe in the file that gets published.

     Ships without legal review, by decision (docs/submission-week.md, decision 3).
     The data flows below were checked against the code and the schema rather than
     written from intent, which is what makes that decision defensible rather than
     merely fast.

     Two things remain open and BOTH could change what this policy has to say:

       1. A processor agreement with OpenRouter covering special-category data.
       2. Whether the configured COACH_MODEL's provider trains on inference
          inputs. A per-model property, so changing the model can change the
          answer, and this document deliberately claims neither way until it is
          confirmed.

       3. What the RevenueCat SDK collects on its own account. We pass it an
          account identifier and nothing else, which is the claim made below,
          but a purchase SDK typically also collects an install identifier, a
          store country and an OS version for itself. Check its privacy
          manifest before filing the App Store's privacy labels. Same open item
          as Run's policy, because it is the same SDK.

     RevenueCat was named here on 2026-09-29, in the commit that wired it.
     test/legal/legal_copy_test.dart fails if a processor reaches the pipeline
     without reaching the reader; do not silence it by editing the list without
     editing the policy.
-->

**Last updated:** 1 October 2026 · **Controller:** MGKCodes Ltd · **Contact:**
lift@mgkfitness.mgkcodes.com

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

- **Account data** — your email address and an account identifier. If you sign
  in with Apple or Google, that is what they pass us too: an email address and
  an identifier, and nothing else. We do not ask either for your name or
  photograph. With Apple's Hide My Email, the address is one Apple forwards to
  yours, and we never see the real one.
- **Training data** — the sessions you log: exercise names, sets, reps, weight,
  set type, and for cardio work its duration and distance. Session and exercise
  notes are free text you wrote, so they hold whatever you chose to put there.
- **Progress photos** — the photos you take, the week and pose you filed them
  under, and any note against them. Part of the paid tier; see *Progress photos*
  below.
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
- **Subscription status** — if you subscribe: which tier you hold, whether it is
  active, and the store's record of the purchase (the product, its dates and the
  store's transaction identifier). It reaches us from RevenueCat, below. We never
  see your card or payment details.

We collect only what the training product needs (data minimisation).

## Health data

Your training, your injury notes, and what you tell your coach about your body
are health data — special-category data under UK GDPR. We process it to provide
the logging and coaching service you request (the lawful basis is your consent,
which you can withdraw by deleting your data).

## Who we share it with

- **Supabase** — hosts our database, authentication, and server functions.
- **Apple and Google** — only if you sign in with them. They confirm who you
  are and pass us an email address and an identifier; we tell them nothing
  about your training. On an iPhone, deleting an account made with Apple asks
  Apple to confirm first, so that when the login goes we can also end the app's
  access to your Apple ID.
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
- **RevenueCat** — handles subscription purchases on the App Store and Google
  Play, and tells our server whether yours is active. We send it your account
  identifier and nothing else: no training, no photos, and nothing you said to
  your coach. Like any purchase SDK it also collects technical information of
  its own about the install, such as a device-scoped identifier, your store
  country and your app version.
- **SMTP2GO** — sends the emails your account needs: the link to confirm your
  address when you sign up, the link to reset your password, and a note when
  your password changes. It receives your email address and the email itself,
  through its servers in the EU, and nothing about your training. Its open and
  click tracking are turned off.

We do not sell personal data, and we do not use it for third-party advertising.

## The coach is optional and can be turned off

The coach is the only part of the app that sends anything to an AI provider.
Turning off **Use the AI coach** in Settings stops that entirely: no message, no
training summary and no plan answer leaves the app for OpenRouter. Logging,
plans you already have, photos and syncing all keep working. Nothing you have
already said is un-sent by turning it off, but you can erase what the coach
remembers from the same screen.

## Progress photos

Progress photos are part of the paid tier. They are stored on your phone and
copied to a private storage bucket in our Supabase project, where only your
account can read them.

**They are never sent to the coach or to any AI provider.** That is the one
promise on this page we would have to change code to break, and it is the reason
the photos and the coach are kept apart in the first place.

Deleting a photo removes it from both, immediately. If your subscription ends
the photos you already have stay, and you can still look at them and delete
them; only taking new ones stops. Delete account removes them from our servers,
the picture files included, whether you delete only this app's data or your
whole account.

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

You can sign in with Apple, with Google, or with an email address and a
password. Choosing Hide My Email with Apple starts a separate account, because
the address Apple gives us is not one any other account uses.

## Your rights

Under UK GDPR you can access, correct, export, or delete your data, and withdraw
consent. Delete account removes every record we hold for you — your sessions,
exercises and sets, your plans, your progress photos, your coach conversations
and your usage records. Your phone keeps its own copy until you uninstall.

**Deletion asks how much**, because your login is your MGKFitness account and it
is shared with MGKFitness: Run. Delete this app only, and we erase everything
this app holds, your progress photos included; your account survives so Run
keeps working. Delete your whole account, and everything Run holds goes too,
along with the login itself.

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

MGKCodes Ltd — lift@mgkfitness.mgkcodes.com.

Controller: MGKCodes Ltd. We note the date this policy changes.
