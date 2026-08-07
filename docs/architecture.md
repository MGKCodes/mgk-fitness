# Architecture

How the suite fits together, and the decisions that shaped it.

## The premise

Two apps that run independently, share an account and a backend, and notice each
other when both are installed. Everything below follows from wanting all three
of those at once.

```
┌─────────────┐   ┌─────────────┐
│  mgk_run    │   │  mgk_lift   │      Flutter apps. Independent binaries,
└──────┬──────┘   └──────┬──────┘      independent App Store records.
       │                 │
       └────────┬────────┘
                │
         ┌──────┴──────┐
         │   mgk_ui    │               Design system. Tokens, motion,
         └──────┬──────┘               components. No app declares a colour.
                │
    ┌───────────┴───────────┐
    │   Supabase project    │
    │                       │
    │  core · coach         │          One Postgres, four schemas.
    │  lift · run           │          RLS is the boundary.
    │                       │
    │  Edge Functions:      │          The only place a provider key exists.
    │  coach                │
    │  delete-account       │
    │  daily-ai-summary     │
    └───────────────────────┘
```

## Why a monorepo

The apps share three things that are expensive to keep in sync across repos: a
design system, a database schema, and an account model. Splitting them means
every change to any of the three becomes a coordinated release across
repositories.

It's a **native pub workspace** (`workspace:` in the root `pubspec.yaml`), not
Melos. Dart 3.11 added glob support to that field, which was Melos's last
remaining advantage here — and Melos 7 dropped `melos.yaml` entirely. One
lockfile, one `flutter pub get`, no extra tool.

One sharp edge: **a workspace glob matching zero packages is a hard error**, not
an empty set. `apps/**` had to stay commented out until the first app existed.
If `apps/` ever empties again, comment it back out rather than wondering why
resolution broke.

## Layers

### `packages/mgk_ui` — the design system

Greyscale tokens, a shared motion vocabulary, and the components that implement
them. Extracted from the running app rather than designed speculatively, which
matters: every component in it was already earning its place in a real screen.

Apps declare **no colours, no motion curves, and no fonts**. If a screen needs
something the design system lacks, the fix is to add it there, not to work
around it locally.

Inter is bundled by the package, so the family is addressed as
`packages/mgk_ui/Inter`. Use `AppTheme.fontFamily` — writing the bare string
`'Inter'` resolves to nothing and silently falls back to the platform default.
That is a bug only catchable by eye, so there's a test for it.

### `apps/*` — the apps

Each is a normal Flutter app that happens to live in a workspace. They share
`mgk_ui` and the backend, and nothing else — no shared app-level code, no
cross-app imports. If two apps need the same logic, it becomes a package.

Candidates already visible in `mgk_run/lib/src/core/`: `units`, `database`,
`supabase`, `config`. All pure-Dart, all testable without Flutter. None have
been extracted yet, on the principle that a package should be pulled out of
working code rather than designed for a second caller that doesn't exist.

### `supabase/` — the backend

Schema, Edge Functions and schema tests. See
[database.md](database.md) for the schema itself.

Edge Functions exist for one reason: **there is no provider key in the client.**
Every AI call goes app → Edge Function → provider. The model is a server-side
choice, so it can be swapped as prices and capabilities move without shipping an
app update.

They also live here rather than in an app repo, which is not cosmetic — the
previous arrangement, where two repos each defined a function under the same
slug against the same project, is precisely how the account-deletion bug
happened.

## The coach

App-agnostic by design, and app-agnostic in fact: **one Edge Function serves
both apps**, with one conversation store, one rate limiter and one spend cap.
Lift and Run each contribute surfaces to the same `SURFACES` table.

A request names a `surface`, never an app. `SURFACES[name].app` is what
`core.entitlements` is keyed on, so a caller cannot ask for its Run subscription
to pay for a Lift turn — and a surface added without an app does not compile.

The rule that keeps it honest: **the model proposes, the validator disposes.**
Every LLM output — a plan, a session, a profile extraction — is a structured
proposal that passes through deterministic Dart-side validation before anything
uses it. The model never writes a number straight into a plan.

That rule also decides which model runs where. The surfaces with a validator
behind them can afford a cheap one, because a mistake comes back as a rejected
plan; the three that reach a person directly (`chat`, `summarise`, `lift_chat`)
cannot, because a mistake arrives as prose. So **tiers move the conversational
model and never the planning one** — there is nothing to sell on a surface whose
safety comes from the validator rather than from the price of the model.

Tiers are framed to users as a 1/3, 2/3, 3/3 star coach rather than by model
name, so the underlying model can change silently. Users are warned as they
approach limits and degraded to a cheaper model near the ceiling rather than
hitting a wall.

**Where each app's context comes from differs, on purpose.** Run's app renders
its own typed state into a prose brief and sends it, because the numbers a
runner cares about (paces, race predictions) are computed client-side. Lift's
log is read by the function under the caller's own JWT, so RLS scopes it and the
client cannot describe a session that did not happen.

## Cross-app awareness

The mechanism is one table, `core.activities`, written by triggers on the detail
tables. See [database.md](database.md#2-coreactivities-is-the-load-bearing-table).

The consequence worth naming: an app does not integrate with another app. It
reads a table. There is no API between Lift and Run, no shared client code, and
no version coupling — Run had to change nothing to start feeding the shared
feed.

## Identity and payment

One account across the suite (`auth.users`), with shared identity in
`core.profiles` and domain extensions in each app's own schema —
`run.runner_profiles` is the pattern.

Payment is **per app, never cross-app**, so entitlements are keyed
`(user_id, app)`. A future suite bundle is two rows, not a migration. Bundles
are deferred rather than rejected: they're additive later, whereas going the
other way would mean repricing existing subscribers.

**Cross-app visibility is free and always will be.** A Lift user seeing their
runs surface is the main funnel into the second app; paywalling it would be
charging for the thing that sells the suite.

One genuinely unsolved problem: **shared session across separate binaries.**
Free on iOS via Keychain access groups, genuinely hard on Android with no shared
keychain. The likely answer is "just log in again", which is fine, but it hasn't
been designed yet.

## Naming

The suite name is not finalised, and deliberately blocks nothing. Display
strings are cheap to change.

Exactly one naming decision is expensive later: **bundle IDs**, because they
cannot be changed on an existing App Store record. Hence
`com.mgkcodes.fitness.run` and `com.mgkcodes.fitness.lift` — "fitness" is
descriptive, not brand, so it survives whatever the suite ends up called.

Everything else stays brand-neutral for the same reason: Dart packages
(`mgk_run`, `mgk_ui`) and Postgres schemas (`core`, `lift`, `run`, `coach`).

## Testing

Four layers, each catching what the others can't:

| Layer | Tool | Catches |
|---|---|---|
| Unit + widget | `flutter test` | app logic, validators, rendering |
| Schema contract | `supabase test db` (pgTAP) | RLS gaps, privilege drift, tables that escape deletion |
| Schema reproducibility | `supabase db reset` + `db diff --linked` | the repo and the database disagreeing |
| Edge Functions | `deno test` | wire shapes, limiter failure modes |

The schema-contract layer is the one that's easy to skip and shouldn't be. It
asserts against the **real catalog**, so it fails when the database is wrong —
not merely when the SQL was written differently. Its predecessor regex-parsed
migration files, which checks a proxy for the schema rather than the schema, and
broke the moment tables started moving between schemas.

## Planning

Lift's blocks live in `lift.plans` / `plan_weeks` / `plan_sessions`, which is
`run.*` with the units changed. The arc is decided once and the sessions are
filled in a week ahead, so they are generated separately and stored separately.

**The rule worth knowing before reading any of it: the model cannot prescribe a
weight.** `lift_week`'s schema has no field for a kilogram. The coach returns an
intensity — a percentage of what the lifter can already do — and `PlanValidator`
resolves it against their own estimated 1RM, rounds to a loadable 2.5 kg, and
returns nothing at all when there is no qualifying set behind it. A null target
is a real prescription rather than a gap.

That is ADR-0003 in its strongest form. A prompt asking a model not to invent a
number is a request; a schema with nowhere to put one is a guarantee, and it
means no validator has to catch what cannot be said.

`plan_sessions.workout_id` is the join that makes "did they do the plan"
answerable without guessing which workout was probably which. It is
`ON DELETE SET NULL`, so tidying the log cannot punch holes in the block.

Changes to a running block are a **diff** (`lift_adapt`), never a regenerated
week: move, lighten, drop, swap a movement. A regenerated week would rewrite
sessions already trained and lose what actually happened. A session that has
been done is never editable — it is a record, not a draft.

## Decisions

The running app carries 20 ADRs in
[`apps/mgk_run/docs/decisions/`](../apps/mgk_run/docs/decisions/). Several are
suite-wide in effect and worth reading before changing anything structural:

- **0003** — the LLM generates, the validator enforces
- **0004** — offline-first; the device owns a run in progress
- **0005** — AGPL-3.0, and why
- **0007** — secrets via backend proxy
- **0008** — one shared Supabase platform
- **0009** — greyscale design language
