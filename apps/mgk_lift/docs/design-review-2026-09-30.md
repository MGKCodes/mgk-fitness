# Design review, 30 September 2026

Matthew's pass over the [Lift Screen Board](https://claude.ai/artifact/UZKDFbA8qht1Nj9TQ3dQB1)
(version 11, built from `8a0014a` on 2026-09-29, 84 plates). These are his
findings, recorded screen by screen with the code each one touches. **This is not
a plan.** Nothing here is designed or scheduled yet; the next step is to discuss
these and turn them into one.

Codes are the board's (`W6`, `P7`, …): the letter is the act, the number is the
plate. Open the board to see any screen named here.

---

## The direction, from the three references

Matthew supplied three reference mockups. They are kept locally, not in git, at
`apps/mgk_lift/screenshots/design-refs/` (third-party work, and this repository
is public):

| File | What it is | What to take from it |
|---|---|---|
| `ref-1-glass-plants.png` | A plant-care app on frosted glass over a soft photo | Glass cards with real translucency and a light edge; a greeting headline; small, calm stat tiles; pill tabs; a clear single primary action |
| `ref-2-hiking-tiles.png` | A hiking app over mountain photography | Full-bleed photo carrying the top of the screen with the title set on it; **big-number tiles** in a two-column grid ("84 Your Hiking Score", "78 Good", "42 Trails"); mixed surfaces side by side (glass over photo, solid accent, dark); one dominant pill action with an arrow, anchored low |
| `ref-3-interior-dark.png` | A dark interior-design app | Photo-led hero with the headline over it; warm restrained palette; one "Get Started" pill; image cards in horizontal rows |

The common thread: **photography and space do the work, numbers are big, surfaces
are mixed rather than one card style everywhere, and each screen has one obvious
action.**

---

## Findings

### 1. Sign in (S1, S2)

- **Add a background image.** The screen is currently plain charcoal.
- **Add Sign in with Apple and Sign in with Google** beside email and password.

Code: `lib/src/features/auth/presentation/sign_in_screen.dart`,
`lib/src/features/auth/data/supabase_auth.dart`.

Worth knowing before planning: both providers are Supabase Auth configuration as
well as code (Apple's Services ID and key; a Google Cloud OAuth client). Sign in
with Apple is also an **App ID capability**, and Lift signs iOS with a
provisioning profile uploaded to Codemagic by hand (see `codemagic.yaml`,
`lift-ios-release`), so adding it means regenerating and re-uploading that
profile. Offering Google sign-in without Apple would trip App Store guideline
4.8, so the pair is the right unit.

### 2. Track, the home screen (T1 to T7)

**It doesn't work as it is.** Rework it along the lines of the references: use
of space, imagery, big numbers, and **"Start a session" emphasised as the
purpose of the page.** Run's home screen is closer to right than Lift's today,
but Lift's start action needs to be more dominant than Run's is.

Finding 17 below moves today's planned session onto this screen as well ("Start
today's session", with its explanation), so the redesign has to hold both an
unplanned start and a planned one.

Code: `lib/src/features/tracking/presentation/track_surface.dart`; for
comparison, Run's `apps/mgk_run/lib/src/features/home/presentation/home_tab.dart`
and `home_tiles.dart`.

### 3. The session screen's background (W1, and the session generally)

**No photograph behind a workout.** Use a different, calmer image, or simply a
gradient. A photo is not needed mid-workout and adds noise to the screen used at
the rack.

Code: `lib/src/features/tracking/presentation/active_session_screen.dart`
(`PhotoBackdrop`, grounded, with parallax).

### 4. Your workouts (W3)

Rework it to the glass design; the background image has fallen out of place.
Finding 7 also puts a **Start** button on each workout here.

Code: `lib/src/features/tracking/presentation/workout_library_screen.dart`.

### 5. Premade workouts (W4)

**Confusing.** Make it much simpler, easier to read, with fewer options. The
intent is that the **coach offers workouts**, rather than a catalogue being the
main way to get one.

Code: `lib/src/features/tracking/presentation/premade_library_sheet.dart`.

### 6. Build a workout (W5)

**This screen doesn't make logical sense to Matthew.** The session screen already
does this job: a saved workout is designed while somebody works out, if they
choose to build their own. So the standalone builder is in question, not just
its layout.

Code: `lib/src/features/tracking/presentation/workout_editor_screen.dart` (it
also serves W17, editing an existing workout, which the discussion should cover).

### 7. A saved workout's preview (W15, and W16)

**One step too many.** Put Start on each workout in the list (W3), which makes
the preview screen redundant. W16, the blocked version of the same sheet, goes
with it; the "a session is already open" rule still needs a home.

Code: `lib/src/features/tracking/presentation/workout_preview_sheet.dart`.

### 8. Session running (W6)

- The layout is fine. Give the **heading block more glass treatment** (title,
  elapsed time, volume, sets, movements) so that information reads better.
- **"Add exercise" should not be the main button.** Today it is the dock at the
  bottom of the screen. Make it a smaller "+ Add" button to the left of Finish in
  the top bar.

Code: `active_session_screen.dart` (`_TopBar`, `_LargeTitle`, `_Dock`, `_AddRow`).
The dock is also where the rest timer grows from, so moving Add out of it changes
what the dock is when nothing is resting.

### 9. Rest timer (W10, W18)

**Good as it is.** No change.

### 10. The coach during a workout (W6 onward)

- The **coach mark (C) should be reachable on the session screen**, so somebody
  can talk to the coach mid-workout. Today it floats over the three tabs only.
- Use **Run's open-then-minimise bubble** for nudges: the mark opens with a short
  line, e.g. "PB on the bench press, well done", then retracts into the C. It
  shows the coach is following the workout.

Code: Run's `apps/mgk_run/lib/src/features/coaching/presentation/coach_reveal.dart`
("the coach says its piece, then goes back to its corner"); the shared mark is
`packages/mgk_ui/lib/src/widgets/coach_mark.dart`; Lift's shell places the mark
in `lib/src/features/home/presentation/lift_shell.dart`.

### 11. Exercise search (W7, W19)

- **Search is too strict.** Spelling has to be close, and movements that go by
  more than one name ("single arm cable" and "one arm cable") are hard to find.
- **Add ways to narrow the list:** filter by muscle group and by equipment,
  alongside search.

Code: `lib/src/features/tracking/presentation/exercise_picker_sheet.dart`,
`lib/src/features/tracking/data/exercise_lookup.dart` (the 266-movement catalogue
and its search).

### 12. The session summary (W11)

- **More glass**, and the **totals should stand out** more.
- **"Back to Track" reads confusingly.** Call it "Finish" or similar.
- **Saving is the default, asked at Finish, not a button to find.** Pressing
  Finish asks something like "Save this to your Push workout for next time?",
  yes or no.
- **Only ask when movements were added.** Different sets or reps never trigger
  the question.

This **changes a settled decision.** D1 in
[lift-2.0.0-logging-rework.md](lift-2.0.0-logging-rework.md) has the workout
learn at Finish **automatically, with Undo** (the "lesson" on W21); this asks
first instead, and only for added movements. It also replaces the "Save to your
workouts" button on the summary (W11, W14) and on the session screen.

Code: `lib/src/features/tracking/presentation/session_summary_screen.dart`,
`save_workout_prompt.dart`, `lib/src/features/tracking/domain/template_movement.dart`
(`TemplateUpdate.between`).

### 13. The coach on the summary (W11, W12, W21)

- **Remove** the "Talk it over with your coach" button and the **"New bests"**
  section.
- The **coach C bubble** says it instead (the new bests, anything worth saying),
  then minimises.
- **Tapping the C opens a chat about the session.**
- **Tapping the C also counts as Finish**, including the save question, so
  nobody has to come back to the summary to save.

### 14. Backup status after a session (W22, W23)

- Replace the line under the totals with a **small horizontal pill at the top of
  the screen**: "Syncing…", then "Success" or "Failed".
- On success it simply goes away.
- On failure it **says why** and links to **Settings** to sync again.

Code: `session_summary_screen.dart` (`_BackupLine`),
`lib/src/features/sync/presentation/backup_messages.dart`.

### 15. The purchase screen (P7)

- This is what an **unsubscribed person sees whenever they tap the C, anywhere in
  the app.** Today the C opens the coach sheet and the paywall lives on Plan and
  Photos.
- **Redesign it properly as a sales screen**, not a slide-up sheet, even though
  it belongs to the coach. It must give **absolute clarity** in the purchase
  decision.
- **Drop the separate "Subscribe to Coach" button**: choosing a tier *is* the
  purchase.
- Show each tier's **benefits as a bulleted feature list**, not a sentence, so
  the difference is easy to see.

The App Store requirements met by today's sheet still apply to whatever replaces
it: each tier's name, period and store price; the renewal terms in the store's
own words; working links to the terms and privacy policy; and Restore. They are
pinned by `test/purchases/purchase_ui_test.dart`.

Code: `lib/src/features/purchases/presentation/purchase_sheet.dart`.

### 16. Plan, paid with no plan yet (P2)

This is **what a new subscriber sees first**, so it needs more work: explain
what happens next and which button to press.

Code: `lib/src/features/coaching/presentation/plan_surface.dart` (`_entitled`).

### 17. Plan with a live plan (P5, P6)

Matthew likes them, but the content moves:

- **Today's session moves to Track**: "Start today's session" on the home screen,
  with the explanation below it (see finding 2).
- **Plan becomes the whole plan, calendar-led**: how the week is going, the full
  calendar, the goals, and explanations. **Workouts are not started from Plan.**

Code: `lib/src/features/planning/presentation/standing_plan_surface.dart`,
`track_surface.dart`.

### 18. Profile (G1, G2)

- Give the **six-stat block** at the top the glass treatment from the references,
  and make better design choices throughout.
- **Remove the personal bests section.** Bests belong in each exercise's full
  stats.
- **Previous workouts are what matters here.** Show each one as its name, date
  and stats, and give the list its own contained space rather than letting it run
  down the whole page.

An exercise stats screen does not exist yet, so moving bests there implies
building one.

Code: `lib/src/features/profile/presentation/profile_surface.dart`;
`lib/src/features/stats/presentation/history_screen.dart` for the full list (G10).

### 19. Settings (A1 to A10)

It works, but uses space badly and has too much text:

- **Explanations go behind a "?" or info tap** rather than printed in full.
- **The account is the main thing** on the screen.
- **Distance and weight are shared MGKFitness settings**, so follow Run's
  Settings design.
- The unit choices should **take less space** and be better thought out than
  full-width toggles.
- Rethink the spacing of the whole screen.

Code: `lib/src/features/settings/presentation/settings_screen.dart`; Run's
`apps/mgk_run/lib/src/features/settings/presentation/settings_screen.dart`.

---

## Themes across the findings

- **One obvious action per screen.** Track's start (2), the session's Finish with
  Add demoted (8), the summary's Finish (12), and the tier choice as the purchase
  (15).
- **The coach becomes the connective tissue.** It is reachable mid-workout (10),
  offers workouts instead of a catalogue (5), speaks through the minimising
  bubble instead of buttons and sections (10, 13), and its mark is the entry to
  buying for anybody unsubscribed (15).
- **Fewer screens and steps.** The builder is questioned (6), the preview goes (7),
  saving becomes a question at Finish (12), and Finish can happen from the C (13).
- **Glass and photography where they help, and not where they don't.** More glass
  on headings, totals, stats and lists (4, 8, 12, 18); photography on Track and
  Sign in (1, 2); none behind a workout (3).
- **Say less on screen.** Settings text behind "?" (19); bullets instead of
  sentences on the purchase screen (15).

## Decisions this reopens

| Settled | Where | What the review says instead |
|---|---|---|
| D1: a saved workout learns at Finish automatically, with Undo | `lift-2.0.0-logging-rework.md` | Ask at Finish, only when movements were added (12) |
| The standalone workout builder (W5) and preview sheet (W15) | Phase 3 of the logging rework | Builder questioned (6); preview removed (7) |
| The premade library as a way to start | Phase 3 | Simplify; the coach offers workouts (5) |
| "Add exercise" as the dock's resting state | Phase 5 | "+ Add" beside Finish (8) |
| The paywall as Plan's and Photos' empty state | `plan_surface.dart`, `photos_surface.dart` | The C opens the sales screen for anybody unsubscribed (15) |
| Planned sessions start from Plan | `standing_plan_surface.dart` | Start from Track; Plan is the calendar (17) |

## Out of scope for this review

Everything outside design: the migration, the merge to `main`, the store
dashboards and the store screenshots. Those are tracked in
[submission-week.md](submission-week.md) and [store-setup.md](store-setup.md).
**Store screenshots wait for this redesign**, by Matthew's decision on
2026-09-29.
