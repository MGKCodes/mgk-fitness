# MGKFitness: Lift 2.0.0 — the punch list from the first TestFlight build

What the first build on a real phone turned up, and the work it implies. The
source is a session of [testflight-2.0.0-test-sheet.md](testflight-2.0.0-test-sheet.md)
run on 2026-08-24, plus the reading of the code that followed it.

Same discipline as [release-2.0.0.md](release-2.0.0.md): tick items as they
land, and when something is settled differently from how it is written here,
**change the item and say why**. The reasoning is worth more than the checkbox.

This plan is UI and interaction only. Identity, compliance, payments and the
store submissions stay in [release-2.0.0.md](release-2.0.0.md); nothing here
replaces a phase of it.

---

## Read this before working from the report

**The build predates the shared coach mark.** The two build commits (`a5d2d3e`,
`10d1552`) landed on 2026-08-21 at 14:52 and 15:06. `c04193d`, which moved the
coach mark into `mgk_ui` and deleted this app's own 56px circle, landed at 18:24
and was not pushed until 2026-08-24. Codemagic builds from the remote, so that
build **cannot** contain it.

So "the coach icon is different between the two apps" was true of the build and
is already false of the branch. Nothing to fix; there is a build to cut. The
same caveat applies to anything else on the report that looks like a styling
difference — **re-cut before judging parity**, or the sweep will chase things
that are already gone.

## The thing underneath most of this

`mgk_ui` exports twenty-eight modules, including `app_card`, `app_radius`,
`stat_block`, `primary_button`, `section_label`, `glass_surface` and
`press_scale`. This app imports that package and then hand-rolls its own version
anyway.

The rest timer is the clean example: `rest_bar.dart` builds a bare
`Material(color: AppColors.surface)` with no shape anywhere in the file, while
`AppRadius.sheet` (20) and `AppRadius.cardAll` sit in the package it already
depends on. The coach mark was the same defect, and it took **rendering the
screen and looking at it** to find — which is the lesson worth carrying into
Phase A. A hand-rolled surface does not fail a test; it just looks wrong next to
the other app.

So "make this app's UI exactly like Run's" is not a restyle. It is a sweep for
every place this app draws something the shared package already owns.

---

## Phase A — the app speaks the shared vocabulary

Cheapest phase, and it closes several report items at once. Nothing here is in
doubt.

- [ ] **Re-cut a build before judging parity.** See above. Everything else in
      this phase can proceed without waiting for it; only the *verification* of
      parity needs it.
- [ ] **Rest timer corner radius.** `rest_bar.dart` has no shape at all. Give it
      the shared token rather than a number — `AppRadius.sheet` is what a
      bottom-anchored surface uses elsewhere. **Verified:** grep of the file
      returns exactly one styling line, `color: AppColors.surface`.
- [ ] **Sweep the rest of the presentation layer.** Every container, radius,
      button and surface in `apps/mgk_lift/lib/src/features/*/presentation/`
      that `mgk_ui` already owns. Do it by rendering screens, not by reading —
      that is how both known instances were found.
- [ ] **Two `coach_sheet.dart` files.** One in `coaching/presentation/`, one in
      `planning/presentation/`. Establish whether they are duplicates, and if so
      which one is the considered version. Same shape of problem one layer up
      from the coach mark, and worth checking *before* the sweep so the sweep
      does not tidy both copies of the same thing.

## Phase B — the active session

- [ ] **A set cannot be removed.** `exercise_card.dart` has `onRemove`, but its
      tooltip is `Remove ${exercise.name}` — it removes the whole movement.
      Nothing removes a single set. **Verified:** confirmed gap, not a wiring
      fault.
- [ ] **Set types: two of the four this app used to have.** Tapping the set
      number toggles warm-up and the cell renders `W` or the set number.
      Liftio had **the same interaction** with four types — Normal, Warm-up
      (`W`), Drop Set (`D`), Failure (`F`) — see
      `Liftio/components/workout/ExerciseCard.tsx`, whose own tooltip reads
      *"Tap a set number to change its type"*.

      **This corrects the report.** There is no dropdown failing to open; there
      is no dropdown, and there never was one in either app. The interaction
      carried over and the vocabulary did not. The half that *did* carry is the
      part that matters for correctness — Liftio excluded warm-ups from volume
      and PB tracking, and this app already does the same through `workingSets`.
      **Settled 2026-08-24: all four come back**, cycled by tapping the set
      number, as Liftio did. Warm-ups stay out of volume and PB tracking; drop
      sets and failure sets count, which is what Liftio did and what the
      `workingSets` split already implements.
- [ ] **The top bar is a strip, not a widget.** `_Header` takes name, elapsed,
      volume, completed sets and the finish button and compresses them into a
      row. Wanted: something that reads as a card carrying the session's state.
- [ ] **Previous stat.** *"What you did on this movement last time"* is the
      number you actually want mid-set. Note this is **per-movement**, so it
      belongs on the exercise card rather than the session header — the two
      items above are adjacent but not the same job. **Settled 2026-08-24: the
      exercise card**, at the point of use. The domain layer can already answer
      it (see Phase C).

### A workout library, which is not what the picker is

The report asked for "templates or sessions to start from". Read as a request to
promote `TemplatePickerSheet`, that reverses the Knowledge entry *"Lift
templates are the coach's grounding layer, not a user-facing library"*. **It
turns out not to be that request**, and the two do not conflict.

What is wanted is Liftio's actual model, which had two separate things the
Flutter port collapsed into one:

1. **Premades** — the fifteen ready-made sessions and eight splits, ported into
   `workout_templates.dart`. In Liftio these were never something you started a
   session from. `WorkoutLibrarySlideUp.tsx` let you browse them and **add** one
   to your own library, writing a `workouts` row with `is_template = 1` and a
   `premade_id` back-reference.
2. **Your library** — your saved workouts, whether added from a premade, built
   by hand in `create-template.tsx`, or generated by the coach. *This* is what
   you start a session from.

So the app-provided list stays the coach's raw material, exactly as the decision
says, and the user-facing surface is the lifter's own saved work. **The decision
is upheld, not superseded.** What gets deleted is the current shortcut —
`_useTemplate` tipping a premade's exercises straight into a blank session.

The schema is already most of the way there: `isTemplate` and `templateId` exist
on the workouts table and in `supabase_sync.dart`, and the remote constraint
`workouts_template_has_no_date` already enforces that a template carries no
`started_at`. **Nothing in the app writes `isTemplate = true` today.**

- [ ] **Save a workout to the library.** From a finished session, from a
      coach-generated one, and from scratch. This is the write path nothing
      currently exercises.
- [ ] **The library surface.** Your saved workouts, and starting a session from
      one. Replaces `Use a template` in the empty state.
- [ ] **Adding a premade to your library.** Browse the fifteen and the eight
      splits, add to your own list. Liftio's `WorkoutLibrarySlideUp` is the
      reference. Keeps the empty-state problem `workout_template.dart` was
      written to solve, without making the premades a start path.
- [ ] **Decide the back-reference.** Liftio had both `template_id` and
      `premade_id`; the Flutter schema has only `templateId`. Either add the
      second column or accept one field doing both jobs — but decide it before
      the write path lands, because it is a migration afterwards.
- [ ] **Retire `_useTemplate`.** The straight-to-session shortcut goes once the
      library replaces it. Do not leave both.

## Phase C — Profile

The largest phase, and the one with an existing design to work from.

- [ ] **The surface collapses when the log is empty.** `profile_surface.dart`
      line 87: `if (log.isEmpty) _Empty(onOpenTrack:)` replaces the entire
      contents. A new lifter sees one empty-state widget and learns nothing
      about what the app will track for them.

      Wanted: the real layout, with placeholder grids, so the screen advertises
      lifetime volume, PBs, streak and history rather than hiding them until
      they have values.
- [ ] **Surface what the domain layer already computes.** This is presentation
      work, not modelling work. `TrainingStats` already returns `sessions`,
      `totalVolume`, `totalSets`, `totalTime`, `currentWeekStreak`,
      `longestWeekStreak` and `sessionsPerWeek`, plus `byFrequency` and
      `bestOneRepMax` per movement. Profile shows six of those and **no PBs at
      all**, despite the estimator existing.

      Worth knowing before using it: `estimateOneRepMax` is Epley, capped at
      **12 reps**, returning null above that. Liftio capped at 30. The cap was
      tightened on purpose — *"a confidently wrong PB is worse than no PB"* —
      so a PB surface has to render "no estimate yet" as a real state.
- [ ] **Port the year activity grid.** Source:
      `Liftio/components/shared/YearActivityGrid.tsx`, used at
      `app/(tabs)/logs.tsx:132`.

      Shape: a **rolling** 52 weeks ending today, not a calendar year; seven
      days per column; 2px gaps; month labels above.

      The part to port carefully is the shading. Five opacity tiers (0.40 →
      1.00) thresholded against the *window's own* median and 95th-percentile
      session duration, rather than a fixed scale. That is what keeps it
      readable whether someone trains twice a week or six times — a fixed scale
      makes a light trainer's year uniformly pale and a heavy one uniformly
      solid, and in both cases the grid stops carrying information.
- [ ] **PBs, lifetime totals, per-movement history.** The remaining half of what
      the report describes as "just thrown in there". Scope this after the grid
      lands, since the grid establishes the surface's layout.

## Phase D — the coach remembers, but the screen does not

- [ ] **Resumable transcript on open.** Already carried on
      [release-2.0.0.md](release-2.0.0.md) Phase 5, written before this build
      was tested: *"the memory survives and the screen does not, which reads as
      amnesia even though it isn't."* The report confirms it from the phone.
      **Verified:** `CoachMemoryStore` and `coach_memory_screen.dart` both
      exist, so the coach genuinely does remember.
- [ ] **Sessions, with history.** Beyond the Phase 5 item: closing the app, or
      tapping a suggested question, starts a *new* conversation, and the old one
      is kept as a readable "previous chats" list that the coach still draws on
      when relevant.

      The run app is getting the same capability in separate work. **Settled
      2026-08-24: wait and copy the run app's model.** Designing it twice is the
      more expensive mistake, and this is a model that should be identical in
      both apps. Phase D therefore blocks on work not visible from this
      session — which is a reason to run Phases A to C first, not a reason to
      revisit the choice.

---

## Settled, 2026-08-24

All four questions this plan opened were answered the day it was written. Kept
rather than deleted, because the reasoning is the part worth having later.

1. **Templates.** Neither promoted nor deleted — the request was for a
   different thing than the picker, and the recorded decision stands. See *A
   workout library* above.
2. **Set types.** All four of Liftio's, cycled by tapping the set number.
   Warm-ups excluded from volume and PBs; drop sets and failure sets counted.
3. **Chat history.** Wait and copy the run app's model rather than designing it
   twice.
4. **Previous stat.** On the exercise card, at the point of use.

## Still open

- **Nothing blocks Phases A or C.** Both can start now.
- Phase B's library work needs the back-reference column decided before the
  write path lands.
- Phase D is blocked on the run app, by choice.

## Not in this plan

Named so they are decisions rather than omissions.

- **Anything under `apps/mgk_run`.** The run app's own punch list is being
  worked separately. Shared-package changes made here will reach it, which is
  the point of the package, but no run screen is touched from this plan.
- **Payments.** Phase 3 of [release-2.0.0.md](release-2.0.0.md), untouched.
- **Elevation, steps and Health integration.** Those came from the run app's
  testing and do not apply here.
