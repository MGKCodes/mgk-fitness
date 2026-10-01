# Launch films

Four designs for how Run opens, drawn in [Remotion](https://www.remotion.dev)
and rendered to video so they could be watched before one was built.
**Slipstream was chosen on 1 October 2026** and is what build 28 ships.

| Film | The idea |
|---|---|
| **Slipstream** (chosen) | The mark winds back, then goes. The name is uncovered behind it, and it rests as `RUN »` |
| Odometer | The icon tile on screen; the mark rolls out, R rolls in, the tile opens for U and N |
| Pace | The word huge and heavy, rising letter by letter over a rule in metres and a clock |
| Route | A run draws itself across a street map and ends on the mark |

The first attempt, before these, drew its own letters out of thick lines and
looked hand-drawn. All four set the name in Inter, the app's own type, and
keep the mark at the icon's exact proportions (`tool/build_app_icons.py`).

## This is the sketchbook, not what ships

The app cannot play a Remotion film. The chosen one is rebuilt in Flutter in
[`lib/src/core/launch/launch_curtain.dart`](../../lib/src/core/launch/launch_curtain.dart),
with the same numbers: `LaunchTimeline` there and `Slipstream.tsx` here read
side by side. Change the timing in one and change it in the other.

To watch what the app actually draws, without a phone:

```
flutter test test/plates/launch_film.dart
python tool/stitch_launch_film.py      # writes plates/launch.gif
```

## Rendering the films

From this folder. `public/` is not committed: it holds the app's own fonts and
a screenshot of Home, copied in.

```
npm install
mkdir -p public
cp ../../../../packages/mgk_ui/assets/fonts/Inter-{Black,ExtraBold,Bold,SemiBold,Medium,Regular}.ttf public/
cp ../../plates/home-with-plan.png public/home.png   # draw the plates first
bash render.sh                                       # all four, to out/
bash render.sh Slipstream                            # or one
```

`render.sh` also writes a contact sheet of stills per film, which is how each
was checked before it was shown.

## Licence

Remotion is free for individuals and for companies of up to three people; a
larger company needs a company licence. Check that still holds before using
it for anything published, such as a store preview video.
