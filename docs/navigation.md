# Navigation

Every screen in Lift: how you get in, how you get out, what the next action is,
and what back does when something is in flight.

Written as a pass over the whole app rather than screen by screen as they were
built, because the faults this finds are the ones no individual screen looks
wrong for having. The preview harness enumerates every screen and is the
checklist this was worked from — `flutter run -t lib/preview/main.dart`.

## The rule

**Every screen needs an obvious way in, an obvious way back, and an obvious
next step.** Where back would interrupt something, it is either safe (and
therefore unguarded) or blocked while the thing is in flight. There is no third
option: a screen that lets you leave mid-operation and then cannot say what
happened is the failure this pass exists to find.

## The shell

Three tab roots, correctly with no back — there is nothing above them.

| Surface | In | Out | Next action |
|---|---|---|---|
| Track | tab bar, launch default | tab bar | Start / resume a session, or start today's planned one |
| Plan | tab bar | tab bar | Build a plan, open a session, ask for a change |
| Profile | tab bar | tab bar | Open photos, settings, or the log |

The **coach mark** floats over all three. It is the only navigation element
that is not part of a surface, which is deliberate (Run's ADR-0017): a dock
inside one tab would make the coach available on a third of the app.

## Pushed screens

| Screen | In | Out | In flight |
|---|---|---|---|
| Active session | Track's primary button | **back arrow** (session stays open), Finish, Discard | back is safe — every change is already persisted |
| Coach | coach mark | app bar back | a reply in flight is abandoned; the turn is charged either way |
| Plan intake | Plan → Build a plan | app bar back, or "Build my plan" | **blocked** while a turn is in flight |
| Plan review | after generation | app bar back (draft is kept), or Start this plan | generation has already finished |
| Coach memory | Settings → Coach | app bar back | read and clear are both fast; no guard |
| Photos | Profile → Photos | app bar back | — |
| Pose series | Photos → a pose | app bar back | — |
| Series playback | Pose series → play | app bar back | the timer is cancelled in `dispose` |
| Sign in | Settings, or any gated action | app bar back | **blocked** while signing in |
| Settings | Profile → Settings | app bar back | — |
| Credits | Settings → Credits | app bar back | — |

## Sheets

Sheets dismiss by drag or scrim tap. **Both gestures are invisible**, so every
sheet carries a [`SheetHandle`] — the grab bar is the only thing on it that says
it can be closed. The claim that used to sit here, that the convention "needs no
affordance of its own", was wrong and is what let three sheets ship without one.

| Sheet | In | Result |
|---|---|---|
| Template picker | Active session, empty state | a template, or nothing |
| Exercise picker | Active session → Add | a movement name, or nothing |
| Swap | Active session → a movement's swap icon | a replacement movement, or nothing |
| Adapt | Plan → "Something changed?" | the accepted changes, or nothing |

Both coach-backed sheets ask on open or on submit and show the reply whatever
happens to the options. Dismissing mid-request abandons the answer; the call is
charged either way, which is the same trade the coach screen makes.

## What this pass changed

**The active session had no back affordance at all.** No app bar, and the only
exits were Finish — disabled until a set is ticked — and Discard, at the foot of
a list. A lifter who opened a session by accident had to find "Discard session"
to escape, or know that the Android system back gesture worked, which nothing on
screen said. It now has a back arrow in its header.

Backing out is deliberately **unguarded**: the session is already persisted, it
stays open, and Track offers to resume it. A confirmation dialog there would be
asking permission for something with no consequence.

**Sign in and plan intake now block back while a request is in flight.** Both
complete regardless of whether the screen is still there, and both report their
result into a screen that may have been disposed — sign-in leaves the lifter on
Track not knowing whether it worked, and an abandoned intake turn is a paid call
whose answer would have been merged into what the coach knows.

## The exit sweep, 2026-08-08

A second pass, asking one question of every screen and sheet in **both** apps:
is there something visible that gets you out? Findings, all now fixed:

- **Three sheets had no dismiss affordance at all** — Lift's photo-source picker
  and progress-photo actions, and Run's week-adjust sheet. Each was a bare
  `Column` of `ListTile`s: escapable by drag or scrim, with nothing saying so.
  The progress-photo one was the worst of them, because its most prominent
  control is a red **Delete photo** and it opens on a tap — a mistap put you in
  front of an irreversible action with no visible way back.
- **Six hand-written copies of the same grab bar**, already drifted: Lift drew
  it in `textTertiary`, Run in `elevated`, which on a `surface` card is nearly
  invisible. Now one `SheetHandle` in `mgk_ui` (principle 9 in
  [design.md](design.md), third instance in two days).
- **Run's week-adjust sheet had a "Back" button that was not an exit** — it
  clears the proposal and returns to the ask, and only exists in one state of
  three. Easy to mistake for a dismiss when reading the code.

Checked and correct, no change needed:

- Every pushed route in both apps has a back affordance. Most inherit it from
  `AppBar`/`SliverAppBar` with no `leading` override; Lift's active session and
  Run's recording screen draw their own (an arrow and a cross respectively),
  because neither has an app bar.
- Tab roots have none, correctly — there is nothing above them.
- Every confirmation dialog has a cancel: "Keep it" against "Forget", "Keep it"
  against "Delete".
- Run's `plan_reveal_screen` sets `canPop: false` with no visible exit, which is
  right: it blocks only while two model calls are in flight, and both terminal
  states (failed, revealed) offer a button out.
- Run's `coach_flow` blocks back at the confirmation step and sends it to the
  conversation instead, which is a step back rather than a trap.

**The first version of this sweep was done by reading code, and that was not
good enough.** Three things went wrong, and all three are worth remembering:

- `grep appBar:` misses `SliverAppBar`, so Run's run-summary screen looked like
  a dead end. It is not.
- A `width: 36` search matches layout columns as readily as grab bars, so Run's
  week-detail sheet looked like it had one. It did not.
- **The harness could not show a back arrow at all.** It mounted the named
  screen as the root, where `Navigator.canPop()` is false and `AppBar` draws no
  leading — so no screenshot taken from it could distinguish a screen that has a
  back arrow from one that does not. The conclusion here was right, but it rested
  on reading code plus a single screen reached by tapping through. That is not
  the same as having looked.

Both harnesses now push by default and Lift's index scrolls, so all 35 screens
open by hand. Every pushed screen in Lift has since been opened and its arrow
seen: active session, plan intake, plan review, photos, pose series, settings,
credits, sign-in, coach, coach memory.

> Check whether the tool can even express the fault before trusting it to report
> the fault absent.

## Known and accepted

- **The coach screen abandons a reply on back.** The turn is charged. It is not
  guarded because a conversation is not an operation: leaving mid-reply is a
  legitimate thing to do, and the cost is one turn rather than an ambiguous
  state.
- **Sheets have no in-flight guard.** Same reasoning, and dismissing a sheet is
  a much more casual gesture than leaving a screen — a `PopScope` on a drag
  would feel broken.
- **There is no deep linking**, so every screen's "in" is a tap from inside the
  app. When that changes, this table is what has to be re-checked: a screen
  entered directly has no back stack to return to.
