# Release 1.0.0 — Run, first shippable

The plan to take `apps/mgk_run` from "records a run" to "somebody can hold it",
written against the first real field test.

Written 2026-08-24, from a 10 km run recorded on 23 Aug under
`mattkay02@gmail.com` alongside Strava as a control. Screenshots in
`attachments/`. Tick items as they land; when something is settled differently
from how it is written here, change the item and say why — the reasoning is
worth more than the checkbox, which is the lesson [roadmap.md](roadmap.md)
records about itself.

---

## What the test run established

The recorder works. 10.18 km / 58:28 against Strava's 10.01 km / 57:47 is a
sane delta for two phones in two pockets, the splits looked right, and the live
screen held up for an hour.

**Everything after the finish line did not.** The run was recorded, displayed,
and then disappeared. Profile said *No runs yet* the next morning. That is the
subject of Phase 0 and it blocks everything else in this document, because
every other surface here is a surface that shows runs.

One thing worth naming separately: the coach, asked to "look at my previous
run", replied *"You ran 10 km in 60 minutes yesterday."* The log was empty at
the time.

**This is not the coach inventing things.** That run is real — it was logged
through natural language a week earlier, while testing the chat's add-run
intent. Because there is only ever one chat session, week-old context was still
in front of the model, and it read it as current. The coach recalled something
true and placed it yesterday.

Which makes it a better bug than a hallucination would have been, because it is
diagnostic of two things at once:

- **Phase 4 is the root cause, not a polish item.** One endless transcript means
  the coach cannot tell what is current from what is a week stale. Every session
  boundary this app doesn't have is a chance to answer confidently about the
  wrong week.
- **It is a second, independent witness for Phase 0.** A run logged through the
  chat a week ago is also absent from the log. Whatever swallows a recorded run
  swallows a conversationally-logged one, which points at the shared write path
  rather than at anything specific to the recorder.

---

## The finding this plan rests on

**The log is read from the backup, and writing to the backup is both optional
and silently failable.**

- `main.dart:177` — `historySource: SupabaseRunRepository().fetchRuns`. History
  reads **Supabase**, not the local Drift database.
- `recording_run_recorder.dart:352` — `stop()` finalizes the run locally, then
  mirrors it. Its own comment says the quiet part out loud: *"Mirroring it is
  what makes it appear in the log at all, because History reads Supabase."*
- `recording_run_recorder.dart:59` — `_backup()` wraps every push in
  `catch (_) {}`. A failed push is indistinguishable from a successful one.
- `consented_run_backup.dart` — a runner who declined backup gets `pushRun`
  returning `false`. No error, no surface, no trace.

So there are three independent ways for a recorded run to become invisible, and
**none of them tell anybody**:

| Trigger | What happens | What the runner sees |
|---|---|---|
| Backup consent off | `pushRun` returns false | "No runs yet" |
| Offline / RLS / auth error at finish | `catch (_)` swallows it | "No runs yet" |
| `backfill()` throws at launch | `unawaited`, unhandled | "No runs yet" |
| **A typo in a schema name** | **PostgREST `PGRST106`, caught and dropped** | **"No runs yet"** |

### The fourth one is the one that fired — 2026-08-24

Found while implementing the fix, and it is not a race or a consent path. It
fired on **every launch, for every runner, unconditionally**:

```dart
// supabase_run_repository.dart, now deleted
line 25:  .schema('runSchema')                     // fetchRuns      — BROKEN
line 36:  final runSchema = _client.schema('run');  // fetchRunDetail — correct
```

A find-replace during the move into the monorepo renamed the *local variable*
at line 36 correctly and corrupted the *string literal* eleven lines above it.
`fetchRuns` — the single function behind the entire log — asked PostgREST for a
schema that does not exist. PostgREST answered `PGRST106`, and
`home_shell.dart:752` reads history inside a bare `catch (_)`, so the error
became an empty list.

**The 23 Aug run was never lost.** It was recorded, finalized, and very possibly
mirrored to Supabase exactly as designed. The log simply could not load, and had
not been able to since the rename. That retires the open question about whether
consent was on — the answer does not matter, because no setting would have shown
that run.

Two things follow, and the second is the reason this document leads with
architecture rather than with the typo:

- **A one-word typo caused total, silent, permanent data invisibility.** That is
  only possible because the log had a single remote read path with no local
  fallback and a swallowing catch around it. Fix the typo alone and the same
  class of bug returns with the next rename.
- **The bare `catch (_)` is the real defect.** It converted a loud, specific,
  immediately-diagnosable backend error into the app's own empty state. An error
  that renders as "you have not done anything yet" is worse than a crash.

This contradicts
[ADR-0004](decisions/0004-offline-first-local-source-of-truth.md) directly. The
local database is written on every fix and finalized on stop — it is a
complete, correct source of truth that nothing ever reads. "Offline-first"
describes the write path and nothing else.

It also quietly breaks the consent bargain in
[ADR-0012](decisions/0012-backup-is-consented-restore-only-adds.md). Backup is
meant to be optional. As built, declining it means your own runs are invisible
to you on your own phone — so the toggle is not really consent, it is the price
of using the app. That is a compliance problem as well as a product one.

**The fix is to read the log locally and let Supabase be what ADR-0012 says it
is: a mirror.** Not to add error toasts to the push, which keeps the
contradiction and merely narrates it.

---

## Phase 0 — The run that vanished

Blocks everything else. Until the log is trustworthy there is no point styling
the screens that show it.

- [x] **Diagnose before fixing.** Answered from the code rather than the device:
      the schema typo above fired unconditionally, so no reading of the phone was
      needed to explain the empty log. The second witness agrees — a run logged
      through the chat went in via `RunEditor` and was equally invisible,
      because both were invisible for the same reason: nothing could *read*.
- [ ] **Recover the 23 Aug run — needs the device.** The remaining device work,
      and now a recovery rather than an investigation. The run should be in the
      phone's Drift database, and with the log reading locally it will simply
      appear on next launch. If it does not, it never finalized, and *that* is a
      new bug rather than this one.
- [x] **Point the log at the local database.** `historySource` reads Drift;
      `SupabaseRunRepository` stops being the read path for History. This is
      the actual fix and everything else in Phase 0 is support for it.
- [x] **Write the ADR.** This reverses a live architectural decision and needs
      recording as one — `00XX-the-log-is-read-from-the-phone.md`, extending
      0004 and correcting the read path 0012 implies. Include the consent
      argument; it is the strongest reason and the least obvious.
- [x] **Stop swallowing push failures silently.** With the log read locally, a
      failed push is no longer data loss — but it is still a backup that did
      not happen, and it should be visible somewhere honest (Settings, next to
      the toggle) rather than nowhere.
- [x] **`backfill()` must not be fired into the void.** `unawaited` with no
      error handler means a throwing backfill is invisible.
- [x] **A test that fails the old way.** Record → finish → assert the run is in
      the log **with backup disabled and the network down**. That test would
      have caught this before the field did.

---

## Phase 1 — Finishing a run

Right now `_finish()` calls `recorder.stop()` and pops (`home_shell.dart:952`,
`onFinish: () => Navigator.of(routeContext).pop()`). An hour of effort ends by
the screen disappearing.

- [x] **A run completed screen.** `RunSummaryScreen` already exists and is
      already wired for viewing a run from the log — finishing should route to
      it rather than to nothing.
- [x] **The route with per-km markers**, each with its timestamp. This is the
      thing a runner actually wants to look at afterwards.
- [x] **Splits, elevation, steps** on the completion screen (see Phase 2 for
      where the data comes from).
- [x] **A word from the coach on the run**, with a "keep asking your coach"
      affordance into the chat. The coach has an opinion about the session that
      was just run, and this is the moment it is worth the most.
- [x] **Strava's control model in-run.** Only **Pause** and **Lap** while
      running; **Finish** appears once paused. Finishing is a two-step act, and
      today all three sit side by side (`IMG_4685`) with Finish as the filled,
      most prominent one — the easiest button to hit by accident is the
      irreversible one.
- [x] **Cut the RPE control from the in-run screen.** Noise mid-effort.
- [x] **Cut the "THIS WEEK" block from the in-run screen.** Weekly load is a
      dashboard question. Nobody 8 km into a run needs to know what Thursday
      looks like.

---

## Phase 2 — Track what a running app tracks

Strava's summary for the same run carried elevation gain (167 m), max elevation
(111 m) and steps (8,468). Ours carried none of them.

- [x] **Elevation gain and max elevation — built end to end, and permanently
      empty.** Corrected 2026-08-24: this item said "the recorder already
      reports climb". **There is no barometric source and never has been.**
      `GeolocatorLocationSource._toRunPoint` writes `altitudeMeters: null`
      unconditionally, and the `CMAltimeter` channel that several doc comments
      referred to was never built — so `run_points.altitude_m` has been null for
      every point of every run this app has ever recorded. The refusal to
      substitute GPS altitude was real and is kept; the barometer behind it was
      imaginary. Everything from the trace to the tile now exists and waits on
      native code under `ios/` and `android/`, which is not this lane.
      The CHANGELOG had been advertising the barometer as a shipped feature.
- [x] **Steps**, read from Health. The one metric here that genuinely arrives.
- [x] **Audit what else Health offers.** Corrected: this item said "heart rate
      is already read". **It is not** — `HealthDataType.HEART_RATE` appears
      nowhere in the app; `runs.avg_hr` is written only by the manual-entry form
      and by a Supabase restore, so the `AVG HR` tile has only ever shown
      hand-typed data. What the audit found is recorded in ADR-0024 and
      summarised under *Deliberately not built* below.
- [x] Each new metric needs a rule for its absence. A denied Health read is
      indistinguishable from no data, so every one of these renders as "not
      recorded" rather than as zero or as an error. Health returning `0` steps
      counts as absent too — that is a phone on a desk, not a runner who took no
      steps.

### Deliberately not built, and why

- **Heart rate.** Buildable and stopped on purpose. HR only exists if the runner
  wore a watch — and a runner with a watch also has a HealthKit workout for the
  same run that the import path already dedupes against ours. Reading HR onto
  our run *and* importing the watch's copy are two answers to one question and
  need designing together. It also means pulling several hundred raw
  special-category samples across a channel per run.
- **Cadence.** Cannot be read: the `health` plugin exposes no cadence type. It
  could be derived as steps ÷ moving minutes, one line now that steps exist —
  but `runs.cadence` is also written by a restore from a watch's *measured*
  cadence, and mixing a derivation into a measured column is a decision rather
  than a chore.
- **Active energy.** Readable, but `RunSummary.caloriesEst` is documented as a
  derived estimate rather than a measurement, and iOS active energy for a
  phone-only run is poor. Same double-count risk as HR; decide them together.
- **`FLIGHTS_CLIMBED`** — the interesting one. The iPhone barometer *does* feed
  HealthKit, and flights climbed is the only barometric signal reachable without
  native code. But Apple's ~3 m per flight would turn "12 flights" into "36 m of
  climb", which is exactly the plausible-wrong-number ADR-0024 exists to refuse.
  Showable as flights; never as metres.

### Still open after Phase 2

- [ ] **A barometric source** — `CMAltimeter` on iOS, `Sensor.TYPE_PRESSURE` on
      Android. Native, and the only thing standing between the elevation tiles
      and real data. Note for whoever builds it: `CMAltimeter`'s *relative*
      stream gives gain but is useless for a maximum, since it starts at zero
      wherever you set off. Store gain and leave the maximum null unless
      `CMAbsoluteAltitudeData` is wired.
- [ ] **`NSHealthShareUsageDescription`** in `ios/Runner/Info.plist` says the app
      "reads your workouts from Health". It now also reads steps, and that string
      has to say so before submission. An App Store review item, not a nicety.
- [ ] **`steps` and `elevation_max_m` are local-only.** The mirror enumerates its
      columns and `run.runs` has neither, so a restore onto a new phone silently
      drops them. Two lines here plus a Postgres migration in `supabase/` — a
      `db/` lane change.
- [ ] **Elevation renders in metres everywhere**, in an app whose rule 4 is
      "store metric, convert at display". `mgk_units` has `Distance`, `Pace` and
      `Mass` and no elevation type. Adding a local feet conversion on one screen
      while the in-run readout kept metres would be the two-numbers-for-one-thing
      bug this document complains about elsewhere, so it needs an `Elevation`
      type in `packages/mgk_units`.
- [ ] **Widening the Health request will re-prompt existing installs** for Steps.
      Untested, and it sits awkwardly beside the onboarding doc's claim that
      neither permission can be asked twice.

---

## Phase 3 — The three surfaces

### Home (`IMG_4702`)

Today it is a wordmark, one session card, and then two-thirds of a screen of
nothing.

- [x] **Widgets, in the Apple sense** — square tiles carrying one fact each,
      filling the screen.
- [x] **Today's session** as its own tile, which **says so when there is
      nothing today** rather than being absent. A rest day is information.
- [x] **The rest of the week** as a tile.
- [x] **A note from the coach**, distinct from the chat surface.
- [x] **Recent runs / PBs** as a tile.
- [x] **"TODAY" over "Threshold" reads as two headings and no sentence.** The
      card needs to say what the runner is doing today in words a person would
      use — the same fix as the naming item under Plan.
- [x] Home says **4.1 km** where Plan says **4 km** for the same Monday
      session — see the section below, which is where that fix belongs.

### Plan (`IMG_4700`)

- [x] **The black bar beside the coach mark.** Hypothesis to verify:
      `_coachMarkReserve = 64` (`home_shell.dart:1027`) is applied as
      MediaQuery bottom padding across the whole tab, and on Plan the reserved
      strip falls outside the glass card, so it reads as a full-width black band
      rather than as breathing room. Verify on device before fixing.
- [x] **Drop "THE WHOLE BLOCK".** It reads as a second, competing plan. The week
      section is the plan.
- [x] **Name the activity, not the physiology.** "Threshold" / "Easy" /
      "Recovery" are the coach's vocabulary, not the runner's. Strava says
      *Afternoon Run*; we should say *Afternoon easy run* — the session type
      survives, attached to something a person recognises.

### Profile (`IMG_4699`)

- [x] **Empty is not the same as absent.** The whole screen is one "No runs yet"
      card. It should show the full stat grid — lifetime distance, PBs, recent
      runs, per-run detail — **as empty placeholders**, so a new runner can see
      what the app is going to tell them once they run.
- [x] This is the counter-signal
      [ADR-0019](decisions/0019-onboarding-is-two-moments.md) names: a
      plan-shaped hole on a free screen. A profile that says only "No runs yet"
      reads as broken rather than as new. Recorded as a consequence on that ADR,
      with the general rule it leaves behind: a screen with no data states its
      structure, and hiding a section is only right when it is about something
      that may never exist at all.

---

## Phase 3b — A prescription is a whole number, and only ever a suggestion

Two rules, and the code already believes both of them in one place and ignores
them in nine others.

**A prescribed distance is a whole number in the runner's unit.** The algorithm
produces 4.1 km because a weekly volume got split by a share table. Nobody
cares about the 0.1. To any runner alive that is a 4 km run, and
`prescribed_distance.dart` already says so at length —
[ADR-0011](decisions/0011-a-plan-has-a-shape.md) settled it.

**It is a suggestion, never a floor or a ceiling.** Going further or shorter is
a runner making a decision, not failing a check. `fulfils()` already implements
this as a ±12% band with a 500 m floor, so the idea is built; what needs
auditing is whether any *surface* presents the number as a target to hit.

### What is actually wrong

The formatter is correct and under-used. `formatPrescribed()` returns "4 km";
three surfaces call it and nine bypass it with
`Distance.meters(...).format(unit, fractionDigits: 1)`:

| Uses `formatPrescribed` ✓ | Bypasses it ✗ |
|---|---|
| `week_list.dart:233` (the Plan rows) | `home_tab.dart:394, 447, 505` |
| `week_calendar.dart:315` | `today_card.dart:92` |
| `session_brief_sheet.dart:111` | `week_adjust_sheet.dart:225` |
| | `week_detail_screen.dart:307` |
| | `chat_widgets.dart:288, 618, 667` |

That table is the whole "4 km on Plan, 4.1 km on Home" bug. Plan is in the left
column; Home is in the right.

**The previous attempt at this fixed the symptom in the wrong direction.**
`home_tab.dart:500` carries the note: *"One decimal, matching the figure
directly above it. They disagreed — 'Easy 6.2 km' over 'Start · 6 km easy' — and
two numbers for one session eight pixels apart reads as a bug whichever is
right."* The observation was correct and the resolution inverted — the button
was moved onto the raw value instead of both being moved onto the formatter.

**And the stored grid is documented but never applied.** `roundPrescribed()`
says prescribed distances are *stored* on a whole-kilometre grid. It is called
exactly once in the app, at `plan_headline.dart:161`, to size a tolerance band
— never when a session is generated. So the stored value really is 4100 m, and
every decimal formatter is faithfully reporting it.

- [x] **Apply `roundPrescribed()` at generation**, which is what its own doc
      comment claims already happens. Sessions store on the whole-kilometre
      grid.
- [x] **Move all nine bypassing sites onto `formatPrescribed()`**, including the
      two in `home_tab.dart` that the earlier fix deliberately aligned on
      decimals.
- [x] **Leave actual run distances alone.** `training_standing.dart:133/137/211`
      and `profile_screen.dart:626` show distances a runner really covered —
      10.18 km is earned precision and reads as respect for the effort. The rule
      is: *prescriptions round, achievements don't.*
- [x] **Audit every surface that shows a target for lock-like language.** The
      in-run third column counts down to the session target; a countdown that
      hits zero and keeps going must read as "past it", never as done-or-failed.
      Same for the Start button and the session brief.
- [x] **A test that pins the rule**, so the tenth call site cannot reintroduce
      it: no prescribed distance renders with a decimal, in either unit.

---

## Phase 4 — The coach has sessions, not one endless chat

Currently every message lands in one transcript forever. Closing and reopening
the app continues it; there is no notion of a conversation that ended.

Settled in [ADR-0025](decisions/0025-a-coach-conversation-is-a-session.md).
**The boundary is silence, not a lifecycle event**: a conversation ends when
nothing has been said in it for 30 minutes, measured from `lastTurnAt`. One rule
covers the cold start, the resume from background, and the runner who never
closed the app — and a runner who checks a notification and comes back in ten
seconds keeps their conversation, which is the case that ruled out "any
background → foreground transition". "Cold start only" was ruled out because an
iOS process survives for days, which is the bug.

- [x] **A new session** when the app is reopened, and when a runner taps a
      suggested question. `restore()` now asks `openConversationId(window:)`
      rather than `lastConversationId()`, which was the one line that made the
      chat endless. A tapped chip goes through `ask()`, which starts a session
      regardless of the window.
- [x] **Previous chats** kept and readable — a history button in the
      conversation sheet, listing by `lastTurnAt` with the opening line, and a
      read-only page per conversation. Read-only on purpose: reopening an old
      transcript to write into it is the thing this phase ends.
- [x] **Old sessions feed the coach's memory but are not in its context by
      default.** `recall()` existed, was documented as the on-demand tier, and
      had no caller; it has one now. Four constraints on it, each narrowing:
      queried with the message rather than replayed, the live conversation
      excluded, **only the runner's own turns** (the coach's past replies are
      conclusions derived from a brief that is rebuilt every turn, so
      re-injecting one launders a stale derivation into the context), and every
      line dated under a paragraph that says what it is *before* it says any of
      it. Semantic search is still the `CoachMemoryRecall` seam's job and was
      deliberately not built here.
- [x] **A recalled run needs its real date.** Both halves: recalled turns carry
      their own relative date, and `_recent` now names the runs before the
      latest with theirs, plus an instruction not to describe a run as more
      recent than its date or to describe one that is not listed.
- [x] **A coach with no run data has to say it has none.** The brief now carries
      an explicit refusal naming the exact case — a run mentioned in
      conversation and never logged — and it is asserted, including a test that
      reconstructs the field-test answer from an empty log plus a week-old turn.

Still open, and recorded as a cost on the ADR rather than done here: a
conversation abandoned by force-quitting the app mid-sentence is folded into the
rolling summary by nothing. Closing that means a model call on the launch path,
against the per-hour allowance in
[ADR-0015](decisions/0015-spend-is-capped-over-three-windows.md).

---

## Open questions

- **Was backup consent on during the 23 Aug run?** Settings showed it on the
  next morning (`IMG_4698`), which does not answer it. Phase 0's first item
  settles this.
- **Location is "On while the app is open"** (`IMG_4698`), not Always. The run
  survived an hour, so the screen was presumably on — but a backgrounded run on
  While-Using is a data-loss path that has not been tested, and should be before
  anybody else runs with this.
