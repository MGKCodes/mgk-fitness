"""C×D hybrids for Run, and the Lift siblings that prove the language travels.

C gave legibility — three bold chevrons, unmistakable at 48px, and generic.
D gave meaning — an elevation trace, specific to an app whose whole point is
reading training, and the thinnest mark of the five. The hybrid wants C's
weight carrying D's idea: **something that both moves forward and climbs.**

The family rule these are built on, and the thing to judge as much as the Run
mark itself:

    A greyscale angular mark on charcoal, ascending, with exactly one
    white element marking the live end. Run ascends to the RIGHT, because
    a run is distance. Lift ascends UPWARD, because a lift is load.

Same palette, same stroke, same white-tip rule, one rotation apart. Eat would
take the third axis when it exists.

Constraints unchanged: greyscale (ADR-0009), inside the 66dp safe circle, and
judged at 48px.
"""

from PIL import Image, ImageDraw
import math
import os
import sys

OUT = sys.argv[1] if len(sys.argv) > 1 else '.'

S = 8
N = 1024
C = N * S
BG = (0x1A, 0x1A, 0x1A, 255)
SILVER = (0xC0, 0xC0, 0xC0, 255)
DIM = (0x8A, 0x8A, 0x8A, 255)
WHITE = (0xFF, 0xFF, 0xFF, 255)
SAFE = 0.61


def canvas():
    im = Image.new('RGBA', (C, C), BG)
    return im, ImageDraw.Draw(im)


def finish(im):
    return im.resize((N, N), Image.LANCZOS)


def disc(d, cx, cy, r, fill):
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill)


def path(d, pts, width, fill):
    """Stroked polyline with round joins and caps."""
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        d.line([(x0, y0), (x1, y1)], fill=fill, width=int(width))
    for x, y in pts:
        disc(d, x, y, width / 2, fill)


def frame():
    w = C * SAFE
    return w, (C - w) / 2, C / 2


# ── H1 · Rising chevrons ────────────────────────────────────────────────────
# C's three chevrons, but climbing: each sits higher than the last, so the mark
# moves forward AND up. The leading one is white — it is where you are.
def rising_chevrons(up=False):
    im, d = canvas()
    w, x0, cy = frame()
    stroke = C * 0.080
    lean = w * 0.19
    step_x = w * 0.30
    step_y = w * 0.17
    half = w * 0.20
    for i, colour in enumerate((DIM, SILVER, WHITE)):
        x = x0 + w * 0.08 + i * step_x
        y = cy + w * 0.19 - i * step_y
        pts = [(x, y - half), (x + lean, y), (x, y + half)]
        if up:
            # Lift: the same chevron turned to point upward, climbing in place.
            x = x0 + w * 0.19 + i * (w * 0.005)
            y = cy + w * 0.26 - i * (w * 0.26)
            pts = [(x, y), (x + half, y - lean), (x + half * 2, y)]
        path(d, pts, stroke, colour)
    return finish(im)


# ── H2 · The climb ──────────────────────────────────────────────────────────
# D's trace, sharpened: one continuous angular line that nets upward, ending in
# a white arrowhead rather than a dot. The line is the terrain; the head is the
# runner still going.
def climb(up=False):
    im, d = canvas()
    w, x0, cy = frame()
    stroke = C * 0.085
    h = w * 0.66
    y0 = cy - h / 2
    pts = [(0.00, 0.92), (0.24, 0.54), (0.44, 0.74), (0.70, 0.22)]
    line = [(x0 + px * w, y0 + py * h) for px, py in pts]
    if up:
        line = [(x0 + (1 - py) * w, y0 + h - px * h) for px, py in pts]
    path(d, line, stroke, SILVER)
    # The head: a chevron, not a dot — C's shape doing D's job.
    hx, hy = line[-1]
    dx, dy = hx - line[-2][0], hy - line[-2][1]
    ang = math.atan2(dy, dx)
    arm = w * 0.21
    for s in (+1, -1):
        a = ang + s * math.radians(140)
        path(d, [(hx, hy), (hx + arm * math.cos(a), hy + arm * math.sin(a))],
             stroke, WHITE)
    return finish(im)


# ── H3 · Steps ──────────────────────────────────────────────────────────────
# Three ascending strokes, no chevron. Reads as intervals, as a week of
# sessions, as progressive overload.
#
# **And it fails the family test by passing it too well.** Run and Lift come
# out identical, because there is no direction in the mark to rotate — a family
# needs a shared language AND a per-app difference, and this has only the
# first. Two apps on one home screen wearing the same icon is worse than two
# unrelated icons. Left in as the control: it is the cleanest of the four and
# it is the one that cannot ship.
def steps(up=False):
    im, d = canvas()
    w, x0, cy = frame()
    stroke = C * 0.105
    gap = w * 0.34
    for i, (frac, colour) in enumerate(
        ((0.42, DIM), (0.70, SILVER), (1.0, WHITE))
    ):
        x = x0 + stroke / 2 + i * gap
        bottom = cy + w * 0.30
        top = bottom - w * 0.56 * frac
        path(d, [(x, bottom), (x, top)], stroke, colour)
    return finish(im)


# ── H4 · The trace and the tip ──────────────────────────────────────────────
# H2's terrain with C's three chevrons riding it, rather than one head. More to
# look at, and the one most likely to fall apart small — included because it is
# the fullest expression of the mix and that is worth seeing fail or not.
def trace_and_tip(up=False):
    im, d = canvas()
    w, x0, cy = frame()
    stroke = C * 0.070
    h = w * 0.58
    y0 = cy - h / 2
    pts = [(0.00, 0.95), (0.26, 0.55), (0.46, 0.76), (0.74, 0.20)]
    lean = w * 0.15
    half = w * 0.16
    if up:
        # Lift: the same terrain and the same chevrons, turned a quarter so the
        # climb is vertical. Load rather than distance.
        line = [(x0 + w * 0.5 + (py - 0.5) * h, y0 + h - px * h) for px, py in pts]
        path(d, line, stroke * 0.85, DIM)
        for i, colour in enumerate((SILVER, WHITE)):
            x = x0 + w * 0.5 + (0.34 - i * 0.16 - 0.5) * h
            y = y0 + h - h * (0.62 + i * 0.21)
            path(d, [(x - half, y), (x, y - lean), (x + half, y)], stroke, colour)
        return finish(im)
    line = [(x0 + px * w, y0 + py * h) for px, py in pts]
    path(d, line, stroke * 0.85, DIM)
    for i, colour in enumerate((SILVER, WHITE)):
        x = x0 + w * 0.62 + i * w * 0.21
        y = y0 + h * (0.34 - i * 0.16)
        path(d, [(x, y - half), (x + lean, y), (x, y + half)], stroke, colour)
    return finish(im)


RUN = [
    ('h1-rising', 'Rising chevrons', rising_chevrons),
    ('h2-climb', 'The climb', climb),
    ('h3-steps', 'Steps', steps),
    ('h4-trace', 'Trace and tip', trace_and_tip),
]


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
    for key, _name, fn in RUN:
        fn(up=False).save(os.path.join(OUT, f'run-{key}.png'))
        fn(up=True).save(os.path.join(OUT, f'lift-{key}.png'))

    big, small = 260, 48
    pad, gap = 40, 34
    cols = big + gap + big + gap + 3 * (small + 16)
    sheet = Image.new('RGBA', (pad * 2 + cols, pad * 2 + len(RUN) * (big + gap)),
                      (0x0E, 0x0E, 0x0E, 255))
    for i, (key, _n, fn) in enumerate(RUN):
        y = pad + i * (big + gap)
        run = fn(up=False)
        lift = fn(up=True)
        a = masked(run, big)
        sheet.paste(a, (pad, y), a)
        b = masked(lift, big)
        sheet.paste(b, (pad + big + gap, y), b)
        for k, art in enumerate((run, run, lift)):
            s = masked(art, small)
            sheet.paste(s, (pad + 2 * (big + gap) + k * (small + 16),
                            y + big // 2 - small // 2), s)
    sheet.save(os.path.join(OUT, 'hybrids.png'))
    print('wrote', len(RUN), 'hybrids with Lift siblings')


main()
