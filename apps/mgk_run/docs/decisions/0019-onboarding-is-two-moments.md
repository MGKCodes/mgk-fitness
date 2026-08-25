# 0019 — Onboarding is two moments, and only the second one is about a plan

**Status:** Accepted
**Extends:** [0018](0018-onboarding-opens-as-a-conversation.md), [0017](0017-the-coach-is-the-entry-point.md)

## Context

[ADR-0018](0018-onboarding-opens-as-a-conversation.md) made arrival a
conversation: a scripted exchange in the coach's voice, with the sign-up form as
its last step. That was right and it stays. What it did not question was the
*assumption underneath* the exchange — that everybody arriving at Runio wants a
training plan, and wants it now.

Three things followed from that assumption, and all three were wrong.

**A plan was the price of finishing sign-up.** `HomeShell` took a
`startOnboarding` flag and, the instant the shell mounted, pushed the whole plan
flow over Home. A runner who had just made an account did not land in Runio;
they landed in an interview. The flow's close button was the only way to say
"not yet", and a close button is a strange thing to have to find on your first
screen.

**The shape question was asked before it could matter.** "What are you after?"
was the second thing Runio ever said, before an account existed — so the answer
had to survive the widget swap that replaces the signed-out subtree with the
shell. `auth_gate.dart` carried a field, a callback and a paragraph of
explanation for exactly that, and `home_shell.dart` carried a matching parameter
to hand it on. Three files coordinating to move one enum across a boundary that
only existed because the question was asked too early.

**The free product was never designed, because it was never named.** Home for a
runner without a plan was a plan-Home with nothing in it. That reads as broken
rather than as a product, and it is the screen somebody decides on.

Pricing is what forced the issue. A plan is the expensive thing — it is
`skeleton` plus a `week` call per week of the block, and it is what a
subscription has to pay for
([ADR-0015](0015-spend-is-capped-over-three-windows.md) sizes its ceilings
against a monthly subscription). Recording and logging runs cost nothing to run
and work offline by construction
([ADR-0004](0004-offline-first-local-source-of-truth.md)). The commercial line
and the technical line are the same line, and onboarding was drawn across it.

## Decision

**Onboarding is two moments. The first is free and ends with an account. The
second is entered only when a runner asks for a plan.**

### Moment one — after install

| Step | What happens |
|---|---|
| Greeting | Hello, what it is (an AI, called Coach), and what the app does |
| Name | What to call them. Anything accepted |
| Permissions | One at a time: explained, then **the real OS dialog**, then answered |
| Sign-up | The shared account |

It ends on Home, with a working run tracker. Nothing in it asks what the runner
is training for, and nothing in it mentions money, because neither is relevant
to anything it delivers.

### Moment two — when a plan is asked for

Medical disclaimer → **the shape question** → the LLM intake, seeded with name
and shape → the editable confirmation → the plan.

The disclaimer stays first *within* the flow for a commercial reason as well as
a legal one: when the paywall lands it goes in front of this route, and a runner
who pays and only then meets a disclaimer they decline is a refund.

### Permissions are asked here, one at a time, for real

The coach explains one permission, the runner taps, **the real OS dialog
appears**, and the coach says something about whichever way it went before
moving to the next.

The considered alternative was to explain here and let each dialog fire at the
moment of first use — the textbook iOS advice, and what this ADR said in its
first draft. It is wrong for Runio for a reason the textbook does not cover:
the first thing a runner does after onboarding is *press start*, and a
permission sheet landing on top of a run they are trying to begin is worse than
one asked by a coach that has just explained itself. Deferring does not avoid
the interruption, it relocates it to the least convenient moment the app has.

What made the textbook advice right is kept: nothing is asked cold. The
explanation still comes first, it is still in the runner's terms rather than
the API's, and asking them one at a time means two system dialogs never arrive
back to back looking like a toll.

**Both answers get a reply, and a refusal is never an error.** A denied
permission is a shape the app is built for, not a failure it recovers from, so
the refusal copy says what still works and where to change their mind. A runner
who declines has made a choice; being scolded for it by a coach they met ninety
seconds ago is how an app gets deleted. `intro_permission_test.dart` asserts
the refusal names Settings and contains none of *sorry*, *unfortunately*,
*error*, *required*.

**Two permissions are asked: location, then Health.** Location first because it
is what recording needs, so it is the one worth spending the runner's patience
on. Health second because it is an enhancement — a runner who declines simply
starts from an empty log.

**Both requests are real, since 2026-08-21.** They were stubbed when this ADR
was written — the conversation was built first and the platform calls behind it
returned "granted" without asking anything, because the shape of the exchange
was what was being designed and neither call could be verified from the Windows
harness this repo is developed on.

That has landed. Location goes through `geolocator`, reading the current state
before asking so a runner who granted it on a previous install is not asked
again. HealthKit goes through `health: 13.2.0`, and `true` from it means "the
sheet was answered" rather than "reads were allowed" — iOS refuses to say which
reads it granted, by design, so the coach's reply is written not to over-claim
on the strength of it.

The warning this section used to carry — that wiring HealthKit was a release
blocker, because asking for authorisation to data the app never reads is an App
Store rejection — is discharged, not dropped. It was correct, and it was acted
on. It is recorded here because the notice in
`intro_permission_requester.dart` went on claiming the work was outstanding
long after it was done, which is a more expensive kind of staleness than a
missing note: it sent a reader looking for a blocker that did not exist.

## Amendment, 2026-08-21 — signed in is not onboarded

This ADR assumed the two were the same, and while sign-up and onboarding were
one moment they were. They are not any more, and the assumption had already
started costing: an existing session survives an app update, so the
conversation simply did not run.

The case that matters is not that one. It is a runner who makes their profile
in **Lift** and then installs this app. They arrive signed in, having never met
this coach, and under a shared profile that is the growth path rather than an
edge case. They would have landed in the shell — and then met the location
dialog on top of the first run they tried to start, because
`GeolocatorLocationSource` asks at recording time when it has not been granted.
That is the exact scenario the section above rejects, reached by a door this
ADR did not know it had left open.

So the gate no longer asks "signed out?". Each step is asked whether it is
already satisfied, because the steps do not share a lifetime:

| Step | Belongs to | Skipped for an arrival from Lift |
|---|---|---|
| Meet the coach | this app | No — a different coach, never met |
| Name | the profile, shared | **Yes** — already on it |
| Permissions | **the install** | No — and a new phone needs them again |
| Profile | the profile, shared | **Yes** — they have one |

Two rules hold this together:

- **Only "met the coach" is persisted**, in auth metadata, namespaced per app
  (`run_intro_seen`). Metadata for the same reasons the name uses it: it travels
  with the account, needs no migration, and arrives with the session. Namespaced
  because the profile is shared and meeting a coach is not.
- **Permission state is never persisted.** The OS is the only honest source and
  it can be revoked behind the app's back, so it is asked every time. The
  requester already reads the current state before prompting, so an
  already-granted permission answers itself without a dialog.

Note what this does not do: nothing is backfilled. Every existing account will
see the conversation once more, on next launch. That is deliberate rather than
overlooked — the app is not released, the accounts are testers', and inventing a
backfill heuristic for a userbase of a handful is more code and more ways to be
wrong than the thing it saves.

Still open: Settings replays the intro to re-ask permissions and has no `auth`
to hand, so it still asks for a name the profile already knows. Harmless, and
the same skip applies once the section is given one.

## The obvious alternative

**Keep one flow and put the paywall in front of all of it.** Simpler to build,
and it means every account is a paying account.

Rejected because it prices the free product at the moment nobody has seen it
work. Runio's cheapest and most defensible claim is "press start and I track
your run" — a claim it can make offline, for nothing, to somebody who has not
decided anything yet. Charging before that claim has been demonstrated throws
away the only part of the app that costs nothing to give away.

## Cost function

Judge this by whether a runner who never buys a plan still has a coherent app —
one that records, logs, remembers and answers, and never reads as a demo of
something better. If free Home still looks like a paid Home with the contents
removed, the split was administrative rather than real.

The counter-signal is a plan-shaped hole appearing on a free screen: an empty
week ribbon, a disabled Plan tab, a "no plan yet" placeholder where a card
should be. Each one is the old assumption growing back.

### Amendment, 2026-08-25 — a locked stat is not a hole, if it is a stat you never had

This section, read literally, forbids the thing Home now does: a greyed
*Upgrade to see this stat* block, on a free screen, where a card would be. That
reading is too broad, and the line it was drawing needs restating rather than
enforcing.

**What the counter-signal is actually about is subtraction.** Every example it
gives is a thing the runner *has* — their week, their plan tab, their own
training — presented as an absence in order to sell it back. A free Home that
is a paid Home with the contents removed teaches a runner that they are using a
crippled product, and that is what makes the split administrative.

The comparison against a coach's session is not that. It is not the runner's
data with something taken out; it is **a second reading laid on top**, and it
does not exist at all unless a coach set the session. So the rule the two cases
separate on:

| | Free shows | Locked |
|---|---|---|
| The runner's own numbers — distance, pace, time, history, the year | Everything | Nothing, ever |
| The coach's reading of them — asked versus ran | — | The whole comparison |

**A tracker that hides your own pace behind a paywall is not a tracker**, and
nothing in the free product is a preview of a better one. What is sold is the
coach, which is what [ADR-0014](0014-model-is-chosen-per-surface-and-per-tier.md)
and this ADR's own consequences already say the subscription buys.

Two rules keep this honest, and both are asserted in `test/home/last_run_test.dart`:

- **A runner with no plan is never shown the lock.** With no session there is no
  comparison to sell, and an upgrade prompt on that screen would be an advert
  where a fact should be — which *is* the counter-signal above, exactly.
- **The lock states what is behind it.** The rows are drawn in the shape they
  will take, dimmed, with the offer named. A blurred rectangle tells a runner
  they are missing something without telling them what of, which is a worse
  offer and a ruder one.

Nothing sets the paid value yet. `CoachAccess` defaults to `free` and resolves
every unknown answer to `free`, for the reason ADR-0014 gives about tier
parsing, applied to the client: a bug must not hand out what nobody bought.

## Disconfirming condition

Reverse this if runners create accounts and never reach moment two. The whole
bet is that a working free tracker earns the plan conversation better than an
interview does. If the plan flow is entered far less often than sign-up used to
complete it, then forcing the interview was doing real work, and the honest
response is to put it back in front rather than to keep the split and add
nagging.

## Consequences

- **`introShape` is deleted end to end.** The field on `AuthGate`, the
  `onIntroShape` callback, and `HomeShell.introShape` all go. The question is
  asked one screen before the intake that consumes it.
- **`startOnboarding` becomes `justSignedUp`** and no longer pushes anything. It
  still marks the new-account road, which skips a restore of data that cannot
  exist yet.
- **The backup consent question is not asked in the first session.** It used to
  follow the forced plan flow; with nothing forced, the ordinary path picks it
  up on the next launch, by which time the runner has used the app — which is
  what [ADR-0012](0012-backup-is-consented-restore-only-adds.md) wanted. Asking
  it after the first *recorded run* would be better still and needs a hook that
  does not exist.
- **`introCostsCopy` becomes `planGateCostsCopy`** and moves to the gate, with
  its `PRICING — PLACEHOLDER` block intact. ADR-0018's principle survives the
  move: the cost is stated before the commitment, and the commitment is now the
  purchase rather than the form.
- **The plan reveal finally has somewhere to live.** Onboarding used to end by
  `pop`-ing a value back to the tab that launched it, so there was nowhere to
  put a moment. A flow that a runner chose to enter can end in one.
- **`PlanShape.log` stays on offer inside the paid flow**, which looks wrong
  until you see what the paid tier actually is. "Just record my runs / No plan
  needed" describes exactly what moment one delivers for free, so offering it
  to somebody who has just tapped *Build a plan* reads as the free tier wearing
  a plan-shaped costume.
  It is not, because **the subscription buys a coach, not a plan.** A paying
  runner gets the coach without ads; a free one watches an ad to unlock a
  conversation. So "record my runs, no plan, and a coach I can talk to
  whenever" is a real thing to be paying for, and a runner who wants that must
  be able to say so. The chip stays.
  This lands properly when payment does; until then every runner is pinned to
  `free` ([ADR-0014](0014-model-is-chosen-per-surface-and-per-tier.md)) and the
  distinction is invisible.
- **The coach got one mark.** The floating button was a C and every surface the
  coach actually spoke from — the chat bubble, the session brief, the note on
  Home, the standing on Profile, the note after a run — was
  `Icons.auto_awesome`. Two marks for one coach, with the considered one on the
  button nobody reads and the universal chatbot badge on everything they do.
  `CoachLetter` is now the only one.
- **The sign-up line stopped selling sync.** It said an account "keeps all of
  this yours on any phone", which is a cross-device pitch, and cross-device is
  not why anybody makes an account ninety seconds into a running app. It was
  also not true by default: backup is opt-in and off until asked for
  ([ADR-0012](0012-backup-is-consented-restore-only-adds.md)), so the promise
  outran the product. It now says what the account is actually for.
- **The counter-signal fired, and not from the plan side.** The cost function
  above watches for a plan-shaped hole; what appeared was a run-shaped one. A
  runner with nothing recorded opened Profile to a single "No runs yet" card
  over bare background — every other section on the page hidden behind an
  `isEmpty` guard, including the coach's own read of them. Read against this
  ADR that is the same failure with a different noun: a free screen announcing
  its own emptiness instead of showing what the free product does. Fixed
  2026-08-24 by giving each section an empty state rather than a fork, with
  every figure held open as a dash. The general rule it leaves behind, for the
  next screen somebody builds for a runner on day one: **a screen with no data
  states its structure, and a dash is an absence where a zero would be a
  claim.** Hiding a section is only right when the section is about something
  that may never exist — past plans, for instance, which a runner on their
  first has not got and is not waiting for.
- The entitlement work that gates moment two is not decided here. It needs a
  verified App Store transaction rather than anything the client can assert
  ([ADR-0014](0014-model-is-chosen-per-surface-and-per-tier.md)), and it wants
  its own ADR once pricing is agreed.
