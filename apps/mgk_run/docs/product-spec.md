# Runio — Product specification

**Status:** Pre-alpha (design). **Owner:** MGKCodes Ltd. **Platform:** iOS only.
**Stack:** Flutter / Dart · Supabase · OpenRouter (LLM gateway).

This is the source-of-truth product definition. Engineering depth lives in the
[architecture docs](architecture/overview.md); the *why* behind big calls lives
in the [ADRs](decisions/).

---

## 1. What Runio is

An AI running coach for iOS. Three surfaces behind one account:

1. **Record** — track a run with GPS and a map route, or log a treadmill /
   manual run.
2. **Plan** — a personalised training programme generated from a conversational
   intake. Any distance, any block length, and **not necessarily a block**: a
   plan may be a dated race build, an open-ended ramp toward a distance with no
   race entered, or a rhythm to hold
   ([ADR-0011](decisions/0011-a-plan-has-a-shape.md)).
3. **History** — all past activity, with routes, splits and trends.

The coach is present throughout: conversational onboarding, session rationale,
and negotiated adaptation when life gets in the way.

**What it is not:** a social network, a route planner, a Strava competitor. It
is a personal training tool built to professional App Store standards.

## 2. Resolved: the in-run experience (v1)

The handoff left one open product decision. **Resolved for v1: a live in-run
screen showing pace, distance and splits. Spoken audio cues are deferred to
post-v1.** This keeps the first version focused on a correct, reliable recorder
and a visible coach in Plan/History, with the `flutter_tts` audio layer added
once recording is solid. See
[ADR-0006](decisions/0006-in-run-audio-deferred.md).

## 3. Decisions already made

| Area | Decision |
|---|---|
| Platform | iOS only. No Android, no watchOS app. |
| Framework | Flutter. |
| Merging with Liftio | Rejected. Separate product. |
| Strava integration | None — their API policy prohibits use in an AI app and uses competitive to Strava. Do not integrate, read, or write. |
| Watch support | Indirect only. Apple Watch / Garmin / Coros runs arrive via HealthKit. No companion app. |
| Map | `flutter_map` with a commercial tile source, for design control over the basemap. |
| Health data | `health` package, read **and** write. Runs recorded in Runio are written back as `HKWorkout`. |
| Plan generation | LLM generates, deterministic validator enforces structure. |
| Plan shape | Skeleton generated up front; sessions generated one week ahead. |
| Onboarding | Conversational LLM slot-filling. No form fallback. |
| Connectivity | Connection assumed. Cached data viewable offline; only run recording is authored offline. |
| Units | Stored metric, displayed in km or miles per user preference. Both from day one. |
| License | AGPL-3.0 with DCO sign-off. See [ADR-0005](decisions/0005-license-agpl.md). |
| AI transport | The LLM provider is called only through a Supabase Edge Function — provider-agnostic via OpenRouter, model chosen server-side. See [ADR-0007](decisions/0007-secrets-via-backend-proxy.md). |

## 4. The surfaces in depth

- **Record** — see [run recording](architecture/run-recording.md). GPS capture
  behind a `RunRecorder` interface, points persisted to local SQLite as they
  arrive, accuracy filtering, autopause, barometric elevation, calorie
  estimate. Treadmill/manual entry with no route.
- **Plan** — see [plan generation](architecture/plan-generation.md). A visible
  skeleton (phases, volume, deloads, taper) plus weekly session generation,
  every model output validated in Dart before use.
- **History** — all runs with routes, splits and trends. List uses pre-rendered
  static route thumbnails (not live map instances) for scroll performance.

## 5. Packages

| Purpose | Package | Notes |
|---|---|---|
| GPS | `geolocator` | Behind the `RunRecorder` interface. |
| Map | `flutter_map` | Tile provider: MapTiler or Stadia. Do **not** ship against OSM public tiles. |
| Health | `health` | Read workouts/HR/energy; write `HKWorkout`. |
| Cadence / steps | `pedometer` | Treadmill distance fallback. |
| Local DB | `drift` | Typed queries over SQLite. |
| Backend | `supabase_flutter` | Auth + sync. |
| Notifications | `flutter_local_notifications` | One per day, morning, today's session. |
| Audio cues | `flutter_tts` | **Deferred to post-v1** (see §2). Must duck background audio, not stop it. |

## 6. iOS capabilities & Info.plist

Required:

- `UIBackgroundModes: location`
- `NSLocationAlwaysAndWhenInUseUsageDescription`
- `NSLocationWhenInUseUsageDescription`
- `NSHealthShareUsageDescription`
- `NSHealthUpdateUsageDescription`
- `NSMotionUsageDescription`
- HealthKit capability in Xcode.

App Review requires a justification for always-on location. "Recording a run
with the screen off" is accepted.

## 7. Compliance

Runio processes special-category health data and prescribes physical load. A
privacy policy, a working deletion path, named sub-processors, and a medical
disclaimer are prerequisites for submission — not follow-ups. See
[compliance.md](compliance.md).

## 7a. What it costs

Settled by [ADR-0029](decisions/0029-what-a-tier-costs-and-buys.md). Three
tiers, one row per (user, app) in `core.entitlements`, and the model behind each
is a server-side choice that can move without the tier meaning anything
different to a runner ([ADR-0014](decisions/0014-model-is-chosen-per-surface-and-per-tier.md)).

| Tier | `product` | Price | What it adds |
|---|---|---|---|
| Free | `free` | — | The whole tracker: recording, the log, splits, records, the runner's own history. A taste of the coach on the cheapest model. |
| Coach | `paid` | **£1/month** | A plan, and the coach's reading of a run against the session it set. |
| Sharper coach | `premium` | **£3/month** | The same, on a model that thinks harder, with roughly three times the monthly allowance. |

**Recording is free and stays free.** The subscription buys a coach, not a
plan-shaped paywall over the tracker —
[ADR-0019](decisions/0019-onboarding-is-two-moments.md) is why the app opens on
a working tracker with no account at all.

Each tier's spend ceiling is sized against what that tier actually earns, in
`supabase/functions/coach/limits.ts`. The prices live once, as consts in
`plan_gate_copy.dart`; a test asserts the gate copy interpolates them rather
than quoting a number somebody typed.

Purchases run through RevenueCat
([ADR-0028](decisions/0028-revenuecat-is-the-purchase-path.md)), which is
**unbuilt at 1.0.0** — nothing sets `subscribed` yet.

## 8. Out of scope

Route planning. Live location sharing. Social feed, following, leaderboards.
Gamification and badges. Android. watchOS companion app. Strava integration of
any kind. Garmin direct developer programme.

**On streaks.** What is out of scope is the *mechanic* — a counter that unlocks
something, or that punishes the runner for breaking it. Reporting how
consistently someone has trained is not that, and for a Rhythm plan it is the
training state itself: there is no volume ramp and no date to count down to, so
whether they have been showing up is the only thing there is to measure. "14
parkruns this year" is the same class of statement as "week 1 of 16"
([ADR-0011](decisions/0011-a-plan-has-a-shape.md)).

## 9. Prompt surfaces (reference)

The coach persona and tone are defined **once** and shared across every prompt.
Prompts to build: `intake`, `skeleton`, `week`, `adapt`, `rationale`,
`checkin`. All structured outputs return JSON against a fixed schema and pass
Dart-side validation before use. See
[plan generation](architecture/plan-generation.md) and
[onboarding](architecture/onboarding.md).
