# Lift

**Lifting: workouts, progress photos, and the AI coach.** Part of the
[mgk-fitness](../../README.md) suite.

[![Status: rewrite in progress](https://img.shields.io/badge/Status-rewrite%20in%20progress-orange.svg)](#status)

## Status

**This is a shell.** It renders, it takes its theme from `mgk_ui`, and that is
currently all it does.

Lift exists today as a live React Native / Expo app with a small number of real
users. This directory is its **rewrite in Flutter**, not a continuation — which
is why the version starts at `0.1.0` while the shipped app is at `1.4.0`. It
will only claim a `1.x` number when it can actually replace what is on the store.

### Why it goes last

The migration order was database → Run → Lift, and the ordering is deliberate.

Run was already Flutter, already namespaced, and already had the coach, so
moving it was near-zero risk — and it *proved the workspace and the shared
packages using code that already ran*. The shared packages got extracted from
something working rather than designed speculatively.

Lift needs the most work, which is exactly why it doesn't go first. It lands
into a proven system instead of being the thing that proves it.

### What it inherits for free

Most of the backend is already built and tested by the time screens arrive here:

- **The coach.** App-agnostic, in the `coach` schema — one conversation store,
  one rate limiter. Most of Lift's AI feature already exists.
- **Its data.** `lift.workouts`, `exercises`, `sets` already hold real rows; the
  restructure moved them out of `public` without touching the data.
- **Cross-app awareness.** `core.activities` is already populated by Run, so
  "show me my runs" is a query, not an integration.
- **The design system.** `mgk_ui`, extracted from Run.

## A note on the bundle ID

This app is `com.mgkcodes.liftio` — the live app's id, inherited rather than
replaced, so **this ships as an update to the existing App Store record** and
existing installs receive it as 2.0.0.

It was `com.mgkcodes.fitness.lift` until 2026-08-17, matching the suite
convention that `mgk_run` still follows. That would have created a second
listing beside Liftio: no upgrade path, no inherited reviews, and the App Store
id already published on `getliftio.com` pointing at a retired app.

Bundle IDs still cannot be changed on an existing App Store record — which is
precisely why the id moved this direction and not the other. The reasoning, and
the earlier decision it reverses, is in
[docs/decisions/0001-liftio-is-replaced-not-relaunched.md](docs/decisions/0001-liftio-is-replaced-not-relaunched.md).

## Running it

```sh
flutter run          # from this directory
flutter test
```

The workspace resolves from the repo root, so `flutter pub get` there covers
this app too.

## Conventions

Everything visual comes from [`mgk_ui`](../../packages/mgk_ui). This app
declares no colours, no motion curves, and no fonts — including Inter, which is
bundled by the package and reached through `AppTheme.fontFamily`. Writing the
bare string `'Inter'` silently falls back to the platform default, so there is a
test guarding it.

The suite-wide rules are in [CONTRIBUTING.md](../../CONTRIBUTING.md). The ones
that will shape this app most:

- No provider key in the client — AI calls go through an Edge Function.
- The model proposes, the validator disposes.
- Store metric, convert at display.
- Health data is special-category data. Never log raw values.
