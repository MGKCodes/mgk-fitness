# Changelog

All notable changes to Runio are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **A note on the gap.** This file was written at the scaffold and then not kept
> for roughly 120 commits, because the repo's definition of done did not ask for
> it. The entries below were reconstructed from the ADRs and the commit log on
> 2026-08-21 rather than written as the work happened, so they describe *what
> the app does* rather than every step it took to get there. `CONTRIBUTING.md`
> now asks for a line in the same PR, which is the part that stops this
> recurring.

## [Unreleased]

Nothing has been released. The app has been built to TestFlight but has never
been on a store, so everything Runio does is still listed here.

### Added

**Recording a run**
- GPS run recording that is offline-first: the device owns a run in progress and
  points are persisted as they arrive, never held only in memory.
- Two accuracy gates rather than one — 50 m to draw a point on the map, 20 m
  before it is allowed to affect distance.
- Live route map, automatic kilometre splits, and manual laps.
- Climb and high point computed from the trace and stored with the run, and
  reported as absent rather than guessed from GPS altitude. **Absent is what
  they always are today** — see the note under *After the finish line* below.
  This line previously claimed "barometric climb on devices with a barometer",
  which the app has never had: `altitudeMeters` is written null on every fix,
  and the `CMAltimeter` channel the code's own comments referred to was never
  built. The refusal to substitute GPS altitude was real; the barometer behind
  it was not.
- An in-run screen built as one surface: a full-bleed map with the numbers on a
  glass panel over it, distance as a hero numeral, and two resting positions for
  the panel rather than three.
- A pace band showing where the current effort sits against the session's
  target, with hysteresis so the verdict does not flicker.
- Android as a supported target, with a foreground service so a run survives the
  screen locking.

**The coach**
- Training plans generated from a conversation rather than a form, validated
  in Dart before anything is shown — the model proposes, the validator disposes.
- Plans have a shape derived from what the runner said (block, horizon, rhythm,
  log), and prescribed distances are round numbers in the runner's own unit.
- The coach appears as a mark at the app shell rather than as a tab, and speaks
  in a conversation that carries validated proposals inline.
- Effort briefs and pace bands computed locally, so they render with no signal.
- Weekly adaptation: a week can be adjusted or swapped, and the plan reconciles
  every missed week rather than only the latest.

**Elsewhere**
- Home, Plan and Profile tabs, with lifetime totals, records, training standing
  and the full run log.
- Account deletion scoped to the app asking, with an export beforehand.
- Health integration designed for absence: a denied read is indistinguishable
  from no data, so it is never an error state.

**After the finish line**
- **A run completed screen.** Pressing Finish now arrives somewhere: the run
  summary, headed *Run complete* and dated *Just now*, with the route, the
  numbers, the coach's read of them and the splits. It used to pop the screen —
  an hour of effort ended with the display going away.
- **The route with a pin per kilometre**, each carrying the time it turned over
  and how far into the run that was. The pins and the splits list come from one
  walk over the trace, so a pin and its row can never disagree.
- **Splits are kept.** They were computed live for the in-run readout and stored
  nowhere, so a finished run had none; they are written to the device when the
  run finishes, alongside its distance and time.
- **A run opened from the log brings its trace with it**, which is what lets the
  summary draw a route for a run that was not just recorded.
- **A word from the coach on the run, and a way to keep asking** — the note is
  one true sentence by design, and *Ask your coach about this run* is the way
  past that, at the moment the answer is worth the most.
- **Steps on the summary, read from Health.** A GPS trace cannot count steps, so
  nothing did — Strava's summary for the same 10 km said 8,468 and ours said
  nothing. The run's own window is asked of Health when the run finishes, after
  the run is already safe on the phone, so a slow or refusing Health store costs
  a pause on the Finish button and nothing more. Absent far more often than not,
  and absent is drawn as no tile: a denied read is indistinguishable from no
  data, and `0` would be a claim that somebody who just ran 10 km took no steps.
- **Elevation gain is kept, and the route's high point is kept beside it.**
  Climb was computed on every fix for the in-run readout and stored nowhere —
  the splits' bug exactly — so an hour of watching it tick up ended with a
  summary that had no column to read it back from. It is written when the run
  finishes now, from the same walk over the trace as the distance and the
  splits. The maximum sits beside it because it answers a different question:
  hill repeats are enormous gain over an unremarkable high point, and one long
  climb is the reverse. The two elevation tiles are named apart for the same
  reason. **Both stay empty for now**, and honestly so: elevation comes from a
  barometer or it does not come at all (ADR-0024), and the app has no barometric
  source yet — GPS altitude is wrong by enough to invent a few hundred metres of
  climb on a flat run, so it is not substituted. Everything from the trace to
  the tile is built and waiting on `CMAltimeter`.
- Health is asked once, in onboarding, for everything the app reads — workouts
  and now steps. A permission sheet arriving at the end of a first run, in front
  of somebody who has just stopped and wants their numbers, is the version of
  this that does not ship.

**Home**
- **Home is a grid of tiles, each carrying one fact.** It was a wordmark, one
  session card and then two-thirds of a screen of nothing. It now holds today,
  the week, four squares of the runner's own record — last run, runs logged,
  longest run, fastest pace — and a note from the coach, in that order, over the
  charts that were already there.
- **A week tile**, with the seven days across the top and two figures under
  them. With a plan those are sessions done and distance covered, and it ends by
  naming the next session and the day it falls on. The *Next ·* line moved here
  off the rest-day card, where it was the only place in the app that said it.
- **A tile for the coach that is always on the page.** It used to be dropped
  whenever the coach had nothing notable to say — which is exactly the state a
  runner on day one is in, so the one surface saying anybody is paying attention
  was missing from the screen somebody decides on. It is held open now, saying
  what will land there, and it claims nothing about training it has not read.
- **The last run, the furthest and the quickest are on the front page**, one
  figure each rather than the three-row log Profile already owns properly.
  Tapping the last run opens it.

### Changed

- **A runner with no plan gets a Home about their running, not about the plan
  they have not bought.** Free Home was a plan Home with the contents taken out:
  a card headed *No plan yet* over an empty screen, which is the counter-signal
  [ADR-0019](docs/decisions/0019-onboarding-is-two-moments.md) names for its own
  reversal, in as few words as it is possible to put it. Every permanent tile
  now answers off the run log when there is no plan behind it — today is the run
  they have done or the one they have not, and the week counts runs where a plan
  would have counted sessions. Same tiles, different facts, no outline of
  something they were never offered.
- **Home's empty state states its structure.** Following the Profile tab: every
  figure is held open at a dash with a line saying what will fill it, because a
  dash is an absence where `0.0 km` would be a claim.
- **"TODAY" over "Threshold" was two headings and no sentence.** The eyebrow is
  a date now — *TODAY · MONDAY 24 AUG* — and the line under it names the
  activity with the hour on it: *Afternoon threshold run*. The Start button
  keeps the plain name, because "Start · 9 km afternoon threshold run" is
  nobody's sentence.
- **One clock for the whole of Home.** The header carried a private copy of
  `timeOfDayName` with the same three words and the same two boundaries, kept in
  step by hand — two answers to "what time of day is it" in one app, waiting for
  somebody to move one boundary and give a header reading *Evening* over a card
  reading *Afternoon easy run*. There is one function and one reading of the
  clock per build.
- **A session is named for the activity, not the physiology — and dated only
  where the app knows the date.** "Threshold", "Easy" and "Recovery" name an
  intensity; on their own they tell a runner how hard and never what they are
  doing. Every kind now reads as something a person does — *Easy run*,
  *Threshold run*, *Long run* — and where the hour is genuinely known, on
  today's session and on a run already recorded, it is named as an occasion:
  *Afternoon easy run*. A planned Wednesday four days out gets no time of day,
  because it does not have one yet. The runner's own word for a session still
  beats all of it.
- **The Plan tab is the week, and nothing beside it claiming to be the plan.**
  The card headed "The whole block" sat under the week at the same weight and
  read as a second, competing plan. The block view survives — it is still the
  only place the shape of nine or sixteen weeks can be seen — and is now reached
  by tapping the goal at the top of the tab, which is the line ("week 3 of 9")
  that raises the question. Its arc and the sentence describing it moved onto
  that screen, and it is no longer headed with block vocabulary for runners on
  plans that have no block.
- **A profile with no runs on it shows what it is going to say, not that it has
  nothing to say.** The page collapsed to a single "No runs yet" card over bare
  background, which reads as an app that is broken rather than one that is new.
  The lifetime figure, the runs / time / streak row, both records, the coach's
  read and the log now all render before the first run, with their figures held
  open as dashes rather than filled in with zeroes — a zero is a claim, a dash
  is an absence. The one sentence worth keeping moved into the lifetime card,
  where it captions the totals it was always describing, and *Add a run* is
  reachable from an empty log instead of being hidden behind having already
  recorded one (ADR-0019).
- **The in-run screen leads with the numbers, and the map earns its area.**
  During the first 400 m — or three minutes, whichever comes first — the panel
  carries the session's effort brief, and hands that height back to the map once
  the route has a shape worth the space.
- **The coach holds its verdict until the run has earned one.** Every run starts
  from a standstill, so the first rolling pace is an acceleration; until the
  warm-up threshold passes, the screen says it is still finding your pace rather
  than telling you to speed up.
- **On an easy, recovery or long session the pace band is a ceiling, not a
  corridor.** Running under it is the session working, so only "ease off" is
  offered. On threshold, marathon pace and time trials both directions apply.
- **The pace rail names its ends** — slower on the left, faster on the right,
  with the unit — because a pace runs backwards to every other number on the
  screen.
- On a planned session the third figure counts down what is left instead of
  averaging what has passed.
- The whole app now answers a touch: controls settle under the finger and tick,
  screens arrive rather than appear, and both pages move through a transition.
- A kilometre turning over, and the signal dropping, are felt as well as shown —
  the two things that matter to somebody who cannot look at the screen.
- **A run cannot be ended from the running state.** Lap, Pause and Finish sat
  side by side with Finish as the filled one — the loudest, most findable
  control on the screen, and the only one of the three that cannot be undone.
  While the run is going there is Lap and Pause; Finish appears once the runner
  has paused, and Resume is the prominent one when it does.
- **The RPE figure is gone from the in-run screen.** A number on a ten-point
  scale is a thing to convert before it is a thing to act on. The sentence
  underneath already says how the session should feel, in words that survive
  being read at a glance while moving; the scale itself belongs on a session
  brief, read before the run.
- **The weekly load block is gone from the in-run screen.** Nobody eight
  kilometres into a Sunday long run needs to know what Thursday looks like.
  Where the week stands is Home's question.

### Fixed

- **A prescribed distance is a whole number, on every screen that shows one.**
  Plan said "4 km" and Home said "4.1 km" for the same Tuesday, because nine
  surfaces formatted the session by hand instead of going through the one
  function that decides what a prescription reads like. Underneath, the
  whole-kilometre grid the plan documented was never applied when a session was
  generated, so the stored number really was 4,137 m. Sessions are now generated
  onto the grid and every surface reads it the same way. Distances a runner
  actually covered keep their decimal — a 10.18 km run is not a 10 km run.
- **The training log is read from the phone, not from the backup.** A recorded
  run appeared only if it had been successfully mirrored to Supabase, so a run
  that was complete and correct on the device was shown nowhere if the runner
  had declined backup, if the push failed, or if the read itself failed — and
  none of the three said so. The first real 10 km run recorded with this app
  vanished overnight that way. History now reads the on-device database, which
  was the source of truth all along, and Supabase is the mirror ADR-0012 always
  described (ADR-0023).
- A backup that fails is written down and reported in Settings, next to the
  switch that offered it, instead of being swallowed by a `catch` and forgotten.
- The live pace no longer survives the fixes it was computed from: when the
  signal goes, it dashes instead of holding its last value beside a distance
  that has stopped growing.
- A refused location permission that can be asked for again now offers to ask
  again, instead of sending people to the system Settings app.
- The coach says nothing at all on a screen that has just reported it is
  recording nothing.
- The pace marker keeps showing *by how much* when the effort is well outside
  the band, instead of pinning to the end of the rail.
- Button labels are set in Inter, like the rest of the app, instead of falling
  back to the platform's own font.
- Autopause was removed: it stopped runs that had not stopped.
- **The in-run countdown counts against what the runner was told.** A 7 km
  session reads as "4 mi" on Plan, and the third column converted the stored
  number instead — so the same session opened at 4.35 under a plan that said 4.
- **And it goes past the prescription instead of stopping at it.** The figure
  clamped at zero under a heading still reading TO GO, so running further froze
  it at `0.00` and a suggestion read as done-or-failed. The label changes to
  PAST and the figure counts up again, because a prescription is a suggestion
  and running past one is a decision rather than an overrun.
- **The black band at the foot of the Plan tab.** The shell reserved 64pt of
  bottom padding for the floating coach mark, on top of the room every tab
  already leaves for it. Home and Profile ignored the reserve outright; Plan's
  `SafeArea` spent it as a viewport inset, so the last card was cut through
  mid-row and the strip beneath it showed the backdrop's near-opaque foot as a
  full-width band. The reserve is gone; the per-tab clearance that was always
  doing the work stays.

[Unreleased]: https://github.com/MGKCodes/mgk-fitness/commits/main
