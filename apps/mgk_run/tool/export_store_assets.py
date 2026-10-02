#!/usr/bin/env python3
"""Export and check the images that go into App Store Connect and Play Console.

    python tool/export_store_assets.py            # export, then check everything
    python tool/export_store_assets.py --check    # check only, change nothing

Run from `apps/mgk_run`. Writes to `../../store-assets/derived/`.

The listing pictures themselves are not made here. `test/plates/store.dart`
draws the screens and `design/store-shots/render.sh` sets them in their frames;
this script checks what they wrote and hands it out.

**Why this exists rather than a drag from Finder.** App Store Connect refuses an
image with an alpha channel, and every plate has one, because a Flutter render
target is RGBA. The first IAP review screenshot went out of this repo at 786x1704
RGBA and would have been rejected on upload. Flattening is one line and
forgetting it is one submission.

The checks below are the ones a machine can make. Nothing here can tell you the
screenshot is of the right screen, or that the icon has square corners.

## Derived and captured are different kinds of thing

`derived/` is generated from the plate board and is **gitignored**: a committed
copy of a generated file is a copy that drifts, which is the failure this repo
has spent a lot of effort not having. Re-run this script instead.

`captured/` comes off a real device and is **committed**, because a screenshot of
a run somebody actually did cannot be regenerated, and an App Store asset that
exists on one laptop is a liability rather than an asset.
"""
from __future__ import annotations

import os
import pathlib
import shutil
import sys

try:
    from PIL import Image
except ImportError:  # pragma: no cover - the message is the whole value
    sys.exit("Pillow is needed: python -m pip install Pillow")

PLATES = pathlib.Path("plates")
ROOT = pathlib.Path("../../store-assets")
DERIVED = ROOT / "derived"
CAPTURED = ROOT / "captured"
LISTING = DERIVED / "listing"
PLAY_ICON_ART = pathlib.Path("design/store/play-listing-icon-512.png")
PLAY_ICON = "play-icon-512.png"
PLAY_FEATURE = "play-feature-graphic.png"

# The app's own near-black, so a flattened transparent edge does not show as a
# white halo against the screen it came from.
GROUND = (10, 10, 10)


class Spec:
    """What a store will accept, as far as a file can answer it."""

    def __init__(self, name, min_w=0, min_h=0, exact=None, note="",
                 alpha=False, side=None, max_ratio=None,
                 store="App Store Connect"):
        self.name = name
        self.min_w = min_w
        self.min_h = min_h
        self.exact = exact  # list of (w, h) accepted verbatim
        self.note = note
        self.alpha = alpha  # True where the store wants a 32-bit image
        self.side = side  # (shortest, longest) either side may be
        self.max_ratio = max_ratio  # long side over short side, at most
        self.store = store

    def check(self, img):
        problems = []
        if self.alpha and "A" not in img.mode:
            problems.append("has no alpha channel; %s wants a 32-bit PNG"
                            % self.store)
        if not self.alpha and "A" in img.mode:
            problems.append("has an alpha channel; %s refuses it" % self.store)
        w, h = img.size
        if self.side and not all(self.side[0] <= s <= self.side[1] for s in (w, h)):
            problems.append("is %dx%d; each side must be %d to %d px"
                            % (w, h, self.side[0], self.side[1]))
        if self.max_ratio and max(w, h) > self.max_ratio * min(w, h):
            problems.append("is %dx%d; the long side may be at most %gx the "
                            "short one" % (w, h, self.max_ratio))
        if self.exact and (w, h) not in self.exact:
            allowed = " or ".join("%dx%d" % e for e in self.exact)
            problems.append("is %dx%d; must be %s" % (w, h, allowed))
        if w < self.min_w or h < self.min_h:
            problems.append(
                "is %dx%d; minimum is %dx%d" % (w, h, self.min_w, self.min_h)
            )
        return problems


# **App Store Connect refuses arbitrary dimensions here.** The documented
# "640x920 minimum" is the old rule and no longer what the form accepts: a
# 786x1704 render, comfortably over that minimum, was rejected outright. What it
# takes is a real iPhone screenshot size, so `paywall-store` is rendered at
# 430x932 logical by 3, which is 1290x2796.
#
# Content-wise an IAP review screenshot only has to show the reviewer where the
# purchase happens, so a board plate is legitimate. The LISTING screenshots are
# a different requirement, and the board's plates are still not usable for
# them: no basemap tiles, and fixtures that show stats the app does not record.
# `test/plates/store.dart` draws those, with the map and an honest runner.
IPHONE_SCREENSHOT_SIZES = [
    (1320, 2868),  # 6.9in, iPhone 16 Pro Max
    (1290, 2796),  # 6.7in, iPhone 15/14 Pro Max
    (1284, 2778),  # 6.5in
    (1242, 2688),  # 6.5in, older
    (1179, 2556),  # 6.1in, iPhone 15/14 Pro
    (1242, 2208),  # 5.5in
]
IAP_REVIEW = Spec("IAP review screenshot", exact=IPHONE_SCREENSHOT_SIZES)
LISTING_69 = Spec(
    "6.9in listing screenshot",
    exact=[(1320, 2868), (1290, 2796)],
    note="read the required set off App Store Connect rather than trusting this",
)
MARKETING_ICON = Spec(
    "1024 marketing icon",
    exact=[(1024, 1024)],
    note="square corners and no alpha; Apple rounds it for you",
)

# Google Play's three, which are not Apple's rules with the names changed.
# A phone screenshot may be any size from 320 to 3840 px a side, but no more
# than twice as tall as it is wide, which a modern phone's own screenshot is.
# The icon is the one image either store wants WITH an alpha channel.
PLAY_PHONE = Spec(
    "Play phone screenshot", side=(320, 3840), max_ratio=2,
    store="Play Console",
)
PLAY_FEATURE_SPEC = Spec(
    "Play feature graphic", exact=[(1024, 500)], store="Play Console",
)
PLAY_ICON_SPEC = Spec(
    "Play icon", exact=[(512, 512)], alpha=True, store="Play Console",
)

# A set of listing pictures is a folder under derived/listing, and its name
# says which store it is for. How many each store takes: (fewest, most).
LISTING_SETS = {
    "ios-": (LISTING_69, (1, 10)),
    "play-": (PLAY_PHONE, (2, 8)),
}

# plate -> (output name, spec, what it is for)
DERIVED_FROM_PLATES = {
    "paywall-store.png": (
        "run-iap-review-screenshot.png",
        IAP_REVIEW,
        "Both subscriptions. Shows the purchase surface.",
    ),
}

# Anything dropped in captured/ is checked against the spec its name implies.
CAPTURED_SPECS = {
    "listing-": LISTING_69,
    "icon-": MARKETING_ICON,
}


def export():
    if not PLATES.is_dir():
        sys.exit(
            "no plates/ directory. Generate the board first:\n"
            "    flutter test test/plates/flows.dart"
        )
    DERIVED.mkdir(parents=True, exist_ok=True)
    made = []
    for plate, (out_name, _spec, _why) in DERIVED_FROM_PLATES.items():
        src = PLATES / plate
        if not src.exists():
            sys.exit(
                "missing %s. Regenerate the board:\n"
                "    flutter test test/plates/flows.dart" % src
            )
        img = Image.open(src)
        flat = Image.new("RGB", img.size, GROUND)
        flat.paste(img, mask=img.split()[3] if img.mode == "RGBA" else None)
        dst = DERIVED / out_name
        flat.save(dst, "PNG")
        made.append((dst, img.size))
    # Play's icon: the art is saved as 24-bit and Play wants 32. Nothing about
    # the picture changes.
    if PLAY_ICON_ART.exists():
        Image.open(PLAY_ICON_ART).convert("RGBA").save(DERIVED / PLAY_ICON, "PNG")
    return made


def check():
    """Every asset against its spec. Returns the number of problems."""
    problems = 0
    rows = []

    for _plate, (out_name, spec, why) in DERIVED_FROM_PLATES.items():
        path = DERIVED / out_name
        if not path.exists():
            rows.append(("MISSING", out_name, "run without --check to export it"))
            problems += 1
            continue
        found = spec.check(Image.open(path))
        problems += len(found)
        rows.append(
            ("OK" if not found else "BAD", out_name, "; ".join(found) or why)
        )

    # The listing pictures, a set at a time.
    if LISTING.is_dir():
        for folder in sorted(p for p in LISTING.iterdir() if p.is_dir()):
            found_spec = next(
                (v for k, v in LISTING_SETS.items() if folder.name.startswith(k)),
                None,
            )
            if found_spec is None:
                rows.append(("?", "listing/%s" % folder.name,
                             "no spec: name the set ios-* or play-*"))
                continue
            spec, (fewest, most) = found_spec
            pictures = sorted(folder.glob("*.png"))
            found = []
            for path in pictures:
                found += ["%s %s" % (path.name, f)
                          for f in spec.check(Image.open(path))]
            if not fewest <= len(pictures) <= most:
                found.append("has %d pictures; the store takes %d to %d"
                             % (len(pictures), fewest, most))
            problems += len(found)
            rows.append((
                "OK" if not found else "BAD",
                "listing/%s" % folder.name,
                "; ".join(found) or "%d x %s" % (len(pictures), spec.name),
            ))
    else:
        rows.append(("--", "listing/",
                     "not rendered: see design/store-shots/README.md"))

    for name, spec in ((PLAY_FEATURE, PLAY_FEATURE_SPEC), (PLAY_ICON, PLAY_ICON_SPEC)):
        path = DERIVED / name
        if not path.exists():
            rows.append(("MISSING", name, "Play will not publish without it"))
            problems += 1
            continue
        found = spec.check(Image.open(path))
        if name == PLAY_ICON and path.stat().st_size > 1024 * 1024:
            found.append("is over 1 MB")
        problems += len(found)
        rows.append(("OK" if not found else "BAD", name,
                     "; ".join(found) or spec.name))

    if CAPTURED.is_dir():
        for path in sorted(CAPTURED.iterdir()):
            if path.suffix.lower() not in (".png", ".jpg", ".jpeg"):
                continue
            spec = next(
                (s for p, s in CAPTURED_SPECS.items() if path.name.startswith(p)),
                None,
            )
            if spec is None:
                rows.append(
                    ("?", path.name,
                     "no spec: name it listing-* or icon-* to have it checked")
                )
                continue
            found = spec.check(Image.open(path))
            problems += len(found)
            rows.append(
                ("OK" if not found else "BAD", path.name,
                 "; ".join(found) or spec.name)
            )
    else:
        rows.append(("--", "captured/", "nothing off a device yet"))

    width = max(len(r[1]) for r in rows)
    for state, name, note in rows:
        print("  %-7s %-*s  %s" % (state, width, name, note))
    return problems


def handout(dest):
    """Copy the exported assets somewhere a human can reach them.

    This repository is usually worked in as a worktree, several levels down
    inside a hidden .claude directory. That is a fine home for a build output
    and a hopeless one for a file about to be dragged into a browser -- and
    uploading a stale copy found somewhere easier is a real way to lose an
    afternoon, which is exactly how this flag came to exist.
    """
    dest.mkdir(parents=True, exist_ok=True)
    singles = [n for _p, (n, _s, _w) in DERIVED_FROM_PLATES.items()]
    for out_name in singles + [PLAY_FEATURE, PLAY_ICON]:
        src = DERIVED / out_name
        if src.exists():
            shutil.copy2(src, dest / out_name)
            print("  %s" % (dest / out_name))
    # The listing sets go in a folder of their own, replaced whole: a picture
    # left over from an earlier render is the stale copy this flag exists to
    # stop anybody uploading.
    if LISTING.is_dir():
        out = dest / "run-listing"
        if out.exists():
            shutil.rmtree(out)
        shutil.copytree(LISTING, out)
        for folder in sorted(p for p in out.iterdir() if p.is_dir()):
            print("  %s  (%d pictures)" % (folder, len(list(folder.glob("*.png")))))


def main() -> int:
    check_only = "--check" in sys.argv
    if not check_only:
        print("Exporting from plates/")
        for dst, size in export():
            print("  %s  <- %dx%d, flattened onto %s" % (dst, size[0], size[1], GROUND))
        print()
    print("Checking %s" % ROOT)
    problems = check()
    if problems:
        print("\n%d problem%s. Nothing here is a judgement about whether the "
              "image is of the right screen." % (problems, "" if problems == 1 else "s"))
        return 1
    dest = None
    if "--downloads" in sys.argv:
        dest = pathlib.Path(os.path.expanduser("~/Downloads"))
    elif "--to" in sys.argv:
        i = sys.argv.index("--to")
        if i + 1 >= len(sys.argv):
            sys.exit("--to needs a directory")
        dest = pathlib.Path(sys.argv[i + 1])
    if dest is not None:
        print("\nCopied to")
        handout(dest)

    print("\nEvery asset fits its spec. Whether each is the RIGHT picture is "
          "still yours to say.")
    return 0


if __name__ == "__main__":
    if not os.path.isdir("tool"):
        sys.exit("run this from apps/mgk_run")
    sys.exit(main())
