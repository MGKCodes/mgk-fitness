# Roadmap — MGKFitness: Run

The build order is deliberate. **Steps 1–6 are a working run tracker. Steps
7–10 are the coach. Do not interleave them** — a half-built coach on top of a
shaky recorder is worse than a solid recorder alone.

Each step should land behind tests and leave `main` shippable.

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
[app-store-1.0.0.md](app-store-1.0.0.md)**, which is the live checklist — six
gates from a green build to a live listing. This section is kept as the original
statement of intent rather than maintained alongside it, because two checklists
are how one of them goes stale.

The four items it named, and where they stand:

- **Phases A and B complete.** Done.
- **Privacy policy + deletion path live** ([compliance.md](compliance.md)). The
  deletion path is built and correctly scoped. The policy is written and
  rendered in-app, and the published page is generated but **not live** — Gate 2.
- **Medical disclaimer surfaced at onboarding.** Done: `CoachFlow` gates the
  onboarding conversation on it.
- **Git history scrubbed of secrets before the repo goes public.** Still open,
  and deliberately **not** on the App Store critical path — it is a prerequisite
  for making the repo public, not for shipping the app, and conflating the two
  adds a hard job to the release for no store benefit.
