# 0008 — Shared Supabase project (the MGKCodes fitness platform)

**Status:** Accepted

## Context

Runio (running) and Liftio (lifting) are being built as **sister apps**: a
shared account, data each app can read from the other (e.g. a lifting coach that
sees your runs), both moving to an AI-coach model, and both intended to go open
source. Liftio may also move to Flutter in a future v2.

A Supabase project has exactly **one** `auth.users` pool — auth cannot be split
within a project. So the choice of one-project-vs-two *is* the choice of
shared-login-vs-separate. Given the product intent, a shared login is a feature,
not a liability. Practical facts confirmed at decision time:

- Liftio's project already has `public.profiles` (identity) and
  `public.user_settings.distance_unit` — the shared identity and unit preference
  Runio needs already exist.
- The account is on Supabase's free tier (2-project limit), already used by
  Liftio and frunt. A dedicated Runio project would force a paid plan.

## Decision

Runio **shares Liftio's Supabase project**, reframed as the MGKCodes fitness
platform backend.

- Runio's tables live in a dedicated **`runio` schema**; Liftio stays in
  `public` for now (it can move to a `liftio` schema during its v2).
- Runio **reuses `public.profiles`** (identity) and
  `public.user_settings.distance_unit` (display units); body metrics `dob` and
  `weight_kg` were added to `public.profiles` as shared, additive, nullable
  columns.
- **RLS on every `runio` table**, row-scoped to `auth.uid()`. Cross-app reads
  for the same user are then trivial and safe.
- Runio's repo owns its migrations for now (`supabase/migrations/`). **One
  database, one migration home** — no second repo migrates it independently.

## Consequences

- Shared login and shared identity across both apps, by construction. Liftio's
  existing users are valid Runio logins.
- Cross-app data reads need no cross-project plumbing.
- **Shared blast radius**: one project means shared limits and shared fate for
  migrations/incidents. Mitigated by additive, isolated migrations and RLS; the
  earlier open-source-vs-closed concern is moot since both apps go open source.
- When Liftio joins the platform properly (its v2), revisit: move Liftio into a
  `liftio` schema and/or extract migrations to a neutral infra repo.
- Once both are Flutter, shared concerns (units, auth, profile) can become a
  shared Dart package — the units domain is already a candidate.
