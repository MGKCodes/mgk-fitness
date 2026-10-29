# 0006 — Lift opens with a welcome and a walkthrough over the real app, once

**Status:** Accepted (2026-10-29), for 2.0.1

Rewritten the day it was written, rather than superseded: the first version
never shipped, and the owner asked for this record to say what was built.
*Built, and replaced the same day*, below, keeps what the first version was
and why it went.

## Context

Lift 2.0.0 had no first open. `main.dart` went straight to the shell, which
opens on Track, so a new lifter's first screen was the front page of an app
nobody had explained: three tabs, a round C in the corner, and nothing to say
what any of it was for, which half was paid, or where a session went once it
was logged. Track's empty state even promised a backup ("backs up when you are
back") that a new install, signed out, does not make.

Run solved the same problem in August (Run's
[ADR-0018](../../../mgk_run/docs/decisions/0018-onboarding-opens-as-a-conversation.md)
and [ADR-0019](../../../mgk_run/docs/decisions/0019-onboarding-is-two-moments.md))
with a welcome screen, then the coach's lines arriving one at a time as a
conversation, then a button.

## Built, and replaced the same day

The first version (merged to `develop` as `c617442` on 29 October 2026) was
Run's pattern in Lift's words: the welcome, then six lines from the coach on a
screen of their own (`IntroScreen`, `intro_script.dart`, drawn with a shared
`ScriptedLine`), then *Start training*. It was chosen that morning over three
swipe pages and over hints laid on the screens themselves.

The owner looked at it running and said: "The onboarding I wanted to be a
walkthrough in the UI, not just a screen saying what happens: a full run
through where it takes you through the app." Six lines describing three tabs
the lifter had not yet seen were the swipe pages' fault in a different form:
a description of a screen, read before the screen. The lines were removed the
same day, and `ScriptedLine` with them, since nothing else drew it.

## Decision

**Lift opens on a welcome, and *Get started* plays a walkthrough over the
real app.** The owner's rulings, 29 October 2026:

- **A walkthrough over the real app.** One real control at a time, lit through
  a dimmed screen with a hole cut round it, the coach's card beside it (the
  small C and a line), *Next* and *Skip*, the tabs changing as it goes:
  Track's *Start a session*; the same button as the way to the saved workouts;
  the Plan tab; the Profile tab; Profile's Settings; the C. Then *Let's try a
  set*, and a **practice set** in a real session screen: the first set's tick,
  which waits for the lifter's own tap; the rest timer it starts; the swap;
  holding a movement to move it; and *Start training*, which closes the
  practice and lands on Track. The words are in `walkthrough_script.dart`.
- **The welcome stays, and leads into it.** *Get started* goes straight into
  the walkthrough over the app. *I already have an account* goes through
  Lift's sign-in and then straight into the app, with no walkthrough, marked
  seen: somebody with an account has their reason to be here already.
- **Replayable.** Settings › About › *Show me around* closes Settings and plays
  it again from the top.
- **Upgraders from 2.0.0 never meet it on their own.** They can play it from
  Settings.

How it is built:

- **The app is running underneath.** The veil is one `OverlayEntry` in the
  root overlay (`WalkthroughOverlay` in `mgk_ui`), so it stays above the
  practice session when that is pushed, and nothing in the shell is rebuilt to
  make room for it. It takes every tap, and every screen reader action, except
  a tap on the lit tick on the one step that waits for one. Back is *Skip*.
- **Controls by name, not by position.** Each lit control carries a
  `WalkthroughTarget` id (`WalkthroughSpot`), and the hole is measured on
  screen after every frame the app draws, so it follows the control at any
  width or text size, and through a tab sliding in.
- **A step whose control is not drawn is not shown.** The C with the coach
  switched off, or in a build with no coach; *Your workouts* behind a button
  that resumes an open session instead, or in a build with no database; the
  rest timer when the practice set was not ticked. The walkthrough never points
  at nothing. Two lines change for the lifter they would not be true for:
  somebody signed in is told their sessions back up to their account, not that
  they stay on the phone, and somebody whose swap does not ask the coach is not
  told the coach will suggest one.
- **The practice set is never real.** The real session screen, over an
  in-memory recorder (`InMemorySessionRecorder`, the preview harness's, moved
  into the app for this) seeded with one movement: Barbell Bench Press, three
  sets of eight at 40 kg, or 95 lb for somebody in pounds. No library, planner,
  log, rest alerts, remembered rest lengths or backup are handed to it, so
  nothing reaches the database, a backup, history, bests, the log a plan's
  weights are read from, or Track's *Resume*; no notification is scheduled and
  none is asked for. No coach and no network anywhere in the walkthrough.

**Shown once per install**, recorded on the phone (`LocalIntroStore`,
`intro.seen` in SharedPreferences) when it ends, by *Start training*, *Skip*
or back alike. The key kept the first version's name: the fact is the same.

**Never to somebody who used 2.0.0.** The first launch after the update finds
no record, which would read every existing lifter as new. So the gate in front
of the shell (`FirstRunGate`) lets through, and marks seen without a word,
anybody the phone already knows: a session restored at launch, or any training
on the phone. The welcome is shown only on positive evidence of a new install.

**It fails towards the app.** A record that cannot be read, a check that
throws, or either taking longer than three seconds opens the app rather than
the welcome. This is the opposite of Run's, whose intro carries the
permissions a tracker needs, so skipping it wrongly costs a run with no route.
Lift's carries nothing, so skipping it wrongly costs a walkthrough the lifter
can still play from Settings, while a gate that guessed the other way could
stand a welcome in front of somebody's training on every launch.

## Alternatives

- **The coach's lines on a screen of their own**, Run's pattern. Built first,
  and replaced the same day at the owner's request; see above.
- **Three swipe pages**, one per tab. The common pattern, and the one people
  have learned to swipe past without reading. A page describing a screen the
  reader has never seen explains nothing.
- **Hints in place**, a callout on each tab the first time it opens. Teaches
  at the moment of use, which is its strength, but it lays something over
  Track at the moment somebody is trying to start a session, and it never
  says, in one sitting, which half is paid and that nothing is backed up until
  they sign in. The walkthrough is the same idea run once, in order, when the
  lifter has asked for it by pressing *Get started*.

## Consequences

- The shell is not built until the welcome has been answered, so nothing it
  starts at launch (a backup checkpoint, the plan, the store) runs for somebody
  still on the welcome. The launch curtain plays over whichever opens.
- The shell is built for the walkthrough, and does its launch work under it:
  a new install has no backup, plan or account to start, so in practice this
  is reading empty stores.
- Lift's first open no longer matches Run's. The two apps arrive differently
  now, by the owner's choice; Run is unchanged.
- A lifter who signs in on a second phone does not meet it there (they arrive
  with an account). One who presses *Get started* on a second phone does.
- Track's first-session line promises a backup only to somebody signed in.
- Seen is written when the walkthrough ends, so a phone that dies half way
  through meets the welcome again on the next launch. If the record cannot be
  written at all, the welcome comes back until there is training on the phone
  or an account.
- The practice set has one movement, so holding it moves nothing: the step
  about holding a movement points at where the hold is and says what it does,
  but there is no second movement to drag past.
- `CoachAvatar` moved into `coach_mark.dart` beside the mark it is a small copy
  of; `ScriptedLine` and its file are gone from `mgk_ui`.

## Cost function

Judge this by **whether new lifters log a real session in their first week**,
and by whether they use the coach unprompted afterwards. The walkthrough's case
over a page of words is that a control that has been lit, and a set that has
been ticked once, are known; if lifters who see it log no more and ask the
coach no more than those who skip it, it taught nothing.

## Disconfirming condition

Reverse it if most new installs press *Skip* before the practice set, or if
lifters who finish it log their first session no sooner than those who skip
it. Then it is a delay in front of Track, and the in-place hints this was
chosen over are worth trying in its place.
