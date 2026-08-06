# Run — instructions for Claude Code

Read this before making changes in `apps/mgk_run/`. Suite-wide rules are in the
repo root's [CONTRIBUTING.md](../../CONTRIBUTING.md); this file covers what is
specific to the running app.

## Current state

**Built and working, not yet released anywhere.** Tracking, plan generation and
the coach all run; 917 tests pass. `lib/` holds ~178 Dart files.

This was previously a standalone repo called Runio. It moved into the monorepo
on 2026-08-06 and was repointed at `packages/mgk_ui`. If you find a doc here
still describing a pre-scaffold design phase, or referring to a `runio` Postgres
schema, it is stale — say so rather than working around it.

## The load-bearing rules (do not violate)

1. **Offline-first.** A run in progress is owned by the on-device database.
   Supabase is a backup / cross-device store, not the source of truth for live
   recording. Persist run points **as they arrive** — never hold a run only in
   memory.
2. **The model proposes, the validator disposes.** Every LLM output (plan,
   session, profile extraction, adaptation) is a structured proposal that passes
   deterministic Dart-side validation before it is used. The model never writes
   a number straight into a plan.
3. **No provider key in the client.** All AI calls go
   `app → Supabase Edge Function → LLM provider`. The model is a server-side
   choice, not hard-wired. See
   [docs/architecture/llm-and-secrets.md](docs/architecture/llm-and-secrets.md).
4. **Store metric, convert at display.**
5. **No Strava. No copyrighted training tables.** Do not integrate Strava in any
   form. Do not reproduce VDOT tables or published plan schedules — derive paces
   from formulae (Riegel, % of threshold). This repo is public.
6. **Health data is special-category data.** Never log raw health values. A
   denied HealthKit read is indistinguishable from no data — design for absence,
   not error states.

## Working in a monorepo now — what changed

- **Nothing visual lives here.** Colours, motion and components come from
  `packages/mgk_ui`. If a screen needs something it lacks, add it *there*.
  There is no `lib/src/core/theme/` any more — it was deleted, not moved.
- **Inter comes from the package**, so the family is `packages/mgk_ui/Inter`.
  Use `AppTheme.fontFamily`; the bare string `'Inter'` silently falls back to
  the platform default.
- **The schema is not here.** It lives in `supabase/` at the repo root. Do not
  add migrations under this directory.
- **Postgres schemas are named explicitly.** `.schema('run')`,
  `.schema('coach')`, `.schema('core')`. The client defaults to `public`, which
  is now empty, so an un-namespaced call fails at runtime with a 404 rather than
  at compile time. There is no `runio` schema.
- **`flutter pub get` at the repo root**, not here — it resolves the whole
  workspace.

## Conventions

- **Commits:** Conventional Commits, scoped (`feat(run): …`), with DCO sign-off
  — always `git commit -s`.
- **Formatting:** `dart format .`; no new `flutter analyze` warnings.
- **Tests:** new behaviour needs tests; validator invariants need regression
  coverage.
- **Attribution:** this is an **MGKCodes** (business hat) project.

## Testing traps

- `PrimaryButton(busy: true)` renders an indeterminate spinner, so
  `pumpAndSettle` never returns on a screen showing one. Use `pump(duration)`.
- **Do not test schema guarantees from Dart.** Things like "coach memory is
  erased on account deletion" or "the transcript is append-only" are pgTAP
  assertions in `supabase/tests/`, run by `supabase test db`. They check the
  real catalog. The previous versions regex-parsed migration files and broke the
  moment tables moved between schemas — which is exactly the class of change
  they existed to survive.

## Where things live

- `docs/product-spec.md` — the source-of-truth product definition.
- `docs/architecture/` — run recording, plan generation, onboarding, LLM and
  secrets.
- `docs/decisions/` — 20 ADRs (the *why*).
- `docs/roadmap.md` — phased build order.
- `docs/compliance.md`, `docs/privacy-policy.md`, `docs/medical-disclaimer.md`.

## Definition of done

Format clean, analyzer clean, tests pass, commit signed off, and — if the change
alters a decision — the relevant ADR and `docs/` are updated in the same PR.
