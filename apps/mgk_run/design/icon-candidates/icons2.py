"""Five candidate launcher marks for MGKFitness: Run — second pass.

The first pass drew with bare `ImageDraw.line`, which has no round caps: the
stride's chevrons collided into a block and the monogram's bowl never closed.
Everything here is stroked through `path()`, which draws the segments and then
a disc at every vertex, so joins and ends are round like the rest of the app.

Constraints, all real rather than taste:

  * **Greyscale.** ADR-0009 reserves colour for status. Charcoal #1A1A1A
    ground, silver #C0C0C0 mark, white #FFFFFF for the one live element.
  * **The 66dp safe circle.** An adaptive icon is 108dp of which only the
    central 66dp survives every launcher mask, so each mark sits inside 61% of
    the canvas. That is why these look smaller than the iOS art and why the
    iOS art could not simply be pasted across.
  * **Legible at 48dp**, which is where four of the five first-pass marks fell
    apart. Each is rendered at 48px as well as large.
"""

from PIL import Image, ImageDraw, ImageFont
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


def canvas():
    im = Image.new('RGBA', (C, C), BG)
    return im, ImageDraw.Draw(im)


def finish(im):
    return im.resize((N, N), Image.LANCZOS)


def disc(d, cx, cy, r, fill):
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill)


def path(d, pts, width, fill, cap=True):
    """A stroked polyline with round joins and ends."""
    r = width / 2
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        d.line([(x0, y0), (x1, y1)], fill=fill, width=int(width))
    verts = pts if cap else pts[1:-1]
    for x, y in verts:
        disc(d, x, y, r, fill)


def arc_pts(cx, cy, r, a0, a1, n=180):
    return [
        (cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a)))
        for a in [a0 + (a1 - a0) * i / n for i in range(n + 1)]
    ]


# ── A · The track ───────────────────────────────────────────────────────────
# A stadium, seen from above — the shape of the place rather than a symbol of
# the act. Proportions are a real 400m track: the bends are half the width.
def track():
    im, d = canvas()
    w = int(C * SAFE)
    h = int(w * 0.72)
    cx, cy = C // 2, C // 2
    stroke = int(C * 0.082)
    r = h / 2
    sx = w / 2 - r
    pts = (
        arc_pts(cx + sx, cy, r, -90, 90)
        + arc_pts(cx - sx, cy, r, 90, 270)
    )
    pts.append(pts[0])
    path(d, pts, stroke, SILVER)
    # The runner, on the near straight, sitting ON the lane rather than beside
    # it — the first pass had it half off the bottom edge.
    disc(d, cx - sx * 0.2, cy + r, stroke * 0.62, WHITE)
    return finish(im)


# ── B · The loop ────────────────────────────────────────────────────────────
# A route that does not quite close, with the runner on it — the iOS mark's
# idea, rebuilt. The gap sits at the BOTTOM: at the right, as in the first
# pass, the whole thing read as a letter C.
def loop():
    im, d = canvas()
    r = C * SAFE / 2
    cx = cy = C / 2
    stroke = int(C * 0.092)
    path(d, arc_pts(cx, cy, r, 108, 432), stroke, SILVER)
    a = math.radians(108)
    disc(d, cx + r * math.cos(a), cy + r * math.sin(a), stroke * 0.62, WHITE)
    return finish(im)


# ── C · The stride ──────────────────────────────────────────────────────────
# Three chevrons at a runner's forward lean — direction and cadence, no figure
# and no track. Spaced by a full stroke width so they read as three marks and
# not one block, which is what went wrong first time.
def stride():
    im, d = canvas()
    w = C * SAFE
    stroke = int(C * 0.078)
    h = w * 0.78
    cx, cy = C / 2, C / 2
    lean = w * 0.17
    gap = stroke * 2.05
    for i, (scale, colour) in enumerate(
        ((0.74, SILVER), (0.87, SILVER), (1.0, WHITE))
    ):
        ch = h * scale / 2
        x = cx - gap + i * gap - w * 0.16
        path(d, [(x, cy - ch), (x + lean, cy), (x, cy + ch)], stroke, colour)
    return finish(im)


# ── D · The profile ─────────────────────────────────────────────────────────
# An elevation trace: the shape of the hill you ran, which is the thing a
# runner actually looks at afterwards. Data rather than iconography, and the
# only candidate that says anything about *this* app rather than running.
def profile():
    im, d = canvas()
    w = C * SAFE
    x0 = (C - w) / 2
    h = w * 0.64
    y0 = (C - h) / 2
    stroke = int(C * 0.082)
    pts = [(0.00, 0.86), (0.22, 0.52), (0.40, 0.68),
           (0.62, 0.14), (0.82, 0.44), (1.00, 0.24)]
    line = [(x0 + px * w, y0 + py * h) for px, py in pts]
    path(d, line, stroke, SILVER)
    disc(d, line[-1][0], line[-1][1], stroke * 0.62, WHITE)
    return finish(im)


# ── E · The monogram ────────────────────────────────────────────────────────
# An R with the leg run off into a stride. Set in a real typeface rather than
# drawn by hand — the first pass built one from arcs and the bowl never
# closed. The only candidate that scales to a family: L for Lift, E for Eat.
def monogram():
    im, d = canvas()
    stroke = int(C * 0.075)
    size = int(C * 0.62)
    font = None
    for name in ('seguibl.ttf', 'ariblk.ttf', 'arialbd.ttf'):
        try:
            font = ImageFont.truetype(f'C:/Windows/Fonts/{name}', size)
            break
        except OSError:
            continue
    if font is None:
        return finish(im)
    box = d.textbbox((0, 0), 'R', font=font)
    tw, th = box[2] - box[0], box[3] - box[1]
    tx = C / 2 - tw / 2 - box[0] - C * 0.04
    ty = C / 2 - th / 2 - box[1] - C * 0.03
    d.text((tx, ty), 'R', font=font, fill=SILVER)
    # The leg, carried on past the letter and out to the runner.
    start = (tx + tw * 0.72, ty + th * 0.80)
    end = (C / 2 + C * SAFE / 2 * 0.92, C / 2 + C * SAFE / 2 * 0.80)
    path(d, [start, end], stroke, SILVER)
    disc(d, end[0], end[1], stroke * 0.70, WHITE)
    return finish(im)


CANDIDATES = [
    ('a-track', track),
    ('b-loop', loop),
    ('c-stride', stride),
    ('d-profile', profile),
    ('e-monogram', monogram),
]


def masked(im, size, radius_frac):
    im = im.resize((size, size), Image.LANCZOS).convert('RGBA')
    m = Image.new('L', (size * 4, size * 4), 0)
    dd = ImageDraw.Draw(m)
    if radius_frac >= 0.5:
        dd.ellipse((0, 0, size * 4, size * 4), fill=255)
    else:
        dd.rounded_rectangle((0, 0, size * 4, size * 4),
                             radius=int(size * 4 * radius_frac), fill=255)
    m = m.resize((size, size), Image.LANCZOS)
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    out.paste(im, (0, 0), m)
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    big, sq, small = 300, 300, 48
    pad, gap = 44, 40
    sheet_w = pad * 2 + big + gap + sq + gap + 3 * (small + 18)
    row_h = big + gap
    sheet = Image.new('RGBA', (sheet_w, pad * 2 + row_h * len(CANDIDATES)),
                      (0x0E, 0x0E, 0x0E, 255))
    for i, (key, fn) in enumerate(CANDIDATES):
        art = fn()
        art.save(os.path.join(OUT, f'icon-{key}.png'))
        y = pad + i * row_h
        a = masked(art, big, 0.5)
        sheet.paste(a, (pad, y), a)
        b = masked(art, sq, 0.26)
        sheet.paste(b, (pad + big + gap, y), b)
        for k in range(3):
            s = masked(art, small, 0.5)
            sheet.paste(s, (pad + big + gap + sq + gap + k * (small + 18),
                            y + big // 2 - small // 2), s)
    sheet.save(os.path.join(OUT, 'icon-candidates.png'))
    print('wrote', len(CANDIDATES), 'candidates and a contact sheet')


main()
