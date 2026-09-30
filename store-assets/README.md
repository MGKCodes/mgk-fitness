# store-assets

Images destined for App Store Connect.

```
python tool/export_store_assets.py             # from apps/mgk_run
python tool/export_store_assets.py --check     # check only
python tool/export_store_assets.py --downloads # also copy to ~/Downloads
python tool/export_store_assets.py --to <dir>  # ...or somewhere specific
```

**`--downloads` is not a convenience, it is a correctness feature.** This
repository is usually worked in as a worktree, so `derived/` sits several levels
down inside a hidden `.claude` directory: a fine home for a build output and a
hopeless one for a file about to be dragged into a browser. The first version of
this asset was uploaded from an easier-to-find copy that was two revisions
stale, and nothing about that looked wrong until App Store Connect refused it.

## Two kinds of thing, and only one of them is committed

**`derived/` is generated and gitignored.** It comes out of the plate board, so
it can always be made again, and a committed copy of a generated file is a copy
that drifts. Run the script.

**`captured/` comes off a real device and is committed.** A screenshot of a run
somebody actually did cannot be regenerated, and an App Store asset that exists
on one laptop is a liability rather than an asset.

## Why a script rather than a drag from Finder

**App Store Connect refuses an image with an alpha channel, and every plate has
one**, because a Flutter render target is RGBA. The first IAP review screenshot
left this repo at 786x1704 RGBA and would have been rejected on upload. The
script flattens onto the app's own near-black, so a transparent edge does not
come out as a white halo against the screen it came from.

**And it refuses arbitrary dimensions.** The documented "640x920 minimum" for
an IAP review screenshot is the old rule: a 786x1704 render, comfortably over
it, was rejected by the form. What App Store Connect takes is a real iPhone
screenshot size, so the paywall is rendered once at 430x932 logical by 3, which
is 1290x2796, rather than upscaled from something smaller.

It checks what a machine can check: alpha, and dimensions against the spec each
asset is for. **It cannot tell you the screenshot is of the right screen**, or
that an icon has square corners.

## What is here

| File | Spec | For |
|---|---|---|
| `derived/run-iap-review-screenshot.png` | 1290x2796, no alpha | Both subscriptions' review screenshot |

## What is not here yet

**The 6.9" listing screenshots.** Those are a different requirement and the
plates are *not* usable for them: plates are 393x852 logical renders and the
test framework answers every network image with a 400, so there are no basemap
tiles, and the map is half of what makes the in-run shot worth showing. Take
them off an iPhone running the TestFlight build, drop them in `captured/` named
`listing-*.png`, and the script will check the dimensions (it accepts 1320x2868
and 1290x2796; App Store Connect also takes 1260x2736).

### There are stand-ins, and they are not submittable

`derived/stand-ins/` holds six captures at the right dimensions, taken on
2026-09-08 from the **Android emulator** with `wm size 1290x2796` and
`wm density 480` — which is the 6.7" iPhone's geometry, so they pass
`--check` — driven through `lib/preview/main.dart`'s screen keys. The captioned
versions are in `derived/mockups/`.

**They exist to settle composition and caption copy, and for nothing else.**
Three reasons they cannot be submitted:

1. **They are an Android render of an iOS app.** The emulator's own status bar
   and gesture pill are cropped out of the mockups, but the widgets underneath
   are Material's, not UIKit's.
2. **There are no basemap tiles.** Same absence the plates have, for a different
   reason — the preview harness points at a keyless dev basemap and the emulator
   has no MapTiler key. The in-run and finished-run shots draw the route on the
   charcoal ground.
3. **The fixtures show what the app does not.** `_demoSummary()` fills
   `avgHr`, `caloriesEst` and elevation; a recorded run fills none of the three
   (`recording_run_recorder.dart` never sets them, and there is no barometric
   source). The finished-run shot therefore advertises three stats the shipped
   build leaves out. Deliberate, decided 2026-09-08, and recorded here so it is
   a choice rather than a surprise.

**They live in `derived/` on purpose.** `captured/` is where the real device
shots go, and a stand-in sitting there under the name the script expects is
exactly the file somebody drags into App Store Connect by mistake. `derived/`
is gitignored, so nothing here is committed either.

The six worth shooting are named in
[app-store-listing.md](../apps/mgk_run/docs/app-store-listing.md) § Screenshots,
which is the only copy of the list, chosen off
[the board](https://claude.ai/code/artifact/9ddfd186-11ad-4260-bde9-ef8b7a5d9190).

**No marketing icon to upload.** App Store Connect takes the 1024 icon from the
build's asset catalogue, so there is nothing to put here for it.
**`captured/icon-1024.png` is the old loop mark**, committed on 2026-09-10,
before both apps got their current icons on 2026-09-11. Do not upload it
anywhere; it can be deleted. The script still checks any `icon-*` file it finds
for 1024x1024 and no alpha.

**Google Play's images are not checked here.** Its 512 icon, feature graphic and
phone screenshots have different rules (a 32-bit icon, a 1024x500 graphic,
screenshots no longer than twice their width), listed in
[play-listing.md](../apps/mgk_run/docs/play-listing.md).
