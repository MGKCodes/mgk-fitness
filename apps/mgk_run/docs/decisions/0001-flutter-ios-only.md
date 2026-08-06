# 0001 — Flutter, iOS only

**Status:** Accepted

## Context

Runio is a solo/studio product that needs to reach a shippable, polished v1
without spreading effort across platforms. The valuable device integrations
(HealthKit, CoreLocation, CMAltimeter, Live Activities) are richest and most
predictable on iOS. Android background location introduces a class of problems
(Doze, OEM process killing) that would dominate the recording work.

## Decision

Build with **Flutter/Dart**, targeting **iOS only** for the foreseeable future.
No Android build, no watchOS companion app. Watch data (Apple Watch, Garmin,
Coros) is ingested indirectly via HealthKit.

## Consequences

- The recording layer can assume iOS behaviour; the paid Android
  background-geolocation licence is unnecessary (see
  [ADR-0004](0004-offline-first-local-source-of-truth.md) and
  [run-recording.md](../architecture/run-recording.md)).
- Flutter keeps the door open to Android later, but no code should assume it is
  coming. Platform channels (e.g. `CMAltimeter`) are iOS-specific by design.
- Choosing Flutter over native SwiftUI trades some platform fidelity for
  development speed and a single codebase — an acceptable trade for this product.
