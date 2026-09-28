#!/usr/bin/env python3
"""Export and check the images that go into App Store Connect.

    python tool/export_store_assets.py            # export, then check everything
    python tool/export_store_assets.py --check    # check only, change nothing

Run from `apps/mgk_run`. Writes to `../../store-assets/derived/`.

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

# The app's own near-black, so a flattened transparent edge does not show as a
# white halo against the screen it came from.
GROUND = (10, 10, 10)


class Spec:
    """What Apple will accept, as far as a file can answer it."""

    def __init__(self, name, min_w=0, min_h=0, exact=None, note=""):
        self.name = name
        self.min_w = min_w
        self.min_h = min_h
        self.exact = exact  # list of (w, h) accepted verbatim
        self.note = note

    def check(self, img):
        problems = []
        if "A" in img.mode:
            problems.append("has an alpha channel; App Store Connect refuses it")
        w, h = img.size
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
# purchase happens, so a plate is legitimate. The LISTING screenshots are a
# different requirement and plates are not usable for them: no basemap tiles.
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
    for _plate, (out_name, _spec, _why) in DERIVED_FROM_PLATES.items():
        src = DERIVED / out_name
        if src.exists():
            shutil.copy2(src, dest / out_name)
            print("  %s" % (dest / out_name))


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
