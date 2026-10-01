#!/usr/bin/env bash
# Renders the films named (or all four), and a contact sheet of stills for each.
set -e
names="${@:-Slipstream Odometer Pace Route}"
for n in $names; do
  npx remotion render src/index.ts "$n" "out/$n.mp4" --codec=h264 --crf=16 --log=error
  for f in 0 18 30 39 48 57 66 81 96 104 125; do
    ffmpeg -loglevel error -y -i "out/$n.mp4" -vf "select=eq(n\,$f)" -vframes 1 "out/still-$n-$(printf %03d $f).png"
  done
  python sheet.py "$n" 0 18 30 39 48 57 66 81 96 104 125
done
ls -la out/*.mp4
