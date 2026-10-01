# Lift 2.0.0: Track, rebuilt as a front page

Decided with Matthew on 1 October 2026, after the dashboard sweep. Track as
built on 30 September (a photograph across the top, one big number, a row of
workout cards, an action pill anchored at the foot) is replaced by the layout
Run's Home uses: a quiet backdrop, a greeting, and three cards, with the main
button inside the first card rather than floating under everything.

This is the last piece of UI before the release candidate
([submission-week.md](submission-week.md), *What is left*, 2). No build is cut
until Matthew has looked at the new plates on the screen board.

Tick items as they land, and when something is settled differently from how it
is written here, change the item and say why.

## What was decided

**TR1. The start button lives in the Today card.** One card answers "what is
today" and carries the button that acts on it. The pill at the foot of the
screen goes. The coach's mark stays where it is, bottom right above the nav
bar.

**TR2. What the button does.** With a plan that has something today it starts
the plan's session. Otherwise it reads *Start a session* and opens *Your
workouts*, where a saved workout or a blank session is one more tap. Starting a
saved workout is two taps from Track now, where it was one. That was accepted
for a front page that reads at a glance.

**TR3. The workouts row leaves Track.** No cards of saved workouts and no
starters on the front page. Both live on *Your workouts*.

**TR4. This week shows when, not how much.** Monday to Sunday, a dot on each
day trained and the time that session started under it, today picked out. Two
figures: sessions (as "2 of 4" with a plan) and time in the gym. No volume: a
leg day and an arm day do not compare by weight moved. With a plan, the days it
runs on are ringed and the card says what is next.

**TR5. The planned day shows a count only.** The day's name, "6 movements",
and the button. The list of movements with last time's numbers went: it is one
tap away, inside the session, and on Plan.

**TR6. Last session.** Its name, the day and the time it started, then how
long it took, sets and movements. No volume here either. It opens the session's
own page. The summary a session ends on is unchanged.

**TR7. A quiet backdrop.** The photograph stays, as texture at about a third
strength behind the cards, the way Run's Home has it. It no longer leads the
screen.

**TR8. Your workouts gets a blank start, and loses its pictures.** A *Blank
session* row sits above the saved workouts (and above the three starters when
nothing is saved) whenever the screen was opened to start something. The
photograph behind the rows is replaced by the soft light the session screen
uses (the redesign's R13), the rows become solid cards, and the three starters
lose their thumbnails. Matthew's words: "the images are too much it is
difficult to read the screen."

## The Today card, state by state

| State | Plate | Headline | Under it | Button |
|---|---|---|---|---|
| Nothing logged ever | T8 | Ready when you are | Log a session set by set… | Start a session |
| No plan, nothing today | T1 | No session yet today | Pick a workout, or start blank. | Start a session |
| Trained today | (none) | the session's name | Done at 19:32 · 1h 02m · 7 sets | Start another session |
| Plan, training day | T4 | the day's name | 6 movements (and "moved from Thursday") | Start upper, then *Start something else* |
| Plan, rest day | T9 | Rest day | Next: Lower on Friday. | *Start a session anyway*, outlined |
| A session is open | T3 | the session's name | 3 sets in · 2 movements · started 17:56 | Resume session |
| Left open on another day | T5 | the session's name | Left open yesterday · 2 sets in | Resume session |

T2 (the coach has a note) is T1 with the dot on the mark. T6 and T7 (backup
needs the lifter) keep their one-line notice, now between the greeting and the
Today card.

Things settled while building, all small:

- **Two sessions in a day are two dots**, not the first time with "×2" as
  first described. A cell is about 44 points wide and "18:30 ×2" does not fit
  at a readable size.
- **A day already trained hides *Last session*.** The Today card is showing
  that session, and the same session twice on one screen reads as a bug. Run's
  Home makes the same call.
- **The week and the last session are drawn on a first open**, with dashes
  where the numbers will be, rather than left off as the old Track left its
  one number off. A front page of one card over empty space was the failure
  Run's Home was rebuilt to fix.
- **Times follow the phone's clock setting**: 18:30 on a 24-hour phone,
  6:30pm on a 12-hour one.
- **With a session open, nothing else can be started from Track.** The Today
  card is Resume and only Resume, so the "resume it, or discard it" question
  is now only reachable from inside the workouts screen.
- **The last session's first figure is *Length***, because *This week* has a
  *Time* of its own and that one is a total.

## Build

- [x] `track_surface.dart` rebuilt: header, backup notice, Today, This week,
      Last session. The workouts row, the starter cards, the action pill and
      the hero photograph are removed.
- [x] `lift_shell.dart`: Track is handed the library, the plan tab and a past
      session to open; the shell no longer keeps a copy of the saved workouts
      for Track.
- [x] `workout_library_screen.dart`: *Blank session*, the soft light, solid
      rows, no starter thumbnails.
- [x] Tests rewritten for the new Track and the changed library.
- [x] Preview plates and `tool/screen_board.json`: T1 to T8 rewritten, T9
      (rest day) added.
- [x] Board rebuilt (version 17) and republished for Matthew to review.
      Checked against version 16 plate by plate: the nine Track plates and the
      three workouts plates changed, T9 is new, and the other 74 are the same.
- [x] Matthew's review of the plates, 1 October: "happy with the screens for
      now", and he wants to feel it in a build. Nothing changed from it.

## Added on the way to the build

Matthew trained on build 32 that evening, which predates all of this, and
asked for two things from Run's lane before a new build.

- [x] **The shared motion.** `develop` is merged into this branch, which
      brings `mgk_ui`'s `TabStack` and the nav bar whose selection travels.
      The bar is shared, so Lift had that the moment it merged. The shell now
      uses `TabStack` where it used `IndexedStack`: a change of tab is a
      short shift and a fade, not a cut, with every tab still kept alive.
      Nothing else of Run's motion work is shared code.
- [x] **TR9. The app opens on its mark.** Run's launch
      (`LaunchCurtain`), rebuilt for Lift in
      `lib/src/core/launch/launch_curtain.dart`. The icon's two chevrons dip,
      drive up, and lift LIFT into place under them, with MGKFitness beneath;
      then the curtain fades at 1.94 seconds. Run's timing and Run's rules:
      the app loads underneath from the first frame, the curtain takes every
      touch while it is up, it plays once per cold start and never on coming
      back from the background, and it is not shown with Reduce Motion on.
      Stacked where Run's lockup is in a line, because this mark travels up.
      Plates O1 to O4 are the animation stopped at four moments. Lift's
      Android and iOS launch windows were already charcoal, so nothing native
      changed.
- [x] **Watched on a phone.** Matthew, on build 41, 1 October: "the intro
      animation is good". It was built straight from Run's numbers and had
      only been seen as four stills before that.

## Left for later

- The three split photographs in `assets/images/splits/` are no longer drawn
  anywhere. They stay in the bundle until the design is confirmed, then go.
- The start button is Lift's own copy of the shape Run's Home uses. If both
  keep it, it belongs in `mgk_ui`; moving it means editing Run, which is not
  this lane's to do.
- The same goes for the launch curtain: the widget around the painter is a
  copy of Run's, and only the painter differs.
