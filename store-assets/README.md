# store-assets

Images destined for App Store Connect and Play Console.

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
| `derived/screens/iphone/`, `derived/screens/android/` | 1290x2796, 1080x2160 | The six listing screens, as the app draws them. An input, not something to upload |
| `derived/listing/ios-still/` | 1290x2796, no alpha | The App Store listing pictures |
| `derived/listing/play-still/` | 1080x1920, no alpha | The Google Play listing pictures |
| `derived/play-feature-graphic.png` | 1024x500, no alpha | Play's feature graphic |
| `derived/play-icon-512.png` | 512x512, **with** alpha | Play's icon, re-saved from `apps/mgk_run/design/store/` |
| `derived/submission-sheet.html` | | Every store field, ready to paste: `python tool/build_submission_sheet.py`. Published as [the submission sheet](https://claude.ai/artifact/Y2zLyeNxVuTrJTfHUn7tqM) |

`listing/` holds the design that was chosen (Still) and nothing else. The other
two are drawn only when `render.sh` is asked for them by name, and asking
replaces what is there.

## The listing pictures are drawn

Three steps, each repeatable, described in
[`apps/mgk_run/design/store-shots/README.md`](../apps/mgk_run/design/store-shots/README.md):
`test/plates/store.dart` draws the six screens with the real map,
`design/store-shots/render.sh` sets each in a frame with its words, and the
script above checks the result against what each store accepts.

**This file used to say the plates were not usable for the listing**, for two
reasons: no basemap tiles, and fixtures that showed stats the app does not
record. Both are answered in `store.dart` rather than worked round. It takes
the test framework's network stub off and waits for the tiles, and its runner
has no elevation and no heart rate, with steps on the iPhone only. The board's
own plates are still not usable, for the same two reasons.

A capture off a real phone is still welcome in `captured/`, named
`listing-*.png`, and is checked the same way.

Which six screens, in what order, with what words, and which design is on the
listing: [app-store-listing.md](../apps/mgk_run/docs/app-store-listing.md)
§ Screenshots, which is the only copy of the list.

**No marketing icon to upload.** App Store Connect takes the 1024 icon from the
build's asset catalogue, so there is nothing to put here for it.
**`captured/icon-1024.png` is the old loop mark**, committed on 2026-09-10,
before both apps got their current icons on 2026-09-11. Do not upload it
anywhere; it can be deleted. The script still checks any `icon-*` file it finds
for 1024x1024 and no alpha.

**Google Play's images are checked here too.** Its rules are its own: a
32-bit icon, a 1024x500 graphic, and screenshots no longer than twice their
width. They are listed in
[play-listing.md](../apps/mgk_run/docs/play-listing.md).
