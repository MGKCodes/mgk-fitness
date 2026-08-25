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
- [x] **Rest timer corner radius.** `rest_bar.dart` has no shape at all. Give it
      the shared token rather than a number — `AppRadius.sheet` is what a
      bottom-anchored surface uses elsewhere. **Verified:** grep of the file
      returns exactly one styling line, `color: AppColors.surface`.
- [x] **Sweep the rest of the presentation layer.** Done, and it found
      something felt rather than seen. Lift had 29 raw `TextButton`s and
      `IconButton`s and zero of the shared ones; Run has 4 and 32. Those
      wrappers exist because Material's `Feedback.forTap` is a haptic on
      Android and **nothing on iOS**, so every cancel, close and back arrow in
      Lift was dead under the finger on the platform shipping first. All 29
      converted; the 4 left raw are `OutlinedButton`s, which have no shared
      variant — exactly the 4 Run kept.

      Hardcoded radii were *not* the problem: Lift had one, Run has eighteen.
      On that axis Lift was the cleaner app and the rest timer was the outlier.

      Original scope: Every container, radius,
      button and surface in `apps/mgk_lift/lib/src/features/*/presentation/`
      that `mgk_ui` already owns. Do it by rendering screens, not by reading —
      that is how both known instances were found.
- [x] **One heading convention, across both apps.** Added 2026-08-25, from the
      Run/Lift screen comparison. Lift's Profile announced itself with a
      `SectionLabel` — the same component its own subsections use — so the
      screen title and its section headings were set identically and the
      surface had no hierarchy. It was the only screen in either app
      introducing itself the way it introduces its own parts. Now an eyebrow
      and a headline, matching Lift's own Track and Run's app-bar title.
- [x] **Two `coach_sheet.dart` files.** Not duplicates — one is the coach as a
      sheet, one is the shell that "ask the coach to change something" sheets
      share. Nothing imported both, so the collision never failed a build; it
      just made every doc reference ambiguous, including two that pointed the
      wrong way. The planning one is now `AskCoachSheet`. Original scope: One in `coaching/presentation/`, one in
      `planning/presentation/`. Establish whether they are duplicates, and if so
      which one is the considered version. Same shape of problem one layer up
      from the coach mark, and worth checking *before* the sweep so the sweep
      does not tidy both copies of the same thing.

## Phase B — the active session

- [x] **A set cannot be removed.** Needed no new plumbing:
      `SessionRecorder.removeSet` has existed and been implemented since the
      beginning and only the UI was missing. Swipe to remove, as Liftio did —
      but see the code for a limit that did not survive the port.
      Original finding: `exercise_card.dart` has `onRemove`, but its
      tooltip is `Remove ${exercise.name}` — it removes the whole movement.
      Nothing removes a single set. **Verified:** confirmed gap, not a wiring
      fault.
- [x] **Set types: two of the four this app used to have.** Turned out to be a
      data-fidelity fix as much as a feature — `fromStored` mapped every
      unrecognised value to `working`, so the `dropset` and `failure` rows the
      shipped app already wrote to the cloud were being read back as ordinary
      working sets. Original finding: Tapping the set
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
- [x] **The top bar is a strip, not a widget.** `_Header` takes name, elapsed,
      volume, completed sets and the finish button and compresses them into a
      row. Wanted: something that reads as a card carrying the session's state.
- [x] **Previous stat.** *"What you did on this movement last time"* is the
      number you actually want mid-set. Note this is **per-movement**, so it
      belongs on the exercise card rather than the session header — the two
      items above are adjacent but not the same job. **Settled 2026-08-24: the
      exercise card**, at the point of use. The domain layer can already answer
      it (see Phase C).

- [x] **A screen after you finish.** Added 2026-08-25, from the Run/Lift
      comparison: Run has a summary, Lift finished a session and dropped you
      back with nothing. Now the four figures, any personal bests, and the
      movements with the sets actually logged.

      The personal-best rules are decisions, not implementation. Strictly
      greater, because matching a best is not setting one. A movement with **no
      history is not a best** — there is nothing to have beaten, and counting
      it would make a first session nothing but bests. The session is filtered
      out of its own log by id. And "no estimate" is a separate fact from
      "nothing beat your best", because Epley is capped at 12 reps.

      Saving to the library moved here from a dialog on Finish. The reason was
      already in the code it replaced: saving is a decision about the shape of a
      session made *after* seeing it, and until this screen there was nowhere
      to see it.

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

- [x] **Save a workout to the library.** From a finished session, from a
      coach-generated one, and from scratch. This is the write path nothing
      currently exercises.

      **Landed as one write method, not three.** `WorkoutLibrary.save` takes a
      name and an ordered list of movement names, because all three ways in
      reduce to exactly that — the session screen reads them off the session,
      the premade browser reads them off the premade, the builder collects them
      one at a time. Three methods would have been three chances to write a
      half-formed row.

      Two entry points on the active session, deliberately: a footer button
      that works at any point (which is how a *coach-generated* session gets
      kept without being performed first), and an offer at Finish (which is the
      only moment the app knows a session actually worked). The Finish offer is
      suppressed for a session that came from the library or was already saved.
- [x] **The library surface.** Your saved workouts, and starting a session from
      one. Replaces `Use a template` in the empty state.
- [x] **Adding a premade to your library.** Browse the fifteen and the eight
      splits, add to your own list. Liftio's `WorkoutLibrarySlideUp` is the
      reference. Keeps the empty-state problem `workout_template.dart` was
      written to solve, without making the premades a start path.

      **All fifteen and all eight, so `offered` now orders rather than
      filters.** The flag existed to keep the *picker* to six, because starting
      a session is a decision made standing up in a hurry. Curating a library is
      the opposite kind of decision, so hiding nine of the fifteen there would
      be withholding for no reason the app could give. The six still lead the
      list. See `WorkoutTemplate.offered`.
- [x] **Decide the back-reference.** Liftio had both `template_id` and
      `premade_id`; the Flutter schema has only `templateId`. Either add the
      second column or accept one field doing both jobs — but decide it before
      the write path lands, because it is a migration afterwards.

      **Settled: add the column.** `premadeId` on `Workouts`, schemaVersion
      4 → 5, one `addColumn` and no backfill. Three reasons, in order of
      weight:

      1. **It needs no Supabase migration and never will.**
         `lift.workouts.premade_id` has existed remotely since the Liftio
         baseline (`20260806120000_baseline.sql:148`). The fear that made this
         a decide-first item was a remote migration, and there isn't one.
      2. **The two fields answer different questions about different rows** —
         `templateId` on a *session* means "the saved workout this came from",
         `premadeId` on a *template* means "which of the fifteen this was added
         from". One column doing both would be disambiguated only by
         `isTemplate`, so every reader would have to check a flag before it
         could know what the string it was holding meant.
      3. **Now is strictly cheaper than later**, which is the item's own
         argument: after the write path ships, the same migration also needs a
         backfill guessing which meaning each existing value carried.
- [x] **Retire `_useTemplate`.** The straight-to-session shortcut goes once the
      library replaces it. Do not leave both.

      Gone, and `template_picker_sheet.dart` with it — it had exactly one
      caller. Its split-tile visual survives in `premade_library_sheet.dart`,
      where a tap *adds* rather than starts.

### What the library work turned up

Two things worth carrying, found while building the above.

- **A template row is indistinguishable from an interrupted session on
  `endedAt` alone.** Both are workout rows that never ended.
  `DriftSessionRecorder.current()` checked only `endedAt` and `deletedAt`, so
  the moment the library had anything in it, "Resume session" would have
  offered the lifter one of their own routines — and finishing it would have
  filed a workout they never did. Fixed with an explicit `isTemplate` clause;
  `SyncQueue.dirtyWorkouts` gained the same clause for the same reason, rather
  than relying on the `endedAt` rule to exclude templates by coincidence.

- **The pull could not read a template, and there are 47 of them up there.**
  `supabase_sync._applyRemote` did `raw['started_at'] as String`, and
  `workouts_template_has_no_date` requires a template's `started_at` to be
  null — `20260806150000_lift_schema_modernise.sql` records that `date = 0`
  held for "exactly the 47 templates". The cast would have thrown and taken the
  whole pull with it. It never fired only because nothing in this app had ever
  asked for a template. Now guarded, and a remote template maps to a local one,
  so an old Liftio library comes back on a new phone.

**Templates go down but not up, for now, and that is a stated limit rather than
an oversight.** The push writes `started_at` unconditionally, which the remote
constraint forbids for a template — and `_push` walks the dirty rows in a loop,
so one server-rejected row would block every real session queued behind it.
Lifting this is a branch in the upsert, not a migration (the nullable
`started_at` and `premade_id` are both already remote), but it is a change only
the live server can prove, so it is not made blind. **The limit in plain words:
a library built on this phone does not survive losing this phone.**

## Phase C — Profile

The largest phase, and the one with an existing design to work from.

- [x] **The surface collapses when the log is empty.** `profile_surface.dart`
      line 87: `if (log.isEmpty) _Empty(onOpenTrack:)` replaces the entire
      contents. A new lifter sees one empty-state widget and learns nothing
      about what the app will track for them.

      Wanted: the real layout, with placeholder grids, so the screen advertises
      lifetime volume, PBs, streak and history rather than hiding them until
      they have values.
- [x] **Surface what the domain layer already computes.** This is presentation
      work, not modelling work. `TrainingStats` already returns `sessions`,
      `totalVolume`, `totalSets`, `totalTime`, `currentWeekStreak`,
      `longestWeekStreak` and `sessionsPerWeek`, plus `byFrequency` and
      `bestOneRepMax` per movement. Profile shows six of those and **no PBs at
      all**, despite the estimator existing.

      Worth knowing before using it: `estimateOneRepMax` is Epley, capped at
      **12 reps**, returning null above that. Liftio capped at 30. The cap was
      tightened on purpose — *"a confidently wrong PB is worse than no PB"* —
      so a PB surface has to render "no estimate yet" as a real state.
- [x] **Port the year activity grid.** Source:
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
- [x] **PBs, lifetime totals, per-movement history.** The remaining half of what
      the report describes as "just thrown in there". Scope this after the grid
      lands, since the grid establishes the surface's layout.

## Phase D — the coach remembers, but the screen does not

- [ ] **Resumable transcript on open — built, and never once exercised.**
      Not a gap in the code, and the earlier diagnosis in this file was wrong.
      It is corrected here rather than deleted, because the way it was wrong is
      the useful part.

      `CoachScreen._resume()` reads the transcript and replays it, `main.dart`
      wires `SupabaseCoachTranscript`, and the feature landed in `3c35200` on
      2026-08-19 — an ancestor of the build that was tested. This file then
      reasoned that it must be failing at runtime and pointed at PostgREST's
      exposed-schema list.

      **Checked against production, and that was wrong on both counts.** The
      whole `coach.turns` table holds one conversation,
      `coach-1786397895824351`, and it is `app = 'run'`. There has never been a
      single `lift:` conversation. Nothing was failing to load; there was
      nothing to load.

      The reason is one row that does not exist. `core.entitlements` is
      **empty** — zero rows, for anybody. The deployed coach function gates on
      it (`EntitlementStore`, `tierFor`), and the decision *"Tracking is never
      gated; the coach is the paid half"* is enforced there. So every Lift
      coach request in production has been refused, the paid half of the app
      has never run, and the transcript is empty because the conversation never
      happened.

      `testflight-2.0.0-test-sheet.md` opens with the fix — a one-row `insert
      into core.entitlements` under "Before you start", with the warning that
      *"without a row you will test the free half of the app and conclude the
      paid half is broken"*. That is exactly what happened.

      **Action: grant the entitlement and re-test the coach and the plan.**
      Every observation of Lift's paid half so far was of a gated app, and this
      item cannot be judged until then.

      Two things fall out of it. The silent catch in
      `SupabaseCoachTranscript.read()` did not cause this, but it is why the
      investigation took a database query rather than a glance — "empty" and
      "could not load" render identically. And a reminder that a hypothesis
      written down confidently reads exactly like a finding three commits
      later; this one survived a commit before anybody checked it against the
      server it was about.

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

## Found by comparison, not by the report

Two items on this list came from putting the two apps' screens side by side on
2026-08-25 rather than from the phone. Both are ticked above: the heading
convention, and the missing post-session screen. A third fault was found the
same way and fixed in `1fd86d6` — the session header rendered `1410 kg3`,
because four `StatBlock`s do not fit at 390pt and `shrinkToFit` cannot widen a
box, only shrink what is in it.

That is three layout faults in one week that neither `flutter analyze` nor 414
tests could see, and all three surfaced by rendering a screen and looking at it.
It is the cheapest review step available here and the easiest to skip.

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
- ~~Phase B's library work needs the back-reference column decided before the
  write path lands.~~ Settled and landed: `premadeId` is a second column, and
  the write path went in behind it. What remains open is **uploading a
  template**, which wants a live-server change rather than a decision — see
  *What the library work turned up* above.
- Phase D is blocked on the run app, by choice.

## Not in this plan

Named so they are decisions rather than omissions.

- **Anything under `apps/mgk_run`.** The run app's own punch list is being
  worked separately. Shared-package changes made here will reach it, which is
  the point of the package, but no run screen is touched from this plan.
- **Payments.** Phase 3 of [release-2.0.0.md](release-2.0.0.md), untouched.
- **Elevation, steps and Health integration.** Those came from the run app's
  testing and do not apply here.
