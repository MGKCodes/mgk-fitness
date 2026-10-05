#!/usr/bin/env python3
"""Run and Lift on the App Store and Google Play, from the terminal.

    python scripts/store/stores.py status      <run|lift> [--ios|--android]
    python scripts/store/stores.py submit      <run|lift> --ios --build 52 [--notes FILE] [--yes]
    python scripts/store/stores.py submit      <run|lift> --android [--notes FILE] [--draft] [--yes]
    python scripts/store/stores.py release     <run|lift> [--yes]
    python scripts/store/stores.py test-notes  <run|lift> --notes FILE [--ios --build 52 | --android] [--yes]
    python scripts/store/stores.py testers     <run|lift> [--ios|--android]
    python scripts/store/stores.py add-tester  <run|lift> --email ADDRESS --group NAME [--yes]
    python scripts/store/stores.py listing     <run|lift> [--ios|--android] [--from FILE] [--yes]
    python scripts/store/stores.py screenshots <run|lift> [--ios|--android] [--yes]

**Nothing changes without --yes.** Without it every command prints what it
would do and stops, so a plan can be read before a store is touched.

Releases are automatic once a store approves them (Matthew, 5 October 2026):
an iOS version is submitted to release itself on approval, and an Android
release goes to production at 100%, live as soon as Google approves it.
`release` is for a version that was submitted to be held instead.

Like scripts/codemagic-build.sh, this exists so that "Claude may release Run
and Lift" can be granted as one permission without also granting "Claude may
call the stores with a key": the apps are fixed in _common.APPS, and the keys
stay outside the repository (README.md).
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from _common import APPS, StoreError  # noqa: E402

REPO = Path(__file__).resolve().parents[2]

# What each app's store pictures are drawn into (apps/<app>/design/store-shots
# renders them; the folders are not in git).
SHOTS = {
    'run': REPO / 'apps/mgk_run/screenshots/store/listing',
    'lift': REPO / 'apps/mgk_lift/screenshots/store/listing',
}
FEATURE = {
    'run': REPO / 'apps/mgk_run/screenshots/store/play-feature-graphic.png',
    'lift': REPO / 'apps/mgk_lift/screenshots/store/play-feature-graphic.png',
}


def _platforms(args) -> tuple[bool, bool]:
    """Both stores unless one is named."""
    if not args.ios and not args.android:
        return True, True
    return args.ios, args.android


def _text(path: str | None) -> str | None:
    return Path(path).read_text(encoding='utf-8').strip() if path else None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog='stores.py', description=__doc__.split('\n\n')[0])
    parser.add_argument('command', choices=[
        'status', 'submit', 'release', 'test-notes', 'testers', 'add-tester',
        'listing', 'screenshots',
    ])
    parser.add_argument('app', choices=sorted(APPS))
    parser.add_argument('--ios', action='store_true')
    parser.add_argument('--android', action='store_true')
    parser.add_argument('--build', help='the iOS build number, as TestFlight shows it')
    parser.add_argument('--notes', help="a text file: What's New, or what to test")
    parser.add_argument('--draft', action='store_true',
                        help='Android: send to production as a draft, for an app never rolled out')
    parser.add_argument('--email')
    parser.add_argument('--group')
    parser.add_argument('--from', dest='source', help='the listing file (default apps/<app>/store/listing.json)')
    parser.add_argument('--yes', action='store_true', help='do it, rather than show the plan')
    args = parser.parse_args(argv)
    ios, android = _platforms(args)

    out: list[str] = []
    try:
        if args.command == 'status':
            if ios:
                from asc import AppStore
                out += AppStore(args.app).status()
            if android:
                from play import Play
                out += Play(args.app).status()

        elif args.command == 'submit':
            if ios == android:
                parser.error('submit one store at a time: --ios or --android')
            notes = _text(args.notes)
            if ios:
                if not args.build:
                    parser.error('--ios needs --build, the TestFlight build number')
                from asc import AppStore
                out += AppStore(args.app).submit(args.build, notes, args.yes)
            else:
                from play import Play
                out += Play(args.app).submit(notes, args.draft, args.yes)

        elif args.command == 'release':
            from asc import AppStore
            out += AppStore(args.app).release(args.yes)

        elif args.command == 'test-notes':
            notes = _text(args.notes)
            if not notes:
                parser.error('test-notes needs --notes FILE')
            if ios:
                if not args.build:
                    parser.error('--ios needs --build, the TestFlight build number')
                from asc import AppStore
                out += AppStore(args.app).test_notes(args.build, notes, args.yes)
            if android:
                from play import Play
                out += Play(args.app).test_notes(notes, args.yes)

        elif args.command == 'testers':
            if ios:
                from asc import AppStore
                out += AppStore(args.app).testers()
            if android:
                from play import Play
                out += Play(args.app).testers()

        elif args.command == 'add-tester':
            if not args.email or not args.group:
                parser.error('add-tester needs --email and --group (a TestFlight group)')
            from asc import AppStore
            out += AppStore(args.app).add_tester(args.email, args.group, args.yes)

        elif args.command == 'listing':
            source = Path(args.source) if args.source else REPO / f"apps/mgk_{args.app}/store/listing.json"
            if not source.exists():
                raise StoreError(f'No listing file at {source}.')
            listing = json.loads(source.read_text(encoding='utf-8'))
            if ios and 'ios' in listing:
                from asc import AppStore
                out += AppStore(args.app).listing(listing['ios'], args.yes)
            if android and 'android' in listing:
                from play import Play
                out += Play(args.app).listing(listing['android'], args.yes)

        elif args.command == 'screenshots':
            if ios:
                from asc import AppStore
                out += AppStore(args.app).screenshots(SHOTS[args.app] / 'ios-still', args.yes)
            if android:
                from play import Play
                feature = FEATURE[args.app]
                out += Play(args.app).screenshots(
                    SHOTS[args.app] / 'play-still', feature if feature.exists() else None, args.yes)
    except StoreError as e:
        print('\n'.join(out + [f'Stopped: {e}']))
        return 1
    print('\n'.join(out))
    return 0


if __name__ == '__main__':
    sys.exit(main())
