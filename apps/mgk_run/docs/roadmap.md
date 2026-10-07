# Roadmap — MGKFitness: Run

The build order is deliberate. **Steps 1–6 are a working run tracker. Steps
7–10 are the coach. Do not interleave them** — a half-built coach on top of a
shaky recorder is worse than a solid recorder alone.

Each step should land behind tests and leave `develop` shippable (it said
`main` until the branches changed on 2026-10-01; see CONTRIBUTING.md).

## Phase A — A working run tracker (v1 foundation)

### 1. Scaffold
Project scaffold, Supabase auth, database schema, local Drift DB, unit
handling (metric storage, km/mi display). Offline-first plumbing from the first
commit — retrofitting it is painful.

### 2. Run recording
`RunRecorder` interface with a `geolocator` implementation. Point persistence
to local SQLite **as points arrive**, autopause, accuracy filtering. See
[run-recording.md](architecture/run-recording.md).

### 3. Map display
Live route polyline, post-run route view. `flutter_map` + commercial tile
provider.

### 4. Save & write back
Save run → local → Supabase → write `HKWorkout` back to HealthKit.

### 5. HealthKit read + deduplication
Read workouts/HR/energy. **Deduplication** on `HKSource` bundle id + time-window
overlap — the highest-risk area in the app. Manual and treadmill entry.

> **As built, steps 4 and 5 are narrower, on purpose.** Run writes nothing to
> Health, and since 2026-09-29 it reads one thing: the step count over a run
> recorded in the app (`health_read_types.dart`). Workouts, heart rate and
> energy are not read; heart rate and calories are specified for 1.0.1 in
> [after-1.0.0.md](after-1.0.0.md). Do not build from the two lines above
> without reading that first.

### 6. History
History list with **pre-rendered static route thumbnails** (not live map
instances — matters for scroll performance). Splits and trends.

> At the end of Phase A, the app is a credible standalone run tracker.

## Phase B — The coach

### 7. Onboarding
Conversational slot-filling → structured runner profile. See
[onboarding.md](architecture/onboarding.md).

### 8. Plan skeleton
Skeleton generation + validator + plan overview screen. See
[plan-generation.md](architecture/plan-generation.md).

### 9. Weekly sessions
Weekly session generation + validator. Today view, week view, mark
complete/skipped, adaptation flow.

> At the end of Phase B, the app is an AI running coach.

## Phase C — Post-v1

### 10. Audio cues *(deferred from v1 — see [ADR-0006](decisions/0006-in-run-audio-deferred.md))*
Spoken in-run coaching via `flutter_tts`, ducking background audio.

### 11. Polish & extras
Live Activities, home-screen widget, share cards, shoe mileage, weather
context, readiness inputs (resting HR / HRV / sleep).

## Definition of "v1 shippable"

Phases A and B are complete. **What "shippable" now means is
[app-store-1.0.0.md](app-store-1.0.0.md)**, which is the live checklist for
both stores, from a green build to a live listing. This section is kept as the
original statement of intent rather than maintained alongside it, because two
checklists are how one of them goes stale.

The four items it named, and where they stand:

- **Phases A and B complete.** Done.
- **Privacy policy + deletion path live** ([compliance.md](compliance.md)).
  Done: the deletion path is built and correctly scoped, and the policy is
  rendered in-app and published at `mgkfitness.mgkcodes.com/run/privacy`
  (live since 2026-09-03).
- **Medical disclaimer surfaced at onboarding.** Done: `CoachFlow` gates the
  onboarding conversation on it.
- **Git history scrubbed of secrets before the repo goes public.** Done: the
  history was scanned on 2 and again on 7 October 2026 and held no secret, and
  the repository went public on 7 October ([`docs/going-public.md`](../../../docs/going-public.md)).
  It was kept off the App Store critical path on purpose: a prerequisite for
  making the repo public, not for shipping the app.
