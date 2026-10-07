# MGKFitness

**Run and Lift: a running app and a strength app on one account, both open
source.** Run tracks your runs and builds you a training plan. Lift logs your
sets and rests. Tracking is free in both; an AI coach is the part you pay for.

[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](LICENSE)
[![Built with Flutter](https://img.shields.io/badge/Built%20with-Flutter-02569B.svg)](https://flutter.dev)
[![Backend: Supabase](https://img.shields.io/badge/Backend-Supabase-3ECF8E.svg)](https://supabase.com)
[![Status: on Google Play](https://img.shields.io/badge/Status-on%20Google%20Play-3DDC84.svg)](#status)

> An open-source project by [MGKCodes](https://mgkcodes.com) ·
> [mgkfitness.mgkcodes.com](https://mgkfitness.mgkcodes.com) ·
> [@mgkfitness.app](https://www.instagram.com/mgkfitness.app/) on Instagram

---

## The idea

Most fitness apps are islands. You run in one, lift in another, and neither
knows the other exists, so the training you are actually carrying is something
only you can see.

Run and Lift are built as one suite. **What is true today:** one account signs
into both, both are built from one design system, and both keep your training in
one database. **What comes next:** each app showing the other's training, so
Lift knows you ran on Tuesday and the coach plans around your whole week. The
database is already shaped for it (`core.activities`, below); neither app reads
it yet.

Either app works on its own. You never have to install the second one.

## Status

As of 7 October 2026.

| App | Package | Where it is |
|---|---|---|
| **Run** | `apps/mgk_run` | 1.0.0 on [Google Play](https://play.google.com/store/apps/details?id=com.mgkcodes.fitness.run). In review on the App Store. Tracking, plans and the AI coach. |
| **Lift** | `apps/mgk_lift` | 2.0.0 on [Google Play](https://play.google.com/store/apps/details?id=com.mgkcodes.liftio). In review on the App Store, where it replaces Liftio 1.4.0. Logging, a rest timer, plans and the AI coach. |
| **Eat** | — | An idea, deliberately not built. The structure makes adding a third app cheap; that is the claim. |

The suite is called MGKFitness and the apps Run and Lift
([docs/naming.md](docs/naming.md)). Package names (`mgk_run`, `mgk_lift`) and
bundle IDs are brand-neutral on purpose.

**What is in the stores is built from this repository**, and every build is
tagged on the commit it was built from (`run/build-29`, `lift/build-45`), so the
code behind any version you have installed can be read exactly. `main` moves
when an app goes to review; work in progress is on `develop`.

## What's in here

```
mgk-fitness/
├─ pubspec.yaml            workspace root: one lockfile for the whole tree
├─ apps/
│  ├─ mgk_run/             running: tracking, plans, the coach
│  └─ mgk_lift/            strength: logging, rest timer, plans, the coach
├─ packages/
│  ├─ mgk_ui/              the design system: tokens, motion, components
│  ├─ mgk_auth/            the one account both apps sign into
│  └─ mgk_units/           metric storage, km/mi at display
├─ supabase/
│  ├─ migrations/          the schema; this repository is the source of truth
│  ├─ functions/           Edge Functions: coach, delete-account, revenuecat, daily-ai-summary
│  └─ tests/               pgTAP assertions against the real catalog
├─ scripts/store/          submits and releases both apps on both stores
├─ web/                    mgkfitness.mgkcodes.com (NOT AGPL, see NOTICE.md)
└─ docs/
   ├─ architecture.md      how the suite fits together
   └─ database.md          the schema, and why it looks like that
```

Each app has its own `README.md`, `CHANGELOG.md` and `docs/decisions/` (the
ADRs: what was decided, what was weighed against it, and why).

It's a **native pub workspace**, not Melos: Dart 3.11 added glob support to the
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

Each app reads its settings from `config/app_config.json`, which is never
committed. Copy `config/app_config.example.json` beside it and fill in your own
Supabase project's address and publishable key (a local one from
`supabase start` works). Without it the app opens on a screen that says it is
not configured, rather than crashing.

```sh
cd apps/mgk_run
flutter run --dart-define-from-file=config/app_config.json
```

Generated code is not committed either. In an app, after a fresh clone:
`dart run build_runner build --delete-conflicting-outputs`.

### The database, locally

The whole Supabase stack runs in Docker, so you can break it freely:

```sh
supabase start           # Postgres, PostgREST, auth, storage, studio
supabase db reset        # replays every migration into a clean database
supabase test db         # pgTAP schema contract tests
```

`supabase db reset` is the one that matters. It rebuilds the database from
`supabase/migrations/` alone, so if it works, the repository genuinely describes
the schema rather than merely claiming to.

### Tests

```sh
flutter test                                   # from any app or package
supabase test db                               # schema invariants
deno test --allow-net --allow-env supabase/functions/coach/
```

## Architecture in one paragraph

Four Postgres schemas, one per domain: `core` (the person and the platform),
`coach` (the AI, app-agnostic), `lift`, and `run`. Apps read only what they own,
plus `core`. The load-bearing table is `core.activities`: one row per training
event whatever produced it, maintained by triggers rather than by clients, which
is what will make "Lift shows your runs" a single query instead of an
integration. Row-level security is the security boundary, not secrecy: the
publishable key ships in every binary and is meant to. Every AI call goes app →
Edge Function → provider, so no provider key is ever in an app.

The longer version is in [docs/architecture.md](docs/architecture.md), and the
schema rationale, including what was wrong with the old one, is in
[docs/database.md](docs/database.md).

## Pricing

Per app, never across apps. Run and Lift each have their own subscription.

| Tier | Price (UK) | What you get |
|---|---|---|
| Free | — | Full tracking. Log runs, log workouts, keep your history. No account needed to start. |
| Coach | £0.99 a month | A training plan, adjusted every week, and a coach to ask. |
| Premium Coach | £2.99 a month | The same coach, with far more room to talk. |

No free trial. The stores set the price in other countries.

Two rules that won't change:

- **Tracking is never paywalled.** If you just want to log training, that's free
  and complete.
- **Seeing one app's training in the other will be free.** A Lift user seeing
  their runs is the point of the suite, not an upsell.

## Contributing

Contributions are welcome: a bug, an idea, a fix, a feature. Fork the
repository, branch from `develop`, and open a pull request into `develop`.
Commits need a [DCO](https://developercertificate.org/) sign-off
(`git commit -s`). For anything big, open an issue first.
[CONTRIBUTING.md](CONTRIBUTING.md) has the rest, including the rules a change
can't break.

Found a way to read or change somebody else's data? Please don't open an issue:
[SECURITY.md](SECURITY.md) says how to tell us privately.

## Licence

The **code** is [AGPL-3.0](LICENSE). You can read it, run it, change it and
share it. If you run a modified version for other people, including over a
network, you have to publish your changes under the same licence.

That's deliberate: this project is meant to be read, and the licence keeps it
that way.

**With one additional permission, for app stores**
([`LICENSE-EXCEPTION.md`](LICENSE-EXCEPTION.md)). App stores attach terms of
their own that the AGPL would not otherwise allow. The permission lets anybody
ship this code, or their own version of it, through an app store, as long as
they publish its full source. Contributions come in under it too, so the apps
in the stores can carry everybody's changes. Nothing else in the AGPL changes.

**`web/` is not.** The website is proprietary, all rights reserved, under its
own [`web/LICENSE`](web/LICENSE). Copyleft was chosen to stop somebody reskinning
the *apps*; applied to marketing pages it would do the opposite, and AGPL's
section 13 would oblige us to offer source to every visitor. Visible, not
reusable.

**Assets are licensed separately**: see [NOTICE.md](NOTICE.md). In particular
the exercise illustrations in `apps/mgk_lift/assets/exercises/` are
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/), adapted from
the [Everkinetic](https://github.com/everkinetic/data) dataset by Greg Priday.
Reuse them freely, including commercially; keep the notice and share alike.

## Attribution

Built by [Matthew Kay](https://github.com/MattKay02) under
[MGKCodes](https://mgkcodes.com) · [hello@mgkcodes.com](mailto:hello@mgkcodes.com)
