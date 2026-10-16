"""App Store Connect, for Run and Lift: status, submission, release,
TestFlight notes and testers, listing text, screenshots and the creative
assets (product page header and search results asset).

The key is an App Store Connect API team key (App Manager), saved outside the
repository as `asc.json` ({"issuer_id": ..., "key_id": ...}) beside its
`AuthKey_<key_id>.p8`. See README.md.
"""

from __future__ import annotations

import hashlib
import json
import shutil
import struct
import subprocess
import time
import urllib.parse
from fractions import Fraction
from pathlib import Path

from cryptography.hazmat.primitives import serialization

from _common import APPS, StoreError, call, es256_jwt, keys_dir

API = 'https://api.appstoreconnect.apple.com'

# A version can be changed in these states and no others.
EDITABLE = {
    'PREPARE_FOR_SUBMISSION',
    'DEVELOPER_REJECTED',
    'REJECTED',
    'METADATA_REJECTED',
}

# The 6.9-inch and 6.7-inch iPhones, which is the 1290x2796 the kit draws.
IPHONE_SCREENSHOTS = 'APP_IPHONE_67'

# A version that is out: on sale, or replaced by a newer one. Any other state
# not in EDITABLE is a version on its way (waiting for review, in review,
# approved and not yet released), which nothing here may touch.
DONE = {
    'READY_FOR_SALE',
    'READY_FOR_DISTRIBUTION',
    'REPLACED_WITH_NEW_VERSION',
    'REMOVED_FROM_SALE',
    'DEVELOPER_REMOVED_FROM_SALE',
}

# --- Creative assets ---------------------------------------------------------
# The product page header and the search results asset, which go on a version
# through the App Asset Library: a file is uploaded to the app's library once,
# then placed on each of the version's localizations. One of each per version.
# The sizes are Apple's reference data (GET /v1/appAssetLibraryRefData) as
# read on 9 October 2026; the uploads are checked against it again after
# processing, so a change on Apple's side stops the run rather than slipping by.
HEADER = 'PRODUCT_PAGE_HEADER_ASSET'
SEARCH = 'APP_STORE_SEARCH_RESULTS_ASSET'
PLACE = {HEADER: 'product page header', SEARCH: 'search results'}
GROUP = 'DEFAULT_PROFILE'
VIDEOS = ('.mp4', '.mov', '.m4v')
KIND = {'image': 'appAssetLibraryImages', 'video': 'appAssetLibraryVideos'}
MAX_BYTES = 500 * 1024 * 1024

# What each file fills, and the size it has to be.
ROLES = {
    'universal': ((HEADER, SEARCH), '5244x2950 (16:9)', lambda w, h: (w, h) == (5244, 2950)),
    'header': ((HEADER,), '3840x1646 (21:9)', lambda w, h: (w, h) == (3840, 1646)),
    'search': ((SEARCH,), '3:2, from 1920x1280 to 3840x2560',
               lambda w, h: 2 * w == 3 * h and 1920 <= w <= 3840),
}
TAKES = 'universal.png, or header and search as .png, .mp4, .mov or .m4v'

# An asset's states: still processing, ready to place, and (for one already in
# the library) worth reusing rather than uploading again.
# `COMPLETE` is not in Apple's guide, which says UPLOAD_COMPLETE, but it is what
# a video reported between the commit and PREPARE_FOR_SUBMISSION on 2026-10-09
# (Lift's header film), with no spec matched yet. So it is still processing.
PROCESSING = {'AWAITING_UPLOAD', 'UPLOAD_COMPLETE', 'COMPLETE'}
READY = {'PREPARE_FOR_SUBMISSION', 'READY_FOR_REVIEW', 'WAITING_FOR_REVIEW', 'IN_REVIEW',
         'ACCEPTED', 'APPROVED'}
REUSABLE = READY | {'UPLOAD_COMPLETE', 'COMPLETE'}
POLL_SECONDS = 5
POLL_LIMIT = 15 * 60

PNG_COLOURS = {0: 'greyscale', 3: 'a palette', 4: 'greyscale with alpha', 6: 'RGBA'}


def _token() -> str:
    folder = keys_dir()
    config = folder / 'asc.json'
    if not config.exists():
        raise StoreError(
            f'No App Store Connect key: expected {config} and its .p8 beside '
            'it. See scripts/store/README.md.'
        )
    cfg = json.loads(config.read_text(encoding='utf-8'))
    key_file = folder / cfg.get('key_file', f"AuthKey_{cfg['key_id']}.p8")
    if not key_file.exists():
        raise StoreError(f'No private key at {key_file}.')
    key = serialization.load_pem_private_key(key_file.read_bytes(), password=None)
    now = int(time.time())
    return es256_jwt(
        {'alg': 'ES256', 'kid': cfg['key_id'], 'typ': 'JWT'},
        # Apple refuses a token that lives longer than twenty minutes.
        {'iss': cfg['issuer_id'], 'iat': now, 'exp': now + 15 * 60, 'aud': 'appstoreconnect-v1'},
        key,
    )


def _state(attributes: dict) -> str:
    return attributes.get('appVersionState') or attributes.get('appStoreState') or '?'


def _say(line: str) -> None:
    """A step as it happens, so a long upload is not silent."""
    print(line, flush=True)


def _png_size(path: Path) -> tuple[int, int]:
    """Width and height from the PNG's IHDR. Refuses alpha: Apple takes RGB
    only (colour type 2), and no transparent colour (tRNS) either."""
    with path.open('rb') as source:
        if source.read(8) != b'\x89PNG\r\n\x1a\n':
            raise StoreError(f'{path.name} is not a PNG.')
        length, kind = struct.unpack('>I4s', source.read(8))
        if kind != b'IHDR' or length < 13:
            raise StoreError(f'{path.name} has no PNG header (IHDR).')
        width, height, _depth, colour = struct.unpack('>IIBB', source.read(10))
        if colour != 2:
            raise StoreError(
                f'{path.name} is {PNG_COLOURS.get(colour, f"PNG colour type {colour}")}: the App '
                'Store takes RGB with no alpha (PNG colour type 2). Flatten it and save it as RGB.')
        source.seek(length - 10 + 4, 1)  # the rest of IHDR, and its CRC
        while True:
            head = source.read(8)
            if len(head) < 8:
                break
            length, kind = struct.unpack('>I4s', head)
            if kind == b'IDAT':
                break
            if kind == b'tRNS':
                raise StoreError(f'{path.name} has a transparent colour (a tRNS chunk): '
                                 'the App Store takes no alpha. Save it again without one.')
            source.seek(length + 4, 1)
    return width, height


def _video_facts(path: Path) -> tuple[int, int, Fraction, float]:
    """Width, height, frame rate and length, from ffprobe."""
    probe = shutil.which('ffprobe')
    if not probe:
        raise StoreError(
            f'ffprobe is not on PATH, and {path.name} has to be checked (size, frame rate, '
            'length) before it is uploaded. Install FFmpeg, then run again.')
    done = subprocess.run(
        [probe, '-v', 'error', '-select_streams', 'v:0',
         '-show_entries', 'stream=width,height,r_frame_rate:format=duration',
         '-of', 'json', str(path)],
        capture_output=True, text=True)
    if done.returncode != 0:
        raise StoreError(f'ffprobe could not read {path.name}: {done.stderr.strip()[:300]}')
    facts = json.loads(done.stdout or '{}')
    streams = facts.get('streams') or []
    if not streams:
        raise StoreError(f'{path.name} has no video stream.')
    stream = streams[0]
    try:
        fps = Fraction(stream['r_frame_rate'])
    except (KeyError, ValueError, ZeroDivisionError):
        raise StoreError(f'ffprobe gave no frame rate for {path.name}.') from None
    return int(stream['width']), int(stream['height']), fps, float(facts['format']['duration'])


def creative_files(folder: Path) -> list[dict]:
    """The creative assets in [folder], each checked on disk before anything is
    called: universal.png fills both placements; header.* and search.* (.png,
    or a video) fill one each. Anything else in the folder is refused by name,
    so nothing is quietly left behind."""
    if not folder.is_dir():
        raise StoreError(f'No folder at {folder}. It takes {TAKES}.')
    found: dict[str, Path] = {}
    unknown: list[str] = []
    for entry in sorted(folder.iterdir()):
        role, suffix = entry.stem, entry.suffix
        known = entry.is_file() and role in ROLES and (
            suffix == '.png' or (suffix in VIDEOS and role != 'universal'))
        if not known:
            unknown.append(entry.name)
        elif role in found:
            raise StoreError(f'{found[role].name} and {entry.name} both fill the same place: keep one.')
        else:
            found[role] = entry
    if unknown:
        raise StoreError(f'{folder} holds what assets does not take: {", ".join(unknown)}. '
                         f'It takes {TAKES}; move anything else out.')
    if not found:
        raise StoreError(f'Nothing in {folder}. It takes {TAKES}.')
    if 'universal' in found and len(found) > 1:
        others = ', '.join(p.name for r, p in found.items() if r != 'universal')
        raise StoreError(f'universal.png fills both placements, so {others} cannot go with it: '
                         'keep universal.png, or header and search.')

    files = []
    for role in ('universal', 'header', 'search'):
        if role not in found:
            continue
        path = found[role]
        fills, expected, fits = ROLES[role]
        size = path.stat().st_size
        if size > MAX_BYTES:
            raise StoreError(f'{path.name} is {size // (1024 * 1024)} MB: Apple takes up to 500 MB.')
        if path.suffix == '.png':
            kind = 'image'
            width, height = _png_size(path)
        else:
            kind = 'video'
            width, height, fps, seconds = _video_facts(path)
        if not fits(width, height):
            raise StoreError(f'{path.name} is {width}x{height}: it has to be {expected}.')
        facts = f'{width}x{height}'
        if kind == 'video':
            if fps not in (30, 60):
                raise StoreError(f'{path.name} runs at {float(fps):g} fps: Apple takes exactly 30 or 60.')
            if not 15 <= seconds <= 30:
                raise StoreError(f'{path.name} is {seconds:.1f} s long: keep it from 15 to 30 s.')
            facts += f', {int(fps)} fps, {seconds:.1f} s'
        entry = {'path': path, 'name': path.name, 'size': size, 'kind': kind,
                 'fills': fills, 'facts': facts}
        if kind == 'video':
            entry.update(fps=int(fps), seconds=seconds)
        files.append(entry)
    return files


def check_poster(poster: str | None, files: list[dict]) -> str | None:
    """The opening still, as App Store Connect takes it: HH:MM:SS:FF, the
    frame shown before a video plays. Checked against every video in the
    folder before anything is sent, so a time past the end stops here rather
    than as a processing failure on Apple's side."""
    if poster is None:
        return None
    videos = [f for f in files if f['kind'] == 'video']
    if not videos:
        raise StoreError('--poster is for a video, and this folder has none.')
    parts = poster.split(':')
    if len(parts) != 4 or not all(p.isdigit() and len(p) == 2 for p in parts):
        raise StoreError(f'--poster {poster} is not HH:MM:SS:FF, e.g. 00:00:05:00.')
    hours, minutes, seconds, frame = (int(p) for p in parts)
    for f in videos:
        if frame >= f['fps']:
            raise StoreError(f"--poster {poster}: {f['name']} has {f['fps']} frames a second, "
                             f"so the last part runs 00 to {f['fps'] - 1:02d}.")
        at = hours * 3600 + minutes * 60 + seconds + frame / f['fps']
        if at >= f['seconds']:
            raise StoreError(f"--poster {poster} is past the end of {f['name']} "
                             f"({f['seconds']:.1f} s).")
    return poster


class AppStore:
    def __init__(self, app: str):
        self.key = app
        self.app = APPS[app]
        self.token = _token()
        found = self.get('/v1/apps', {'filter[bundleId]': self.app['bundle']})['data']
        if not found:
            raise StoreError(f"No app with bundle id {self.app['bundle']} on this team.")
        self.app_id = found[0]['id']
        self.locale = found[0]['attributes'].get('primaryLocale', 'en-GB')

    # --- HTTP ---------------------------------------------------------------

    def get(self, path: str, params: dict | None = None):
        query = f'?{urllib.parse.urlencode(params)}' if params else ''
        return call('GET', f'{API}{path}{query}', token=self.token)

    def post(self, path: str, body: dict):
        return call('POST', f'{API}{path}', token=self.token, body=body)

    def patch(self, path: str, body: dict):
        return call('PATCH', f'{API}{path}', token=self.token, body=body)

    def delete(self, path: str):
        return call('DELETE', f'{API}{path}', token=self.token, expect_json=False)

    # --- Reading ------------------------------------------------------------

    def versions(self, limit: int = 3) -> list[dict]:
        data = self.get(
            f'/v1/apps/{self.app_id}/appStoreVersions',
            {'filter[platform]': 'IOS', 'limit': limit},
        )['data']
        return [
            {
                'id': v['id'],
                'version': v['attributes'].get('versionString'),
                'state': _state(v['attributes']),
                'release': v['attributes'].get('releaseType'),
                'created': (v['attributes'].get('createdDate') or '')[:10],
            }
            for v in data
        ]

    def builds(self, limit: int = 3, number: str | None = None) -> list[dict]:
        params = {
            'filter[app]': self.app_id,
            'sort': '-uploadedDate',
            'limit': limit,
            'include': 'preReleaseVersion',
        }
        if number is not None:
            params['filter[version]'] = number
        res = self.get('/v1/builds', params)
        versions = {
            i['id']: i['attributes'].get('version')
            for i in res.get('included', [])
            if i['type'] == 'preReleaseVersions'
        }
        out = []
        for b in res['data']:
            rel = b['relationships'].get('preReleaseVersion', {}).get('data') or {}
            out.append({
                'id': b['id'],
                'number': b['attributes'].get('version'),
                'version': versions.get(rel.get('id')),
                'state': b['attributes'].get('processingState'),
                'uploaded': (b['attributes'].get('uploadedDate') or '')[:16],
            })
        return out

    def submissions(self, limit: int = 3) -> list[dict]:
        data = self.get(
            '/v1/reviewSubmissions',
            {'filter[app]': self.app_id, 'filter[platform]': 'IOS', 'limit': limit},
        )['data']
        return [
            {
                'id': s['id'],
                'state': s['attributes'].get('state'),
                'submitted': (s['attributes'].get('submittedDate') or '')[:16],
            }
            for s in data
        ]

    def status(self) -> list[str]:
        lines = [f"App Store: {self.app['name']} ({self.app['bundle']})"]
        for v in self.versions():
            lines.append(
                f"  version {v['version']}: {v['state']}, release {v['release']}, "
                f"created {v['created']}"
            )
        for b in self.builds():
            lines.append(
                f"  build {b['number']} ({b['version']}): {b['state']}, uploaded {b['uploaded']}"
            )
        for s in self.submissions():
            lines.append(f"  review submission: {s['state']} {s['submitted']}".rstrip())
        return lines

    def link(self) -> list[str]:
        """The public App Store page, and what is on sale there: the address
        answers only once a version is."""
        on_sale = [v for v in self.versions(limit=5)
                   if v['state'] in ('READY_FOR_SALE', 'READY_FOR_DISTRIBUTION')]
        state = f"on sale: {on_sale[0]['version']}" if on_sale else 'not on sale yet'
        return [f"App Store: https://apps.apple.com/app/id{self.app_id} ({state})"]

    # --- Submitting ---------------------------------------------------------

    def _version_named(self, version: str) -> dict | None:
        data = self.get(
            f'/v1/apps/{self.app_id}/appStoreVersions',
            {'filter[platform]': 'IOS', 'filter[versionString]': version},
        )['data']
        return data[0] if data else None

    def _version_to_rename(self) -> dict | None:
        """The version open for changes, under another number, if there is one.

        Apple keeps one version open at a time, so a build of the next number
        cannot have a version of its own while that one is open: it takes the
        new number instead. Run 1.0.0 was rejected under guideline 4 on
        16 October 2026 and went back as 1.0.1, because a version is submitted
        once (ADR-0046) and the fix needed a new binary.
        """
        for v in self.versions(limit=10):
            if v['state'] in EDITABLE:
                return v
        return None

    def _build_and_version(self, build_number: str) -> tuple[dict, str, dict | None]:
        """The build, its version string, and the version it goes on, if one
        exists: `{'id', 'from'}`, where `from` is the number an open version
        is renamed from, or None when it already has the build's. Refuses a
        build still processing and a version that can no longer change."""
        found = self.builds(limit=1, number=build_number)
        if not found:
            raise StoreError(f'No build {build_number} for {self.app["name"]}.')
        build = found[0]
        if build['state'] != 'VALID':
            raise StoreError(f"Build {build_number} is {build['state']}, not VALID yet.")
        version = build['version']
        existing = self._version_named(version)
        if existing and _state(existing['attributes']) not in EDITABLE:
            raise StoreError(
                f'Version {version} is {_state(existing["attributes"])}: '
                'it cannot be changed or submitted again (a version is submitted once).'
            )
        if existing:
            return build, version, {'id': existing['id'], 'from': None}
        open_now = self._version_to_rename()
        if open_now:
            return build, version, {'id': open_now['id'], 'from': open_now['version']}
        return build, version, None

    @staticmethod
    def _opening(version: str, existing: dict | None) -> str:
        """The plan's line for the version a build goes on."""
        if existing is None:
            what = f'create version {version}'
        elif existing['from']:
            what = (f"rename version {existing['from']} to {version} "
                    '(the one open for changes; Apple keeps one at a time)')
        else:
            what = f'use version {version}'
        return f'  {what}; release automatically on approval'

    def _open_version(self, build: dict, version: str, existing: dict | None) -> str:
        """Create the version, or take the one open for changes, renamed to
        the build's number if it has another; set it to release itself on
        approval; attach the build. Returns its id."""
        if existing:
            version_id = existing['id']
            attributes = {'releaseType': 'AFTER_APPROVAL'}
            if existing['from']:
                attributes['versionString'] = version
            self.patch(f'/v1/appStoreVersions/{version_id}', {
                'data': {'type': 'appStoreVersions', 'id': version_id,
                         'attributes': attributes},
            })
        else:
            version_id = self.post('/v1/appStoreVersions', {
                'data': {
                    'type': 'appStoreVersions',
                    'attributes': {'platform': 'IOS', 'versionString': version,
                                   'releaseType': 'AFTER_APPROVAL'},
                    'relationships': {'app': {'data': {'type': 'apps', 'id': self.app_id}}},
                },
            })['data']['id']
        self.patch(f'/v1/appStoreVersions/{version_id}/relationships/build', {
            'data': {'type': 'builds', 'id': build['id']},
        })
        return version_id

    def prepare(self, build_number: str, apply: bool) -> list[str]:
        """Open the build's version without sending it for review, so the
        listing, the screenshots and the version page's subscriptions can be
        added first. Apple takes a first subscription only from that page."""
        build, version, existing = self._build_and_version(build_number)
        plan = [
            f"App Store: {self.app['name']} {version} with build {build_number}",
            self._opening(version, existing),
            f'  attach build {build_number}',
            '  not sent for review: submit does that',
        ]
        if not apply:
            return plan + ['  (plan only: run again with --yes to do it)']
        self._open_version(build, version, existing)
        return plan[:1] + ['  ready: listing, screenshots and subscriptions can go on it now']

    def _draft_submission(self) -> str | None:
        """A review submission started in App Store Connect and not yet sent
        (its Draft Submissions panel). A first subscription is added there, and
        the version has to go for review in the same submission."""
        drafts = self.get('/v1/reviewSubmissions', {
            'filter[app]': self.app_id, 'filter[platform]': 'IOS',
            'filter[state]': 'READY_FOR_REVIEW',
        })['data']
        return drafts[0]['id'] if drafts else None

    def _holds_version(self, submission: str, version_id: str) -> bool:
        """Whether the version was already added to the submission (Add for
        Review on its page), which Apple will not take twice."""
        items = self.get(f'/v1/reviewSubmissions/{submission}/items',
                         {'include': 'appStoreVersion'})['data']
        for item in items:
            linked = ((item.get('relationships') or {}).get('appStoreVersion') or {}).get('data') or {}
            if linked.get('id') == version_id:
                return True
        return False

    def submit(self, build_number: str, whats_new: str | None, apply: bool) -> list[str]:
        """Attach the build to its version, release it automatically once
        Apple approves it, set What's New, and send it for review: in the
        draft submission started in App Store Connect when there is one, so
        whatever was added there goes with it."""
        unresolved = self.get('/v1/reviewSubmissions', {
            'filter[app]': self.app_id, 'filter[platform]': 'IOS',
            'filter[state]': 'UNRESOLVED_ISSUES',
        })['data']
        if unresolved:
            # A second submission would be refused while this one is open, and
            # cancelling it drops the subscriptions in it back to the version
            # page (Run, 7 October 2026). App Store Connect resubmits it whole.
            raise StoreError(
                f"Review submission {unresolved[0]['id']} has unresolved issues from "
                'App Review. Use prepare to attach the new build, then resubmit that '
                'submission in App Store Connect (App Review, the submission, Resubmit '
                'to App Review), which keeps everything in it.'
            )
        build, version, existing = self._build_and_version(build_number)
        draft = self._draft_submission()
        plan = [
            f"App Store: {self.app['name']} {version} with build {build_number}",
            self._opening(version, existing),
            f'  attach build {build_number}',
            f"  What's New ({self.locale}): {'set' if whats_new else 'left as it is'}",
            '  submit for review' + (', in the draft submission started in App Store Connect '
                                     'and with everything already in it' if draft else ''),
        ]
        if not apply:
            return plan + ['  (plan only: run again with --yes to do it)']

        version_id = self._open_version(build, version, existing)
        if whats_new:
            self._localization_update(version_id, {'whatsNew': whats_new})

        submission = draft or self.post('/v1/reviewSubmissions', {
            'data': {
                'type': 'reviewSubmissions',
                'attributes': {'platform': 'IOS'},
                'relationships': {'app': {'data': {'type': 'apps', 'id': self.app_id}}},
            },
        })['data']['id']
        if not (draft and self._holds_version(submission, version_id)):
            self.post('/v1/reviewSubmissionItems', {
                'data': {
                    'type': 'reviewSubmissionItems',
                    'relationships': {
                        'reviewSubmission': {'data': {'type': 'reviewSubmissions', 'id': submission}},
                        'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': version_id}},
                    },
                },
            })
        self.patch(f'/v1/reviewSubmissions/{submission}', {
            'data': {'type': 'reviewSubmissions', 'id': submission,
                     'attributes': {'submitted': True}},
        })
        return plan[:1] + ['  submitted: it releases itself once Apple approves it']

    def release_type(self, automatic: bool, apply: bool) -> list[str]:
        """How the next version goes live once Apple approves it: by itself,
        or held for `release`. Changes the newest version not yet on sale."""
        wanted = 'AFTER_APPROVAL' if automatic else 'MANUAL'
        on_sale = {'READY_FOR_SALE', 'READY_FOR_DISTRIBUTION', 'REPLACED_WITH_NEW_VERSION',
                   'REMOVED_FROM_SALE', 'DEVELOPER_REMOVED_FROM_SALE'}
        coming = [v for v in self.versions(limit=5) if v['state'] not in on_sale]
        if not coming:
            return [f"App Store: {self.app['name']} has no version on its way to the store."]
        version = coming[0]
        label = 'release itself on approval' if automatic else 'wait for a manual release'
        if version['release'] == wanted:
            return [f"App Store: {self.app['name']} {version['version']} already set to {label}."]
        plan = [f"App Store: {self.app['name']} {version['version']} ({version['state']}): "
                f"{version['release']} -> {wanted}, to {label}"]
        if not apply:
            return plan + ['  (plan only: run again with --yes to do it)']
        self.patch(f"/v1/appStoreVersions/{version['id']}", {
            'data': {'type': 'appStoreVersions', 'id': version['id'],
                     'attributes': {'releaseType': wanted}},
        })
        return plan + ['  changed']

    def release(self, apply: bool) -> list[str]:
        """Release a version Apple approved and is holding for a manual release."""
        held = [v for v in self.versions(limit=5) if v['state'] == 'PENDING_DEVELOPER_RELEASE']
        if not held:
            return [f"App Store: {self.app['name']} has no version waiting to be released."]
        version = held[0]
        if not apply:
            return [f"App Store: release {self.app['name']} {version['version']}",
                    '  (plan only: run again with --yes to do it)']
        self.post('/v1/appStoreVersionReleaseRequests', {
            'data': {
                'type': 'appStoreVersionReleaseRequests',
                'relationships': {'appStoreVersion': {
                    'data': {'type': 'appStoreVersions', 'id': version['id']}}},
            },
        })
        return [f"App Store: {self.app['name']} {version['version']} released"]

    # --- TestFlight ---------------------------------------------------------

    def test_notes(self, build_number: str, text: str, apply: bool) -> list[str]:
        found = self.builds(limit=1, number=build_number)
        if not found:
            raise StoreError(f'No build {build_number} for {self.app["name"]}.')
        build_id = found[0]['id']
        plan = [f"TestFlight: What to Test for {self.app['name']} build {build_number} ({self.locale})"]
        if not apply:
            return plan + ['  (plan only: run again with --yes to do it)']
        existing = self.get(f'/v1/builds/{build_id}/betaBuildLocalizations')['data']
        mine = [l for l in existing if l['attributes'].get('locale') == self.locale] or existing
        if mine:
            self.patch(f"/v1/betaBuildLocalizations/{mine[0]['id']}", {
                'data': {'type': 'betaBuildLocalizations', 'id': mine[0]['id'],
                         'attributes': {'whatsNew': text}},
            })
        else:
            self.post('/v1/betaBuildLocalizations', {
                'data': {
                    'type': 'betaBuildLocalizations',
                    'attributes': {'locale': self.locale, 'whatsNew': text},
                    'relationships': {'build': {'data': {'type': 'builds', 'id': build_id}}},
                },
            })
        return plan + ['  set']

    def testers(self) -> list[str]:
        lines = [f"TestFlight: {self.app['name']}"]
        for group in self.get('/v1/betaGroups', {'filter[app]': self.app_id, 'limit': 50})['data']:
            people = self.get(f"/v1/betaGroups/{group['id']}/betaTesters", {'limit': 200})['data']
            kind = 'internal' if group['attributes'].get('isInternalGroup') else 'external'
            emails = ', '.join(p['attributes'].get('email') or '?' for p in people)
            lines.append(f"  {group['attributes']['name']} ({kind}, {len(people)}): {emails}")
        return lines

    def add_tester(self, email: str, group_name: str, apply: bool) -> list[str]:
        groups = self.get('/v1/betaGroups', {'filter[app]': self.app_id, 'limit': 50})['data']
        match = [g for g in groups if g['attributes']['name'].lower() == group_name.lower()]
        if not match:
            names = ', '.join(g['attributes']['name'] for g in groups)
            raise StoreError(f'No TestFlight group "{group_name}". There are: {names}.')
        plan = [f"TestFlight: add {email} to {match[0]['attributes']['name']} ({self.app['name']})"]
        if not apply:
            return plan + ['  (plan only: run again with --yes to do it)']
        self.post('/v1/betaTesters', {
            'data': {
                'type': 'betaTesters',
                'attributes': {'email': email},
                'relationships': {'betaGroups': {'data': [{'type': 'betaGroups', 'id': match[0]['id']}]}},
            },
        })
        return plan + ['  added: TestFlight emails the invitation']

    # --- The listing --------------------------------------------------------

    def _editable_version(self) -> dict:
        for v in self.versions(limit=5):
            if v['state'] in EDITABLE:
                return v
        raise StoreError(
            f"{self.app['name']} has no version open for changes. Create the next "
            'one first (prepare creates it), or wait for a rejection to reopen one.'
        )

    def _editable_info(self) -> dict:
        """The app information that goes out with the next version. While one is
        being prepared there are two, and the live one cannot be changed.
        Apple's newer `state` says READY_FOR_DISTRIBUTION where the older
        `appStoreState` said READY_FOR_SALE, so both are read."""
        for info in self.get(f'/v1/apps/{self.app_id}/appInfos')['data']:
            attributes = info['attributes']
            if (attributes.get('state') or attributes.get('appStoreState')) in EDITABLE:
                return info
        raise StoreError(
            f"{self.app['name']} has no app information open for changes. "
            'Run prepare first: a new version opens it.'
        )

    def _review_notes(self, version_id: str, notes: str) -> None:
        found = self.get(f'/v1/appStoreVersions/{version_id}', {'include': 'appStoreReviewDetail'})
        detail = found['data'].get('relationships', {}).get('appStoreReviewDetail', {}).get('data')
        if detail:
            self.patch(f"/v1/appStoreReviewDetails/{detail['id']}", {
                'data': {'type': 'appStoreReviewDetails', 'id': detail['id'],
                         'attributes': {'notes': notes}},
            })
        else:
            self.post('/v1/appStoreReviewDetails', {
                'data': {
                    'type': 'appStoreReviewDetails',
                    'attributes': {'notes': notes},
                    'relationships': {'appStoreVersion': {
                        'data': {'type': 'appStoreVersions', 'id': version_id}}},
                },
            })

    def _localization_update(self, version_id: str, attributes: dict) -> None:
        locs = self.get(f'/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations')['data']
        mine = [l for l in locs if l['attributes'].get('locale') == self.locale]
        if not mine:
            raise StoreError(f'Version has no {self.locale} localization.')
        self.patch(f"/v1/appStoreVersionLocalizations/{mine[0]['id']}", {
            'data': {'type': 'appStoreVersionLocalizations', 'id': mine[0]['id'],
                     'attributes': attributes},
        })

    def listing(self, fields: dict, apply: bool) -> list[str]:
        """Text from the app's store/listing.json "ios" block: version-level
        fields on the version open for changes, app-level ones on the app
        information going out with it, and the notes for App Review."""
        version_level = {k: fields[k] for k in
                         ('description', 'keywords', 'promotionalText', 'supportUrl',
                          'marketingUrl', 'whatsNew') if k in fields}
        version_own = {k: fields[k] for k in ('copyright',) if k in fields}
        app_level = {k: fields[k] for k in ('name', 'subtitle', 'privacyPolicyUrl') if k in fields}
        notes = fields.get('reviewNotes')
        version = self._editable_version()
        plan = [
            f"App Store listing: {self.app['name']} {version['version']} ({self.locale})",
            f"  version: {', '.join([*version_level, *version_own]) or 'nothing'}",
            f"  app: {', '.join(app_level) or 'nothing'}",
            f"  App Review notes: {'set' if notes else 'left as they are'}",
        ]
        if not apply:
            return plan + ['  (plan only: run again with --yes to do it)']
        if version_level:
            self._localization_update(version['id'], version_level)
        if version_own:
            self.patch(f"/v1/appStoreVersions/{version['id']}", {
                'data': {'type': 'appStoreVersions', 'id': version['id'], 'attributes': version_own},
            })
        if notes:
            self._review_notes(version['id'], notes)
        if app_level:
            info = self._editable_info()
            locs = self.get(f"/v1/appInfos/{info['id']}/appInfoLocalizations")['data']
            mine = [l for l in locs if l['attributes'].get('locale') == self.locale]
            if not mine:
                raise StoreError(f'App info has no {self.locale} localization.')
            self.patch(f"/v1/appInfoLocalizations/{mine[0]['id']}", {
                'data': {'type': 'appInfoLocalizations', 'id': mine[0]['id'],
                         'attributes': app_level},
            })
        return plan + ['  updated']

    def screenshots(self, folder: Path, apply: bool) -> list[str]:
        """Replace the iPhone screenshots on the version open for changes with
        the PNGs in [folder], in name order."""
        files = sorted(folder.glob('*.png'))
        if not files:
            raise StoreError(f'No PNGs in {folder}.')
        version = self._editable_version()
        plan = [f"App Store screenshots: {self.app['name']} {version['version']}, "
                f"{len(files)} at {IPHONE_SCREENSHOTS}: " + ', '.join(f.name for f in files)]
        if not apply:
            return plan + ['  (plan only: run again with --yes to do it)']
        locs = self.get(f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations")['data']
        loc = next(l for l in locs if l['attributes'].get('locale') == self.locale)
        sets = self.get(f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")['data']
        current = next((s for s in sets if s['attributes'].get('screenshotDisplayType') == IPHONE_SCREENSHOTS), None)
        if current:
            for shot in self.get(f"/v1/appScreenshotSets/{current['id']}/appScreenshots")['data']:
                self.delete(f"/v1/appScreenshots/{shot['id']}")
            set_id = current['id']
        else:
            set_id = self.post('/v1/appScreenshotSets', {
                'data': {
                    'type': 'appScreenshotSets',
                    'attributes': {'screenshotDisplayType': IPHONE_SCREENSHOTS},
                    'relationships': {'appStoreVersionLocalization': {
                        'data': {'type': 'appStoreVersionLocalizations', 'id': loc['id']}}},
                },
            })['data']['id']
        for file in files:
            data = file.read_bytes()
            reserved = self.post('/v1/appScreenshots', {
                'data': {
                    'type': 'appScreenshots',
                    'attributes': {'fileName': file.name, 'fileSize': len(data)},
                    'relationships': {'appScreenshotSet': {'data': {'type': 'appScreenshotSets', 'id': set_id}}},
                },
            })['data']
            for op in reserved['attributes']['uploadOperations']:
                part = data[op['offset']:op['offset'] + op['length']]
                headers = {h['name']: h['value'] for h in op.get('requestHeaders', [])}
                call(op['method'], op['url'], data=part, headers=headers, expect_json=False)
            self.patch(f"/v1/appScreenshots/{reserved['id']}", {
                'data': {'type': 'appScreenshots', 'id': reserved['id'],
                         'attributes': {'uploaded': True,
                                        'sourceFileChecksum': hashlib.md5(data).hexdigest()}},
            })
        return plan + ['  uploaded: Apple processes them in a few minutes']

    # --- Creative assets ----------------------------------------------------

    def _version_for_assets(self) -> tuple[dict | None, str | None]:
        """The version open for changes, or None when there is none, with a
        note when the reason is a version on its way to the store (waiting for
        review, in review, or approved and not yet released). Nothing is ever
        placed on one of those. The files can still go to the Asset Library,
        which does not touch a version, ready to place once the next one is
        open."""
        versions = self.versions(limit=5)
        for v in versions:
            if v['state'] in EDITABLE:
                return v, None
        for v in versions:
            if v['state'] not in DONE:
                return None, f"{self.app['name']} {v['version']} is {v['state']}: nothing is placed on it"
        return None, None

    def _in_library(self, library: str, kind: str) -> list[dict]:
        return self.get(f'/v1/appAssetLibraries/{library}/{kind}s', {
            'filter[category]': 'CREATIVE_ASSETS', 'limit': 200,
        })['data']

    @staticmethod
    def _reusable(assets: list[dict], file: dict) -> dict | None:
        """An asset already in the library with the file's name and size, ready
        or still processing: placed again rather than uploaded again."""
        same = [a for a in assets
                if a['attributes'].get('fileName') == file['name']
                and a['attributes'].get('fileSize') == file['size']
                and a['attributes'].get('state') in REUSABLE]
        same.sort(key=lambda a: a['attributes'].get('state') not in READY)
        return same[0] if same else None

    def _placed(self, localization: str) -> dict[str, list[dict]]:
        """The header and search results placements on a localization now, by
        type, each with the asset it shows."""
        res = self.get(f'/v1/appStoreVersionLocalizations/{localization}/placements', {
            'filter[placementType]': f'{HEADER},{SEARCH}', 'include': 'image,video', 'limit': 200,
        })
        names = {i['id']: (i.get('attributes') or {}).get('fileName') for i in res.get('included') or []}
        placed: dict[str, list[dict]] = {}
        for p in res['data']:
            attributes = p.get('attributes') or {}
            links = p.get('relationships') or {}
            asset = ((links.get('image') or {}).get('data')
                     or (links.get('video') or {}).get('data') or {}).get('id')
            shown = names.get(asset) or (attributes.get('mediaType') or 'asset').lower()
            placed.setdefault(attributes.get('placementType'), []).append(
                {'id': p['id'], 'asset': asset, 'label': f'the one there now ({shown})'})
        return placed

    def _upload(self, library: str, file: dict, poster: str | None = None) -> str:
        """Reserve, send the parts, commit. Returns the asset's id. A video's
        opening still is set on the reservation, as Apple's guide does it."""
        kind = KIND[file['kind']]
        attributes = {'fileName': file['name'], 'fileSize': file['size'],
                      'category': 'CREATIVE_ASSETS'}
        if file['kind'] == 'video' and poster:
            attributes['previewFrameTimeCode'] = poster
        reserved = self.post(f'/v1/{kind}', {
            'data': {
                'type': kind,
                'attributes': attributes,
                'relationships': {'assetLibrary': {'data': {'type': 'appAssetLibraries', 'id': library}}},
            },
        })['data']
        operations = reserved['attributes'].get('uploadOperations') or []
        parts = len(operations)
        _say(f"  {file['name']}: reserved in the Asset Library, sending it in "
             f"{parts} part{'' if parts == 1 else 's'}")
        with file['path'].open('rb') as source:
            for op in operations:
                source.seek(op['offset'])
                part = source.read(op['length'])
                headers = {h['name']: h['value'] for h in op.get('requestHeaders') or []}
                call(op['method'], op['url'], data=part, headers=headers, expect_json=False)
        self.patch(f"/v1/{kind}/{reserved['id']}", {
            'data': {'type': kind, 'id': reserved['id'], 'attributes': {'uploaded': True}},
        })
        _say(f"  {file['name']}: uploaded; Apple is processing it")
        return reserved['id']

    def _processed(self, file: dict, asset: str) -> str:
        """Wait until Apple has processed the asset. Returns its spec id."""
        kind = KIND[file['kind']]
        waited = 0
        while True:
            attributes = self.get(f'/v1/{kind}/{asset}')['data']['attributes']
            state = attributes.get('state')
            if state in READY:
                return attributes.get('specId')
            if state == 'FAILED':
                details = '; '.join(d.get('description') or d.get('code') or ''
                                    for d in attributes.get('stateDetails') or []) or 'no reason given'
                raise StoreError(f"Apple could not process {file['name']} ({details}). It stays in "
                                 'the Asset Library as FAILED; fix the file and run again.')
            if state not in PROCESSING:
                raise StoreError(f"{file['name']} is {state} in the Asset Library, not ready to place.")
            if waited >= POLL_LIMIT:
                raise StoreError(f"{file['name']} is still processing after {POLL_LIMIT // 60} minutes. "
                                 'Run again later: the upload is reused, not sent twice.')
            time.sleep(POLL_SECONDS)
            waited += POLL_SECONDS

    def _specs(self) -> tuple[dict[str, set[str]], dict[str, str]]:
        """From Apple's reference data: the specs each placement type takes in
        its group, and each spec's short name."""
        data = self.get('/v1/appAssetLibraryRefData')['data']
        ref = data[0]['attributes'] if data else {}
        takes = {
            t.get('placementTypeId'): {s for m in t.get('specMappings') or []
                                       if m.get('placementGroupId') == GROUP for s in m.get('specs') or []}
            for t in ref.get('placementTypes') or []
        }
        names = {s['specId']: s.get('shortName') or s['specId']
                 for s in (ref.get('imageSpecs') or []) + (ref.get('videoSpecs') or [])}
        return takes, names

    @staticmethod
    def _check_spec(file: dict, spec: str | None, takes: dict, names: dict) -> None:
        """Apple matches each upload to a spec. Stop unless it is one that every
        placement the file is meant for takes."""
        for placement in file['fills']:
            if spec not in takes.get(placement, set()):
                wanted = ', '.join(names.get(s, s) for s in sorted(takes.get(placement, set())))
                raise StoreError(
                    f"Apple matched {file['name']} to spec {names.get(spec, spec)}, which the "
                    f"{PLACE[placement]} placement does not take ({wanted or 'none listed'}). "
                    'Nothing placed.')
        _say(f"  {file['name']}: ready, matched to {names.get(spec, spec)}")

    def assets(self, files: list[dict], source: str, apply: bool,
               poster: str | None = None) -> list[str]:
        """Upload the creative assets to the app's Asset Library (once: a file
        already there with the same name and size is reused), then place them
        on every localization of the version open for changes, replacing what
        is there. With no version open, they are only uploaded. [poster] is a
        video's opening still, HH:MM:SS:FF, already checked by check_poster."""
        version, held_back = self._version_for_assets()
        library = self.get(f'/v1/apps/{self.app_id}/assetLibrary')['data']['id']
        kinds = {f['kind'] for f in files}
        held = {kind: self._in_library(library, kind) for kind in kinds}
        reuse = {f['name']: self._reusable(held[f['kind']], f) for f in files}

        plan = [f"App Store creative assets: {self.app['name']}, from {source}"]
        for f in files:
            where = ' and '.join(PLACE[p] for p in f['fills'])
            how = 'in the Asset Library already, reused' if reuse[f['name']] else 'upload it'
            if f['kind'] == 'video' and poster:
                was = (reuse[f['name']] or {}).get('attributes', {}).get('previewFrameTimeCode')
                how += (f', opening still {poster}' if was in (None, poster)
                        else f', opening still changed from {was} to {poster}')
            plan.append(f"  {f['name']} ({f['facts']}): {where}; {how}")

        steps: list[tuple[str, str, str, dict, list[dict]]] = []
        if version is None:
            if held_back:
                plan.append(f'  {held_back}')
            plan.append('  no version is open for changes: the files can go to the Asset Library '
                        'now, and the placements wait for prepare (then run assets again)')
        else:
            locs = self.get(f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations")['data']
            if not locs:
                raise StoreError(f"{self.app['name']} {version['version']} has no localizations.")
            plan.append(f"  on version {version['version']} ({version['state']}), in "
                        + ', '.join(l['attributes'].get('locale') or '?' for l in locs) + ':')
            for loc in locs:
                locale = loc['attributes'].get('locale') or '?'
                placed = self._placed(loc['id'])
                for f in files:
                    reused = reuse[f['name']]
                    for placement in f['fills']:
                        old = placed.get(placement, [])
                        if reused and [o['asset'] for o in old] == [reused['id']]:
                            plan.append(f"    {locale}: {PLACE[placement]}: {f['name']} is there "
                                        'already, left as it is')
                            continue
                        gone = ''.join(f"delete {o['label']}, then " for o in old)
                        plan.append(f"    {locale}: {PLACE[placement]}: {gone}place {f['name']}")
                        steps.append((loc['id'], locale, placement, f, old))
        if not apply:
            return plan + ['  (plan only: run again with --yes to do it)']

        for line in plan:
            _say(line)
        takes, names = self._specs()
        ready: dict[str, str] = {}
        for f in files:
            reused = reuse[f['name']]
            if reused:
                _say(f"  {f['name']}: in the Asset Library already "
                     f"({reused['attributes'].get('state')}), reused")
                asset = reused['id']
                if f['kind'] == 'video' and poster and \
                        reused['attributes'].get('previewFrameTimeCode') != poster:
                    self.patch(f"/v1/{KIND['video']}/{asset}", {
                        'data': {'type': KIND['video'], 'id': asset,
                                 'attributes': {'previewFrameTimeCode': poster}},
                    })
                    _say(f"  {f['name']}: opening still set to {poster}")
            else:
                asset = self._upload(library, f, poster)
            self._check_spec(f, self._processed(f, asset), takes, names)
            ready[f['name']] = asset

        # Every asset is ready before any placement is touched, so a failed
        # upload never leaves a localization with its old placement deleted.
        for localization, locale, placement, f, old in steps:
            for o in old:
                self.delete(f"/v1/appAssetLibraryPlacements/{o['id']}")
                _say(f"  {locale}: {PLACE[placement]}: deleted {o['label']}")
            self.post('/v1/appAssetLibraryPlacements', {
                'data': {
                    'type': 'appAssetLibraryPlacements',
                    'attributes': {'placementType': placement, 'placementGroup': GROUP},
                    'relationships': {
                        f['kind']: {'data': {'type': KIND[f['kind']], 'id': ready[f['name']]}},
                        'appStoreVersionLocalization': {
                            'data': {'type': 'appStoreVersionLocalizations', 'id': localization}},
                    },
                },
            })
            _say(f"  {locale}: {PLACE[placement]}: placed {f['name']}")
        if version is None:
            return ['  uploaded only: no version is open, so nothing was placed. Run prepare, '
                    'then assets again; the uploads are reused.']
        return [f"  done: they go out with {version['version']} when it is submitted"]
