# 0002 — A coach conversation is a session, bounded by silence

**Status:** Accepted

## Context

This follows mgk_run's
[ADR-0025](../../../mgk_run/docs/decisions/0025-a-coach-conversation-is-a-session.md),
and the decision to wait for it was recorded in the Lift 2.0.0 punch list on
2026-08-24: *"wait and copy the run app's model. Designing it twice is the more
expensive mistake."* That model now exists, so this is the copy.

The bug it was written about was found in the field, in the run app. A runner
asked the coach about their previous run and it answered:

> You ran 10 km in 60 minutes yesterday.

The log was empty. **That was not a hallucination** — the run was real, logged
through chat a week earlier. There had only ever been one conversation, so a
sentence from last Tuesday sat in the transcript with nothing distinguishing it
from something said a moment ago. The model did the reasonable thing with an
undated pile of recent-looking context and read it as current.

Two things follow, and they are general rather than about running.

**Time in a prompt is positional, not absolute.** A model has no clock. Anything
in its context that is not explicitly dated is dated by where it sits, and
everything in a transcript sits under "this conversation".

**Every session boundary the app does not have is a chance to answer
confidently about the wrong week.**

### Lift had the identical defect, and said so out loud

`SupabaseCoachTranscript` carried this doc comment:

> The conversation is addressed rather than looked up. Lift keeps exactly one
> per person, and the function derives its id the same way — `lift:<user id>`

and queried `.eq('conversation_id', 'lift:$userId')`. The Edge Function's
`conversationId(app, userId)` returned the same string, with its own reasoning:

> Lift keeps one, because nothing in its design asks for a boundary: the summary
> is what survives, the last N turns are what get replayed, and neither is
> improved by knowing which visit a turn came from.

That is the argument this decision overturns. The last N turns being replayed is
not neutral — it *is* the mechanism. Lift's version of the bug is a shoulder
complaint from last month read as this morning's.

### Where lift differs from run, and why the copy is not a port

The model is identical. The implementation cannot be, because the two apps store
a transcript in different places.

|  | run | lift |
|---|---|---|
| Owns the transcript | the client, in Drift, mirrored to Supabase | the server, in `coach.turns` |
| Sends per turn | the history it holds | one line: surface and message |
| Reads history | locally | the Edge Function reads it under the caller's JWT |

So run enforces the boundary in a `ChatController` over its own store, and lift
cannot: the function replays whatever it finds under the id it derives. The
boundary has to reach the thing doing the replaying.

The schema needed nothing. `coach.conversations` has carried `id`, `app`,
`started_at` and `last_turn_at` since the memory was built, and it is shared by
both apps. As in run: **the gap was policy and UI, not storage.**

## Decision

**A conversation ends when nothing has been said in it for 30 minutes. The
client owns the id, sends it with every turn, and the function derives
nothing. Past conversations are kept and readable.**

### The boundary is a gap, not a lifecycle event

`coachSessionWindow` is a duration measured from the last turn:

- On open, `openConversationId(window:)` asks *what is still open* rather than
  *what was last spoken in*. A conversation whose last turn is outside the
  window is not restored at all.
- On return to the foreground, the same comparison runs against the newest turn
  on screen. Nothing is torn down — the turns stay visible, because a transcript
  vanishing while somebody is looking at it is a worse surprise than the coach
  starting fresh. What changes is where the next thing said goes.
- Inside the window everything continues as before.

One rule covers the cold start, the trip to the home screen, and the lifter who
never closed the app. Thirty minutes is deliberately short, and the asymmetry is
the argument: ending one too eagerly costs context the rolling summary largely
covers, and ending one too late is the answer at the top of this document.

### The id is the client's, and the derivation is deleted

`newCoachConversationId()` is pure and knows nothing about who is signed in —
the function writes `user_id` from the verified JWT, so the id only has to be
unique. `conversationId(app, userId)` is **removed** rather than kept as a
fallback: two ways to answer "which conversation?" is how the wrong one gets
reached for again.

This is not a new trust boundary. The id names a row; `user_id` comes from the
JWT and RLS owns the rest, so a client naming somebody else's conversation
writes nothing. A request with no `conversation` is a `400` rather than a
silent fallback to the old behaviour.

### A question the lifter did not type always starts one

A tapped suggestion is a subject the *screen* raised, arriving with its own
topic. Continuing into it is how a half-finished exchange about a sore shoulder
becomes the context for "how has my training been going". The wheel under a
question is not one of these — it answers what was just asked, and belongs to
the conversation asking it.

### Old conversations are read, not replayed

`PastConversationsSheet` lists them and `PastConversationScreen` reads one back,
with no composer and nothing that loads one into the live conversation.
Reopening an old transcript to write into it is the endless chat this ends.

**Lift stops here, and run goes one step further.** Run also feeds old
conversations back through *recall* — queried not replayed, live conversation
excluded, only the runner's own words, four turns each dated. Lift has no
recall: `coach.turns` is read by the Edge Function, and adding a search over it
is a function change with its own failure modes. The rolling summary is what
survives a boundary here, which is the tier lift already has. **Named as a
limit rather than an omission**, and the next thing to copy from run.

## Consequences

**Now is the only free moment to do this.** The function's own comment warned
that changing the id *"silently orphans every turn written by the other"*. There
is nothing to orphan: `coach.turns` holds one conversation and it is
`app = 'run'`. There has never been a single `lift:` conversation, because the
paid half has been gated by an empty `core.entitlements` since launch. After the
first shipped build this becomes a migration.

**The coach re-establishes context more often.** That is the intended cost. The
summary carries what matters across a boundary, and a coach that asks again is
better than one that answers confidently about the wrong month.

**A conversation with no turns is never listed.** A `conversations` row with no
readable turns is what a failed write leaves behind, and listing it offers to
open an empty screen.

**`dayLabel` is duplicated, deliberately, and it is written down here so it is
a debt rather than an accident.** Both apps date these rows and should date them
identically, so the helper belongs in `mgk_ui`. It cannot go there yet: mgk_run
declares its own `dayLabel` in `chat_widgets.dart`, and `coach_conversation.dart`
and `coach_history_sheet.dart` both import that *and*
`package:mgk_ui/mgk_ui.dart`. Exporting the name from the shared package makes
those ambiguous imports and stops the run app compiling the moment the branches
meet — a break with no textual merge conflict to warn anybody. Consolidating
needs both apps in hand at once, which is a cross-lane change this plan does not
make. Lift's copy therefore sits in `coaching/presentation/day_label.dart`.
