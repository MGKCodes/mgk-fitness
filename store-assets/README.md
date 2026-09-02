# store-assets

Images destined for App Store Connect.

```
python tool/export_store_assets.py            # from apps/mgk_run
python tool/export_store_assets.py --check    # check only
```

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
them off a device on TestFlight, drop them in `captured/` named `listing-*.png`,
and the script will check the dimensions.

The six worth shooting are named in
[app-store-listing.md](../apps/mgk_run/docs/app-store-listing.md), chosen off
[the board](https://claude.ai/code/artifact/9ddfd186-11ad-4260-bde9-ef8b7a5d9190).

**The 1024 marketing icon.** Name it `captured/icon-1024.png` and the script
will check it is exactly 1024x1024 with no alpha, which is the most common
trivial rejection there is.
