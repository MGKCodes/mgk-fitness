# 0022 — The in-run map is north-up

**Status:** Accepted

## Context

The in-run map has always drawn north-up, and never because anyone decided it
should. `RouteMap` passes `MapOptions` an `initialZoom` and nothing else; there
is no `initialRotation`, no `MapController.rotate`, no bearing anywhere in the
recording layer. North-up is what you get when rotation was never built, which
is a different thing from north-up being right — and undecided defaults are
precisely the ones that get quietly reversed later by whoever assumes the
question was never asked.

The question is worth asking because heading-up is the norm somewhere very
visible: car navigation, where it is close to universal. The instinct to match
it is reasonable and should be answered rather than ignored.

It cannot usefully be answered by looking at a picture. A design plate
(`test/plates/board.dart`) renders a still frame, and heading-up's failure mode
is temporal — a map that rotates under a figure being read at arm's length. A
single frame flatters it. Worse, the test framework answers every network image
with a 400, so a heading-up plate would be a rotated silver line on a blank
ground: it would look fine and demonstrate nothing. The one honest way to judge
it by eye is to build rotation and drive it on a device, which is a real piece
of work to evaluate something the reasoning below already answers.

## Decision

**The in-run map stays north-up, as a choice rather than as an omission.** No
rotation is added to `RouteMap`.

The reason is narrower than the usual north-up/heading-up argument, and it is
the one that decides it: **heading-up solves a wayfinding problem this app does
not have.** There is no route to follow, no turn-by-turn, no destination — the
plan prescribes a distance and a pace band, never a path. Nobody is being
navigated anywhere.

Stripped of wayfinding, the in-run map answers exactly two questions, and
heading-up makes one of them worse and neither of them better:

- *Where am I* — answered by the position marker, which is orientation-agnostic.
  Rotation adds nothing.
- *What have I drawn* — answered by the route's shape. A loop, an out-and-back,
  a familiar block only reads **as a shape** if it holds still. That shape is the
  one thing on the map that belongs to the runner rather than to the tile
  provider, and heading-up destroys it continuously.

This is consistent with what the map already is. It takes no gestures, follows
rather than fits, and the class doc is explicit that panning mid-run loses your
own position and that the summary screen is where a route gets explored. A map
that will not let you navigate it has no business orienting itself as though you
were navigating.

Three supporting reasons, in the order they would bite:

**Bearing noise at running speed.** Car navigation gets away with heading-up
because 50 km/h yields a stable bearing. A runner at 11 km/h with 5 m horizontal
accuracy produces bearing estimates that jitter by tens of degrees between
fixes, so the entire map swims under a hero numeral the screen exists to make
readable. This is the same class of problem the pace band already solves with
hysteresis, and it is worse here because it moves everything at once rather than
one word.

**Rotated labels.** The basemap is raster — `RouteMap.tileUrlTemplate` is a
`{z}/{x}/{y}.png` URL, so labels are baked into the tile image rather than laid
out by the client. They rotate with it, and a heading-up map serves
upside-down street names to a screen that is glanced at, not studied. Vector
tiles would fix the labels specifically; they would not touch the two reasons
above it.

**Battery.** Continuous rotation means continuous redraw, on a display held
awake for the length of a run.

## Consequences

A runner heading south sees their route drawn downward, which is the accepted
cost. It is a cost paid once per run, at the moment of first glance, against a
benefit paid continuously.

Rotation is not "not implemented yet" — it is declined. Anyone adding it is
reversing this decision and should supersede this ADR rather than treat the
absence as an oversight.

**Disconfirming condition.** If Runio ever prescribes a *path* rather than a
distance — a route to follow, a turn to take, a loop suggested by the coach —
the wayfinding problem this ADR says does not exist will exist, and this should
be reopened. Nothing in [ADR-0011](0011-a-plan-has-a-shape.md) points that way,
but that is where the change would come from.

A weaker form remains available without reopening anything: a one-shot
orientation hint (a north arrow, or briefly rotating on demand) gives a
disoriented runner the same answer without rotating the map continuously. That
is additive and does not contradict this decision.
