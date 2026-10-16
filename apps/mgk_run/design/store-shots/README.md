# Store shots

The pictures on Run's App Store and Google Play listings, and Play's feature
graphic. Drawn in [Remotion](https://www.remotion.dev) as stills: a frame, a
status bar and two lines of words round a screen the app drew itself.

## Three steps, all repeatable

```
# 1. The screens. From apps/mgk_run. Needs the real config, for the map tiles.
flutter test test/plates/store.dart --dart-define-from-file=config/app_config.json

# 2. The pictures. From this folder.
npm install
bash render.sh

# 3. Check them against what each store accepts. From apps/mgk_run.
python tool/export_store_assets.py --check
python tool/export_store_assets.py --downloads   # and copy them where a browser can reach them
```

Step 1 writes `store-assets/derived/screens/`, step 2 writes
`store-assets/derived/listing/<set>/` and `play-feature-graphic.png`. All of it
is generated and none of it is committed.

## The sets

| Set | Size | What it is |
|---|---|---|
| `ios-still`, `play-still` | 1290×2796, 1080×1920 | **A · Still. Chosen on 2 October 2026, and what `render.sh` draws by default.** Words centred, the whole phone under them |
| `ios-slipstream`, `play-slipstream` | 1290×2796, 1080×1920 | **B · Slipstream.** The launch animation's picture: mark behind, words hard left, phone running off the bottom |
| `ios-plain`, `play-plain` | 1290×2796, 1080×2160 | **C · Plain.** The screen and its status bar, no words |
| `play-feature` | 1024×500 | Play's feature graphic: `RUN »` and the subtitle |

The other two are kept as source and are drawn only when named:
`bash render.sh ios-slipstream play-slipstream`. All three are on
[the gallery](https://claude.ai/artifact/KmRop4oC1KrHb2UdHykJbU) as they were
when the choice was made.

## Where things are decided

- **The six pictures, their order and their words:** [`src/shots.ts`](src/shots.ts).
  Every line there is checked against "What the app may not claim" in the
  listing doc. The three that show the coach are tagged as the subscription,
  because both stores want that said; the other three carry no tag. **No
  picture says "Free"**: Apple counts it as a price (guideline 2.3.7), and
  Lift 2.0.0 was rejected for it on 7 October 2026.
- **The status bar's clock:** nobody sets it. Home's greeting follows the real
  clock when the screens are drawn, so `store.dart` writes a time that agrees
  with it to `clock.json` beside the screens, and `render.sh` passes it in.
- **The runner in the pictures:** `test/plates/store.dart`. No elevation and no
  heart rate, steps and cadence on iPhone only, this week's sessions run as the
  plan set them.
- **The coach's reply in picture 5:** `StoreCoach` in the same file. Scripted,
  in the runner's own units, until a reply the real coach gave replaces it.
- **The run on the map:** `test/plates/store_route.dart`, a fixed file, so a
  redraw gives the same picture.

## The frame is nobody's phone

The frame is a plain dark rectangle with a camera cut-out, drawn here. It is
not a picture of an Apple or Google product, so there is no trademark rule to
follow and nothing to go out of date when a new phone ships.

## Licence

Remotion is free for individuals and for companies of up to three people; a
larger company needs a company licence. Check that still holds before
rendering for a release.
