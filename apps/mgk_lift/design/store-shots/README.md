# Store shots

The pictures on Lift's App Store and Google Play listings, and Play's feature
graphic. Drawn in [Remotion](https://www.remotion.dev) as stills: a frame, a
status bar and two lines of words round a screen the app drew itself.

**Run's kit, with Lift's pictures in it** (`apps/mgk_run/design/store-shots`).
The frame, the status bars, the type and the layouts are the same, so the two
listings read as one suite. What is Lift's: the six pictures and their words
(`src/shots.ts`), the feature graphic (`src/Feature.tsx`, stacked as Lift's
launch is), and the mark, which climbs.

## Three steps, all repeatable

```
# 1. The screens. From apps/mgk_lift.
flutter build web -t lib/preview/main.dart --release
PLAYWRIGHT_DIR=<folder containing node_modules> node tool/capture_store_screens.mjs

# 2. The pictures. From this folder.
npm install
bash render.sh
```

Step 1 writes `screenshots/store/screens/`, step 2 writes
`screenshots/store/listing/<set>/` and `play-feature-graphic.png`, all under
`apps/mgk_lift`. All of it is generated and none of it is committed.

## The sets

| Set | Size | What it is |
|---|---|---|
| `ios-still`, `play-still` | 1290×2796, 1080×1920 | **A · Still**, as Run's listing, and what `render.sh` draws by default. Words centred, the whole phone under them |
| `ios-slipstream`, `play-slipstream` | 1290×2796, 1080×1920 | **B · Slipstream.** The mark behind, words hard left, phone running off the bottom |
| `ios-plain`, `play-plain` | 1290×2796, 1080×2160 | **C · Plain.** The screen and its status bar, no words |
| `play-feature` | 1024×500 | Play's feature graphic: the mark above `LIFT`, and the subtitle |

The other two are drawn only when named: `bash render.sh ios-plain play-plain`.

## Where things are decided

- **The six pictures, their order and their words:** [`src/shots.ts`](src/shots.ts).
  Picture for picture Run's, and every line says something the listing's
  description already says. Each is tagged free or subscription, because three
  of the six are the coach and both stores want that said.
- **The screens and their data:** the preview harness, `lib/preview/main.dart`,
  the same fixtures the screen board is drawn from.
- **The phones:** `tool/capture_store_screens.mjs`. Run's sizes, pixel ratios
  and safe areas; the harness takes the safe area as `?safe=top,bottom`,
  because a browser has none of its own.
- **The status bar's clock:** `TIME` in `src/shots.ts`. No screen shows the
  time of day, so nothing has to agree with it.

## The frame is nobody's phone

The frame is a plain dark rectangle with a camera cut-out, drawn here. It is
not a picture of an Apple or Google product, so there is no trademark rule to
follow and nothing to go out of date when a new phone ships.

## Licence

Remotion is free for individuals and for companies of up to three people; a
larger company needs a company licence. Check that still holds before
rendering for a release.
