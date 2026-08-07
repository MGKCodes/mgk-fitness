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

Sheets dismiss by drag or scrim tap, which is the platform convention and needs
no affordance of its own.

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
