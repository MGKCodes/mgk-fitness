"""Draws the suite's own mark and writes the website's icons from it.

Run:  python tool/icon.py     (from `web/`; `npm run icon` does the same)

## What the mark is

Run's mark heads right and Lift's heads up. MGKFitness is the two together, so
its mark heads between them: the same two chevrons, the leading one white, on
the diagonal. It is the third of one family; `tool/build_app_icons.py`, at the
repository's root, describes the other two.

Its arms are squared, where the apps' open a little wider, so that at the size
of a browser tab every edge lies on a pixel. On a grid of sixteen the stroke is
two, each arm is four long, and the trailing chevron sits four back and four
down.

**It is provisional, and it bends the family's rule twice.** The rule is one
mark and one rotation, an app to an axis, with the third axis kept for a third
app. This mark is for the suite and not for an app, it squares the arms and so
is not a rotation of the apps' mark, and it takes the diagonal. It was drawn
on 2 October 2026 so that the site had an icon at all. If a third app wants
that heading, or the rule is to hold, redraw it here: everything below is
written from this file's numbers.

## Why it is here and not beside the apps' marks

The apps' icons are part of the apps, which are AGPL. This mark is used by the
website and by the suite's accounts elsewhere, so it is a brand asset, and
those are `web/`'s: see `../NOTICE.md`. The ground is still the family's own
sweep, imported and not copied, so the three cannot drift apart in how they
are lit.

## What it writes

  * `app/favicon.ico`      16, 32 and 48, for a tab. A rounded tile, the mark
                           large in it.
  * `app/icon.svg`         the same drawing as a vector, for anything that
                           takes one.
  * `app/apple-icon.png`   180, for an iPhone's home screen. Square, because
                           iOS rounds it, and at the apps' icons' proportions,
                           because it sits beside them there.
  * `design/brand/mgkfitness-1024.png`   for an account's picture. Square too:
                           those are cropped to a circle, which the mark sits
                           well inside.

Next.js serves the first three by their names. All four are committed, like
the film's stills: Vercel builds from the repository and does not run Python.
`app/(landing)/mark.tsx` draws the same mark beside the suite's name, from
these numbers.
"""

from PIL import Image, ImageDraw
import math
import os
import sys

WEB = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(WEB), 'tool'))
# Importing the family would otherwise leave a `__pycache__` beside it, in a
# folder this script has no business writing to.
sys.dont_write_bytecode = True
import build_app_icons as family  # noqa: E402

# Between Run's heading and Lift's. The family's sweep is keyed by name, so the
# suite's heading is added to it here, in memory; its own file is not touched.
HEADING = -45.0
family.HEADING['suite'] = HEADING
TOP = 0.58                  # how far the ground lifts toward LIGHT, as the apps' does

GRID = 16                   # a tab icon's size, and the grid the mark is drawn on
STROKE = 2                  # in that grid's units
CORNER = 3.5                # the tile's rounding, likewise
# Each chevron as three points on the grid, measured from the tile's centre:
# along one arm to its point, then down the other. The trailing chevron first.
CHEVRONS = (
    (family.SILVER, ((-4, 0), (0, 0), (0, 4))),
    (family.WHITE, ((0, -4), (4, -4), (4, 0))),
)
# One unit of the grid as a share of the tile: large for a tab, and at the
# apps' icons' own proportions, a stroke of 9%, anywhere it sits beside them.
TAB = 1 / GRID
ICON = 0.090 / STROKE


def mark(size, unit):
    """The two chevrons on transparent, drawn big and brought down.

    Every part is a rectangle or a circle placed on whole pixels, and the
    reduction is an area average, so an edge that lies on a pixel boundary at
    the final size stays an edge and not a blur.
    """
    c = size * family.SS
    u = unit * c
    r = u * STROKE / 2
    im = Image.new('RGBA', (c, c), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    def fill(shape, x0, y0, x1, y1, colour):
        shape((round(x0), round(y0), round(x1) - 1, round(y1) - 1), fill=colour)

    for colour, points in CHEVRONS:
        pts = [(c / 2 + x * u, c / 2 + y * u) for x, y in points]
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            across = y0 == y1
            fill(d.rectangle,
                 min(x0, x1) - (0 if across else r), min(y0, y1) - (r if across else 0),
                 max(x0, x1) + (0 if across else r), max(y0, y1) + (r if across else 0),
                 colour)
        for x, y in pts:
            fill(d.ellipse, x - r, y - r, x + r, y + r, colour)
    return im.resize((size, size), Image.BOX)


def tile(size, unit, rounded=False):
    """The family's ground, lit from the suite's heading, with the mark on it."""
    im = family.sweep('suite', size, top=TOP)
    im.alpha_composite(mark(size, unit))
    if rounded:
        c = size * family.SS
        mask = Image.new('L', (c, c), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            (0, 0, c - 1, c - 1), radius=c * CORNER / GRID, fill=255)
        im.putalpha(mask.resize((size, size), Image.BOX))
    return im


def svg():
    """The tab icon as a vector: the same numbers, written out."""
    half = GRID / 2
    angle = math.radians(HEADING)
    dx, dy = math.cos(angle), math.sin(angle)
    # The ramp runs between the two corners furthest apart along the heading,
    # which is how `sweep` measures it.
    reach = max(abs(x * dx + y * dy) for x in (-half, half) for y in (-half, half))
    ends = [round(half + sign * reach * d, 3) + 0.0 for sign in (-1, 1) for d in (dx, dy)]
    light = round(family.DARK + (family.LIGHT - family.DARK) * TOP)

    def grey(v):
        return '#' + f'{v:02x}' * 3

    def colour(rgba):
        return '#' + ''.join(f'{v:02x}' for v in rgba[:3])

    paths = '\n'.join(
        '    <path stroke="{}" d="M{}"/>'.format(
            colour(rgba), ' L'.join(f'{half + x:g} {half + y:g}' for x, y in points))
        for rgba, points in CHEVRONS)
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {GRID} {GRID}">
  <!-- GENERATED by tool/icon.py. Do not edit; edit the generator. -->
  <linearGradient id="sweep" gradientUnits="userSpaceOnUse" x1="{ends[0]:g}" y1="{ends[1]:g}" x2="{ends[2]:g}" y2="{ends[3]:g}">
    <stop stop-color="{grey(family.DARK)}"/>
    <stop offset="1" stop-color="{grey(light)}"/>
  </linearGradient>
  <rect width="{GRID}" height="{GRID}" rx="{CORNER:g}" fill="url(#sweep)"/>
  <g fill="none" stroke-width="{STROKE}" stroke-linecap="round" stroke-linejoin="round">
{paths}
  </g>
</svg>
'''


def main():
    written = []

    tabs = [tile(size, TAB, rounded=True) for size in (48, 32, 16)]
    path = os.path.join(WEB, 'app', 'favicon.ico')
    tabs[0].save(path, format='ICO', sizes=[im.size for im in tabs], append_images=tabs[1:])
    written.append(path)

    path = os.path.join(WEB, 'app', 'icon.svg')
    with open(path, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(svg())
    written.append(path)

    written.append(family.write(
        tile(180, ICON), os.path.join(WEB, 'app', 'apple-icon.png'), opaque=True))
    written.append(family.write(
        tile(1024, ICON), os.path.join(WEB, 'design', 'brand', 'mgkfitness-1024.png'),
        opaque=True))

    for path in written:
        print(os.path.relpath(path, WEB).replace(os.sep, '/'))


if __name__ == '__main__':
    main()
