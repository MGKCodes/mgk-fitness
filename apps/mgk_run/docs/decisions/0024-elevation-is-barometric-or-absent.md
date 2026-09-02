# 0024 — Elevation is barometric or absent

**Status:** Accepted

## Context

Strava's summary for the 23 Aug 10 km carried **167 m of elevation gain** and a
**111 m maximum**. Ours carried neither, and Phase 2 of the 1.0.0 plan is about
closing that gap.

Three separate things were wrong, and only two of them were the ones the plan
expected:

1. **Climb was computed and thrown away.** `climbMeters` ran on every fix to
   feed the in-run readout and was stored nowhere — the splits' bug exactly. A
   runner watched a figure tick up for an hour and the summary afterwards had no
   column to read it back from.
2. **Max elevation did not exist as a question.** It is not the same question as
   gain and the two routinely disagree: hill repeats on a 40 m bank are enormous
   gain over an unremarkable maximum, one long drag up a mountain is the
   reverse. Strava shows both for that reason.
3. **There is no altitude in the trace at all**, and this is the one that
   actually decides the outcome. `GeolocatorLocationSource._toRunPoint` writes
   `altitudeMeters: null` unconditionally. `Position.altitude` is sitting right
   there, from GPS, and is deliberately dropped. Nothing else supplies altitude:
   the `CMAltimeter` channel the code's own comment promised was never built.

So `run_points.altitude_m` has been null for every point of every run this app
has ever recorded, and the two elevation figures derive from that column.

The question this ADR settles is what to do about (3), because there is an
obvious cheap answer — use `Position.altitude`, which is free and already in
hand — and it is the wrong one.

GPS vertical error is roughly two to three times its horizontal error, and
horizontal error is the number the recorder already refuses to measure distance
with above 20 m. Worse, elevation *gain* is a sum: unlike distance, where noise
partially cancels because a trace goes both ways, a gain calculation counts
every upward wobble and discards every downward one. Summing GPS altitude noise
over an hour reliably invents a few hundred metres of climb on a flat run — the
figure does not just have error bars, it is systematically, confidently wrong in
one direction.

That is the shape of bug this codebase already has a rule about, in
`workout_dedup.dart` and `metresFrom` and the two accuracy gates: **a plausible
wrong number is worse than no number**, because nothing about it looks wrong.
A runner shown 340 m of climb on a flat Tuesday has no way to know, and will
believe it, and so will the coach reading their history.

## Decision

**Elevation comes from a barometer or it does not come at all.**

- `climbMeters` and `maxElevationMeters` read `RunPoint.altitudeMeters` and
  nothing else, and answer `null` when it is absent. GPS altitude is never
  substituted, not even as a fallback, not even labelled as an estimate.
- Both figures are computed at `stop()` from the persisted trace — the same walk
  the distance and the splits come from — and stored in `runs.elevation_gain_m`
  and `runs.elevation_max_m`. They are stored whether or not there is anything
  to store, so the day a barometer exists nothing else has to change.
- The two absences are kept distinct rather than collapsed. `climbMeters`
  returns null below a 5 m floor because a flat run's "0 m" is true, useless and
  teaches the eye to skip the row; `maxElevationMeters` has **no** floor,
  because a maximum accumulates nothing and a route topping out at 4 m has
  genuinely topped out at 4 m. Null gain beside a real maximum is a flat run;
  both null is a phone with no barometric source.
- Absence renders as an absent tile. Never `0 m`, which is a claim, and never an
  error, which would make a missing sensor look like a fault.

## Consequences

**The two elevation tiles will not appear on any run this app records today.**
That is the honest state and it is worth stating plainly rather than discovering
later: the wiring is complete from the trace to the tile, and the source end of
it is empty. Everything from `RunPoint.altitudeMeters` onward is built, tested
and dormant.

**Filling them is a platform-channel task**, not an app-layer one: `CMAltimeter`
(`startRelativeAltitudeUpdates`, plus `CMAbsoluteAltitudeData` on iOS 15+ for a
sea-level maximum) and `Sensor.TYPE_PRESSURE` on Android. Both need native code
under `ios/` and `android/` and neither can be verified on the Windows harness
this repo is developed on — the same constraint [ADR-0019](0019-onboarding-is-two-moments.md)
records for the permission work.

**Relative altitude is not enough for the maximum.** `CMAltimeter`'s relative
stream starts at zero wherever the run started, which is fine for gain — gain is
a sum of deltas — and useless for a high point, which is a position above sea
level. A barometric implementation that only wires the relative stream should
store gain and leave the maximum null rather than reporting a number relative to
somebody's front door.

**`elevation_max_m` is local-only.** It was added to the device in schema
version 8; `run.runs` in Postgres does not have it, and `SupabaseRunBackup`
enumerates its columns explicitly, so the mirror does not carry it. The same is
true of `runs.steps`. A restore onto a new phone brings the run back without
either — as absent, not as wrong. Closing that is a migration under `supabase/`
at the repo root, which is not this app's to write (`apps/mgk_run/CLAUDE.md`).
`elevation_gain_m` is unaffected; it has always been in the mirror.

**No decision is made here about units.** Both figures render in metres on every
screen, in an app that otherwise converts everything at display time (CLAUDE.md
rule 4). `mgk_units` has `Distance`, `Pace` and `Mass` and no elevation type,
and inventing a local feet conversion on one screen while the in-run readout
kept metres would produce exactly the two-numbers-for-one-thing bug the 1.0.0
plan complains about elsewhere. It needs an `Elevation` type in the shared
package, and until then metres is at least consistent.
