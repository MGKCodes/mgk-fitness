# 0043 — The map keeps what it has shown, and does not download what it has not

**Status:** Accepted, 2026-10-01.

## Context

A runner who loses signal should not lose the map, and the map should already
be there when they press Start. That was the ask, with one condition: whatever
is kept is kept on the phone, and we store none of it.

Two things were true before this, and neither was written down.

flutter_map already saved every tile it drew, in the app's cache directory.
And it then drew nothing over that saved copy once the copy was a day old and
the network was down. Esri marks a tile fresh for 24 hours
(`Cache-Control: max-age=86400`); past that the loader asks again, and a failed
request was an error rather than a reason to use what it held. So the copy
existed for exactly the moment it was not used in.

The obvious build is the one that was asked for first: download the area around
the runner at first login. It was not built, for a reason outside the code.

## Decision

- **A saved tile is drawn when the network cannot answer, however old it is.**
  `OfflineTileClient` sits under flutter_map's loader and answers a failed or
  refused request from the cache. HTTP allows a stale response from a cache
  that is disconnected, which is what this is. A refusal counts as a failure:
  Esri's free tier stops serving when its monthly allowance is spent, and the
  streets a phone already has should outlast that.
- **The tiles around the runner are loaded when the app opens.**
  `BasemapWarmUp` reads the phone's last known position and fetches what the
  start screen is about to draw: one screen at the run's zoom and the one ring
  of tiles flutter_map loads around any map. Sixteen tiles and about 2.4 MB at
  the largest phone, measured against the real service, once per place. A
  runner who starts somewhere else gets no benefit and no harm.
- **It never asks for location and never takes a fix.** No permission, or no
  last known position, and it does nothing. Opening the app switches no GPS on.
- **Nothing downloads an area.** No radius, no route ahead, no "offline maps".
- **It is a cache and only a cache.** On the phone, capped at 200 MB, emptied by
  the system when storage is short, in no backup of ours and sent nowhere. The
  key leaves the token out, so rotating Esri's key does not orphan it.

## Why not download the area

Esri's terms: *"Systematically requesting ArcGIS tiles for offline use through
other apps or services is prohibited"*, and the product terms rule out
programmatic export of volumes of basemap tiles. Taking tiles offline is
allowed through Esri's own software, which this app does not use.

The line this decision draws is between **loading a map** and **downloading
one**. Asking for the tiles a screen is about to show, a moment before it shows
them, is loading. Asking for tiles nobody is about to look at, so that they
exist later, is the thing the terms name. The ring is on the right side of that
line only because flutter_map draws it anyway; widening it would not be.

This is a reading of the terms by the people building the app, not legal
advice. If Esri says the warm-up is on the wrong side, it comes out and the
first bullet stands on its own.

## What it costs

- **A policy sentence.** The warm-up sends the phone's rough position to Esri
  when the app opens, not only when a map is on screen. The policy says so, in
  all three renderings, and so do the store forms' location rows.
- **Up to 2.4 MB of mobile data** the first time the app is opened in a new
  place, which the start screen would have spent a tap later.
- **A map that can be a day or a year out of date** where there is no signal.
  A stale street is better than a blank one, and it is replaced within five
  minutes of the signal returning.

## What it does not do

The first run somewhere new, with no signal at all, still draws its route on a
plain ground. That is the case a real offline map answers, and it needs a
provider whose terms allow one or tiles we host ourselves. Recorded in
[after-1.0.0.md](../after-1.0.0.md) beside native maps.

## Disconfirming condition

Two things would reverse this. Esri objecting to the warm-up, which removes the
second bullet. And the sitting showing that a stale tile is drawn in place of a
fresh one while the phone *has* a signal, which would mean the client is
answering from the cache when it should not, and removes the first until it is
understood.
