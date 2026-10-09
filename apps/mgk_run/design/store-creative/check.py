"""Flattens a rendered still to RGB, checks its size against Apple's spec, and
writes a check sheet beside it with the safe box from Apple's template ruled
on. For a film, checks size, rate and length, and lays frames out in a sheet.

    python check.py out/search.png
    python check.py out/header-between-sets.mp4

Needs Pillow, and ffmpeg/ffprobe on PATH for a film. Kept in step with
src/spec.ts by hand: the numbers are Apple's and do not move often.
"""
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

SPEC = {
    (3840, 1646): ("header", (1097, 493, 1646, 661)),
    (3840, 2560): ("search", (836, 765, 2168, 1030)),
    (5244, 2950): ("universal", (1921, 660, 1402, 962)),
}
RULE = (255, 64, 64)


def rule(im, box, scale):
    x, y, w, h = (v * scale for v in box)
    d = ImageDraw.Draw(im)
    d.rectangle([x, y, x + w, y + h], outline=RULE, width=3)


def still(path):
    im = Image.open(path)
    if im.mode != "RGB":
        im = im.convert("RGB")
        im.save(path)
    if im.size not in SPEC:
        sys.exit(f"{path}: {im.size} is not a size Apple takes")
    name, box = SPEC[im.size]
    scale = 1200 / im.size[0]
    small = im.resize((1200, round(im.size[1] * scale)), Image.LANCZOS)
    rule(small, box, scale)
    out = path.with_name(path.stem + "-check.png")
    small.save(out)
    print(f"{path}: {name}, {im.size[0]}x{im.size[1]}, RGB. Sheet: {out}")


def film(path):
    probe = json.loads(
        subprocess.check_output(
            ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
             "stream=width,height,r_frame_rate,pix_fmt:format=duration", "-of", "json", str(path)]
        )
    )
    s = probe["streams"][0]
    size = (s["width"], s["height"])
    fps = s["r_frame_rate"]
    secs = float(probe["format"]["duration"])
    if size not in SPEC:
        sys.exit(f"{path}: {size} is not a size Apple takes")
    if fps not in ("30/1", "60/1"):
        sys.exit(f"{path}: {fps} fps; Apple takes exactly 30 or 60")
    if not 15 <= secs <= 30:
        sys.exit(f"{path}: {secs:.2f} s; keep it between 15 and 30")
    name, box = SPEC[size]
    # The last frame of a 15 s film at 30 fps starts at 14.967 s.
    at = [0, 2, 5, 9, 10.2, 11, 11.3, 13, 14.4, 14.7, 14.9]
    tiles = []
    for t in at:
        raw = subprocess.check_output(
            ["ffmpeg", "-v", "error", "-ss", str(t), "-i", str(path), "-frames:v", "1",
             "-f", "image2pipe", "-vcodec", "png", "-"]
        )
        tmp = path.with_name(f".frame-{t}.png")
        tmp.write_bytes(raw)
        im = Image.open(tmp).convert("RGB")
        tmp.unlink()
        scale = 600 / im.size[0]
        im = im.resize((600, round(im.size[1] * scale)), Image.LANCZOS)
        rule(im, box, scale)
        ImageDraw.Draw(im).text((8, 6), f"{t:.2f}s", fill=(255, 255, 0))
        tiles.append(im)
    cols = 3
    th = tiles[0].size[1]
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * 610 + 10, rows * (th + 10) + 10), (60, 60, 60))
    for i, im in enumerate(tiles):
        sheet.paste(im, (10 + (i % cols) * 610, 10 + (i // cols) * (th + 10)))
    out = path.with_name(path.stem + "-check.png")
    sheet.save(out)
    print(f"{path}: {name}, {size[0]}x{size[1]}, {fps} fps, {secs:.2f} s, {s['pix_fmt']}. Sheet: {out}")


for arg in sys.argv[1:]:
    p = Path(arg)
    if p.name.endswith("-check.png"):
        continue
    (film if p.suffix in (".mp4", ".mov", ".m4v") else still)(p)
