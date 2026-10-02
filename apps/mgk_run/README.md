# Run

**An AI running coach.** Track your runs, get a training plan built for your
goal, and have a coach that adapts when life gets in the way. Part of the
[mgk-fitness](../../README.md) suite.

[![Status: in review](https://img.shields.io/badge/Status-1.0.0%20in%20review-blue.svg)](docs/app-store-1.0.0.md)
[![Platforms: iOS and Android](https://img.shields.io/badge/Platforms-iOS%20%7C%20Android-lightgrey.svg)](#)
[![Built with Flutter](https://img.shields.io/badge/Built%20with-Flutter-02569B.svg)](https://flutter.dev)

## Status

**1.0.0 was submitted to the App Store and Google Play on 2 October 2026**, and
is with both reviewers. Tracking, plan generation and the coach all run, and
the coach is sold as a subscription through both stores. `main` holds what was
submitted and `develop` is the next version
([ADR-0046](docs/decisions/0046-a-version-is-submitted-once.md)). Which build
is where, and what is left, is in
[`docs/app-store-1.0.0.md`](docs/app-store-1.0.0.md), and only there: a build
number written here was two builds behind within a week.

Three pages are kept open while this release is worked on. They are private to
the owner's account:

- **[The screen board](https://claude.ai/code/artifact/9ddfd186-11ad-4260-bde9-ef8b7a5d9190)**: every screen of the app, drawn by the app's own
  code, each with what it is for. Rebuilt with the `screen-board` skill.
- **[The store shots](https://claude.ai/artifact/KmRop4oC1KrHb2UdHykJbU)**: the pictures on both listings, and the designs
  they were chosen from. Source in [`design/store-shots`](design/store-shots/).
- **[The submission sheet](https://claude.ai/artifact/Y2zLyeNxVuTrJTfHUn7tqM)**: every field of App Store Connect and Play
  Console, ready to paste. Built by `tool/build_submission_sheet.py`.

The test count lives in
[`docs/app-store-1.0.0.md`](docs/app-store-1.0.0.md) and only there. It read
917 here, 1186 in `CLAUDE.md` and 1,333 in the release plan while the suite
passed 1,352 — four copies, four answers, and the release plan was the closest.

Previously a standalone repo called Runio; moved into this monorepo on
2026-08-06 and repointed at the shared design system. The move deleted 13
duplicated design-system files — `mgk_ui` was extracted from this app, so its
components came home.

## What it does

- **Records runs** with a GPS trace, splits and pace, and on iPhone the step
  count and cadence from Apple Health. No elevation or heart rate: there is no
  barometric source, and the app reads no heart rate
  ([ADR-0024](docs/decisions/0024-elevation-is-barometric-or-absent.md)).
- **Builds a training plan** from your goal, your current volume, and the days
  you can actually run.
- **Adapts.** Miss a week and the plan responds, rather than quietly becoming a
  document you feel guilty about.
- **Coaches conversationally** across three time horizons — today, this week,
  the plan.

Two things it deliberately does not do:

- **Rank you against other people.** It is you versus you.
- **Prescribe what is in a strength session.** It prescribes *when* one happens
  and leaves the content to you — see [ADR-0010](docs/decisions/0010-strength-sessions-not-prescribed.md).

## Running it

```sh
flutter run          # from this directory
flutter test
```

The workspace resolves from the repo root, so a single `flutter pub get` there
covers this app.

You need Supabase credentials for anything involving the account or the coach.
The app shows a config-missing screen rather than crashing when they are absent,
so it runs without them.

## How it's built

Feature-first under `lib/src/features/`, with shared pieces in
`lib/src/core/`:

```
lib/src/
├─ core/
│  ├─ config/      environment and feature flags
│  ├─ database/    drift — the local source of truth
│  ├─ supabase/    client wiring
│  └─ units/       metric storage, display-time conversion
└─ features/       auth, history, coaching, recording,
                   onboarding, settings, legal, home
```

`core/` is all pure Dart and testable without Flutter — the natural candidates
if any of it ever needs to become a shared package. None have been extracted,
on the principle that a package should be pulled out of working code rather
than designed for a caller that doesn't exist yet.

### The rules that shape everything

1. **Offline-first.** A run in progress is owned by the on-device database.
   Supabase is backup and cross-device store, never the source of truth for live
   recording. Points are persisted **as they arrive** — a run is never held only
   in memory. ([ADR-0004](docs/decisions/0004-offline-first-local-source-of-truth.md))
2. **The model proposes, the validator disposes.** Every LLM output is a
   structured proposal that passes deterministic Dart-side validation before
   anything uses it. The model never writes a number straight into a plan.
   ([ADR-0003](docs/decisions/0003-llm-generates-validator-enforces.md))
3. **No provider key in the client.** AI calls go app → Edge Function →
   provider. ([ADR-0007](docs/decisions/0007-secrets-via-backend-proxy.md))
4. **Store metric, convert at display.**
5. **A run is editable; its trace is not.** ([ADR-0016](docs/decisions/0016-a-run-is-editable-its-trace-is-not.md))
6. **Health data is special-category data.** Never log raw values. A denied
   HealthKit read is indistinguishable from no data — design for absence, not
   error states.

### Backend

Reads `run.*` and `coach.*`, plus `core.*` for the shared profile. The schema
lives in [`supabase/`](../../supabase/) at the repo root, not here — see
[docs/database.md](../../docs/database.md).

Calls name their schema explicitly (`.schema('run')`, `.schema('coach')`,
`.schema('core')`). The client defaults to `public`, which is empty, so an
un-namespaced call fails at runtime rather than at compile time.

## Documentation

**Start at [`docs/README.md`](docs/README.md)** — it carries the filing rule
(documents tier by **lifecycle**, not topic) and names the live release set.

- [`docs/app-store-1.0.0.md`](docs/app-store-1.0.0.md) — shipping 1.0.0 on
  both stores, and the only checklist carrying state.
  [`store-setup.md`](docs/store-setup.md) and
  [`play-setup.md`](docs/play-setup.md) are its runbooks;
  [`app-store-listing.md`](docs/app-store-listing.md) and
  [`play-listing.md`](docs/play-listing.md) are listing copy parsed by
  `tool/check_listing.py`.
- [`docs/decisions/`](docs/decisions/) — the ADRs, the *why*. Superseded, never
  edited.
- [`docs/architecture/`](docs/architecture/) — the *how*. Four of the six have
  not been touched since 2026-08-06; trust `decisions/` where they disagree.
- [`docs/compliance.md`](docs/compliance.md),
  [`privacy-policy.md`](docs/privacy-policy.md),
  [`medical-disclaimer.md`](docs/medical-disclaimer.md),
  [`terms-of-use.md`](docs/terms-of-use.md) — the legal source, generated into
  `web/public/run/`. Never edit a generated copy.
- [`../../docs/`](../../docs/) — the suite: the Supabase schema, the design
  language, naming, navigation.
- [`docs/history/product-spec.md`](docs/history/product-spec.md) — **stale, and still titled
  Runio.** It was named here as the source of truth and is not one. History.


## Testing

```sh
flutter test
```

One trap worth knowing: `PrimaryButton(busy: true)` renders an indeterminate
spinner, so `pumpAndSettle` never returns on a screen showing one. Use
`pump(duration)`.

Schema-level guarantees — that coach memory is actually erased on account
deletion, that RLS is on, that the transcript stays append-only — are **not**
tested from Dart. They are pgTAP assertions in
[`supabase/tests/`](../../supabase/tests/) run by `supabase test db`, because
they check the real catalog rather than a regex over migration text.
