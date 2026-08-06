# mgk-fitness

**A fitness suite where the apps actually talk to each other.** Track a run in
one app, and the other one knows. Log a workout, and the coach factors it in.

[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](LICENSE)
[![Built with Flutter](https://img.shields.io/badge/Built%20with-Flutter-02569B.svg)](https://flutter.dev)
[![Backend: Supabase](https://img.shields.io/badge/Backend-Supabase-3ECF8E.svg)](https://supabase.com)
[![Status: pre-release](https://img.shields.io/badge/Status-pre--release-orange.svg)](#status)

> An open-source project by [MGKCodes](https://mgkcodes.com).

---

## The idea

Most fitness apps are islands. You run in one, lift in another, and neither has
any idea the other exists — so the training load you're actually carrying is
something only you can see, by holding two apps in your head at once.

These apps run **fully independently**. You can use one and never know the other
exists. But if you use two, you notice they talk: Lift can see you ran on
Tuesday, and the coach reasons about your whole week rather than a third of it.

That cross-talk is the product. It is also the thing that is free, always —
[see below](#pricing).

## Status

**Pre-release, and honest about it.** The database and the shared packages are
built and verified; the apps are at very different stages.

| App | Package | State |
|---|---|---|
| **Run** | `apps/mgk_run` | Working. Tracking, plans, and the AI coach. Not yet released. |
| **Lift** | `apps/mgk_lift` | A shell. Being rewritten in Flutter from a React Native app that is live today. |
| **Eat** | — | An idea. Deliberately not built. The structure makes adding it cheap; that is the whole claim. |

The suite name is not final. Apps are referred to as **Run** and **Lift**;
package names (`mgk_run`, `mgk_lift`) and bundle IDs
(`com.mgkcodes.fitness.run`) are brand-neutral on purpose, so renaming the suite
costs nothing but display strings.

## What's in here

```
mgk-fitness/
├─ pubspec.yaml            workspace root — one lockfile for the whole tree
├─ apps/
│  ├─ mgk_run/             running: tracking, plans, coach
│  └─ mgk_lift/            lifting (rewrite in progress)
├─ packages/
│  └─ mgk_ui/              the design system: tokens, motion, components
├─ supabase/
│  ├─ migrations/          the schema — this repo is the source of truth
│  ├─ functions/           Edge Functions: coach, delete-account, daily-ai-summary
│  └─ tests/               pgTAP assertions against the real catalog
└─ docs/
   ├─ architecture.md      how the suite fits together
   └─ database.md          the schema, and why it looks like that
```

It's a **native pub workspace**, not Melos — Dart 3.11 added glob support to the
`workspace:` field, which was Melos's last remaining advantage here. One
`flutter pub get` resolves everything.

## Getting started

**You need:** Flutter 3.41+ / Dart 3.11+, and [Docker
Desktop](https://docs.docker.com/desktop) if you want to run the database
locally.

```sh
git clone https://github.com/MGKCodes/mgk-fitness.git
cd mgk-fitness
flutter pub get          # resolves every package in the workspace at once
flutter analyze          # should be clean
```

Run an app:

```sh
cd apps/mgk_run && flutter run
```

### The database, locally

The whole Supabase stack runs in Docker, so you can break it freely:

```sh
supabase start           # Postgres, PostgREST, auth, storage, studio
supabase db reset        # replays every migration into a clean database
supabase test db         # pgTAP schema contract tests
```

`supabase db reset` is the one that matters. It rebuilds the database from
`supabase/migrations/` alone — so if it works, the repo genuinely describes the
schema, rather than merely claiming to.

### Tests

```sh
flutter test                                   # from any app directory
supabase test db                               # schema invariants
deno test --allow-net --allow-env supabase/functions/coach/
```

## Architecture in one paragraph

Four Postgres schemas, one per domain: `core` (the person and the platform),
`coach` (the AI, app-agnostic), `lift`, and `run`. Apps read only what they own,
plus `core`. The load-bearing table is `core.activities` — one row per training
event whatever produced it, maintained by triggers rather than by clients, which
is what makes "Lift shows your runs" a single query instead of an integration.
RLS is the security boundary, not secrecy: the anon key ships in every binary
and is meant to.

The longer version is in [docs/architecture.md](docs/architecture.md), and the
schema rationale — including what was wrong with the old one — is in
[docs/database.md](docs/database.md).

## Pricing

Per-app, never cross-app. You pay separately for Lift and Run.

| Tier | Price | What you get |
|---|---|---|
| Free | — | Full tracking. Log runs, log workouts, keep your history. |
| Paid | £1/mo | The AI coach and plan generation. |
| Premium | £3/mo | More chat, higher limits. |

Two rules that won't change:

- **Tracking is never paywalled.** If you just want to log training, that's free
  and complete.
- **Cross-app visibility is free.** A Lift user seeing their runs is the point
  of the suite, not an upsell.

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Commits need
a [DCO](https://developercertificate.org/) sign-off (`git commit -s`).

## Licence

[AGPL-3.0](LICENSE). If you run a modified version as a network service, you
have to publish your changes.

That's deliberate: this is a portfolio project meant to be read, and the licence
keeps it that way. It follows the Signal precedent for App Store distribution —
sole copyright holder, so the binaries on the store and the source here can
coexist.

## Attribution

Built by [Matthew Kay](https://github.com/MattKay02) under
[MGKCodes](https://mgkcodes.com) · [hello@mgkcodes.com](mailto:hello@mgkcodes.com)
