"""V2 on a gradient ground — eight variations on T6.

T6 was a soft wedge thrown from the corner the mark is heading toward. This
takes that apart: where the light comes from, how hard its edge is, how far it
travels, and whether it is a wedge at all or a sweep.

**Restructured from icons5.** That script drew everything at 8192px and blurred
there, which is minutes of work for a gradient that has no edges to alias. Here
the ground is built at 1024 where it belongs and the mark is drawn at 8192 and
downsampled onto it. Same result, and it renders in seconds.

Held constant, as before: V2's two chevrons unchanged and untouched, greyscale
per ADR-0009, the mark inside the 66dp safe circle, the ground filling the full
108dp because the background layer is meant to be cropped by the mask.

The ground is charcoal #1A1A1A lifted toward #3A3A3A and no further. Anything
brighter starts competing with the silver chevron, which is the only thing on
the tile that is allowed to be the second-lightest element.
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

DARK, LIGHT = 0x1A, 0x3A


def tone(mix):
    v = int(DARK + (LIGHT - DARK) * max(0.0, min(1.0, mix)))
    return (v, v, v, 255)


# ── The mark, drawn big and brought down ────────────────────────────────────
def mark_layer(up):
    im = Image.new('RGBA', (C, C), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    w = C * SAFE
    cx = cy = C / 2
    stroke = C * 0.090
    half, lean, gap, rise = w * 0.215, w * 0.200, w * 0.360, w * 0.215

    def path(pts, colour):
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            d.line([(x0, y0), (x1, y1)], fill=colour, width=int(stroke))
        for x, y in pts:
            d.ellipse((x - stroke / 2, y - stroke / 2,
                       x + stroke / 2, y + stroke / 2), fill=colour)

    for i, colour in enumerate((SILVER, WHITE)):
        if up:
            x, y = cx - half, cy + gap / 2 - i * gap
            path([(x, y), (x + half, y - lean), (x + half * 2, y)], colour)
        else:
            x = cx - gap / 2 - lean / 2 + i * gap
            y = cy + rise / 2 - i * rise
            path([(x, y - half), (x + lean, y), (x, y + half)], colour)
    return im.resize((N, N), Image.LANCZOS)



# ── Dithering ───────────────────────────────────────────────────────────────
# #1A1A1A to #3A3A3A is 32 steps of 8-bit grey stretched over 1024px, so a
# naive gradient bands: measured at 20 distinct levels with flat runs up to
# 56px wide. Visible on a 1024px store tile, and exactly the kind of thing that
# looks like a compression artefact rather than a choice.
#
# An 8x8 ordered (Bayer) threshold fixes it: the ideal value is computed in
# float and the fractional part decides, per pixel, whether to round up. The
# error becomes a fine stipple instead of a stripe. No noise is added where the
# gradient is already flat, because there the fraction is constant.
BAYER8 = [
    [0, 32, 8, 40, 2, 34, 10, 42], [48, 16, 56, 24, 50, 18, 58, 26],
    [12, 44, 4, 36, 14, 46, 6, 38], [60, 28, 52, 20, 62, 30, 54, 22],
    [3, 35, 11, 43, 1, 33, 9, 41], [51, 19, 59, 27, 49, 17, 57, 25],
    [15, 47, 7, 39, 13, 45, 5, 37], [63, 31, 55, 23, 61, 29, 53, 21],
]


def dithered(value_at):
    """An N x N ground from `value_at(x, y) -> mix in 0..1`, ordered-dithered."""
    px = bytearray(N * N)
    span = LIGHT - DARK
    for y in range(N):
        row = y * N
        brow = BAYER8[y & 7]
        for x in range(N):
            v = DARK + span * value_at(x, y)
            base = int(v)
            frac = v - base
            px[row + x] = base + (1 if frac * 64 > brow[x & 7] else 0)
    g = Image.frombytes('L', (N, N), bytes(px))
    return g.convert('RGBA')


def sweep_d(angle_deg, a=0.0, b=1.0, ease=1.0):
    """`sweep`, computed in float and dithered."""
    rad = math.radians(angle_deg)
    dx, dy = math.cos(rad), math.sin(rad)
    # Project onto the heading and normalise over the tile's diagonal extent.
    lo = min(0 * dx + 0 * dy, N * dx + 0 * dy, 0 * dx + N * dy, N * dx + N * dy)
    hi = max(0 * dx + 0 * dy, N * dx + 0 * dy, 0 * dx + N * dy, N * dx + N * dy)
    rng = hi - lo or 1.0

    def at(x, y):
        t = ((x * dx + y * dy) - lo) / rng
        return a + (b - a) * (t ** ease)

    return dithered(at)


def radial_d(cx_f, cy_f, reach, peak=1.0, ease=1.8):
    """`radial`, computed in float and dithered."""
    cx, cy = N * cx_f, N * cy_f
    r = N * reach

    def at(x, y):
        d = math.hypot(x - cx, y - cy) / r
        return peak * max(0.0, 1.0 - min(1.0, d)) ** ease

    return dithered(at)


# ── Grounds ─────────────────────────────────────────────────────────────────
def sweep(angle_deg, a=0.0, b=1.0, ease=1.0):
    """A linear gradient across the tile at `angle_deg`, eased."""
    steps = 512
    strip = Image.new('RGBA', (steps, 1))
    px = strip.load()
    for i in range(steps):
        t = (i / (steps - 1)) ** ease
        px[i, 0] = tone(a + (b - a) * t)
    # Oversized so rotation cannot expose a corner.
    big = int(N * 1.5)
    g = strip.resize((big, big), Image.BILINEAR)
    g = g.rotate(-angle_deg, resample=Image.BICUBIC, expand=False)
    off = (big - N) // 2
    return g.crop((off, off, off + N, off + N))


def wedge(angle_deg, spread_deg, reach, blur, peak=1.0):
    """A cone of light thrown from the centre toward `angle_deg`."""
    g = Image.new('RGBA', (N, N), tone(0.0))
    d = ImageDraw.Draw(g)
    cx = cy = N / 2
    r = N * reach
    a0 = math.radians(angle_deg - spread_deg / 2)
    a1 = math.radians(angle_deg + spread_deg / 2)
    d.polygon([(cx, cy),
               (cx + r * math.cos(a0), cy + r * math.sin(a0)),
               (cx + r * math.cos(a1), cy + r * math.sin(a1))],
              fill=tone(peak))
    return g.filter(ImageFilter.GaussianBlur(N * blur))


def radial(cx_f, cy_f, reach, peak=1.0, ease=1.8):
    """A glow centred wherever you like, including off the tile."""
    g = Image.new('RGBA', (N, N), tone(0.0))
    d = ImageDraw.Draw(g)
    cx, cy = N * cx_f, N * cy_f
    steps = 120
    for i in range(steps, 0, -1):
        r = N * reach * i / steps
        d.ellipse((cx - r, cy - r, cx + r, cy + r),
                  fill=tone(peak * (1 - i / steps) ** ease))
    return g


# Run travels right and climbs, so its light comes from up-and-right at -25°.
# Lift climbs, so its light comes from straight up at -90°. Every ground below
# is written once and rotated by that one number.
def heading(up):
    return -90.0 if up else -25.0


GROUNDS = [
    ('g1-wedge-soft', 'Wedge, soft', 'T6 as it was: a broad cone thrown toward '
     'the heading, edge blurred away to nothing. The baseline.',
     lambda up: wedge(heading(up), 90, 0.95, 0.06, 0.62)),
    ('g2-wedge-tight', 'Wedge, tight', 'The same cone narrowed to 46° and '
     'brightened. Reads as a beam rather than a wash — the most directional '
     'of the eight.',
     lambda up: wedge(heading(up), 46, 1.05, 0.045, 0.85)),
    ('g3-wedge-wide', 'Wedge, wide', 'Opened to 150° and softened further. '
     'Nearly a half-tile wash; the wedge stops being a shape.',
     lambda up: wedge(heading(up), 150, 1.0, 0.09, 0.52)),
    ('g4-sweep', 'Sweep', 'No wedge at all — a straight linear gradient across '
     'the whole tile on the heading. The most even, and the one that survives '
     'any mask identically.',
     lambda up: sweep_d(heading(up), 0.0, 0.58)),
    ('g5-sweep-eased', 'Sweep, eased', 'The same sweep with the light held '
     'back until the last third, so the corner lifts and the rest stays flat.',
     lambda up: sweep_d(heading(up), 0.0, 0.72, ease=2.6)),
    ('g6-corner-glow', 'Corner glow', 'A radial centred off the tile in the '
     'direction of travel. Light with a source rather than a direction.',
     lambda up: radial_d(0.5 + 0.42 * math.cos(math.radians(heading(up))),
                         0.5 + 0.42 * math.sin(math.radians(heading(up))),
                         1.05, 0.80)),
    ('g7-behind', 'From behind', 'The light thrown from where the mark has '
     'come FROM, so the chevrons move out of the light into the dark. The '
     'opposite reading, and worth seeing before it is dismissed.',
     lambda up: wedge(heading(up) + 180, 80, 1.0, 0.06, 0.66)),
    ('g8-sweep-deep', 'Sweep, deep', 'The sweep pushed to the limit of the '
     'palette — #1A1A1A to #3A3A3A end to end. As far as this can go before '
     'the ground starts arguing with the silver chevron.',
     lambda up: sweep_d(heading(up), 0.0, 1.0)),
]


def render(fn, up):
    g = fn(up).convert('RGBA')
    g.alpha_composite(mark_layer(up))
    return g


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
    for key, _label, _note, fn in GROUNDS:
        run, lift = render(fn, False), render(fn, True)
        run.save(os.path.join(OUT, f'run-{key}.png'))
        lift.save(os.path.join(OUT, f'lift-{key}.png'))
        rows.append((key, run, lift))
        print('  ', key)

    big, small = 230, 48
    pad, gap = 36, 26
    width = pad * 2 + 2 * (big + gap) + 2 * (small + 14)
    sheet = Image.new('RGBA', (width, pad * 2 + len(rows) * (big + gap)),
                      (0x0E, 0x0E, 0x0E, 255))
    for i, (key, run, lift) in enumerate(rows):
        y = pad + i * (big + gap)
        a = masked(run, big)
        sheet.paste(a, (pad, y), a)
        b = masked(lift, big, circle=False)
        sheet.paste(b, (pad + big + gap, y), b)
        for k, art in enumerate((run, lift)):
            s = masked(art, small)
            sheet.paste(s, (pad + 2 * (big + gap) + k * (small + 14),
                            y + big // 2 - small // 2), s)
    sheet.save(os.path.join(OUT, 'v2-grounds.png'))

    # The view that actually decides it: store size, side by side.
    size, pad2, gap2 = 300, 30, 22
    big_sheet = Image.new(
        'RGBA', (pad2 * 2 + len(rows) * (size + gap2) - gap2, pad2 * 2 + size),
        (0x0E, 0x0E, 0x0E, 255))
    for i, (key, run, _l) in enumerate(rows):
        a = masked(run, size)
        big_sheet.paste(a, (pad2 + i * (size + gap2), pad2), a)
    big_sheet.save(os.path.join(OUT, 'v2-grounds-large.png'))
    print('wrote', len(rows), 'grounds')


main()
