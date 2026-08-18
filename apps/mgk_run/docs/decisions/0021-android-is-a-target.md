# 0021 — Android is a target, and recording must survive Doze

**Status:** Accepted
**Supersedes:** the platform half of [ADR-0001](0001-flutter-ios-only.md)

## Context

[ADR-0001](0001-flutter-ios-only.md) chose Flutter and then narrowed the target
to iOS alone, for two reasons that were correct at the time: the valuable device
integrations are richest on iOS, and *"Android background location introduces a
class of problems (Doze, OEM process killing) that would dominate the recording
work."*

Both halves have aged differently. The integrations argument still holds —
HealthKit, `CMAltimeter` and Live Activities have no equal on the other side,
and the barometer in particular is why `climbMeters` reports null rather than
guessing from GPS altitude. The recording-work argument has not: the recording
layer has since been built, audited and covered by tests, and the problem ADR-0001
was avoiding is now a known, bounded piece of work rather than an unknown one.

What forced the question was testing. Every layout defect found in the in-run
screen — a readout that collided mid-run, controls that fell off a 375pt screen,
a status pill that overflowed at 320 — was found on an **Android emulator**,
because that is the only device this development machine can run. The platform
was already being used as the truth surface while officially not being a target,
which is an unstable position: the emulator either matters enough to build for or
it should not be trusted for judgement.

## Decision

**Ship Android as well as iOS.** Both are first-class targets, tested on an
emulator during development and on real devices before release.

Two things follow that are not optional:

**Recording runs behind a foreground service.** Android stops delivering
location to a backgrounded app, and — this is the part that matters — it does so
*silently*: no stream error, no exception, the fixes simply stop. On an emulator
this was reproduced directly, with the screen still reading "Recording", the
signal bars holding their last value, and the average pace quietly inflating as
elapsed time divided a frozen distance. A run that stops recording when the
screen locks is the single worst failure this app has, because it is invisible
until the run is over.

`geolocator_android` already ships the service with `foregroundServiceType="location"`;
the app supplies the permissions and a `ForegroundNotificationConfig` with a wake
lock. The notification is the price of the platform, and it is honest: it says
the run is being recorded, which is true and worth saying.

**`ACCESS_BACKGROUND_LOCATION` is deliberately not requested.** A foreground
service with the `location` type, started while the app is in the foreground —
which it always is, because a run starts with a tap — may keep receiving
location without it. Asking for background location instead would trigger a Play
Store review process and present the runner with a scarier permission dialog, to
buy a capability this app does not use.

## Consequences

- Platform-specific code is now legitimate where it was previously a smell.
  `LocationSettings` branches on the platform; iOS keeps `AppleSettings` with
  `allowBackgroundLocationUpdates`, Android gets `AndroidSettings` with the
  foreground notification.
- **Copy that names a settings path has to branch.** The location-denied banner
  read "Settings → Privacy & Security → Location Services", which is the iOS
  path and simply wrong on Android. This class of bug was invisible while there
  was one platform and is now a real defect wherever it appears.
- A second Codemagic workflow, and an Android signing keystore to create (see
  [ADR-0020](0020-codemagic-is-the-build-path.md)). Metered build minutes roughly
  double for a release of both.
- The iOS-only integrations degrade rather than block. Barometric altitude is
  absent on Android, so `climbMeters` returns null and the climb block does not
  draw — which is the behaviour it already had for a device without a barometer.
  HealthKit has no counterpart yet; Health Connect is a separate decision and is
  **not** taken here.
- No watchOS or Wear companion. That half of ADR-0001 stands.
