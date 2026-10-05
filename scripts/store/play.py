"""Google Play, for Run and Lift: status, submission to production, release
notes, testers, listing text and pictures.

The key is a JSON key for the existing Play service account
(`mgk-fitness-play-publisher`), saved outside the repository as
`play-service-account.json`. See README.md.

Every change goes through an *edit*, Play's transaction: opened, changed, then
committed, or deleted when nothing should change.
"""

from __future__ import annotations

import json
import time
import urllib.parse
from pathlib import Path

from cryptography.hazmat.primitives import serialization

from _common import APPS, StoreError, call, keys_dir, rs256_jwt

API = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications'
UPLOAD = 'https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications'
SCOPE = 'https://www.googleapis.com/auth/androidpublisher'

# Said when Play kept a committed edit for sending by hand (Play.commit).
HELD = ('  saved, but Play would not send it for review from here: Play Console › '
        'Publishing overview › Send changes for review')


def _token() -> str:
    path = keys_dir() / 'play-service-account.json'
    if not path.exists():
        raise StoreError(f'No Play key: expected {path}. See scripts/store/README.md.')
    account = json.loads(path.read_text(encoding='utf-8'))
    key = serialization.load_pem_private_key(account['private_key'].encode('utf-8'), password=None)
    audience = account.get('token_uri', 'https://oauth2.googleapis.com/token')
    now = int(time.time())
    assertion = rs256_jwt(
        {'iss': account['client_email'], 'scope': SCOPE, 'aud': audience,
         'iat': now, 'exp': now + 3600},
        key,
    )
    form = urllib.parse.urlencode({
        'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        'assertion': assertion,
    }).encode('ascii')
    res = call('POST', audience, data=form,
               headers={'Content-Type': 'application/x-www-form-urlencoded'})
    return res['access_token']


def _describe(release: dict) -> str:
    fraction = release.get('userFraction')
    rollout = f' at {round(fraction * 100)}%' if fraction else ''
    codes = ', '.join(release.get('versionCodes', [])) or 'no build'
    return f"{release.get('name') or '?'} ({codes}): {release.get('status')}{rollout}"


class Play:
    def __init__(self, app: str):
        self.key = app
        self.app = APPS[app]
        self.package = self.app['package']
        self.token = _token()

    def _url(self, edit: str, path: str = '') -> str:
        return f'{API}/{self.package}/edits/{edit}{path}'

    def open(self) -> str:
        return call('POST', f'{API}/{self.package}/edits', token=self.token, body={})['id']

    def discard(self, edit: str) -> None:
        call('DELETE', self._url(edit), token=self.token, expect_json=False)

    def commit(self, edit: str) -> bool:
        """Commit the edit and send it for review. Play sometimes will not
        send from the API ("Changes cannot be sent for review automatically",
        while changes made in Play Console wait to be sent, for one): the edit
        is then committed unsent, as Play's message asks, and this returns
        False so the caller can say it waits in Publishing overview."""
        try:
            call('POST', self._url(edit, ':commit'), token=self.token)
            return True
        except StoreError as e:
            if 'changesNotSentForReview' not in str(e):
                raise
        call('POST', self._url(edit, ':commit?changesNotSentForReview=true'), token=self.token)
        return False

    def tracks(self, edit: str) -> list[dict]:
        return call('GET', self._url(edit, '/tracks'), token=self.token).get('tracks', [])

    def language(self, edit: str) -> str:
        return call('GET', self._url(edit, '/details'), token=self.token).get('defaultLanguage', 'en-GB')

    # --- Reading ------------------------------------------------------------

    def status(self) -> list[str]:
        edit = self.open()
        try:
            lines = [f"Google Play: {self.app['name']} ({self.package})"]
            for track in self.tracks(edit):
                releases = track.get('releases') or []
                if not releases:
                    continue
                for release in releases:
                    lines.append(f"  {track['track']}: {_describe(release)}")
            return lines
        finally:
            self.discard(edit)

    def link(self) -> list[str]:
        """The public Google Play page. Play's API cannot say whether an app
        is live (a release reads `completed` while still in review), so the
        page itself is asked: it answers 404 until the app is."""
        url = f'https://play.google.com/store/apps/details?id={self.package}'
        try:
            call('GET', url, expect_json=False)
            state = 'live'
        except StoreError:
            state = 'not live yet'
        return [f"Google Play: {url} ({state})"]

    # --- Submitting ---------------------------------------------------------

    @staticmethod
    def _newest(track: dict) -> dict | None:
        releases = [r for r in track.get('releases') or [] if r.get('versionCodes')]
        if not releases:
            return None
        return max(releases, key=lambda r: max(int(c) for c in r['versionCodes']))

    def submit(self, notes: str | None, draft: bool, apply: bool) -> list[str]:
        """The newest internal build to production, for everybody: Google
        reviews it and, unless managed publishing is on, it is live the moment
        it is approved."""
        edit = self.open()
        committed = False
        try:
            by_name = {t['track']: t for t in self.tracks(edit)}
            source = self._newest(by_name.get('internal', {}))
            if source is None:
                raise StoreError(f'No build on the internal track for {self.app["name"]}.')
            language = self.language(edit)
            release = {
                'name': source.get('name'),
                'versionCodes': source['versionCodes'],
                # A draft is all Play takes for an app with nothing ever
                # rolled out; after that, completed is 100% on approval.
                'status': 'draft' if draft else 'completed',
            }
            if notes:
                release['releaseNotes'] = [{'language': language, 'text': notes}]
            plan = [
                f"Google Play: {self.app['name']} {_describe(source)} from internal to production",
                f"  {'as a draft, to roll out by hand' if draft else 'for everybody, live once Google approves it'}",
                f"  release notes ({language}): {'set' if notes else 'none'}",
            ]
            if not apply:
                return plan + ['  (plan only: run again with --yes to do it)']
            call('PUT', self._url(edit, '/tracks/production'), token=self.token,
                 body={'track': 'production', 'releases': [release]})
            try:
                sent = self.commit(edit)
            except StoreError as e:
                if 'draft app' in str(e).lower() and not draft:
                    raise StoreError(
                        f"{e}\n  Play treats an app as a draft until it is first published "
                        '(an internal rollout does not count), and takes only draft '
                        'releases for it. Run again with --draft, then start the rollout '
                        'in Play Console; every later release can go from here.'
                    ) from None
                raise
            committed = True
            if draft:
                return plan[:1] + ['  a draft on production: nothing goes to Google until it is '
                                   'rolled out in Play Console › Production › Start rollout']
            return plan[:1] + (['  sent to Google for review'] if sent else [HELD])
        finally:
            if not committed:
                self.discard(edit)

    def test_notes(self, text: str, apply: bool) -> list[str]:
        """Release notes on the newest internal build, which testers see."""
        edit = self.open()
        committed = False
        try:
            tracks = {t['track']: t for t in self.tracks(edit)}
            internal = tracks.get('internal')
            newest = self._newest(internal or {})
            if newest is None:
                raise StoreError(f'No build on the internal track for {self.app["name"]}.')
            language = self.language(edit)
            plan = [f"Google Play: internal notes for {self.app['name']} {_describe(newest)} ({language})"]
            if not apply:
                return plan + ['  (plan only: run again with --yes to do it)']
            for release in internal['releases']:
                if release is newest:
                    release['releaseNotes'] = [{'language': language, 'text': text}]
            call('PUT', self._url(edit, '/tracks/internal'), token=self.token, body=internal)
            sent = self.commit(edit)
            committed = True
            return plan + ['  set'] + ([] if sent else [HELD])
        finally:
            if not committed:
                self.discard(edit)

    def testers(self) -> list[str]:
        """Who the internal track reaches. Play keeps individual addresses
        in its email lists, which have no API: only Google Groups show here."""
        edit = self.open()
        try:
            found = call('GET', self._url(edit, '/testers/internal'), token=self.token)
            groups = ', '.join(found.get('googleGroups') or []) or 'none'
            return [f"Google Play: {self.app['name']} internal testers, Google Groups: {groups}",
                    '  (email lists are managed in Play Console › Testing › Internal testing)']
        finally:
            self.discard(edit)

    # --- The listing --------------------------------------------------------

    def listing(self, fields: dict, apply: bool) -> list[str]:
        """Text from the app's store/listing.json "android" block."""
        allowed = {k: fields[k] for k in ('title', 'shortDescription', 'fullDescription', 'video') if k in fields}
        edit = self.open()
        committed = False
        try:
            language = self.language(edit)
            plan = [f"Google Play listing: {self.app['name']} ({language}): {', '.join(allowed) or 'nothing'}"]
            if not apply:
                return plan + ['  (plan only: run again with --yes to do it)']
            call('PATCH', self._url(edit, f'/listings/{language}'), token=self.token,
                 body={'language': language, **allowed})
            sent = self.commit(edit)
            committed = True
            return plan + ['  updated'] + ([] if sent else [HELD])
        finally:
            if not committed:
                self.discard(edit)

    def screenshots(self, folder: Path, feature: Path | None, icon: Path | None,
                    apply: bool) -> list[str]:
        """Replace the phone screenshots with the PNGs in [folder], in name
        order, and the feature graphic and the 512x512 icon when given."""
        files = sorted(folder.glob('*.png'))
        if not files:
            raise StoreError(f'No PNGs in {folder}.')
        edit = self.open()
        committed = False
        try:
            language = self.language(edit)
            plan = [f"Google Play pictures: {self.app['name']} ({language}): {len(files)} phone screenshots"
                    + (', the feature graphic' if feature else '')
                    + (', the icon' if icon else '')]
            if not apply:
                return plan + ['  (plan only: run again with --yes to do it)']
            uploads = [('phoneScreenshots', f) for f in files]
            if feature:
                uploads.append(('featureGraphic', feature))
            if icon:
                uploads.append(('icon', icon))
            for kind in {k for k, _ in uploads}:
                call('DELETE', self._url(edit, f'/listings/{language}/{kind}'),
                     token=self.token, expect_json=False)
            for kind, file in uploads:
                call('POST',
                     f'{UPLOAD}/{self.package}/edits/{edit}/listings/{language}/{kind}?uploadType=media',
                     token=self.token, data=file.read_bytes(), headers={'Content-Type': 'image/png'})
            sent = self.commit(edit)
            committed = True
            return plan + ['  uploaded'] + ([] if sent else [HELD])
        finally:
            if not committed:
                self.discard(edit)
