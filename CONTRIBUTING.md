# Contributing

Thanks for looking. This is a real project rather than a demo, so the bar is the
bar — but the rules are short and the reasoning is written down.

## Before a big change

Open an issue first. A pull request that redesigns something is harder to accept
than a conversation that agrees on the design, and it's a worse use of your time
if the answer is no.

Small fixes — a bug, a doc gap, a broken example — just send them.

## Branching

`main` is the trunk. There is no long-lived `develop`: releases are tagged
builds, so a permanent second trunk would buy staging this project doesn't need
and cost a merge hop on every change.

Branches are named for the **lane** they own — the top-level tree the work
belongs to:

```
lift/rest-timer          apps/mgk_lift/
run/split-drift          apps/mgk_run/
ui/glass-tokens          packages/mgk_ui/
db/session-schema        supabase/
```

The lane is deliberately coarser than the commit scope. `feat(coach)` and
`feat(db)` are both `lift/` branches, because coaching and the drift schema
both live inside `apps/mgk_lift` and can't be worked on independently anyway.

### Two lanes at once

Two apps sharing a design system means two people — or two agents — working at
the same time is the normal case, not the exception. What makes it safe is a
worktree, not a branch:

```sh
git worktree add .claude/worktrees/lift lift/rest-timer
```

A branch on its own isn't enough. Both checkouts would still share one working
tree and one index, so `git add -A`, `git stash` or `git reset --hard` from
either side reaches into the other's uncommitted work and there is no undo. A
worktree gives each lane its own index and its own files.

A fresh worktree is a fresh checkout: `.dart_tool/` and `*.g.dart` are ignored,
so pub resolution and generated code don't come with it. Run Setup inside the
worktree before `flutter analyze` there means anything.

### Shared packages

`mgk_ui` and `mgk_units` are imported by both apps, so they are the one place
lanes overlap. The line that matters is additive versus mutative:

- **Adding** — a new widget in a new file, plus one export in `mgk_ui.dart` —
  is fine from any lane. Nothing that already exists changes behaviour, and the
  only shared surface is a one-line append that merges cleanly.
- **Changing** an existing widget's API, or any colour, spacing or motion
  token, changes both apps underneath whoever else is working. That goes on a
  `ui/` branch, merges to `main` first, and the app lanes rebase onto it.

This isn't ceremony about small edits. A token change is a two-app change
whether or not the second app is open in front of you, and the person who finds
out is the one whose running app just started rendering wrong.

## Sign your commits (DCO)

Every commit needs a [Developer Certificate of
Origin](https://developercertificate.org/) sign-off:

```sh
git commit -s -m "fix(run): stop the split timer drifting on resume"
```

That adds a `Signed-off-by:` line, which is you asserting you have the right to
submit the code under this project's licence. No CLA, no copyright assignment —
just the DCO.

Forgot on the last commit: `git commit --amend -s --no-edit`.

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/), scoped to the
package:

```
feat(run): end the plan flow on the plan
fix(ui): stop PrimaryButton eating taps while busy
docs(db): explain why activities uses typed refs
```

Write the subject as what the change *does for someone*, not which files moved.

## Definition of done

A change is done when:

- `flutter analyze` is clean across the workspace — no new warnings.
- `dart format .` has been run.
- New behaviour has tests. Validator invariants need regression coverage.
- If it changes the schema: `supabase db reset` replays cleanly,
  `supabase test db` passes, and `supabase db diff --linked` reports nothing.
- If it changes a decision: the relevant ADR is updated **in the same PR**.

That last one matters more than it looks. A decision record that lags the code
is worse than no decision record, because people trust it.

## Setup

```sh
flutter pub get      # from the repo root — resolves the whole workspace
flutter analyze
```

For anything touching the database you'll want Docker, which gets you the whole
Supabase stack locally:

```sh
supabase start
supabase db reset    # rebuild from migrations alone
supabase test db     # schema invariants
```

Work against the local stack, never against a hosted project. `supabase db
reset` is destructive by design and takes whatever database it is pointed at.

## Rules that aren't negotiable

These are load-bearing. A PR that breaks one won't be merged even if the code is
good.

1. **No provider key in the client.** Every AI call goes app → Edge Function →
   provider. If you find yourself needing a key in Dart, the design is wrong.
2. **The model proposes, the validator disposes.** LLM output is a structured
   proposal that passes deterministic validation before anything uses it. The
   model never writes a number straight into a plan.
3. **RLS on every table, scoped to `auth.uid()`.** The anon key is public and
   meant to be. Row-level security is what protects data, so a new table without
   a policy is a data leak, not a to-do.
4. **Every user-owned table gets a `user_id`.** Account deletion enumerates
   tables by that column. A table without one silently escapes erasure — a GDPR
   problem no test would catch.
5. **Offline-first.** The device owns a run in progress. Persist as data
   arrives; never hold a session only in memory.
6. **Store metric, convert at display.** Distances and paces are metric
   everywhere; km/mi conversion happens at the display layer only.
7. **No Strava, no copyrighted training tables.** Don't integrate Strava in any
   form. Don't reproduce VDOT tables or published plan schedules — derive paces
   from formulae.
8. **Health data is special-category data.** Never log raw health values. A
   denied permission is indistinguishable from no data, so design for absence
   rather than error states.

## Design changes

Colours, spacing, motion and components live in `packages/mgk_ui`. Apps declare
none of them.

If a screen needs something the design system doesn't have, add it to `mgk_ui`
rather than working around it locally — the whole point is that the suite reads
as one product. The rules that aren't expressible in code are in that package's
README.

## Licence

Contributions are licensed under [AGPL-3.0](LICENSE), same as the project.
