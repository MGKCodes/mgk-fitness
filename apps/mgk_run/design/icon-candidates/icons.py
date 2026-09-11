"""Five candidate launcher marks for MGKFitness: Run.

Constraints, all of them real rather than taste:

  * **Greyscale.** ADR-0009 reserves colour for status. Charcoal #1A1A1A
    ground, silver #C0C0C0 mark, white #FFFFFF for the one accent element.
  * **The 66dp safe circle.** An Android adaptive icon is a 108dp canvas of
    which only the central 66dp is guaranteed to survive the launcher's mask,
    and the mask differs per device. So every mark here is drawn inside 61% of
    the canvas width, centred — which is why they look smaller than the iOS
    art, and why the iOS art could not simply be pasted across.
  * **Legible at 48dp.** Each is rendered at 48px as well as large. A stroke
    thinner than about 7% of the canvas turns to mush at that size.

Drawn at 8x and downsampled, because Pillow has no anti-aliasing of its own.
"""

from PIL import Image, ImageDraw
import math
import os
import sys

OUT = sys.argv[1] if len(sys.argv) > 1 else '.'

S = 8                      # supersample
N = 1024                   # final canvas
C = N * S                  # working canvas
BG = (0x1A, 0x1A, 0x1A, 255)
SILVER = (0xC0, 0xC0, 0xC0, 255)
WHITE = (0xFF, 0xFF, 0xFF, 255)

SAFE = 0.61                # fraction of the canvas the mark may occupy


def canvas():
    im = Image.new('RGBA', (C, C), BG)
    return im, ImageDraw.Draw(im)


def finish(im):
    return im.resize((N, N), Image.LANCZOS)


def arc(d, cx, cy, r, a0, a1, width, fill):
    box = (cx - r, cy - r, cx + r, cy + r)
    d.arc(box, a0, a1, fill=fill, width=width)


def dot(d, cx, cy, r, fill):
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill)


# ── A · The track ───────────────────────────────────────────────────────────
# A stadium — the shape of an athletics track, seen from above. The most
# literal of the five and the only one that is a *place* rather than a symbol.
def track():
    im, d = canvas()
    w = int(C * SAFE)
    h = int(w * 0.66)
    x0, y0 = (C - w) // 2, (C - h) // 2
    stroke = int(C * 0.085)
    r = h // 2
    # Two straights and two bends, drawn as one outline.
    d.rounded_rectangle((x0, y0, x0 + w, y0 + h), radius=r,
                        outline=SILVER, width=stroke)
    # The runner, on the near straight.
    dot(d, x0 + int(w * 0.62), y0 + h, int(stroke * 0.95), WHITE)
    return finish(im)


# ── B · The open loop ───────────────────────────────────────────────────────
# The existing iOS mark, rebuilt: a route that does not quite close, with the
# runner on it. Geometric where the original was hand-drawn, because a wobble
# that reads as character at 1024 reads as a mistake at 48.
def loop():
    im, d = canvas()
    r = int(C * SAFE / 2)
    cx = cy = C // 2
    stroke = int(C * 0.095)
    # Open at the lower right, running anticlockwise — the gap is what stops
    # it reading as a plain ring.
    arc(d, cx, cy, r, 30, 340, stroke, SILVER)
    a = math.radians(30)
    dot(d, cx + r * math.cos(a), cy + r * math.sin(a), int(stroke * 0.95), WHITE)
    return finish(im)


# ── C · The stride ──────────────────────────────────────────────────────────
# Three forward chevrons at a runner's lean. No figure, no track: just the
# direction and the cadence. The most abstract, and the most legible small.
def stride():
    im, d = canvas()
    w = int(C * SAFE)
    x0 = (C - w) // 2
    stroke = int(C * 0.085)
    lean = 0.30                    # forward lean, as a fraction of height
    h = int(w * 0.62)
    y0 = (C - h) // 2
    for i, (frac, colour) in enumerate(
        ((0.62, SILVER), (0.82, SILVER), (1.0, WHITE))
    ):
        ch = int(h * frac)
        top = y0 + (h - ch) // 2
        x = x0 + int(w * 0.14) * i + int(w * 0.16)
        d.line(
            [(x, top), (x + int(ch * lean) + int(w * 0.16), top + ch // 2),
             (x, top + ch)],
            fill=colour, width=stroke, joint='curve',
        )
    return finish(im)


# ── D · The profile ─────────────────────────────────────────────────────────
# An elevation trace — the shape of the hill you ran, which is the thing a
# runner actually looks at afterwards. Data rather than iconography.
def profile():
    im, d = canvas()
    w = int(C * SAFE)
    x0 = (C - w) // 2
    h = int(w * 0.60)
    y0 = (C - h) // 2
    stroke = int(C * 0.085)
    pts = [(0.00, 0.82), (0.20, 0.55), (0.37, 0.70),
           (0.58, 0.20), (0.78, 0.48), (1.00, 0.30)]
    line = [(x0 + px * w, y0 + py * h) for px, py in pts]
    d.line(line, fill=SILVER, width=stroke, joint='curve')
    # Where you are on it.
    dot(d, line[-1][0], line[-1][1], int(stroke * 0.95), WHITE)
    return finish(im)


# ── E · The monogram ────────────────────────────────────────────────────────
# An R whose leg runs off as a path. The only candidate that scales to a
# family — L for Lift, E for Eat — which is worth something for a suite.
def monogram():
    im, d = canvas()
    w = int(C * SAFE)
    h = w
    x0, y0 = (C - w) // 2, (C - h) // 2
    stroke = int(C * 0.10)
    # Stem.
    d.line([(x0 + stroke // 2, y0), (x0 + stroke // 2, y0 + h)],
           fill=SILVER, width=stroke)
    # Bowl.
    bowl_h = int(h * 0.52)
    d.arc((x0 + stroke // 2 - bowl_h // 2, y0,
           x0 + stroke // 2 + bowl_h // 2 + int(w * 0.30), y0 + bowl_h),
          -90, 90, fill=SILVER, width=stroke)
    d.line([(x0 + stroke // 2, y0), (x0 + int(w * 0.42), y0)],
           fill=SILVER, width=stroke)
    d.line([(x0 + stroke // 2, y0 + bowl_h),
            (x0 + int(w * 0.42), y0 + bowl_h)], fill=SILVER, width=stroke)
    # The leg, extended into a stride.
    d.line([(x0 + int(w * 0.34), y0 + bowl_h), (x0 + w, y0 + h)],
           fill=SILVER, width=stroke, joint='curve')
    dot(d, x0 + w, y0 + h, int(stroke * 0.90), WHITE)
    return finish(im)


CANDIDATES = [
    ('a-track', 'The track', track),
    ('b-loop', 'The open loop', loop),
    ('c-stride', 'The stride', stride),
    ('d-profile', 'The profile', profile),
    ('e-monogram', 'The monogram', monogram),
]


def circle_mask(im, size):
    """What a round-mask launcher actually shows."""
    im = im.resize((size, size), Image.LANCZOS).convert('RGBA')
    mask = Image.new('L', (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size * 4, size * 4), fill=255)
    mask = mask.resize((size, size), Image.LANCZOS)
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    out.paste(im, (0, 0), mask)
    return out


def squircle_mask(im, size):
    im = im.resize((size, size), Image.LANCZOS).convert('RGBA')
    mask = Image.new('L', (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size * 4, size * 4), radius=int(size * 4 * 0.26), fill=255)
    mask = mask.resize((size, size), Image.LANCZOS)
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    out.paste(im, (0, 0), mask)
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    big, small, sq = 300, 48, 300
    pad, gap, label_h = 40, 36, 0
    sheet_w = pad * 2 + big + gap + sq + gap + 160
    row_h = big + gap
    sheet = Image.new('RGBA', (sheet_w, pad * 2 + row_h * len(CANDIDATES)),
                      (0x0E, 0x0E, 0x0E, 255))

    for i, (key, _name, fn) in enumerate(CANDIDATES):
        art = fn()
        art.save(os.path.join(OUT, f'icon-{key}.png'))
        y = pad + i * row_h
        sheet.paste(circle_mask(art, big), (pad, y), circle_mask(art, big))
        sheet.paste(squircle_mask(art, sq), (pad + big + gap, y),
                    squircle_mask(art, sq))
        # Actual launcher size, three times over so it can be judged.
        for k in range(3):
            s = circle_mask(art, small)
            sheet.paste(s, (pad + big + gap + sq + gap + k * (small + 16),
                            y + big // 2 - small // 2), s)

    sheet.save(os.path.join(OUT, 'icon-candidates.png'))
    print('wrote', len(CANDIDATES), 'candidates and a contact sheet to', OUT)


main()
