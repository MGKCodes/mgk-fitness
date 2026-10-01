"""Stitches the launch animation's frames into a film that can be watched.

Run from apps/mgk_run, after `flutter test test/plates/launch_film.dart`:

    python tool/stitch_launch_film.py

Writes `plates/launch.gif` at the speed the app plays it, and
`plates/launch-slow.gif` at a third of that, for looking at the joins.
Both loop, with a pause on the last frame so the loop reads as a restart.
"""

import glob
import sys

from PIL import Image

FRAMES = 'plates/launch-film/f*.png'
FRAME_MS = 33  # a thirtieth of a second, as the film was drawn
HOLD_MS = 1200


def stitch(out: str, slow: int) -> None:
    paths = sorted(glob.glob(FRAMES))
    if not paths:
        sys.exit('No frames. Run: flutter test test/plates/launch_film.dart')
    frames = [Image.open(p).convert('RGB') for p in paths]
    # One palette for the whole film, from the frame with the most in it (the
    # app, at the end), so the greys do not shimmer from frame to frame.
    palette = frames[-1].quantize(colors=255, method=Image.Quantize.MEDIANCUT)
    quantised = [f.quantize(palette=palette, dither=Image.Dither.NONE) for f in frames]
    durations = [FRAME_MS * slow] * len(quantised)
    durations[-1] = HOLD_MS
    quantised[0].save(
        out,
        save_all=True,
        append_images=quantised[1:],
        duration=durations,
        loop=0,
        optimize=False,
    )
    print(f'{out}: {len(quantised)} frames')


if __name__ == '__main__':
    stitch('plates/launch.gif', 1)
    stitch('plates/launch-slow.gif', 3)
