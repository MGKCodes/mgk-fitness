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
- [ ] **Recover the 23 Aug run** if it is on the device. It is the first real
      run this app ever recorded and it should be in the log.
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

- [ ] **Elevation gain and max elevation.** Barometric where the device has it
      — the recorder already reports climb as absent rather than guessing it
      from GPS altitude, which is the right call and stays.
- [ ] **Steps**, read from Health.
- [ ] **Audit what else Health offers** that belongs on a run summary. Heart
      rate is already read; cadence and energy are the obvious next two.
- [ ] Each new metric needs a rule for its absence. A denied Health read is
      indistinguishable from no data, so every one of these renders as "not
      recorded" rather than as zero or as an error.

---

## Phase 3 — The three surfaces

### Home (`IMG_4702`)

Today it is a wordmark, one session card, and then two-thirds of a screen of
nothing.

- [x] **Widgets, in the Apple sense** — square tiles carrying one fact each,
      filling the screen.
- [ ] **Today's session** as its own tile, which **says so when there is
      nothing today** rather than being absent. A rest day is information.
- [ ] **The rest of the week** as a tile.
- [ ] **A note from the coach**, distinct from the chat surface.
- [ ] **Recent runs / PBs** as a tile.
- [ ] **"TODAY" over "Threshold" reads as two headings and no sentence.** The
      card needs to say what the runner is doing today in words a person would
      use — the same fix as the naming item under Plan.
- [ ] Home says **4.1 km** where Plan says **4 km** for the same Monday
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
- [ ] This is the counter-signal
      [ADR-0019](decisions/0019-onboarding-is-two-moments.md) names: a
      plan-shaped hole on a free screen. A profile that says only "No runs yet"
      reads as broken rather than as new.

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

- [ ] **A new session** when the app is reopened, and when a runner taps a
      suggested question.
- [ ] **Previous chats** kept and readable.
- [ ] **Old sessions feed the coach's memory but are not in its context by
      default** — retrieved when relevant rather than replayed wholesale. This
      is the part with a known problem and it needs designing before it is
      built.
- [ ] **A recalled run needs its real date.** The coach placed a week-old run
      "yesterday" because nothing in one endless transcript distinguishes them.
      Sessions fix the mechanism; the brief should also carry when a run
      actually happened, so a recollection cannot drift forward in time.
- [ ] **A coach with no run data has to say it has none.** Not a live bug — the
      10 km answer was a real memory — but the empty-log path is untested and
      the failure mode is confabulation. Assert it: a brief built from an empty
      log declines rather than invents.

---

## Open questions

- **Was backup consent on during the 23 Aug run?** Settings showed it on the
  next morning (`IMG_4698`), which does not answer it. Phase 0's first item
  settles this.
- **Location is "On while the app is open"** (`IMG_4698`), not Always. The run
  survived an hour, so the screen was presumably on — but a backgrounded run on
  While-Using is a data-loss path that has not been tested, and should be before
  anybody else runs with this.
