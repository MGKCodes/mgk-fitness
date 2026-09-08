# 0031 — The in-run map pans, and following is a mode

**Status:** Accepted
**Amends:** [0022](0022-the-in-run-map-is-north-up.md) in part

## Context

The in-run map took no gestures at all. `RecordingScreen` wrapped it in an
`IgnorePointer` and passed `interactive: false`, and the class doc gave two
reasons:

> **The map takes no gestures.** It follows the runner and is not pannable,
> which is both the right in-run behaviour — panning mid-run loses your own
> position, and the summary screen is where a route is explored — and the thing
> that keeps the sheet drag unambiguous. A pannable map under a draggable sheet
> is a gesture-arena fight, and the strip layout lost it: taps on its body did
> nothing at all.

The panel had two resting places, and that was a decision too:

> **Two resting places, not three.** A middle detent sounds generous and costs
> the gesture its meaning: with three stops a drag lands somewhere the runner
> did not choose, and they have to look to find out where.

The build 13 field test asked for both to change: a pannable map with a
recentre control, and a third, smaller detent showing time and distance with the
map full screen.

## Decision

**The map accepts gestures, and the camera's follow becomes a mode.** A pan
parks the camera where the runner left it; a recentre control puts it back and
is shown only while the map is parked.

**The panel gains a third resting place** — a strip roughly a nav bar tall,
carrying distance and time, with the map taking the screen.

### Why the first objection does not survive

Panning mid-run losing your own position is a real cost, and it is a cost of
panning *without a way back*. Follow is suspendable rather than absent, and the
control that restores it is offered exactly when it is needed.

### Why the second objection does not apply here

The gesture-arena fight is real and was lost by the **strip layout**, where the
map was a 132pt band beneath a sheet that overlapped it. In this layout the map
is `Stack` child 0 and the panel is an opaque `GlassSurface` above it, so a
pointer that goes down on the sheet belongs to the sheet for the whole gesture;
the two never contend for a pixel.

That is an argument, and arguments about touch are cheap. It was checked on a
device: at 6.7" geometry a pan moves the map and leaves the panel where it is,
and the existing sheet-drag test — which drags from a point over the map — still
opens the sheet. That test's comment said "a drag there hits nothing", which is
no longer true and had to be corrected.

### Why a third detent does not cost the gesture its meaning

The original reasoning holds for three stops of the *same content*. The peek is
a different readout, not a smaller one: `DISTANCE` is a 96pt numeral and `TIME`
is one of three columns beneath it, and neither truncates into a strip. You
cannot land on the peek by accident, because it shows something else.

`initialChildSize` is unchanged. The peek is somewhere you can go, not where you
start — a runner opening a run wants the numbers.

### Rotation is still declined

`InteractiveFlag.all` includes rotation, so turning panning on with `all` would
have reversed [ADR-0022](0022-the-in-run-map-is-north-up.md) in one word,
silently. The accepted set is named once as `kMapGestures` and excludes
`rotate`. It also excludes `pinchMove`, which drags on a two-finger move at a
low threshold and is the one flag that could plausibly take a drag the panel
needs.

**What 0022 loses** is its supporting argument at lines 50–53 — *"it takes no
gestures, follows rather than fits… a map that will not let you navigate it has
no business orienting itself as though you were navigating."* Its decision
stands; that sentence no longer supports it, and north-up now rests on the
plainer ground that a rotating map is harder to read at a glance while moving.

## Consequences

- `RouteMap` gains `interactionFlags`, `follow` and `onUserPan`. The camera
  follow was unconditional; a pan would otherwise be undone by the next fix,
  roughly once a second.
- Recentring is `follow` going false to true and nothing else. No controller is
  handed out, no key held — the alternative put a second thing in charge of a
  camera the widget already drives from `build`.
- `mapTop` now follows the sheet's live extent. It was computed once from the
  collapsed fraction, so the position dot was correctly placed at exactly one of
  the panel's resting places and wrong at the others. A third detent would have
  made that worse.
- The board's in-run plates are all stale, and two new ones exist: `23-panned`
  and `24-peek`.

## The disconfirming condition

**Following must never be restored on a timer.** A camera that yanks itself back
while somebody is reading a junction is worse than one that cannot move at all,
because it does it unasked — and it is precisely the failure panning was refused
to avoid. `map_follows_until_you_move_it_test.dart` asserts it does not. If that
test is ever changed to allow an auto-resume, this decision was wrong.
