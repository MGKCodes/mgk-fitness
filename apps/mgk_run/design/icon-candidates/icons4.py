"""H1 refinements — spacing, count, and how far apart Run and Lift should sit.

"Too close to each other" reads two ways and both are worth answering:

  * **Within a mark** — three chevrons at a 2.05x stroke gap crowd each other,
    and the arms nearly touch on the diagonal. Variants 1-4 open that up.
  * **Between the two apps** — Run and Lift are both "three chevrons", one
    rotated. Variant 5 pulls them apart: the count and the rhythm differ, and
    only the language stays shared.

Everything else is held: greyscale (ADR-0009), inside the 66dp safe circle,
white marks the live end, Run ascends rightward and Lift upward.

The trade-off to watch is that air has to come from somewhere. Wider gaps
inside a fixed safe circle mean smaller chevrons, which is what costs
legibility at 48px — so each variant is shown there.
"""

from PIL import Image, ImageDraw
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


def disc(d, cx, cy, r, fill):
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill)


def path(d, pts, width, fill):
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        d.line([(x0, y0), (x1, y1)], fill=fill, width=int(width))
    for x, y in pts:
        disc(d, x, y, width / 2, fill)


def chevrons(up, count, stroke_f, half_f, lean_f, gap_f, rise_f, colours):
    """One mark. `rise_f` is how far each chevron climbs above the last."""
    im, d = canvas()
    w = C * SAFE
    cx = cy = C / 2
    stroke = C * stroke_f
    half = w * half_f
    lean = w * lean_f
    gap = w * gap_f
    rise = w * rise_f
    span = gap * (count - 1)
    for i in range(count):
        colour = colours[i]
        if up:
            # Lift: stacked, climbing in place.
            x = cx - half
            y = cy + span / 2 - i * gap
            pts = [(x, y), (x + half, y - lean), (x + half * 2, y)]
        else:
            # Run: travelling right and climbing as it goes.
            x = cx - span / 2 - lean / 2 + i * gap
            y = cy + (span * rise_f / gap_f) / 2 - i * rise
            pts = [(x, y - half), (x + lean, y), (x, y + half)]
        path(d, pts, stroke, colour)
    return im.resize((N, N), Image.LANCZOS)


T3 = (DIM, SILVER, WHITE)
T2 = (SILVER, WHITE)

VARIANTS = [
    ('v1-wide', 'Wider', 'The same three, opened up — gap raised from 2.0x '
     'stroke to 3.1x. Chevrons shrink to pay for it.',
     dict(count=3, stroke_f=0.072, half_f=0.165, lean_f=0.155,
          gap_f=0.255, rise_f=0.150, colours=T3)),
    ('v2-two', 'Two', 'Drop to two. The most air of any variant and the '
     'cleanest at 48px; loses the sense of a rhythm.',
     dict(count=2, stroke_f=0.090, half_f=0.215, lean_f=0.200,
          gap_f=0.360, rise_f=0.215, colours=T2)),
    ('v3-steep', 'Steeper', 'Three, wide, and climbing harder — the rise per '
     'step nearly doubled so Run reads as one diagonal gesture rather than '
     'three arrows in a row.',
     dict(count=3, stroke_f=0.072, half_f=0.155, lean_f=0.150,
          gap_f=0.235, rise_f=0.225, colours=T3)),
    ('v4-airy', 'Airy', 'Three, thinner stroke, widest gaps. The test of how '
     'far this can be pushed before 48px gives out.',
     dict(count=3, stroke_f=0.060, half_f=0.150, lean_f=0.140,
          gap_f=0.280, rise_f=0.165, colours=T3)),
]


def v5(up):
    """Run and Lift pulled apart: different counts, same language.

    Three chevrons for Run because a run is a sequence of steps; two for Lift
    because a lift is one effort repeated, not a journey. Shared palette,
    shared white tip, shared ascent — different rhythm.
    """
    if up:
        return chevrons(True, 2, 0.098, 0.225, 0.215, 0.380, 0.215, T2)
    return chevrons(False, 3, 0.072, 0.155, 0.150, 0.235, 0.225, T3)


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
    for key, _label, _note, kw in VARIANTS:
        rows.append((key, chevrons(False, **kw), chevrons(True, **kw)))
    rows.append(('v5-apart', v5(False), v5(True)))

    for key, run, lift in rows:
        run.save(os.path.join(OUT, f'run-{key}.png'))
        lift.save(os.path.join(OUT, f'lift-{key}.png'))

    big, small = 240, 48
    pad, gap = 40, 32
    width = pad * 2 + 2 * (big + gap) + 3 * (small + 16)
    sheet = Image.new('RGBA', (width, pad * 2 + len(rows) * (big + gap)),
                      (0x0E, 0x0E, 0x0E, 255))
    for i, (key, run, lift) in enumerate(rows):
        y = pad + i * (big + gap)
        a = masked(run, big)
        sheet.paste(a, (pad, y), a)
        b = masked(lift, big)
        sheet.paste(b, (pad + big + gap, y), b)
        for k, art in enumerate((run, lift, run)):
            s = masked(art, small)
            sheet.paste(s, (pad + 2 * (big + gap) + k * (small + 16),
                            y + big // 2 - small // 2), s)
    sheet.save(os.path.join(OUT, 'h1-variants.png'))
    print('wrote', len(rows), 'variants')


main()
