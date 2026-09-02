# 0017 — The coach is the entry point; completion is observed, not asserted

**Status:** Accepted

## Context

Home accumulated four ways to tell Runio something, and none of them was the
coach.

A **"Mark done" button** on the Today card. A **"Skip"** beside it. A
full-width **"Record a run"** slab under it. And, three taps away on Profile,
an **"Add a run"** form. Meanwhile the coach — the thing the product is named
for — floated over every screen as a mark you could tap to *talk*, and could
change nothing you said to it except the shape of a week.

Two of those four are actively wrong rather than merely redundant.

**"Mark done" is a claim no run backs.** It writes a status string and nothing
else. `plan_sessions` has carried a nullable **`runId`** column since the schema
was written — a session pointing at the run that fulfilled it — and nothing in
`lib/src/features/` has ever written it. So a session could be "completed" with
no run anywhere in the log, which is why marking a session done never made it
into anyone's history. The app was storing an opinion about the past.

Runio already knows this is wrong, in writing. From `plan_headline.dart`, on how
a rhythm counts turn-ups:

> Deliberately not "sessions marked complete" either: a runner who turned up and
> ran has turned up, whether or not they later tapped a button about it.

That is the correct rule. It was applied to one shape and contradicted on Home.

**The four entry points also disagree about the coach.** `AdaptationService`
proposes a revised week, the validator disposes, the runner approves — and there
were two doors to it. One went through the conversation, keeping the exchange in
the transcript. The other threw a modal sheet over the screen. `home_shell.dart`
records why the first exists:

> A runner who asked for a change in a sentence had to leave the conversation to
> agree to it, and the transcript kept no record of what they agreed — so next
> week, when they wondered why Sunday moved, there was nothing to look at.

A Home control added later routed straight back to the modal, which is how a
deliberate decision gets undone by someone who did not know it had been made.

## Decision

**Everything the runner tells Runio goes to the coach, except live tracking.**

That is the line, and it is not a preference. A GPS session is a device
capability with a start and a stop; it cannot be a sentence. Everything else a
runner has to say — *I ran on the treadmill, I'm ill, my calf hurts, I only have
half an hour, did I do enough this week* — is language, and the app already has
something that understands language.

Three consequences follow.

### 1. Completion is observed

A prescribed day is **done** when a run exists on that date. Not when a button
was tapped. The match writes `runId` onto the session, so completion is
auditable rather than asserted, and a run deleted later takes its completion
with it.

A run on the day satisfies the day. **No distance tolerance**, deliberately:
telling someone who ran 8.5 km of a prescribed 9 km that they missed it is the
app being right about a number and wrong about a person. Shortfall is something
the coach can raise in a sentence; it is not grounds for the app to score the
day as a failure.

The derived states are:

| State | Rule |
|---|---|
| **done** | a run exists on that date |
| **today** | the date is today — never missed, they may still run tonight |
| **upcoming** | the date is in the future |
| **missed** | the date has passed, no run, not skipped |

Derived on read, never stored — the same reason `shapeOf()` derives rather than
stores. A stored completion is one more field that can disagree with the log it
describes.

### 2. A miss is raised, never silently absorbed

A real coach neither rewrites your program behind your back nor says nothing.
Runio does what they do: notices, says so, offers.

The response is **graduated**, because reacting equally to everything is what
makes an app feel like a nag rather than a coach:

| What happened | What Runio does |
|---|---|
| One easy run | Carries it in the brief. No prompt, no plan change. |
| A key session — long run, threshold | Raises it; that is the session the block hangs on |
| Two or more in a week | Offers to rebalance what is left |
| A whole week | A conversation about the block, not the week |

The prompt asks the question a coach asks first — *did you actually do it?* —
and both answers hand to the coach:

```
You missed Tuesday's 8 km easy.
[ I ran it ]  →  "I did run Tuesday's 8k, it just wasn't tracked"
[ Adjust   ]  →  "I missed Tuesday — rebalance what's left"
```

The first reaches the `log_run` surface, which turns it into a `RunDraft` the
runner confirms. The second reaches `proposeAdaptation`. Both land in the
transcript, so next month "why did Sunday move?" has an answer.

**Nothing rewrites a plan without approval.** The detection is deterministic
Dart, the proposal is the model's, the validator disposes, and the runner has
the last word — [ADR-0003](0003-llm-generates-validator-enforces.md) end to end.

### 3. The Coach tab becomes the Plan tab

The tab was named for a conversation that no longer lives in it. The dock it was
built around was replaced by a mark floating over all three tabs, precisely so
the coach would stop being a feature of one screen. What remains under that
label is the headline, the current week, the arc and the calendar — a plan.

`PlanScreen` was already taken by the block arc, which becomes `PlanArcScreen`.
Everything named `coach_*` that is genuinely the conversation — the client, the
controller, the transcript, the mark — keeps its name.

**Amended, 2026-09-01 — the entry point to coaching, not to the app.**
[ADR-0030](0030-the-coach-is-the-paid-half.md) makes the coach the paid half on
both apps, so it is no longer what a runner meets first. That job moved to the
scripted intro when onboarding split in two
([ADR-0019](0019-onboarding-is-two-moments.md)), and this record predates both.

What survives is the argument this ADR actually makes: that coaching is a
conversation rather than a form, and that completion is observed rather than
asked for. What does not is the literal reading — a runner without a
subscription now meets a working tracker, and the coach is a door with a price
on it.

## Consequences

**The form does not go away.** The coach needs the network
([ADR-0007](0007-secrets-via-backend-proxy.md)); recording and manual entry must
not ([ADR-0004](0004-offline-first-local-source-of-truth.md)). "Add a run" is
the deterministic path for a runner in a tunnel, and it stays for that reason
alone — demoted from a primary way in to a fallback, not deleted. A build with
no coach reachable is degraded, not broken.

**Home loses its run log.** Recents duplicated Profile, which owns the log. The
week ribbon absorbs the job it was actually doing — *am I on track* — now that it
has real outcomes to draw instead of a single status for today.

**The status write path stays.** `markToday` / `setStatusOn` remain on the
repository for an explicit skip the coach records on the runner's behalf. What
goes is the UI asserting completion; the seam survives.

**Voice costs nothing structurally.** In-run audio is deferred
([ADR-0006](0006-in-run-audio-deferred.md)), but when it lands it is the same
conversation with a different input device. That is the main reason to put the
entry point in language rather than in buttons now, while the buttons are cheap
to remove.

## The obvious alternative

Keep the buttons and let the coach be one input among several.

Rejected because the four entry points were already contradicting each other,
and the contradiction is not cosmetic: a session marked done with no run behind
it corrupts every measure built on the log — the coach's brief, the readiness
assessment, a rhythm's turn-up count. An app that lets you lie to it about your
training is not coaching you, and the lie was one tap away on the front page.

## Cost function

Judge this by whether a runner can go a full week telling Runio nothing except
by talking to it and pressing start — and end that week with a plan and a log
that both match what actually happened.

The counter-signal is a new button that writes training state. If one appears on
Home, this decision has been made and then not kept.

## Disconfirming condition

Reverse this if the coach turns out to be unreliable enough at extraction that
runners routinely have to correct it. The whole decision rests on "I ran 6k in
35 minutes on the treadmill" landing correctly more often than a form would —
if `RunDraft.issues` is firing constantly, or runners abandon the sentence and
go looking for the form, then language is the wrong primary and the buttons
should come back.
