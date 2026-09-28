# Lift 2.0.0 — the logging rework

The plan that follows the 2026-09-28 audit of logging a workout: sets,
templates, saving, sync, and the glass-and-motion design pass. It is the next
phase of [lift-2.0.0-punch-list.md](lift-2.0.0-punch-list.md), written as its
own file because it reaches past UI into the data layer and the server.

Same discipline as the punch list: tick items as they land, and when something
is settled differently from how it is written here, **change the item and say
why**.

---

## Read this first

**The TestFlight build predates almost all of this.** It was cut on
2026-08-21. Set removal, all four set types, the workout library, the summary
screen and the entitlement read all landed on this branch afterwards. The
audit was run against the branch at `56447b2`, which is what the next build
ships, so every finding below is about code a tester has not held yet.

**How each finding is known**, because the difference matters when deciding
what to trust:

- *measured* — a throwaway test against the real Drift recorder (deleted after)
- *seen* — on the Android emulator, through the preview harness
- *read* — from the code, not yet exercised

## What the audit found

The short version, so the phases below can refer to it by number.

| # | Finding | How known |
|---|---|---|
| F1 | One keystroke in a weight or reps field = 16 reads + 2 writes (six movements), and the whole screen rebuilds once a second for the clock | measured |
| F2 | Remove set 2 of 3, add a set → numbered `1, 3, 3` | measured |
| F3 | Warm-ups take a number: rows read `W, 2, 3, 4` rather than `W, 1, 2, 3` | seen |
| F4 | Remove a movement, add one → duplicate order values (`A@0, C@2, D@2`); order is then undefined | measured |
| F5 | Swap sends the replacement to the bottom and deletes the sets already logged on the old movement | measured + read |
| F6 | A set can only be swiped away from the 28px number column; no undo | read (code says so) |
| F7 | The ✕ on a movement deletes it and all its logged sets in one tap, no confirm, no undo | read |
| F8 | The first set of every movement starts blank (`– / –`) although "Last time" is printed above it | seen |
| F9 | `8.5` in reps saves 0; `10..5` saves 0 kg; `102,5` saves 1025 kg | measured |
| F10 | The iOS decimal pad has no return key and Flutter never unfocuses on an outside tap on mobile; nothing dismisses the keyboard | read (SDK source) + seen |
| F11 | A saved workout is names only, so every session from one starts as empty cards | read + seen |
| F12 | The library is only reachable from inside an empty session, which starts the clock before anything is chosen | seen |
| F13 | Saved workouts cannot be edited, renamed or reordered, though the premade sheet says they can | read |
| F14 | Finish is one tap, no confirm; unticked sets are kept and uploaded | read |
| F15 | Finishing does not back up — sync runs at launch, on the hourly token refresh, or from Settings | read |
| F16 | After the summary closes a workout cannot be opened, fixed or deleted | read |
| F17 | The whole history reloads twice on every return to Track, one query per movement, no indexes | read |
| F18 | Sync status exists only in Settings, as one generic message; no retry, no reason | read |
| F19 | Motion is nearly absent: `Entrance` in 2 Lift files (Run 19), `CountUp` in 0 (Run 3) | measured (grep) |
| F20 | Finish, Add set, Add exercise, the set marker and the picker rows are raw Material — silent under the finger on iOS; no `AppHaptics.commit()` on a tick or a finish | read |
| F21 | Glass sheets over the flat session: the blur smears the green ticks and the silver button into smudges | seen |
| F22 | Sheets fixed at 85%: the library sheet is half empty; the picker autofocuses and grows under the status bar | seen |
| F23 | Done set rows are the brightest thing in the card; the set you are about to do is the dimmest | seen |
| F24 | Thumbnails on pure black; white iOS launch screen (Run's is `#1A1A1A`); snackbars should render white suite-wide (no `inverseSurface`); raw red confirm buttons | seen + read |

## Decisions

### Settled 2026-09-28

1. **A template learns from the session.** Remove a movement in a session
   started from a template and the template loses it too. The lifter should
   never have to make the same edit twice.
2. **Everything the lifter makes is backed up.** Finished sessions, edits and
   deletions of them, and templates. Not live while training — saved on the
   phone first, uploaded at checkpoints — and **a failure says so**, with a
   reason and a way to retry.
3. **Sets and reps have limits.** Typing mistakes are stopped at input rather
   than stored.
4. **The glass is Apple-grade and the motion is throughout.** Not a restyle of
   a few screens: every moment of logging moves the same way, in both apps.
5. **The plan in this file is the order of work**, starting with main.

### Open — recommendation first

Each of these changes what gets built. The recommendation is what this file is
written against; change the item if the answer differs.

- **D1. Template updates apply automatically, with Undo.** The summary says
  *"Push updated — removed Cable Fly · Undo"*. Asking every time is the
  alternative; it is safer against one-off changes (a machine taken today) but
  it is exactly the repeated decision the lifter asked not to make. Undo covers
  the one-off case at the moment it matters.
- **D2. The limits.** See Phase 1, item 7. Numbers are a proposal.
- **D3. Unticked sets are dropped at Finish.** They are sets that did not
  happen. Keeping them stores fiction and uploads it. The Finish sheet lists
  them first, so nothing goes silently.
- **D4. A template stores set counts and rep targets, never weights.** This
  revises *"a saved workout says what to do, not what to lift"* rather than
  reversing it: a set count and a rep target are what to do; a weight is what
  to lift, and it comes from last time instead.
- **D5. One RevenueCat webhook.** Keep main's deployed `revenuecat`, extend its
  product map with Lift's products and Liftio's legacy ids, and delete this
  branch's undeployed `revenuecat-webhook`. Port the branch's four decisions
  where main does not already make them. See Phase 0.
- **D6. Glass is for chrome, not content.** Floating bars, the dock, sheets and
  the keyboard bar are glass; exercise cards and set rows stay solid. That is
  Apple's own model — glass is the control layer over scrolling content — and
  it keeps the `mgk_ui` rule true instead of breaking it: content scrolling
  under a glass bar *is* the texture the rule asks for. See Phase 5.

---

## Phase 0 — bring main in

**Why first:** main holds Run's shared-layer work since 2026-08-21 — the
floating nav pill, real icons, the shared upload key, `web/`, Play wiring, the
privacy fixes to the coach function. Most items below touch files main also
changed; doing them first means doing them twice.

- [ ] **Push the 9 unpushed commits** on `lift/release-2.0.0` *(your go —
      outward-facing)*.
- [ ] **Merge main into the branch.** A dry run (`git merge-tree`) finds seven
      conflicted files:
      - `apps/mgk_lift/docs/release-2.0.0.md`,
        `apps/mgk_lift/docs/testflight-2.0.0-test-sheet.md` — the branch moved
        these to `docs/`; keep the moved copies and fold in main's edits.
      - `apps/mgk_lift/lib/src/features/home/presentation/lift_shell.dart` —
        main's floating nav pill against the branch's entitlement and
        purchase wiring. Both halves survive.
      - `apps/mgk_run/.../plan_screen.dart`, `profile_screen.dart`,
        `run_summary_screen.dart` — the shared coach mark move against Run's
        own work. Run's side wins except where the mark is drawn.
      - `packages/mgk_ui/lib/mgk_ui.dart` — both sides added an export; keep
        both.
- [ ] **Read the coach function after the merge, even though it merged
      cleanly.** Both sides changed `supabase/functions/coach/` (main: Run's
      sessions and the privacy fixes; branch: Lift's client-sent conversation
      id). Git joined them without a textual conflict, which says nothing
      about whether they agree. Deno tests must pass, and the conversation rule
      must be one rule for both apps.
- [ ] **One RevenueCat webhook** (D5). Main's `revenuecat` stays; the branch's
      four decisions are checked against it: cancellation does not end access,
      an unknown product grants `paid` (Liftio's legacy subscribers), sandbox
      events are honoured, status codes are a retry policy.
- [ ] Full verification: Run and Lift test suites, Deno, `mgk_ui`, `flutter
      analyze` across the workspace. Run's screens photographed against the
      board, because this merge touches three of them.

**Done when:** the branch contains main, every suite passes, and nothing in
`supabase/functions/` exists twice.

---

## Phase 1 — the data is right

Small changes in `DriftSessionRecorder` and the session screen, each pinned by
a test that fails today.

1. [ ] **Sets renumber on removal** (F2). `removeSet` renumbers the movement's
       remaining sets in the same transaction; `addSet` numbers from the
       count, which is then correct.
2. [ ] **Warm-ups do not take a number** (F3). The label is the set's position
       among working sets: `W, 1, 2, 3`. Stored `setNumber` stays positional;
       only the label changes.
3. [ ] **Order stays contiguous** (F4). `removeExercise` closes the gap;
       `addExercise` appends after the highest index.
4. [ ] **Swap replaces in place and keeps the work** (F5). A movement with
       nothing ticked is replaced at its own position. One with ticked sets
       stays, collapsed, and the replacement goes directly under it — sets
       that happened are never deleted by a swap.
5. [ ] **Every change is one transaction.** `fillFromLibrary`, swap, removal
       with renumbering — a half-applied change cannot reach the disk.
6. [ ] **Input that cannot be wrong** (F9). Reps: digits only, number keyboard,
       three digits. Weight: one decimal separator, `,` read as `.`, two
       decimal places. Rejected characters never reach the field.
7. [ ] **Limits** (D2). A control at its limit disables with a one-line
       reason; a typed value over it is refused at input with an inline hint.
       Nothing is silently clamped. Rows already stored over a limit display
       as they are.

       | What | Limit | Why |
       |---|---|---|
       | Sets per movement | 20 | covers long drop-set chains; stops runaway taps |
       | Movements per session and per template | 30 | a long session is about twelve |
       | Reps per set | 1–200 | a three-digit field; typo guard |
       | Weight | 0–1,000 kg (2,200 lb) | above any sled; 0 is bodyweight |
       | Rep target in a template | 1–200, or blank | blank = "whatever you did" |
       | Session and template names | 60 characters | one line on every screen |

       No server check constraints yet: nothing on `lift.sets` or
       `lift.workouts` limits these today, and adding one first needs the
       1,249 existing sets checked against it.
8. [ ] **A tick needs reps.** Ticking a set with no reps focuses the reps field
       instead of logging an empty set. Weight may stay 0.
9. [ ] **Removing a set: two ways in, and undo** (F6). The swipe works from
       anywhere on the row — the number fields stop claiming horizontal drags.
       Long-press on the set label opens the set's menu: Working, Warm-up, Drop
       set, Failure, Remove. Every removal shows *"Set removed · Undo"* for
       five seconds; undo restores the same row, values and position.
10. [ ] **Removing a movement asks when it matters** (F7). With ticked sets:
        a confirm sheet naming what goes (*"Remove Bench Press and its 3
        logged sets?"*). With none: removed at once, with Undo.
11. [ ] **Finish asks once** (F14, D3). A glass sheet: the session in one line,
        any unticked sets listed (*"2 sets not done — they won't be saved"*),
        and for a template session, what will change in the template. Finish /
        Keep going.
12. [ ] **A fast double-tap is one tick.** Writes from the session screen go
        through one queue, so two taps cannot both read the stale state.

**Done when:** each item has a failing-then-passing test in
`session_recorder_test.dart` or `active_session_screen_test.dart`.

---

## Phase 2 — logging is fast

1. [ ] **The screen answers before the disk does** (F1). A change updates the
       on-screen session at once and is written behind it. A failed write puts
       the old value back and says so. The recorder re-reads once per change,
       not twice, and hydrates in three queries (workout, movements, sets) rather
       than one per movement.
2. [ ] **Typing is not saving.** A number field writes when it loses focus,
       when its set is ticked, when the screen closes, and when the app goes to
       the background — not per keystroke. Pinned by a test: five keystrokes
       and a blur are one write.
3. [ ] **Indexes on the lookups** (F17). `exercises(workout_id, order_index)`
       and `exercise_sets(exercise_id, set_number)`, schema 6 → 7.
4. [ ] **The clock redraws the clock.** The elapsed time and the rest timer
       each own their ticker; the exercise cards stop rebuilding every second.
       "Last time" is worked out once per session, not per card per second.
5. [ ] **The keyboard can be put away** (F10). Tap outside unfocuses; dragging
       the list dismisses; and a glass bar above the keyboard carries
       `‹  ›  Log set  Done` — previous/next field, tick this set, close.
       The focused field scrolls clear of both.
6. [ ] **The first set is filled in** (F8). A new set takes last time's weight
       and reps for that set position, shown in the quieter ink until touched
       or ticked. Ticking accepts it. With no history, the fields stay blank.
7. [ ] **The picker takes several at once, recent first.** Multi-select with
       an *Add 3* button; a *Recent* section built from the log above the
       catalogue; the keyboard opens only when search is tapped — which also
       removes F22's status-bar collision.
8. [ ] *(Optional, needs a permission prompt)* **Rest ends out loud when the
       phone is pocketed** — a local notification. Carried from
       `release-2.0.0.md` Phase 5.

**Done when:** a set edit costs at most four queries (pinned by an
interceptor test), and the keyboard has been opened and closed on an iPhone.

---

## Phase 3 — templates that keep up

### The model

- [ ] **A template movement has a set count and a rep target** (D4).
      `SavedWorkout.movements` becomes a list of `TemplateMovement(name, sets,
      repTarget?)`. Stored the way the schema already allows — the template's
      exercise rows get that many set rows, reps holding the target and weight
      empty. That is also how Liftio built its templates (three empty sets per
      movement, per `drift_workout_library.dart`), so the 47 legacy ones should
      come back from the server with their set counts — **check this against
      the server before relying on it**; it is inferred from a comment, not
      read from the rows.

### Starting a workout from one

- [ ] **One tap from Track** (F12). Track shows your workouts as a row of
      glass cards under *Next up*, and a *See all* link. A card opens a preview
      sheet — movements, sets × reps, when you last did it — with **Start**.
- [ ] **The session arrives ready.** One transaction: name, the template's id,
      every movement in order, the set rows seeded — reps from the target (or
      last time), weight from last time, nothing ticked. The empty session
      screen keeps a *Your workouts* action for starting blank and filling
      afterwards.

### The library and the editor

- [ ] **Your workouts is a screen, not a sheet.** Rows show the name,
      *6 movements · 18 sets*, *last done Tuesday*, and a cloud-off mark only
      when a row is not backed up. Empty state leads with the ready-made ones.
- [ ] **The editor** (F13) replaces the builder: name (60), movements with drag
      handles, a sets stepper (1–20) and a rep target per movement, swipe or ✕
      to remove with Undo, *Add movements* through the multi-select picker.
      Save is disabled until the workout is valid. Leaving with unsaved changes
      asks first.
- [ ] **Row actions:** Start, Edit, Duplicate, Delete. Delete confirms
      (*"Sessions you did from it stay in your log"*) and is a soft delete, so
      it reaches your other devices.
- [ ] **Ready-made ones are browsed inside the library.** Splits and sessions
      with a preview; *Add* shows *"Push added · Undo"*; a premade you already
      have says so, and adding a second copy is its own explicit action rather
      than the same tap twice.

### The template learns (settled item 1, D1)

The session keeps the template's id (already stored as `templateId`) and a
snapshot of its structure at start — a local-only column, never synced. At
Finish the session is compared with the snapshot:

| In the session | What happens to the template |
|---|---|
| Movement removed with ✕ | removed |
| Movement added | added, at the same position |
| Movements reordered | new order saved |
| Set rows added or removed | the set count follows |
| Movement kept, nothing ticked (skipped today) | unchanged — skipping is not removing |
| Sets left unticked | unchanged — a skipped set is not a removed one |
| Movement swapped | the replacement takes its slot |
| Reps and weights | never changed by a session |
| Warm-ups | not part of a template |

- [ ] **Applied automatically, shown on the summary with Undo:** *"Push
      updated — removed Cable Fly, added Dips · Undo"*. Undo puts the template
      back exactly as it was.
- [ ] **When it should not apply on its own:** the template changed since the
      session started (edited on another device, or in the editor mid-session)
      → the summary asks *Update Push / Keep it as it was*. The template was
      deleted meanwhile → *Save as a new workout*.
- [ ] Sessions not from a template keep the existing *Save as a workout*
      offer. Planned sessions from the coach never touch a template. A
      discarded session changes nothing.

---

## Phase 4 — saved, synced, and says so

### When things are uploaded

- [ ] **Nothing on the logging path touches the network** — unchanged, and
      restated because everything below must keep it true. The open session
      is never uploaded.
- [ ] **Checkpoints, not live** (F15): after Finish (once the summary is up),
      after a template is saved, updated or deleted, when the app comes to the
      foreground, when the connection returns, on sign-in, and from *Back up
      now*. A failed run retries at 30 s, 2 min, 10 min, then hourly while the
      app is open.

### Uploading so it cannot half-land

- [ ] **One request per workout.** A Postgres function,
      `lift.save_workout(payload jsonb)`, upserts the workout and replaces its
      movements and sets in one transaction, checking `auth.uid()`. Today it is
      four requests, and a drop between the delete and the inserts leaves the
      server copy empty until the next run. Covered by pgTAP; applied to
      production *(your go)*.
- [ ] **Templates go up** — `is_template` true, `started_at` null, which is
      what `workouts_template_has_no_date` requires — and deletions go up as
      tombstones for sessions and templates alike.
- [ ] **One bad row cannot block the rest.** A row the server rejects is marked
      with the reason and skipped; the queue carries on. Rejections are not
      retried until the row is edited; network failures are.
- [ ] Local columns `syncError`, `syncAttempts`, `lastSyncAttemptAt` on
      `workouts`.

### Saying what happened (F18)

One backup state, read by every surface: *up to date* · *backing up* ·
*waiting (offline)* · *signed out* · *failed, retrying* · *needs attention
(rejected)*.

| Where | What it shows |
|---|---|
| Summary | *Saved on this phone* at once, then *Backed up ✓*, or the reason and a Retry |
| Track | A glass pill **only** when something needs you: *2 workouts waiting to back up* or *Backup failed · Retry*. Nothing when all is well. |
| Settings → Backup | Last backup, what is waiting, each failure with its reason, *Back up now* |
| History and library rows | A cloud-off mark on anything not backed up |

| Case | Message | Action |
|---|---|---|
| Offline | *Saved on this phone. It'll back up when you're online.* | none — automatic |
| Signed out | *Not backed up — you're signed out.* | Sign in |
| Session expired | *Sign in again to keep backing up.* | Sign in |
| Server rejected a workout | *"Push" couldn't be backed up: a value is out of range.* | Open it |
| Server error or timeout | *Backup failed. Trying again shortly.* | Retry |
| Backup unavailable (configuration) | *Backup isn't available right now.* | Retry later |

Raw codes go to the log and never to the screen — the rule `SyncReport.detail`
already states. `AppHaptics.problem()` fires only when a *Back up now* the
lifter pressed fails; a background failure never buzzes.

---

## Phase 5 — glass and motion

### What "Apple glass" means here (D6)

Apple's current design puts glass on the controls that float over content —
bars, docks, sheets, the keyboard bar — and leaves content solid. The content
scrolling beneath is what the glass refracts. `mgk_ui`'s rule says glass needs
something behind it — checked side by side in the harness: over flat charcoal
the blur does nothing. Both say the same thing, and F21 is what breaking it
looks like.

So every glass surface in Lift gets one of two things behind it: the photograph
(with parallax), or content scrolling underneath.

### Shared components (`mgk_ui`, so Run gets them too)

- [ ] **`GlassSurface` desaturates what is behind it.** A saturation-zero stage
      in the same filter pass, so a green tick or a red badge under the pane
      reads as grey light instead of a coloured smudge — ADR-0009's greyscale,
      enforced by the material. Presets for a bar, a dock and a sheet.
- [ ] **`showGlassSheet`** — sized to its content up to a ceiling, safe areas
      top and bottom, keyboard-aware without climbing under the status bar,
      drag detents with a selection haptic on each.
- [ ] **`AppFilledButton`, `AppOutlinedButton`** — the press feel for the two
      kinds of button that still have none (F20). And a test in each app that
      fails on a raw `FilledButton`, `OutlinedButton`, `TextButton.icon` or
      `InkWell` in presentation code, so this cannot drift back — principle 9.
- [ ] **`AppToast`** — the undo and status message, on glass. The colour
      scheme gets its `inverseSurface` so no Material snackbar anywhere turns
      into a white bar (F24).
- [ ] **Springs in `AppMotion`** — one snappy, one gentle — for presses, ticks,
      sheets and the dock. Curves stay for fades and entrances.
- [ ] Run is checked against its board after each shared change.

### The session screen

- [ ] **Photograph behind, content between two glass layers.** The backdrop
      moves from the near-opaque `quiet` scrim to `grounded`, with parallax.
- [ ] **A top bar that folds.** At the top of the list: *In progress*, the
      name large, and elapsed · volume · sets · movements in one row. Scrolled:
      a slim glass bar with the name, the clock and **Finish**. The two-by-two
      card goes; the list scrolls under the bar.
- [ ] **A bottom dock.** *Add exercise* lives there. When a set is ticked the
      rest timer grows out of it — a progress ring, the time, −30 / +30, Skip —
      and shrinks back when rest ends. It replaces the flat `RestBar`.
- [ ] **The set you are on is the loud one** (F23). The next set lifts to
      `elevated` with white numbers; done sets recede to secondary ink with a
      filled check.
- [ ] **Cards stay solid** (`AppCard`), thumbnails sit on charcoal instead of
      black (F24).

### The other screens

- [ ] **Track:** sections arrive in sequence, the figures count up, your
      workouts sit as glass cards over the photograph, the photo drifts as the
      screen scrolls.
- [ ] **Summary:** the same arrival, the totals count up, a new best lands with
      a spring and a commit haptic, and the template-change and backup lines
      sit under the totals.
- [ ] **Library, editor, history:** glass top bar over a quiet photograph;
      rows solid; a dragged row lifts (slight scale and shadow) while it moves.
- [ ] **Sheets** (picker, preview, premades, Finish, confirmations) move to
      `showGlassSheet` (F21, F22).
- [ ] **Launch screens charcoal** on iOS and Android (F24).

### Motion, moment by moment

| Moment | Motion | Haptic |
|---|---|---|
| A screen opens | sections enter in sequence, 40 ms apart | — |
| Any button | settles under the finger | tap |
| Set ticked | the check springs in, the row settles back | **commit** |
| Set added | the row slides and fades in; the card grows | tap |
| Set removed | swiped away, the gap closes, Undo appears | selection |
| Movement finished | the card folds to its one-line summary | — |
| Rest starts | the dock grows into the timer | — |
| Rest ends | the ring completes | milestone (existing) |
| Finish | the sheet rises; the summary replaces the session | **commit** |
| Totals | count up to their value | — |
| Sheet reaches a detent | snaps | selection |

Every one of these goes still under the platform's reduced-motion setting.
Haptics do not change with it.

### Keeping it smooth

- [ ] At most two blurred layers on screen at once — the bar and the dock; a
      sheet hides the dock. No glass inside a scrolling list.
- [ ] Profiled on a real iPhone in a profile build: no dropped frames while
      scrolling a six-movement session under the bars.

---

## Phase 6 — history you can fix

- [ ] **Every session, not the last five** (F16). Profile's *Recent sessions*
      opens a full list, grouped by week.
- [ ] **A session opens** to the summary layout, read-only, with **Edit** and
      **Delete**.
- [ ] **Edit** reuses the session screen's rows, limits and input rules. Saving
      marks it for backup; personal bests and totals follow.
- [ ] **Delete** is soft, with Undo, and reaches other devices as a tombstone.

---

## The test pass

Each phase lands with its tests and its board plates. Then one full run on a
real iPhone, from a fresh install, before the build is offered to anyone.

### Automated

**Sets**
- remove first, middle, last and only set → contiguous numbers; undo restores
  values and position
- warm-up then working sets → labels `W, 1, 2, 3`; cycle all four types, then
  remove one
- add the 20th set → Add disables with its reason; the 21st cannot happen
- carry-forward after a removal takes the last remaining set
- reps: empty, `0`, `1`, `200`, `201` refused, `007` → 7, pasted `abc` refused
- weight: `102.5`, `102,5` → 102.5, `.5` → 0.5, `1000` accepted, `1000.5`
  refused, 225 lb round-trips as 225
- tick with no reps → reps field focused, nothing logged
- double-tap a tick → one completion, one rest
- five keystrokes and a blur → one write; app paused mid-edit → value kept

**Movements**
- remove with ticked sets → confirm; without → immediate, with Undo
- remove then add → order contiguous
- swap with nothing ticked → same position; with ticked sets → old kept,
  replacement below
- the 31st movement refused; the same movement twice in one session
- a typed movement name (not in the catalogue) gets history and prefill

**Templates**
- create: empty name, no movements and a 61-character name are refused
- add a premade → copy made; add again → only through *Add another copy*;
  undo an add
- edit: rename, reorder, remove, sets 1 and 20, rep target blank and set;
  leave with unsaved changes → asked
- delete → sessions from it stay; the tombstone syncs
- start → sets seeded, reps from the target, weight from last time, blank for
  a movement never done
- finish after each change in the learning table → the template matches the
  table; Undo restores it
- template edited elsewhere mid-session → asked, not applied
- template deleted mid-session → *Save as a new workout*
- planned session and discarded session → no template touched
- the 47 legacy Liftio templates pull with their set counts

**Finish and saving**
- unticked sets listed, then dropped
- finish offline → *Saved on this phone*; backs up on reconnect
- app killed straight after Finish → finished on relaunch, backed up
- discard → nothing uploaded, template unchanged

**Sync and messages** (fake client, plus pgTAP for `lift.save_workout`)
- offline → waiting, no error shown; online → backed up
- signed out → the signed-out line, not an error
- 401 → sign in again; rejected row → marked, reason shown, the rest still go
- timeout mid-upload → server copy unchanged (one transaction)
- edited on two devices → newest wins
- 100 waiting workouts → all go up, progress in Settings

### On the device (a TestFlight build, your phone)

- keyboard: open, accessory bar, next/previous, *Log set*, close by tapping
  away and by dragging
- haptics: tick, finish, a failed *Back up now*
- glass legible over the photograph at every point in the scroll; nothing
  under the Dynamic Island or the home indicator
- no dropped frames scrolling a long session
- airplane mode: log, finish, see *Saved on this phone*, reconnect, see it back
  up
- reduced motion on: everything still, nothing missing
- small screen (375 pt) and large text: nothing clipped

### The board

New preview entries, so every state above is photographed rather than
remembered: session scrolled and unscrolled, resting dock, keyboard with its
bar, multi-select picker, library (empty, one, many, one failing), template
preview, editor, Finish sheet (with unticked sets, with template changes),
summary (template updated, backing up, backed up, failed), Track with the
backup pill, Settings backup (waiting, failed), history list, session detail.

---

## Builds

Three builds, each your go because each is outward-facing:

1. **After Phases 0–2** — logging fixed. The one to test at a rack.
2. **After Phases 3–4** — templates and backup.
3. **After Phases 5–6** — the design pass and history; the submission
   candidate.

## Not in this plan

- Payments, compliance, store assets — [submission-week.md](submission-week.md).
- Cardio movements (time and distance): the columns exist, no screen uses them.
- Server-side limits: after the existing rows are checked against them.
- Background upload while the app is closed (iOS background tasks).
