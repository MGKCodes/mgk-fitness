"""V2 with a background that does some work.

V2's two chevrons are the mark and they do not change here. What changes is
everything behind them, and the reason there is room for it is structural:

    An adaptive icon has TWO layers. The foreground is the thing that must
    survive the 66dp safe circle. The **background fills the whole 108dp** and
    is expected to be cropped by whatever mask the launcher applies.

So the mark stays exactly where it is, and the background gets to bleed off
every edge. Nothing here can push the chevrons around or cost them legibility
at 48px, which is why this is the safe place to add interest.

Six treatments, each drawn for Run and for Lift. The rule they are judged
against: at 48px the background must read as *tone*, not as a second subject.
A background you can identify at thumbnail size is competing with the mark.
"""

from PIL import Image, ImageDraw, ImageFilter
import math
import os
import sys

OUT = sys.argv[1] if len(sys.argv) > 1 else '.'

S = 8
N = 1024
C = N * S
BG = (0x1A, 0x1A, 0x1A, 255)
SILVER = (0xC0, 0xC0, 0xC0, 255)
WHITE = (0xFF, 0xFF, 0xFF, 255)
SAFE = 0.61


def disc(d, cx, cy, r, fill):
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill)


def path(d, pts, width, fill):
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        d.line([(x0, y0), (x1, y1)], fill=fill, width=int(width))
    for x, y in pts:
        disc(d, x, y, width / 2, fill)


def draw_mark(d, up):
    """V2, unchanged: two chevrons, silver then white, on the ascent."""
    w = C * SAFE
    cx = cy = C / 2
    stroke = C * 0.090
    half = w * 0.215
    lean = w * 0.200
    gap = w * 0.360
    rise = w * 0.215
    for i, colour in enumerate((SILVER, WHITE)):
        if up:
            x = cx - half
            y = cy + gap / 2 - i * gap
            pts = [(x, y), (x + half, y - lean), (x + half * 2, y)]
        else:
            x = cx - gap / 2 - lean / 2 + i * gap
            y = cy + rise / 2 - i * rise
            pts = [(x, y - half), (x + lean, y), (x, y + half)]
        path(d, pts, stroke, colour)


def base():
    return Image.new('RGBA', (C, C), BG)


def grad(mix):
    """Charcoal lifted toward the surface grey by `mix` (0..1)."""
    a, b = 0x1A, 0x3A
    v = int(a + (b - a) * max(0.0, min(1.0, mix)))
    return (v, v, v, 255)


# ── 1 · Glow ────────────────────────────────────────────────────────────────
# A radial lift behind the mark. The quietest of the six and the only one with
# no shape of its own, so it can never compete at 48px.
def bg_glow(im, up):
    d = ImageDraw.Draw(im)
    steps = 90
    for i in range(steps, 0, -1):
        r = C * 0.72 * i / steps
        d.ellipse((C / 2 - r, C / 2 - r, C / 2 + r, C / 2 + r),
                  fill=grad(0.55 * (1 - i / steps) ** 1.8))
    return im


# ── 2 · Split ───────────────────────────────────────────────────────────────
# The ground divided along the chevrons' own angle, darker below — so the mark
# climbs out of something rather than floating on it.
def bg_split(im, up):
    d = ImageDraw.Draw(im)
    if up:
        d.polygon([(0, C), (C, C), (C, C * 0.46), (0, C * 0.54)], fill=grad(0.30))
    else:
        d.polygon([(0, C), (C, C), (C, C * 0.30), (0, C * 0.70)], fill=grad(0.30))
    return im


# ── 3 · Lane ────────────────────────────────────────────────────────────────
# A track lane running behind the mark and off both edges. The one treatment
# that says "running" on its own.
def bg_lane(im, up):
    d = ImageDraw.Draw(im)
    stroke = C * 0.035
    for off in (-1, 1):
        r = C * 0.40 + off * C * 0.135
        box = (C / 2 - r, C / 2 - r, C / 2 + r, C / 2 + r)
        d.arc(box, 0, 360, fill=grad(0.26), width=int(stroke))
    return im


# ── 4 · Terrain ─────────────────────────────────────────────────────────────
# D's elevation trace demoted to texture: it crosses the whole canvas and runs
# off both sides, so it reads as ground rather than as a second mark.
def bg_terrain(im, up):
    d = ImageDraw.Draw(im)
    stroke = C * 0.045
    pts = [(-0.05, 0.74), (0.18, 0.60), (0.36, 0.70), (0.58, 0.44),
           (0.78, 0.58), (1.05, 0.38)]
    line = [(px * C, py * C) for px, py in pts]
    if up:
        line = [(py * C, C - px * C) for px, py in pts]
    path(d, line, stroke, grad(0.26))
    return im


# ── 5 · Trail ───────────────────────────────────────────────────────────────
# Ghost chevrons receding behind the two real ones — the ones already run.
# Closest to the mark in shape, which is the risk: it can read as four
# chevrons at a glance rather than two with a history.
def bg_trail(im, up):
    d = ImageDraw.Draw(im)
    w = C * SAFE
    cx = cy = C / 2
    stroke = C * 0.090
    half = w * 0.215
    lean = w * 0.200
    gap = w * 0.360
    rise = w * 0.215
    for k, mix in ((2, 0.18), (3, 0.10)):
        i = -k
        if up:
            x = cx - half
            y = cy + gap / 2 - i * gap
            pts = [(x, y), (x + half, y - lean), (x + half * 2, y)]
        else:
            x = cx - gap / 2 - lean / 2 + i * gap
            y = cy + rise / 2 - i * rise
            pts = [(x, y - half), (x + lean, y), (x, y + half)]
        path(d, pts, stroke, grad(mix))
    return im


# ── 6 · Corner ──────────────────────────────────────────────────────────────
# A single soft wedge from the corner the mark is heading toward. Directional
# without drawing anything the eye can name.
def bg_corner(im, up):
    layer = Image.new('RGBA', (C, C), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    if up:
        d.polygon([(0, 0), (C, 0), (C, C * 0.55)], fill=grad(0.34))
    else:
        d.polygon([(C, 0), (C, C), (C * 0.35, 0)], fill=grad(0.34))
    layer = layer.filter(ImageFilter.GaussianBlur(C * 0.06))
    im.alpha_composite(layer)
    return im


TREATMENTS = [
    ('t0-plain', 'Plain', None),
    ('t1-glow', 'Glow', bg_glow),
    ('t2-split', 'Split', bg_split),
    ('t3-lane', 'Lane', bg_lane),
    ('t4-terrain', 'Terrain', bg_terrain),
    ('t5-trail', 'Trail', bg_trail),
    ('t6-corner', 'Corner', bg_corner),
]


def render(fn, up):
    im = base()
    if fn is not None:
        im = fn(im, up)
    draw_mark(ImageDraw.Draw(im), up)
    return im.resize((N, N), Image.LANCZOS)


def masked(im, size, circle=True):
    im = im.resize((size, size), Image.LANCZOS).convert('RGBA')
    m = Image.new('L', (size * 4, size * 4), 0)
    dd = ImageDraw.Draw(m)
    if circle:
        dd.ellipse((0, 0, size * 4, size * 4), fill=255)
    else:
        dd.rounded_rectangle((0, 0, size * 4, size * 4),
                             radius=int(size * 4 * 0.26), fill=255)
    m = m.resize((size, size), Image.LANCZOS)
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    out.paste(im, (0, 0), m)
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    rows = []
    for key, _label, fn in TREATMENTS:
        run, lift = render(fn, False), render(fn, True)
        run.save(os.path.join(OUT, f'run-{key}.png'))
        lift.save(os.path.join(OUT, f'lift-{key}.png'))
        rows.append((key, run, lift))

    big, small = 200, 48
    pad, gap = 36, 26
    width = pad * 2 + 2 * (big + gap) + 3 * (small + 14)
    sheet = Image.new('RGBA', (width, pad * 2 + len(rows) * (big + gap)),
                      (0x0E, 0x0E, 0x0E, 255))
    for i, (key, run, lift) in enumerate(rows):
        y = pad + i * (big + gap)
        a = masked(run, big)
        sheet.paste(a, (pad, y), a)
        b = masked(lift, big, circle=False)
        sheet.paste(b, (pad + big + gap, y), b)
        for k, art in enumerate((run, lift, run)):
            s = masked(art, small)
            sheet.paste(s, (pad + 2 * (big + gap) + k * (small + 14),
                            y + big // 2 - small // 2), s)
    sheet.save(os.path.join(OUT, 'v2-treatments.png'))
    print('wrote', len(rows), 'treatments')


main()
