#!/usr/bin/env bash
# Renders Lift's App Store creative assets: the header and search results
# pictures, the moving header and the universal picture (or only the ones
# named), then a check sheet for each with Apple's safe box ruled on it.
#
# Run from this folder, after `npm install`:
#
#     bash render.sh                                  # everything, to out/
#     bash render.sh header-name search               # or the ones named
#
# The screens come from tool/capture_store_screens.mjs (see store-shots). A
# worktree has none, so point STORE at a checkout that does:
#
#     STORE=/c/Projects/mgk-fitness/apps/mgk_lift/screenshots/store bash render.sh
#
# Apple refuses a PNG with an alpha channel, so every still is flattened to
# RGB after rendering. The film is H.264 at 30 fps, which the spec allows.
set -e
# Its own port: a dev server on 3000 (the website, say) answers Remotion's
# check instead of Remotion and the render fails.
port="${PORT:-3417}"
store="${STORE:-../../screenshots/store}"
fonts="../../../../packages/mgk_ui/assets/fonts"
if [ ! -d "$store/screens/iphone" ]; then
  echo "No screens in $store/screens/iphone. Draw them first, from apps/mgk_lift:"
  echo "  flutter build web -t lib/preview/main.dart --release"
  echo "  node tool/capture_store_screens.mjs"
  exit 1
fi

mkdir -p public out
cp "$fonts"/Inter-{Black,ExtraBold,Bold,SemiBold,Medium,Regular}.ttf public/
rm -rf public/screens
cp -r "$store/screens" public/screens

names="${@:-header-name header-launch header-between-sets search universal}"
for n in $names; do
  if [ "$n" = "header-between-sets" ] || [ "$n" = "header-launch" ]; then
    rm -f "out/$n.mp4"
    npx remotion render src/index.ts "$n" "out/$n.mp4" --codec=h264 --crf=16 --pixel-format=yuv420p --log=error --port="$port"
    test -s "out/$n.mp4"
  else
    rm -f "out/$n.png"
    npx remotion still src/index.ts "$n" "out/$n.png" --log=error --port="$port"
    test -s "out/$n.png"
  fi
  python check.py "out/$n."*
done
ls -la out/
