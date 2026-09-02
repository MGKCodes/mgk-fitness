# 0025 — A coach conversation is a session, bounded by silence

**Status:** Accepted

## Context

During the first field test the runner asked the coach to look at their previous
run. It answered:

> You ran 10 km in 60 minutes yesterday.

The log was empty at the time, and **this was not a hallucination**. That run was
real. It had been logged through the chat's add-run intent **a week earlier**,
while the natural-language logging path was being tested. The coach recalled
something true and placed it yesterday.

Which makes it a more useful bug than an invention would have been, because it
is diagnostic rather than random. There was only ever **one conversation**.
`ChatController.restore()` called `CoachMemoryRepository.lastConversationId()`
on every launch and picked up whatever was last spoken in, unconditionally:

```dart
final id = await memory.lastConversationId();   // chat_controller.dart:219
```

So a transcript begun last Tuesday was still being appended to on Thursday, and
every turn of it went to the model as chat history with nothing distinguishing
the sentence from ten minutes ago from the one from nine days ago. The model did
the reasonable thing with an undated pile of recent-looking context: it read it
as current.

Two things follow from that, and they are separable.

**Time in a prompt is positional, not absolute.** A model has no clock. Anything
in its context that is not explicitly dated is dated by where it sits, and
everything in a transcript sits under "this conversation". A week-old sentence
in a live transcript is not stale data the model could notice and discount; it
is indistinguishable from something said a moment ago.

**Every session boundary the app does not have is a chance to answer
confidently about the wrong week.** The coach was not confused about the run. It
was confused about *when*, and a conversation with no end never supplies a when.

### What already existed

Almost all of the storage. `CoachConversations` has carried `id`, `kind`,
`startedAt` and a denormalised `lastTurnAt` since the memory was built — with a
doc comment saying `lastTurnAt` exists so that listing recent conversations is
an indexed lookup rather than an aggregate. `CoachTurns` is append-only with an
explicit `seq`. `CoachMemoryRepository.recall(query)` was built, documented as
*"the 'read it only when asked' half of tiered memory"*, given its own
swappable-for-semantic-search seam — and **never called by anything**.

The gap was policy and UI, not schema. Nothing here changes a table.

## Decision

**A conversation ends when nothing has been said in it for 30 minutes. Past
conversations are kept, readable, and reachable only through recall.**

### The boundary is a gap, not a lifecycle event

`coachSessionWindow` is a duration, and the rule is measured from the last turn:

- On launch, `restore()` asks `openConversationId(window:)` rather than "what
  was last spoken in". A conversation whose last turn is inside the window is
  picked back up; anything older is not restored at all.
- On return to the foreground, `endStaleConversation()` applies the same
  comparison and closes the conversation if the gap has passed.
- Inside the window, everything continues as before. The dock keeps its
  transcript, the same conversation id keeps being written to.

One rule covers the cold start, the resume from background, and the runner who
never closed the app at all. A runner who checks a notification and comes back
in ten seconds has not started a new conversation; one who comes back after the
school run has.

Thirty minutes is a judgement call and is deliberately short. The cost of ending
a conversation too eagerly is that the coach re-establishes context it already
had, which the rolling summary and recall largely cover. The cost of ending one
too late is the answer at the top of this document.

### A question the runner did not type always starts one

`ChatController.ask()` — the path taken by a tapped suggestion chip and by a
surface handing over, such as the session brief — opens a new session
regardless of the window. A chip is a subject a *surface* raised, arriving with
its own topic; continuing into it is how a half-finished exchange about a sore
calf becomes the context for "how has my training been going".

### Closing the sheet folds the memory; it does not end the conversation

These were one action and are now two, because conflating them was quietly
wrong. Dismissing the sheet rewrites the rolling summary from the turns said
since the last rewrite. It no longer clears the conversation id, so a runner who
shuts the sheet and reopens it two minutes later carries on in the same stored
conversation rather than watching one visible transcript get written into two.

The summariser is still never handed a turn it has already folded in — that is
now a slice of the transcript (`_unsummarised` counts the unfolded tail) rather
than a side effect of resetting the conversation id.

### Old conversations feed memory through recall, never through replay

This is the part the 1.0.0 plan flagged as "the part with a known problem", and
the problem is that naive retrieval reproduces the original bug at smaller
scale: a fragment of last month pasted into the context with no date is exactly
what "you ran 10 km yesterday" was made of.

So recall is wired with four constraints, all of them narrowing:

1. **Queried, not replayed.** The brief function now takes the message being
   sent, because the on-demand tier is a search and a search needs a query. The
   whole transcript never rides along.
2. **The live conversation is excluded.** Its turns are already the chat history
   the coach is sent; recalling them would double-weight what was just said.
3. **Only the runner's own words.** The coach's past replies were themselves
   derived from a brief rebuilt from current data every turn, so re-injecting
   one launders a stale derivation back into context as if it were a fact. What
   the runner said is primary evidence; what the coach said is a conclusion with
   an expiry date.
4. **Four turns, each dated, under a paragraph that says what they are before it
   says any of them.** The framing precedes the lines because a model reads what
   it is given in order.

### Every run in the brief carries when it happened

The mechanism fix is sessions; this is the belt to its braces. `_recent` now
names the runs before the latest with their own relative dates, and tells the
coach not to describe a run as more recent than the date given, or to describe
one that is not listed. So even when a recollection does surface, there is a
dated log beside it to be checked against.

### An empty log is stated as a refusal, not as a shrug

A brief written over no runs now carries an explicit instruction: if asked about
a run, say there is nothing in the log rather than describing one, and
specifically do not report a run mentioned in conversation as though it were
logged. That names the exact case where declining feels wrong to a model and is
nonetheless right.

This was not the live bug — the 10 km answer was a real memory — but the
empty-log path was untested and its failure mode is confabulation.

## Obvious alternatives

**Boundary on cold start only.** Simplest to implement and wrong on iOS, where a
process survives for days. A runner who has not force-quit in a week would still
have had one conversation all week, which is the bug.

**Boundary on every background→foreground transition.** Catches too much: it
makes checking a notification, answering a text, or glancing at a map into a new
conversation, and a coach that reintroduces itself every time you look away is
worse company than one that occasionally over-remembers.

**A "New conversation" button and nothing automatic.** Correct only for the
runner who thinks about conversation hygiene, which is nobody. The failure mode
is that the boundary never gets pressed and the app is back where it started,
except it can now blame the runner.

**Summarise the abandoned conversation at launch.** Tempting — the moment
`restore()` declines to adopt a conversation is the moment we know it ended, and
the fold could happen there. Rejected because it puts a model call on the launch
path, against a per-hour allowance ([ADR-0015](0015-spend-is-capped-over-three-windows.md)),
for a case that only arises when the app was force-quit mid-conversation. The
cost of not doing it is recorded below.

**Semantic recall now.** The `CoachMemoryRecall` seam exists precisely so this
is a swap rather than a rewrite. `KeywordRecall` will match "calf" in *my calf
is sore* and miss it in *lower leg pain*, and that is an honest, documented
limitation rather than a reason to build an embedding index in the same change
that introduces sessions.

**Keep `lastConversationId()` alongside the windowed lookup.** Rejected on the
same grounds [ADR-0023](0023-the-log-is-read-from-the-phone.md) deleted
`SupabaseRunRepository` rather than demoting it: leaving a second way to answer
"which conversation?" is how the wrong one gets reached for again. It is gone.

## Cost function

**A runner no longer opens the app onto yesterday's conversation.** That was a
genuinely nice property and it is being paid for deliberately. The mitigation is
that the conversation is kept and one tap away, under Previous conversations in
the sheet header — read-only, because reopening an old transcript to write into
it is the endless chat this decision ends.

**The rolling summary is written less reliably.** It is folded when the sheet
closes; a conversation abandoned by force-quitting the app mid-sentence is
picked up by nothing, and its turns may never reach the summary. They are still
in the transcript and still reachable by recall, so the cost is a stale summary
rather than lost words — but it is a real gap, and closing it is the launch-time
fold rejected above.

**Restored turns are treated as already folded.** The common path into a restore
is close the sheet (which folds), then relaunch; re-folding would hand the
summariser a copy of what it just wrote, which is the lossy re-encode
`replaceSummary` exists to refuse. The rarer path costs one summary refresh.

**Recall costs a scan per turn.** `KeywordRecall` reads up to 300 recent turns
and counts words on each. Local, bounded, and on the same code path as the brief
— but it is work that did not happen before, and a semantic implementation would
change its shape rather than its cost.

**The day divider is nearly unreachable in the live sheet.** A conversation can
now only span two days by being had across midnight. It earns its place in the
read-back view instead.

## Disconfirming condition

If runners routinely find themselves re-explaining context they gave twenty
minutes ago, the window is too short and the answer is to lengthen it — not to
restore the unconditional pick-up.

If the opposite shows up — the coach treating something from earlier in the same
session as current when it has since changed — then the boundary is not the
whole answer and turns need dating *within* a conversation too, which is a
larger change to the history format the Edge Function receives.

If recall starts surfacing turns that share vocabulary but not meaning often
enough to mislead, that is the trigger for the semantic implementation the seam
was built for, not for switching recall off.

## Consequences

- **No schema change.** `schemaVersion` stays at 8. `CoachConversations` already
  had `lastTurnAt`, and the "previous chats" list is the indexed read its doc
  comment promised.
- **`CoachMemoryStore` gains `recentConversations()`**, implemented on both the
  Drift store (one bounded read of the conversation table, plus one query for
  the opening lines and counts) and the in-memory store (folded from the turns,
  because that is all it holds). Both order by last turn, so the phone and the
  preview cannot disagree about which conversation is the most recent.
- **The brief seam changed shape.** `ChatController`'s `brief` is now
  `Future<String> Function(String message)`. Every caller passes the message
  through; a test that does not care takes `(_)`.
- **The mirror is unaffected and slightly behind.** `SupabaseCoachMemoryMirror`
  already pushes `last_turn_at` on every turn, so the server's conversation rows
  stay usable. It has never pushed a per-conversation summary or any notion of a
  session, and it does not need to — the mirror is best-effort and never on a
  read path ([ADR-0012](0012-backup-is-consented-restore-only-adds.md)). No
  Postgres migration is required by this change, and none is written here;
  `supabase/` is a different lane (`apps/mgk_run/CLAUDE.md`).
- **Transcripts stay unlogged.** Nothing added here logs a turn body, the new
  `CoachConversationSummary.toString()` omits the opening line it carries, and
  the read-back view draws on the runner's own screen only (CLAUDE.md rule 6).
- **The append-only and deletion-cascade guarantees are still pgTAP's.** Nothing
  in this change tests them from Dart (`apps/mgk_run/CLAUDE.md`, *Testing
  traps*).
- **Rule 2 is untouched.** Recall puts prose in front of the model and nothing
  else. No number the app acts on comes from a recalled turn; the plan and the
  log remain the only sources for those, and the recollections paragraph says so
  to the model as well.
