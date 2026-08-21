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
- Barometric climb on devices with a barometer, reported as absent rather than
  guessed from GPS altitude.
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

### Changed

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

### Fixed

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

[Unreleased]: https://github.com/MGKCodes/mgk-fitness/commits/main
