"""App Store Connect, for Run and Lift: status, submission, release,
TestFlight notes and testers, listing text and screenshots.

The key is an App Store Connect API team key (App Manager), saved outside the
repository as `asc.json` ({"issuer_id": ..., "key_id": ...}) beside its
`AuthKey_<key_id>.p8`. See README.md.
"""

from __future__ import annotations

import hashlib
import json
import time
import urllib.parse
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

    # --- Submitting ---------------------------------------------------------

    def _version_named(self, version: str) -> dict | None:
        data = self.get(
            f'/v1/apps/{self.app_id}/appStoreVersions',
            {'filter[platform]': 'IOS', 'filter[versionString]': version},
        )['data']
        return data[0] if data else None

    def _build_and_version(self, build_number: str) -> tuple[dict, str, dict | None]:
        """The build, its version string, and that version if it exists. Refuses
        a build still processing and a version that can no longer change."""
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
        return build, version, existing

    def _open_version(self, build: dict, version: str, existing: dict | None) -> str:
        """Create the version, or take the one open for changes; set it to
        release itself on approval; attach the build. Returns its id."""
        if existing:
            version_id = existing['id']
            self.patch(f'/v1/appStoreVersions/{version_id}', {
                'data': {'type': 'appStoreVersions', 'id': version_id,
                         'attributes': {'releaseType': 'AFTER_APPROVAL'}},
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
            f"  {'use' if existing else 'create'} version {version}; release automatically on approval",
            f'  attach build {build_number}',
            '  not sent for review: submit does that',
        ]
        if not apply:
            return plan + ['  (plan only: run again with --yes to do it)']
        self._open_version(build, version, existing)
        return plan[:1] + ['  ready: listing, screenshots and subscriptions can go on it now']

    def submit(self, build_number: str, whats_new: str | None, apply: bool) -> list[str]:
        """Attach the build to its version, release it automatically once
        Apple approves it, set What's New, and send it for review."""
        build, version, existing = self._build_and_version(build_number)
        plan = [
            f"App Store: {self.app['name']} {version} with build {build_number}",
            f"  {'use' if existing else 'create'} version {version}; release automatically on approval",
            f'  attach build {build_number}',
            f"  What's New ({self.locale}): {'set' if whats_new else 'left as it is'}",
            '  submit for review',
        ]
        if not apply:
            return plan + ['  (plan only: run again with --yes to do it)']

        version_id = self._open_version(build, version, existing)
        if whats_new:
            self._localization_update(version_id, {'whatsNew': whats_new})

        submission = self.post('/v1/reviewSubmissions', {
            'data': {
                'type': 'reviewSubmissions',
                'attributes': {'platform': 'IOS'},
                'relationships': {'app': {'data': {'type': 'apps', 'id': self.app_id}}},
            },
        })['data']['id']
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
