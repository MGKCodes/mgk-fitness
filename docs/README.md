# Suite documentation

**Everything here describes the suite — the things both apps share.** Anything
belonging to one app lives in that app's own `docs/`, next to the code it
describes.

| | Goes here | Goes in `apps/<app>/docs/` |
|---|---|---|
| **Test** | Would it still be true if one app were deleted? | Would it stop being true? |
| **Examples** | the Supabase schema, the design language, the naming rules, navigation, the coach's profile | a release plan, a TestFlight sheet, an app's ADRs, an app's local data model |

That boundary held for the reference documents and failed for the work ones:
Lift's release plan and test sheet sat here until 2026-09-03, not by choice but
because `apps/mgk_lift/docs/` did not exist. They are there now, and both apps
have the same shape.

## Reference

- **[architecture.md](architecture.md)** — how the suite fits together, and the
  decisions that shaped it.
- **[database.md](database.md)** — one Supabase project, the `core` / `coach` /
  `run` / `lift` schemas, and what the shape used to be. Each app's *local*
  mirror is documented in that app.
- **[design.md](design.md)** — the design principles. The implementation is
  [`packages/mgk_ui`](../packages/mgk_ui), which is the design system rather
  than a description of one.
- **[naming.md](naming.md)** — what the platform is called, what each app is
  called, and the six manual escapes that cannot read Dart. `naming_test.dart`
  enforces the rest.
- **[navigation.md](navigation.md)** — the shell, the tabs, and where the coach
  lives.
- **[plan-model.md](plan-model.md)** — standing plans, and why they are not
  blocked.
- **[coach-profile.md](coach-profile.md)** — the shared profile, and what the
  coach is allowed to know.
- **[research/training.md](research/training.md)** — the training claims the
  apps are built on. Grounding for the coach lives in
  [`supabase/knowledge/`](../supabase/knowledge).

## Work

- **[going-public.md](going-public.md)** — what was checked before the
  repository is made public, what it found, and what is left for the day. It
  has an end date: the day after.

## History

- **[roadmap.md](roadmap.md)** — worked through on 2026-08-07 and kept rather
  than deleted. **It is finished, and it name-collides with
  [`apps/mgk_run/docs/roadmap.md`](../apps/mgk_run/docs/roadmap.md), which is
  live.** Check which one you have open.

## Per app

- **[apps/mgk_run/docs/](../apps/mgk_run/docs/)** — 30 documents, and the
  filing rule the suite follows: documents tier by **lifecycle**, not topic.
  Decisions are never edited, architecture is edited whenever the code moves,
  and work documents have an end date.
- **[apps/mgk_lift/docs/](../apps/mgk_lift/docs/)** — the 2.0.0 release, and
  Lift's own decisions.

## Elsewhere

- **[CONTRIBUTING.md](../CONTRIBUTING.md)** — suite-wide conventions.
- **[supabase/](../supabase/)** — migrations, Edge Functions, and a README per
  function.
- **[web/](../web/)** — the static site behind `mgkfitness.mgkcodes.com`,
  generated from each app's legal source so a reviewer's word-for-word check is
  enforced by CI.
