# Contributing

Thanks for looking. This is a real project rather than a demo, so the bar is the
bar — but the rules are short and the reasoning is written down.

## Before a big change

Open an issue first. A pull request that redesigns something is harder to accept
than a conversation that agrees on the design, and it's a worse use of your time
if the answer is no.

Small fixes — a bug, a doc gap, a broken example — just send them.

## Branching

Two long-lived branches, and nothing else:

- **`develop`** is where the work happens: both apps, the shared packages and
  the backend. Anything an app is built from lives here.
- **`main`** is what has shipped. `develop` is promoted to it when both apps
  release, and the release is tagged (`run/build-27`).

**The website is the exception.** `web/` is not an app release and can move
ahead of the apps, so a change there merges **straight to `main`**, which Vercel
deploys, and `main` is then merged back into `develop` so that `develop` always
contains it. The pages under `web/public/` are generated from each app's
`docs/`: regenerate them on `develop`, and they can go to `main` while the
in-app copy waits for the next build.

There are no per-app lanes. Run and Lift once lived on separate `run/` and
`lift/` branches, and the shared packages drifted apart between them: the same
fix was copied across by hand, and one merge met eleven conflicts in shared
files (1 October 2026). A short-lived branch is still fine for work that needs
isolation, such as a risky refactor or a pull request. Name it for what it does
(`fix/split-drift`), merge it back into `develop`, and delete it the same day.

### Two sessions at once

Two people, or two agents, working at the same time is the normal case. What
keeps it safe is a worktree for the short-lived branch, not the branch alone:

```sh
git worktree add .claude/worktrees/split-drift -b fix/split-drift develop
```

A branch on its own isn't enough. Both checkouts would still share one working
tree and one index, so `git add -A`, `git stash` or `git reset --hard` from
either side reaches into the other's uncommitted work and there is no undo. A
worktree gives each its own index and its own files. Remove it
(`git worktree remove`) and delete the branch once it is merged.

A fresh worktree is a fresh checkout: `.dart_tool/` and `*.g.dart` are ignored,
so pub resolution and generated code don't come with it. Run Setup inside the
worktree before `flutter analyze` there means anything.

### Shared packages

`mgk_ui`, `mgk_auth` and `mgk_units` are imported by both apps, so a change to
one is a change to both. The line that matters is additive versus mutative:

- **Adding** (a new widget in a new file, plus one export in `mgk_ui.dart`)
  changes nothing that already exists.
- **Changing** an existing widget's API, or any colour, spacing or motion
  token, changes both apps. Do it anyway where the work calls for it: most of
  the good design-system changes are found while building a real screen, and
  the shared layer only improves if that is allowed.

  What is not optional is finishing it: **run the other app's suite before
  pushing to `develop`, and say in the commit what will look different
  there.** The full set is Run, Lift, `mgk_ui`, `mgk_auth` and
  `deno test supabase/functions`.

A token change is a two-app change whether or not the second app is open in
front of you, and the person who finds out is the one whose running app just
started rendering wrong. Running their tests is how you find out first.

Worked example: work on Run changed `HeroNumeral`, `PressScale`, `AppCard`,
`PaceBandMeter`, `MgkPageTransitions` and the button font token at once. All
six were right, and Liftio inherited a font correction it had never asked for.
What made that safe was `flutter test apps/mgk_lift` before the merge, not the
branch it happened on.

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
- If someone using the app would notice: a line in that app's `CHANGELOG.md`,
  under `[Unreleased]`, **in the same PR**.

The last two matter more than they look. A decision record that lags the code is
worse than no decision record, because people trust it. And a changelog is the
only part of this repo written for somebody who will never read the commits —
the reason it is here at all is that this project is public and AGPL, and
"notable changes" is what a stranger gets instead of your git log.

The test for whether a change earns a line is not how hard it was. It is whether
a person using the app would notice. A refactor with no behaviour change earns
nothing; a two-character fix that stops the pace freezing earns a line.

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
