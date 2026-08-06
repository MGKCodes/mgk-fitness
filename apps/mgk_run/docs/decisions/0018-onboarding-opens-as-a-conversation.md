# 0018 — Onboarding opens as a conversation, and the form comes last

**Status:** Accepted
**Extends:** [0017](0017-the-coach-is-the-entry-point.md)

## Context

[ADR-0017](0017-the-coach-is-the-entry-point.md) made the coach the way a runner
tells Runio anything. It did not change how a runner *arrives*, and arrival
contradicted it: welcome screen, then a form, then a data-privacy modal, then an
empty Home with the coach behind a button. The first three things Runio asked
for were an email, a password, and consent to store health data — none of which
it had yet earned, and none of which teach anything about how the app works.

A runner who reaches the coach after all that has to be told the coach exists.
A runner whose *first act* is talking to it never does.

The obstacle was that the coach cannot run before there is an account. Every
model call goes through an Edge Function authenticated with the runner's session
([ADR-0007](0007-secrets-via-backend-proxy.md)), so a pre-account conversation
needs anonymous auth — a project dashboard setting, an abuse surface, spend
against an unverified user, and rows in the `public.profiles` table Liftio
shares ([ADR-0008](0008-shared-supabase-platform.md)).

That obstacle turned out to be smaller than it looked, because **the questions
worth asking before an account exists are not questions a model is needed for.**

## Decision

**Runio opens with a scripted conversation in the coach's voice, and the sign-up
form is its last step.**

Three exchanges, none of which need a model:

| Asked | Why no model |
|---|---|
| What should I call you? | A name is not a format. Anything is accepted — every rule that rejects a name rejects somebody real — and a mistyped one is fixed on the confirmation screen at the end of intake, which is already editable. |
| What are you after? | This is [`PlanShape`](0011-a-plan-has-a-shape.md), the slot intake settles first. Four answers, offered as chips, so it **cannot** be answered wrong rather than needing an answer understood. |
| What this costs | A statement, not a question. |

Free text arriving where a choice was expected gets a scripted recovery — *"I
didn't quite catch that. Which of these is closest?"* — rather than a guess. It
cannot handle something genuinely novel ("London in April but I also do parkrun
every Saturday"); that is the accepted cost, and the model handles it one screen
later.

**The model arrives where the open questions are.** Weekly volume, longest run,
days that actually work, "Berlin in November", "I just want to get fitter" — all
of these live after sign-up, and all of them are where a runner really does
answer sideways. Intake starts seeded with the name and the shape, so the coach
opens on what it still needs instead of asking what they are training for a
second time.

### Consequences that follow

- **A bounce costs nothing.** An LLM-from-turn-one intake bills for everyone who
  opens the app and leaves. This bills for people who sign up.
- **No anonymous auth**, so no dashboard dependency, no unverified spend, and
  nothing written to the shared identity table before there is an identity.
- **The costs are stated before the form.** A cost discovered after signing up is
  a cost that was hidden. The copy is a placeholder — see below.
- **The shared login is named where it is relevant.** That Runio and Liftio are
  one account was previously first mentioned on the *delete account* screen,
  which is far too late to learn it.

### The pricing placeholder

There is no pricing yet. [ADR-0014](0014-model-is-chosen-per-surface-and-per-tier.md)
defines tiers architecturally and pins every runner to `free` until an App Store
entitlement exists, so there are no figures to quote, and inventing one would
ship a commercial claim nobody has agreed.

`introCostsCopy` in `lib/src/features/onboarding/domain/intro_script.dart` is
therefore true-but-vague, under a `PRICING — PLACEHOLDER` block naming
everywhere that has to change when the real thing lands.
`test/onboarding/intro_script_test.dart` asserts no figure or quota appears; it
is to be **replaced** when pricing is decided, not deleted.

## The obvious alternative

**Anonymous auth, and a real coach from the first word.** Genuinely better at
the one thing the script cannot do — a runner who answers in an unexpected way
gets a real reply rather than a re-ask.

Rejected for now on cost and blast radius rather than on principle: it needs a
setting only the project owner can change, it lets unauthenticated traffic spend
model budget, and it puts anonymous rows in a table another product reads. None
of that is worth buying an answer to a question that chips remove.

## Cost function

Judge this by whether runners use the coach *unprompted* after onboarding. The
whole argument for a conversation the app could have done as a form is that it
teaches what Runio is; if the coach is still something people have to be pointed
at a week later, the teaching did not happen and the conversation was decoration.

The counter-signal is the recovery line firing often. If runners routinely type
past the chips, they are trying to have a conversation the script cannot have,
and the alternative above stops being over-engineering.

## Disconfirming condition

Reverse this if sign-up completion drops. Three exchanges before the form is
three chances to leave, and the current arrangement is a bet that meeting the
coach makes people *more* likely to finish, not less. If it does not, the
conversation moves to after the form and becomes what it replaced.
