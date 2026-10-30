# 0050 — Run tours the app after the intro

**Status:** Accepted, 2026-10-30. Run 1.1.0.

## Context

Lift 2.0.1 opens with a tour over the real app (Lift's ADR-0006): each step
lights one control under a dimmed screen with the coach's line beside it, and
the tabs change as it goes. The shared pieces went into `mgk_ui`
(`walkthrough.dart`) so another app could point at its own controls without
the package knowing what they are.

Run had nothing like it. A new runner meets the coach in the intro (greeting,
name, permissions; ADR-0018, ADR-0019) and lands on Home, and is left to find
Plan, Profile, Settings and the coach's C alone. On 30 October 2026, looking at
Lift's tour on the emulator, the owner asked for Run to have the same.

## Decision

Three rulings, the owner's, on 30 October 2026:

1. **It follows the coach's intro, on the *Get started* path only.** Welcome,
   *Get started*, the intro, then the tour over Home. *I already have an
   account* goes past it, as in Lift, including an account that has never met
   this coach and so has the intro signed in: somebody with an account has a
   reason to be here already. An install updating from 1.0.x has had its
   intro, so nothing plays it to them. Anybody can play it from Settings,
   *Show me around*, the first row under About.
2. **No practice run.** The tour ends by lighting the button that starts a
   run and saying what it does, then lands on Home.
3. **It is a new feature, so Run moves to 1.1.0** (CONTRIBUTING.md, Versions).

The steps, in `onboarding/domain/walkthrough_script.dart` with every line:
Home's Today card, the week card, the Plan tab, the Profile tab, Settings'
gear, the coach's C, and the start button. A control that is not drawn is a
step that is not shown (the C in a build with no coach), except the last,
which is the way out and is said with nothing lit when the Today card has no
start button. *Skip* and back end it from anywhere, on Home.

It is not kept anywhere. The gate passes the shell one flag when the
*Get started* intro finishes; a tour cut short by the app being closed is not
played again.

## Why no practice run

Lift's tour ends with a practice set, and it can: a set is a tap, and the
session screen runs over an in-memory recorder that nothing keeps. A run is
not like that. Starting one asks for the phone's position and keeps asking,
puts the run's figures on the lock screen (ADR-0045), and on finishing reads
Health over the run's window and saves a run to the log. A practice run would
have to hold every one of those off, on two platforms, and a mistake in any of
them is a GPS session or a stray run the runner did not ask for, on their
first minute in the app. Pointing at the button teaches the same thing.

So **nothing in the tour can start a run.** Every step is a statement, so the
veil takes every tap, the lit button included; a test holds that the recorder
is never made.

## Consequences

- Home's Today and week cards, the start button, Profile's gear, the Plan and
  Profile tabs and the coach's C carry `WalkthroughTarget` ids. Outside a tour
  they are nothing.
- **The coach's C is drawn at rest while the tour runs**, rather than playing
  its line under the veil. A free runner's "Coaching is a subscription" line
  plays when the tour ends instead.
- The lines are written in the coach's voice and judged on a phone; they live
  in the one file so they can be changed without touching the sequence.

## Cost function

A tour on every new install costs a new runner seven taps or one *Skip* before
their first run. The intro already costs a conversation; this is the price of
Plan, Profile and the C being found rather than stumbled on.

## Disconfirming condition

New runners skipping it on the first step most of the time, or replays from
Settings being the main way it is seen. Either says the tour belongs somewhere
else, or nowhere.
