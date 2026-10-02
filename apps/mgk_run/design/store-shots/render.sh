#!/usr/bin/env bash
# Renders the store's pictures from the screens `test/plates/store.dart` drew:
# the design on the listing for both stores (or the sets named), and Play's
# feature graphic. Writes them to store-assets/derived/listing/, named for the
# order the stores show them in.
#
# Run from this folder, after `npm install`:
#
#     bash render.sh                          # Still, the one on the listing
#     bash render.sh ios-slipstream ios-plain # or the sets named
#
# **Only what was asked for is left in listing/.** A set from an earlier
# render, in a design that was not chosen, is exactly the folder somebody
# drags into a store by mistake.
set -e
assets="../../../../store-assets/derived"
fonts="../../../../packages/mgk_ui/assets/fonts"
if [ ! -d "$assets/screens/iphone" ]; then
  echo "No screens. Draw them first, from apps/mgk_run:"
  echo "  flutter test test/plates/store.dart --dart-define-from-file=config/app_config.json"
  exit 1
fi

# public/ is not committed: the app's own fonts and the screens, copied in.
mkdir -p public
cp "$fonts"/Inter-{Black,ExtraBold,Bold,SemiBold,Medium,Regular}.ttf public/
rm -rf public/screens
cp -r "$assets/screens" public/screens

# The status bar's clock: the one the screens were drawn by, so it agrees with
# Home's greeting. Without the file the pictures say 18:41.
props=()
if [ -f public/screens/clock.json ]; then
  props=(--props=public/screens/clock.json)
fi

sets="${@:-ios-still play-still}"
names=(1-run 2-today 3-finished 4-plan 5-coach 6-year)
rm -rf "$assets/listing"
for s in $sets; do
  rm -rf "out/$s"
  # One run per set: each picture is a frame of a six-frame sequence.
  npx remotion render src/index.ts "$s" "out/$s" --sequence --image-format=png --log=error "${props[@]}"
  for i in 0 1 2 3 4 5; do
    mv "out/$s/element-$i.png" "out/$s/${names[$i]}.png"
  done
  rm -rf "$assets/listing/$s"
  mkdir -p "$assets/listing/$s"
  cp "out/$s"/*.png "$assets/listing/$s/"
done
npx remotion still src/index.ts play-feature out/play-feature.png --log=error
cp out/play-feature.png "$assets/play-feature-graphic.png"
echo "Written to $assets/listing and $assets/play-feature-graphic.png"
echo "Check them, from apps/mgk_run: python tool/export_store_assets.py --check"
