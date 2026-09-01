# How your coach uses AI — MGKFitness: Lift

> **Draft — legally unreviewed.** Accurate as built: every claim below was
> checked against `supabase/functions/coach/` and the app's own coach code
> rather than written from intent. Open before submission:
>
> 1. **Legal review** of this document.
> 2. **A processor agreement with OpenRouter** covering special-category data.
> 3. **Whether the configured `COACH_MODEL`'s provider trains on inference
>    inputs.** A per-model property, so changing the model can change the answer.
>    Until it is confirmed, this document does not claim either way.

Apple Guideline 5.1.2(i) requires that a person knows their data is going to a
third-party AI service before it goes. This is that disclosure, and it is
reachable from the coach itself as well as from Settings › Privacy & legal.

> The in-app copy lives in `lib/src/features/legal/domain/legal_copy.dart`.
> **Change both together** — a regression test
> (`test/legal/legal_copy_test.dart`) fails if they drift.

## Who answers when you talk to your coach

Your coach is a large language model, not a person and not something we wrote. We
send your request to **OpenRouter**, which routes it to the provider that serves
the model we have selected, and that provider generates the reply.

The request is made by our server, not by your phone. The provider never sees
your IP address, your device, your name, your email or your account identifier.

## What we send

- The messages in the conversation, **as you wrote them.**
- A short written summary of your recent training — the sessions you logged,
  what you lifted, and how much.
- When you ask for a plan: your goal, how many weeks and days a week you can
  train, which days those are, the equipment you have, and **your injury notes if
  you gave any.**

## What we never send

- Your name, email address, or account identifier.
- Your progress photos.
- Any part of the app you use without the coach — logging a session sends
  nothing.

## Say it plainly

Your messages are free text. If you tell your coach about an injury, a symptom,
your weight or how you are feeling, that text is sent to a third-party AI
provider. We do not send anything that names you, but we will not pretend the
rest is anonymous: taken together it is health information about one person.

## Turning it off

**Use the AI coach** in Settings turns this off completely. With it off, nothing
in this document happens — no message, no training summary and no plan answer
leaves the app for OpenRouter. Logging, plans you already have, your photos and
syncing all keep working.

Turning it off does not un-send what you have already said. You can erase what
the coach remembers under Settings › Coach, and Delete account removes your
conversations along with everything else.

## How long it is kept

Coach conversations are kept so your coach remembers you between sessions, then
pruned after 180 days. The short rolling summary is what survives. Usage records —
which part of the coach a request came from, its tokens and its cost, with no
message content — are pruned after 31 days.

## Contact

MGKCodes Ltd — hello@mgkcodes.com.
