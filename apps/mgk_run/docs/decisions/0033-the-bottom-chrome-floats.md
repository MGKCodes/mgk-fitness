# 0033 — The bottom chrome floats, and every surface pads for it

**Status:** Accepted
**Binds both apps.** Numbered in Run's sequence because that is where the ADRs
live; the component is in `packages/mgk_ui` and Lift consumes it.

## Context

The build 13 field test asked for a floating pill-shaped nav bar sitting above
the content rather than a bar beneath it.

Both apps had hand-written the same Material `NavigationBar` — Run's in
`home_shell.dart`, Lift's in `lift_shell.dart`, separate copies of one
construct. `mgk_ui` carried no navigation widget and no `navigationBarTheme` at
all, so each inherited Material's defaults and neither could tell the other had
drifted.

## Decision

**One `FloatingNavBar` in `mgk_ui`, taking its destinations as data.** The two
apps disagree about their first tab: Run's is *Home*, a summary of the day;
Lift's is *Track*, the thing you are doing in the gym, and `lift_shell.dart`
carries a comment explaining why. Baking either in would have made the other
wrong on the day it landed.

**It floats, so it no longer reserves its own height**, and every scrolling
surface pads its own foot.

## The trap, which has already been walked into once

The shortcut is to inject fake `MediaQuery` bottom padding for the subtree and
change nothing else. **Do not.** `home_shell.dart` carried twenty-two lines
about what happened last time: a 64pt fake reserve shortened the viewport a
`SafeArea` was *measuring* rather than the content inside it, so Plan's last
card was sliced and a black band appeared above the bar (IMG_4700).

Reading `MediaQuery` at the widget that needs it is the opposite of overriding
it for everything below.

## The two apps reserve differently, on purpose

**Run pads inside each scroll view**, with `kFloatingChromeClearance` plus the
safe-area inset read at the surface. Its `home_tab.dart` already used
`SafeArea(bottom: false)` and padded its own foot, so this extends a pattern
rather than introducing one. `plan_screen.dart`'s `SafeArea` becomes
`bottom: false` to match — that widget is the one that produced the band, and
deleting the mechanism beats tuning it.

**Lift reserves once at the shell**, extending the `MediaQuery` override it
already had. Its coach mark is conditional, and its own comment records why
per-surface reserving was wrong there: *"three surfaces reserving it themselves
meant dead space above the nav bar whenever the coach was absent."*

This looks like the trap and is not. What produced IMG_4700 was **double**
reservation — the Scaffold taking the bar's height *and* an injected inset on
top. Nothing sits in the Scaffold slot any more, so Lift's single reserve is the
only one. Changing an app's established inset handling at submission time was
the larger risk.

## Consequences

- The coach mark stacks above the pill in both apps. Run's is full width — the
  reveal expands to deliver a note as prose — so it cannot be tucked beside the
  pill the way Lift's circular mark could.
- `AppRadius.pill` is added: the one radius the scale does not moderate, because
  a pill is a shape rather than a softness, and picking 28 or 32 by eye is how
  the drift that class exists to stop begins again.
- Labels stay real `Text`. Seventeen tests across the two apps change tab by
  tapping one, and a bar whose icons alone must be recognised is a bar people
  learn by trial.
- **A merge conflict is expected** with `lift/release-2.0.0`, which still holds
  the identical `NavigationBar` block deleted here. That part merges;
  `_coachMarkReserve` is defined differently there and will conflict.

## The disconfirming condition

If any scrolling surface in either app can be scrolled to a state where its last
row sits under the pill, the clearance model is wrong.
`nothing_hides_under_the_chrome_test.dart` asserts it at the **shell**, not per
screen — last time every screen looked right on its own and the fault was in the
composition. Verified on a device as well: Profile scrolled fully leaves its
last row clear of both the pill and the mark.
