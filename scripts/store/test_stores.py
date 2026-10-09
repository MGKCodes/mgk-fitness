"""Offline tests for the store scripts: signing, the apps they may touch, and
that nothing reaches a store without --yes.

    python -m unittest discover -s scripts/store -p "test_*.py"
"""

from __future__ import annotations

import base64
import contextlib
import io
import json
import struct
import sys
import tempfile
import unittest
import zlib
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))

from cryptography.hazmat.primitives import hashes  # noqa: E402
from cryptography.hazmat.primitives.asymmetric import ec, padding, rsa  # noqa: E402
from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature  # noqa: E402

import asc  # noqa: E402
import play  # noqa: E402
import stores  # noqa: E402
from _common import es256_jwt, rs256_jwt  # noqa: E402


def _unb64(part: str) -> bytes:
    return base64.urlsafe_b64decode(part + '=' * (-len(part) % 4))


class Signing(unittest.TestCase):
    def test_es256_is_what_apple_verifies(self):
        key = ec.generate_private_key(ec.SECP256R1())
        token = es256_jwt({'alg': 'ES256', 'kid': 'K'}, {'iss': 'I', 'aud': 'appstoreconnect-v1'}, key)
        head, body, sig = token.split('.')
        raw = _unb64(sig)
        self.assertEqual(len(raw), 64)  # r and s, not DER
        der = encode_dss_signature(int.from_bytes(raw[:32], 'big'), int.from_bytes(raw[32:], 'big'))
        key.public_key().verify(der, f'{head}.{body}'.encode(), ec.ECDSA(hashes.SHA256()))
        self.assertEqual(json.loads(_unb64(body))['aud'], 'appstoreconnect-v1')

    def test_rs256_is_what_google_verifies(self):
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        token = rs256_jwt({'iss': 'a@b'}, key)
        head, body, sig = token.split('.')
        key.public_key().verify(_unb64(sig), f'{head}.{body}'.encode(), padding.PKCS1v15(), hashes.SHA256())
        self.assertEqual(json.loads(_unb64(head))['alg'], 'RS256')


class OnlyRunAndLift(unittest.TestCase):
    def test_another_app_is_refused_before_anything_is_called(self):
        with mock.patch.object(asc, '_token') as token, contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                stores.main(['status', 'frunt'])
        token.assert_not_called()


class FakeStore:
    """Answers by URL, and remembers what was sent."""

    def __init__(self, answers):
        self.answers = answers
        self.sent: list[tuple[str, str]] = []

    def __call__(self, method, url, **kwargs):
        self.sent.append((method, url))
        for (m, fragment), answer in self.answers.items():
            if m == method and fragment in url:
                return answer.resolve() if hasattr(answer, 'resolve') else answer
        return None

    def writes(self):
        return [(m, u) for m, u in self.sent if m not in ('GET',)]


APPLE = {
    ('GET', '/v1/apps?'): {'data': [{'id': 'A1', 'attributes': {'primaryLocale': 'en-GB'}}]},
    ('GET', '/v1/builds?'): {
        'data': [{'id': 'B52', 'attributes': {'version': '52', 'processingState': 'VALID'},
                  'relationships': {'preReleaseVersion': {'data': {'id': 'P1'}}}}],
        'included': [{'id': 'P1', 'type': 'preReleaseVersions', 'attributes': {'version': '2.0.0'}}],
    },
    ('GET', '/appStoreVersions?'): {'data': []},
    ('POST', '/v1/appStoreVersions'): {'data': {'id': 'V1'}},
    ('POST', '/v1/reviewSubmissions'): {'data': {'id': 'R1'}},
    ('GET', '/v1/reviewSubmissions?'): {'data': []},
    ('GET', '/appStoreVersionLocalizations'): {
        'data': [{'id': 'L1', 'attributes': {'locale': 'en-GB'}}]},
}


class AppleSubmit(unittest.TestCase):
    def run_submit(self, *flags, answers=None):
        fake = FakeStore(answers or APPLE)
        with mock.patch.object(asc, '_token', return_value='t'), \
                mock.patch.object(asc, 'call', fake), \
                contextlib.redirect_stdout(io.StringIO()) as printed:
            code = stores.main(['submit', 'lift', '--ios', '--build', '52', *flags])
        return code, fake, printed.getvalue()

    def test_without_yes_it_only_plans(self):
        code, fake, printed = self.run_submit()
        self.assertEqual(code, 0)
        self.assertEqual(fake.writes(), [])
        self.assertIn('release automatically on approval', printed)
        self.assertIn('--yes', printed)

    def test_with_yes_it_releases_itself_on_approval(self):
        code, fake, _ = self.run_submit('--yes')
        self.assertEqual(code, 0)
        posts = [u for m, u in fake.sent if m == 'POST']
        self.assertTrue(any(u.endswith('/v1/appStoreVersions') for u in posts))
        self.assertTrue(any(u.endswith('/v1/reviewSubmissionItems') for u in posts))
        self.assertTrue(any(m == 'PATCH' and u.endswith('/v1/reviewSubmissions/R1') for m, u in fake.sent))

    def with_draft(self, items):
        answers = dict(APPLE)
        answers[('GET', '/v1/reviewSubmissions?')] = {'data': [{'id': 'D1'}]}
        answers[('GET', '/reviewSubmissions/D1/items')] = {'data': items}
        return answers

    def test_a_draft_started_in_app_store_connect_is_the_one_submitted(self):
        code, fake, printed = self.run_submit(answers=self.with_draft([]))
        self.assertIn('in the draft submission started in App Store Connect', printed)
        code, fake, _ = self.run_submit('--yes', answers=self.with_draft([]))
        self.assertEqual(code, 0)
        self.assertFalse(any(m == 'POST' and u.endswith('/v1/reviewSubmissions') for m, u in fake.sent))
        self.assertTrue(any(m == 'POST' and u.endswith('/v1/reviewSubmissionItems') for m, u in fake.sent))
        self.assertTrue(any(m == 'PATCH' and u.endswith('/v1/reviewSubmissions/D1') for m, u in fake.sent))

    def test_a_version_already_in_the_draft_is_not_added_twice(self):
        already = [{'id': 'I1', 'relationships': {
            'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': 'V1'}}}}]
        code, fake, _ = self.run_submit('--yes', answers=self.with_draft(already))
        self.assertEqual(code, 0)
        self.assertFalse(any(u.endswith('/v1/reviewSubmissionItems') for _, u in fake.sent))
        self.assertTrue(any(m == 'PATCH' and u.endswith('/v1/reviewSubmissions/D1') for m, u in fake.sent))


class ApplePrepare(unittest.TestCase):
    def run_prepare(self, *flags):
        fake = FakeStore(APPLE)
        with mock.patch.object(asc, '_token', return_value='t'), \
                mock.patch.object(asc, 'call', fake), \
                contextlib.redirect_stdout(io.StringIO()) as printed:
            code = stores.main(['prepare', 'lift', '--build', '52', *flags])
        return code, fake, printed.getvalue()

    def test_without_yes_it_only_plans(self):
        code, fake, printed = self.run_prepare()
        self.assertEqual(code, 0)
        self.assertEqual(fake.writes(), [])
        self.assertIn('create version 2.0.0', printed)

    def test_with_yes_the_version_is_opened_and_not_sent_for_review(self):
        code, fake, _ = self.run_prepare('--yes')
        self.assertEqual(code, 0)
        writes = fake.writes()
        self.assertIn(('POST', 'https://api.appstoreconnect.apple.com/v1/appStoreVersions'), writes)
        self.assertTrue(any(u.endswith('/v1/appStoreVersions/V1/relationships/build') for _, u in writes))
        self.assertFalse(any('reviewSubmission' in u for _, u in writes))


class AppleListing(unittest.TestCase):
    """The listing goes on the app information being prepared, never the live one."""

    def run_listing(self, fields):
        sent = []
        fake = FakeStore({
            ('GET', '/v1/apps?'): {'data': [{'id': 'A1', 'attributes': {'primaryLocale': 'en-GB'}}]},
            ('GET', '/appStoreVersions?'): {'data': [
                {'id': 'V2', 'attributes': {'versionString': '2.0.0', 'appVersionState': 'PREPARE_FOR_SUBMISSION'}},
                {'id': 'V1', 'attributes': {'versionString': '1.4.0', 'appVersionState': 'READY_FOR_DISTRIBUTION'}},
            ]},
            ('GET', '/appStoreVersionLocalizations'): {
                'data': [{'id': 'L2', 'attributes': {'locale': 'en-GB'}}]},
            ('GET', '/v1/apps/A1/appInfos'): {'data': [
                {'id': 'LIVE', 'attributes': {'state': 'READY_FOR_DISTRIBUTION'}},
                {'id': 'NEXT', 'attributes': {'state': 'PREPARE_FOR_SUBMISSION'}},
            ]},
            ('GET', '/appInfos/NEXT/appInfoLocalizations'): {
                'data': [{'id': 'IL2', 'attributes': {'locale': 'en-GB'}}]},
            ('GET', '/appStoreVersions/V2?'): {'data': {'id': 'V2', 'relationships': {
                'appStoreReviewDetail': {'data': None}}}},
        })

        def recording(method, url, **kwargs):
            if method != 'GET':
                sent.append((method, url.split('/v1/')[-1], kwargs.get('body')))
            return fake(method, url, **kwargs)

        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / 'listing.json'
            source.write_text(json.dumps({'ios': fields}), encoding='utf-8')
            with mock.patch.object(asc, '_token', return_value='t'), \
                    mock.patch.object(asc, 'call', recording), \
                    contextlib.redirect_stdout(io.StringIO()):
                code = stores.main(['listing', 'lift', '--ios', '--from', str(source), '--yes'])
        return code, sent

    def test_the_name_goes_on_the_information_being_prepared(self):
        code, sent = self.run_listing({'name': 'MGKFitness: Lift'})
        self.assertEqual(code, 0)
        self.assertEqual(sent, [('PATCH', 'appInfoLocalizations/IL2', {
            'data': {'type': 'appInfoLocalizations', 'id': 'IL2',
                     'attributes': {'name': 'MGKFitness: Lift'}}})])

    def test_review_notes_and_copyright_go_on_the_version(self):
        code, sent = self.run_listing({'reviewNotes': 'Sign in with the demo account.',
                                       'copyright': '2026 MGKCodes Ltd'})
        self.assertEqual(code, 0)
        self.assertIn(('PATCH', 'appStoreVersions/V2', {
            'data': {'type': 'appStoreVersions', 'id': 'V2',
                     'attributes': {'copyright': '2026 MGKCodes Ltd'}}}), sent)
        posted = [body for method, path, body in sent if path == 'appStoreReviewDetails']
        self.assertEqual(posted[0]['data']['attributes'], {'notes': 'Sign in with the demo account.'})
        self.assertEqual(posted[0]['data']['relationships']['appStoreVersion']['data']['id'], 'V2')


class AppleReleaseType(unittest.TestCase):
    def run_it(self, *flags):
        sent = []
        fake = FakeStore({
            ('GET', '/v1/apps?'): {'data': [{'id': 'A1', 'attributes': {'primaryLocale': 'en-GB'}}]},
            ('GET', '/appStoreVersions?'): {'data': [
                {'id': 'V9', 'attributes': {'versionString': '1.0.0', 'appVersionState': 'WAITING_FOR_REVIEW',
                                            'releaseType': 'MANUAL'}},
            ]},
        })

        def recording(method, url, **kwargs):
            if method == 'PATCH':
                sent.append((url, kwargs['body']))
            return fake(method, url, **kwargs)

        with mock.patch.object(asc, '_token', return_value='t'), \
                mock.patch.object(asc, 'call', recording), \
                contextlib.redirect_stdout(io.StringIO()) as printed:
            code = stores.main(['release-type', 'run', '--automatic', *flags])
        return code, sent, printed.getvalue()

    def test_without_yes_it_only_plans(self):
        code, sent, printed = self.run_it()
        self.assertEqual(code, 0)
        self.assertEqual(sent, [])
        self.assertIn('MANUAL -> AFTER_APPROVAL', printed)

    def test_with_yes_the_version_in_review_releases_itself(self):
        code, sent, _ = self.run_it('--yes')
        self.assertEqual(code, 0)
        url, body = sent[0]
        self.assertTrue(url.endswith('/v1/appStoreVersions/V9'))
        self.assertEqual(body['data']['attributes'], {'releaseType': 'AFTER_APPROVAL'})


class PlaySubmit(unittest.TestCase):
    def fake(self):
        return FakeStore({
            ('POST', '/edits'): {'id': 'E1'},
            ('GET', '/tracks'): {'tracks': [
                {'track': 'internal', 'releases': [
                    {'name': '2.0.0 (1)', 'versionCodes': ['1'], 'status': 'completed'},
                    {'name': '2.0.0 (3)', 'versionCodes': ['3'], 'status': 'completed'},
                ]},
            ]},
            ('GET', '/details'): {'defaultLanguage': 'en-GB'},
        })

    def run_submit(self, *flags):
        fake = self.fake()
        with mock.patch.object(play, '_token', return_value='t'), \
                mock.patch.object(play, 'call', fake), \
                contextlib.redirect_stdout(io.StringIO()) as printed:
            code = stores.main(['submit', 'run', '--android', *flags])
        return code, fake, printed.getvalue()

    def test_without_yes_it_only_plans_and_closes_the_edit(self):
        code, fake, printed = self.run_submit()
        self.assertEqual(code, 0)
        self.assertFalse(any(m == 'PUT' or u.endswith(':commit') for m, u in fake.sent))
        self.assertTrue(any(m == 'DELETE' for m, _ in fake.sent))  # the edit, discarded
        self.assertIn('2.0.0 (3)', printed)  # the newest internal build

    def test_with_yes_it_goes_to_everybody(self):
        sent_bodies = []
        fake = self.fake()

        def recording(method, url, **kwargs):
            if method == 'PUT':
                sent_bodies.append(kwargs['body'])
            return fake(method, url, **kwargs)

        with mock.patch.object(play, '_token', return_value='t'), \
                mock.patch.object(play, 'call', recording), \
                contextlib.redirect_stdout(io.StringIO()):
            code = stores.main(['submit', 'run', '--android', '--yes'])
        self.assertEqual(code, 0)
        release = sent_bodies[0]['releases'][0]
        self.assertEqual(sent_bodies[0]['track'], 'production')
        self.assertEqual(release['status'], 'completed')
        self.assertNotIn('userFraction', release)
        self.assertEqual(release['versionCodes'], ['3'])
        self.assertTrue(any(u.endswith(':commit') for _, u in fake.sent))


class Links(unittest.TestCase):
    """The public pages: Apple's by the app's id and what is on sale, Play's
    by whether the page itself answers."""

    def test_each_store_says_whether_its_page_is_live(self):
        apple = FakeStore({
            ('GET', '/v1/apps?'): {'data': [{'id': '6759969740', 'attributes': {'primaryLocale': 'en-GB'}}]},
            ('GET', '/appStoreVersions?'): {'data': [
                {'id': 'V2', 'attributes': {'versionString': '2.0.0', 'appVersionState': 'WAITING_FOR_REVIEW'}},
                {'id': 'V1', 'attributes': {'versionString': '1.4.0', 'appVersionState': 'READY_FOR_DISTRIBUTION'}},
            ]},
        })

        def play_page(method, url, **kwargs):
            raise play.StoreError(f'GET {url} refused (404): Not Found')

        with mock.patch.object(asc, '_token', return_value='t'), \
                mock.patch.object(asc, 'call', apple), \
                mock.patch.object(play, '_token', return_value='t'), \
                mock.patch.object(play, 'call', play_page), \
                contextlib.redirect_stdout(io.StringIO()) as printed:
            code = stores.main(['links', 'lift'])
        self.assertEqual(code, 0)
        self.assertIn('https://apps.apple.com/app/id6759969740 (on sale: 1.4.0)', printed.getvalue())
        self.assertIn('https://play.google.com/store/apps/details?id=com.mgkcodes.liftio (not live yet)',
                      printed.getvalue())


class PlayHeldForReview(unittest.TestCase):
    """Play refuses to send some edits for review from the API; they are then
    committed unsent, as its message asks, and the output says where to send them."""

    def test_the_release_waits_in_publishing_overview(self):
        fake = PlaySubmit.fake(self)

        def refusing(method, url, **kwargs):
            if url.endswith(':commit'):
                fake.sent.append((method, url))
                raise play.StoreError(
                    'POST https://androidpublisher.googleapis.com/... refused (400): Changes cannot '
                    'be sent for review automatically. Please set the query parameter '
                    'changesNotSentForReview to true.')
            return fake(method, url, **kwargs)

        with mock.patch.object(play, '_token', return_value='t'), \
                mock.patch.object(play, 'call', refusing), \
                contextlib.redirect_stdout(io.StringIO()) as printed:
            code = stores.main(['submit', 'run', '--android', '--yes'])
        self.assertEqual(code, 0)
        self.assertTrue(any(u.endswith(':commit?changesNotSentForReview=true') for _, u in fake.sent))
        self.assertFalse(any(m == 'DELETE' for m, _ in fake.sent))  # committed, not thrown away
        self.assertIn('Publishing overview', printed.getvalue())


class PlayPictures(unittest.TestCase):
    def test_the_icon_goes_up_with_the_screenshots(self):
        fake = FakeStore({
            ('POST', '/edits'): {'id': 'E1'},
            ('GET', '/details'): {'defaultLanguage': 'en-GB'},
        })
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'play-still').mkdir()
            (root / 'play-still' / '1-log.png').write_bytes(b'shot')
            icon = root / 'icon.png'
            icon.write_bytes(b'icon')
            with mock.patch.dict(stores.SHOTS, {'lift': root}), \
                    mock.patch.dict(stores.FEATURE, {'lift': root / 'none.png'}), \
                    mock.patch.dict(stores.ICON, {'lift': icon}), \
                    mock.patch.object(play, '_token', return_value='t'), \
                    mock.patch.object(play, 'call', fake), \
                    contextlib.redirect_stdout(io.StringIO()) as printed:
                code = stores.main(['screenshots', 'lift', '--android', '--yes'])
        self.assertEqual(code, 0)
        self.assertIn('the icon', printed.getvalue())
        posted = [u for m, u in fake.sent if m == 'POST']
        self.assertTrue(any('/listings/en-GB/icon?' in u for u in posted))
        self.assertFalse(any('/featureGraphic?' in u for u in posted))


def _png(path: Path, width: int, height: int, colour: int = 2) -> None:
    """Enough of a PNG for the size check: its header and an empty image."""
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    path.write_bytes(b'\x89PNG\r\n\x1a\n'
                     + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, colour, 0, 0, 0))
                     + chunk(b'IDAT', zlib.compress(b'')) + chunk(b'IEND', b''))


OPEN = {'id': 'V2', 'attributes': {'versionString': '2.0.1', 'appVersionState': 'PREPARE_FOR_SUBMISSION'}}
LIVE = {'id': 'V1', 'attributes': {'versionString': '2.0.0', 'appVersionState': 'READY_FOR_DISTRIBUTION'}}


def asset_answers(versions, spec='UNI', placed=None, included=None, library=None, videos=None):
    return {
        ('GET', '/v1/apps?'): {'data': [{'id': 'A1', 'attributes': {'primaryLocale': 'en-GB'}}]},
        ('GET', '/appStoreVersions?'): {'data': versions},
        ('GET', '/placements'): {'data': placed or [], 'included': included or []},
        ('GET', '/appStoreVersionLocalizations'): {
            'data': [{'id': 'L1', 'attributes': {'locale': 'en-GB'}}]},
        ('GET', '/assetLibrary'): {'data': {'type': 'appAssetLibraries', 'id': 'LIB'}},
        ('GET', '/appAssetLibraries/LIB/images'): {'data': library or []},
        ('GET', '/appAssetLibraries/LIB/videos'): {'data': videos or []},
        ('POST', '/v1/appAssetLibraryVideos'): {'data': {'id': 'VID1', 'attributes': {
            'state': 'AWAITING_UPLOAD', 'uploadOperations': [{
                'method': 'PUT', 'url': 'https://upload.example/VID1', 'offset': 0, 'length': 10,
                'requestHeaders': [{'name': 'Content-Type', 'value': 'video/mp4'}]}]}}},
        ('GET', '/v1/appAssetLibraryVideos/'): {'data': {'id': 'VID1', 'attributes': {
            'state': 'PREPARE_FOR_SUBMISSION', 'specId': 'HV'}}},
        ('POST', '/v1/appAssetLibraryImages'): {'data': {'id': 'IMG1', 'attributes': {
            'state': 'AWAITING_UPLOAD', 'uploadOperations': [{
                'method': 'PUT', 'url': 'https://upload.example/IMG1', 'offset': 0, 'length': 10,
                'requestHeaders': [{'name': 'Content-Type', 'value': 'image/png'}]}]}}},
        ('GET', '/v1/appAssetLibraryImages/'): {'data': {'id': 'IMG1', 'attributes': {
            'state': 'PREPARE_FOR_SUBMISSION', 'specId': spec}}},
        ('GET', '/v1/appAssetLibraryRefData'): {'data': [{'attributes': {
            'placementTypes': [
                {'placementTypeId': 'PRODUCT_PAGE_HEADER_ASSET', 'specMappings': [
                    {'placementGroupId': 'DEFAULT_PROFILE', 'specs': ['UNI', 'HDR', 'HV']}]},
                {'placementTypeId': 'APP_STORE_SEARCH_RESULTS_ASSET', 'specMappings': [
                    {'placementGroupId': 'DEFAULT_PROFILE', 'specs': ['UNI', 'SRCH']}]},
            ],
            'imageSpecs': [{'specId': 'UNI', 'shortName': 'i5244x2950a0'},
                           {'specId': 'HDR', 'shortName': 'i3840x1646a0'},
                           {'specId': 'SRCH', 'shortName': 'i3x2w1920~3840a0'}],
            'videoSpecs': [{'specId': 'HV', 'shortName': 'v3840x1646f30~60t15~30'}],
        }}]},
    }


class _Next:
    """An answer that changes on each request: the next one from [states]."""

    def __init__(self, states):
        self.states = states

    def resolve(self):
        return next(self.states)


class AppleAssets(unittest.TestCase):
    """The product page header and search results asset: checked on disk
    first, uploaded once, placed on every localization of the open version."""

    def run_assets(self, pictures, *flags, answers=None):
        sent = []
        fake = FakeStore(answers or asset_answers([OPEN, LIVE]))

        def recording(method, url, **kwargs):
            sent.append((method, url, kwargs))
            return fake(method, url, **kwargs)

        with tempfile.TemporaryDirectory() as folder:
            for name, (width, height) in pictures.items():
                if name.endswith('.mp4'):
                    # Not a real film: ffprobe is stood in for below.
                    (Path(folder) / name).write_bytes(b'0' * 64)
                else:
                    _png(Path(folder) / name, width, height)
            film = mock.patch.object(
                asc, '_video_facts', return_value=(3840, 1646, asc.Fraction(30), 15.0))
            with film, mock.patch.object(asc, '_token', return_value='t') as token, \
                    mock.patch.object(asc, 'call', recording), \
                    contextlib.redirect_stdout(io.StringIO()) as printed:
                code = stores.main(['assets', 'lift', '--from', folder, *flags])
        return code, sent, printed.getvalue(), token

    @staticmethod
    def writes(sent):
        return [(m, u, k) for m, u, k in sent if m != 'GET']

    def test_without_yes_it_only_plans(self):
        code, sent, printed, _ = self.run_assets({'universal.png': (5244, 2950)})
        self.assertEqual(code, 0)
        self.assertEqual(self.writes(sent), [])
        self.assertIn('universal.png (5244x2950): product page header and search results; upload it',
                      printed)
        self.assertIn('on version 2.0.1 (PREPARE_FOR_SUBMISSION), in en-GB', printed)
        self.assertIn('--yes', printed)

    def test_universal_fills_both_placements(self):
        code, sent, printed, _ = self.run_assets({'universal.png': (5244, 2950)}, '--yes')
        self.assertEqual(code, 0, printed)
        writes = self.writes(sent)
        reserved = [k['body'] for m, u, k in writes if u.endswith('/v1/appAssetLibraryImages')]
        self.assertEqual(len(reserved), 1)  # one upload for both
        self.assertEqual(reserved[0]['data']['attributes']['category'], 'CREATIVE_ASSETS')
        put = [k for m, u, k in writes if m == 'PUT']
        self.assertNotIn('token', put[0])  # the upload URL takes no key
        commit = [k['body'] for m, u, k in writes if m == 'PATCH']
        self.assertEqual(commit[0]['data']['attributes'], {'uploaded': True})
        placed = [k['body']['data'] for m, u, k in writes if u.endswith('/v1/appAssetLibraryPlacements')]
        self.assertEqual({p['attributes']['placementType'] for p in placed},
                         {'PRODUCT_PAGE_HEADER_ASSET', 'APP_STORE_SEARCH_RESULTS_ASSET'})
        for p in placed:
            self.assertEqual(p['attributes']['placementGroup'], 'DEFAULT_PROFILE')
            self.assertEqual(p['relationships']['image']['data']['id'], 'IMG1')
            self.assertEqual(p['relationships']['appStoreVersionLocalization']['data']['id'], 'L1')

    def test_header_with_universal_is_refused_before_anything_is_called(self):
        code, sent, printed, token = self.run_assets(
            {'universal.png': (5244, 2950), 'header.png': (3840, 1646)}, '--yes')
        self.assertEqual(code, 1)
        self.assertIn('universal.png fills both placements, so header.png cannot go with it', printed)
        self.assertEqual(sent, [])
        token.assert_not_called()

    def test_a_wrong_size_is_refused_with_the_size_expected(self):
        code, sent, printed, _ = self.run_assets({'universal.png': (5244, 2949)}, '--yes')
        self.assertEqual(code, 1)
        self.assertIn('universal.png is 5244x2949: it has to be 5244x2950 (16:9).', printed)
        self.assertEqual(sent, [])

    def test_no_version_open_means_upload_only(self):
        answers = asset_answers([LIVE])
        code, sent, printed, _ = self.run_assets({'universal.png': (5244, 2950)}, answers=answers)
        self.assertEqual(code, 0)
        self.assertEqual(self.writes(sent), [])
        self.assertIn('the placements wait for prepare', printed)
        code, sent, printed, _ = self.run_assets({'universal.png': (5244, 2950)}, '--yes', answers=answers)
        self.assertEqual(code, 0, printed)
        urls = [u for m, u, k in self.writes(sent)]
        self.assertTrue(any(u.endswith('/v1/appAssetLibraryImages') for u in urls))
        self.assertFalse(any('Placements' in u for u in urls))
        self.assertIn('uploaded only', printed)

    def test_what_is_placed_now_is_deleted_before_the_new_one_is_created(self):
        answers = asset_answers(
            [OPEN, LIVE], spec='HDR',
            placed=[{'id': 'OLD', 'attributes': {'placementType': 'PRODUCT_PAGE_HEADER_ASSET',
                                                 'mediaType': 'IMAGE'},
                     'relationships': {'image': {'data': {'type': 'appAssetLibraryImages', 'id': 'IMG0'}}}}],
            included=[{'type': 'appAssetLibraryImages', 'id': 'IMG0',
                       'attributes': {'fileName': 'old-header.png'}}])
        code, sent, printed, _ = self.run_assets({'header.png': (3840, 1646)}, answers=answers)
        self.assertIn('en-GB: product page header: delete the one there now (old-header.png), '
                      'then place header.png', printed)
        code, sent, printed, _ = self.run_assets({'header.png': (3840, 1646)}, '--yes', answers=answers)
        self.assertEqual(code, 0, printed)
        order = [(m, u.split('/v1/')[-1]) for m, u, k in self.writes(sent)]
        deleted = order.index(('DELETE', 'appAssetLibraryPlacements/OLD'))
        created = order.index(('POST', 'appAssetLibraryPlacements'))
        self.assertLess(deleted, created)
        self.assertEqual(sum(1 for o in order if o[1].startswith('appAssetLibraryPlacements')), 2)

    def test_an_asset_already_in_the_library_is_placed_not_uploaded_again(self):
        with tempfile.TemporaryDirectory() as folder:
            _png(Path(folder) / 'universal.png', 5244, 2950)
            size = (Path(folder) / 'universal.png').stat().st_size
        answers = asset_answers([OPEN, LIVE], library=[{'id': 'IMG1', 'attributes': {
            'fileName': 'universal.png', 'fileSize': size, 'state': 'APPROVED'}}])
        code, sent, printed, _ = self.run_assets({'universal.png': (5244, 2950)}, '--yes', answers=answers)
        self.assertEqual(code, 0, printed)
        urls = [u for m, u, k in self.writes(sent)]
        self.assertFalse(any(u.endswith('/v1/appAssetLibraryImages') for u in urls))
        self.assertEqual(sum(1 for u in urls if u.endswith('/v1/appAssetLibraryPlacements')), 2)

    def test_a_version_in_review_gets_nothing_placed_and_the_files_still_upload(self):
        # The Asset Library does not touch a version, so a version waiting on
        # Apple holds nothing back but its own placements.
        waiting = {'id': 'V2', 'attributes': {'versionString': '2.0.1', 'appVersionState': 'WAITING_FOR_REVIEW'}}
        code, sent, printed, _ = self.run_assets(
            {'universal.png': (5244, 2950)}, '--yes', answers=asset_answers([waiting, LIVE]))
        self.assertEqual(code, 0, printed)
        urls = [u for m, u, k in self.writes(sent)]
        self.assertTrue(any(u.endswith('/v1/appAssetLibraryImages') for u in urls))
        self.assertFalse(any('Placements' in u for u in urls))
        self.assertIn('2.0.1 is WAITING_FOR_REVIEW: nothing is placed on it', printed)

    def test_a_videos_opening_still_is_set_when_it_is_reserved(self):
        code, sent, printed, _ = self.run_assets(
            {'header.mp4': (3840, 1646)}, '--poster', '00:00:05:00', '--yes')
        self.assertEqual(code, 0, printed)
        reserve = [k for m, u, k in self.writes(sent) if u.endswith('/v1/appAssetLibraryVideos')]
        self.assertEqual(len(reserve), 1)
        attributes = reserve[0]['body']['data']['attributes']
        self.assertEqual(attributes['previewFrameTimeCode'], '00:00:05:00')
        self.assertIn('opening still 00:00:05:00', printed)

    def test_an_opening_still_past_the_end_is_refused_before_anything_is_sent(self):
        code, sent, printed, _ = self.run_assets(
            {'header.mp4': (3840, 1646)}, '--poster', '00:00:20:00', '--yes')
        self.assertEqual(code, 1)
        self.assertEqual(sent, [])
        self.assertIn('past the end of header.mp4', printed)

    def test_an_opening_still_frame_must_fit_the_frame_rate(self):
        code, sent, printed, _ = self.run_assets(
            {'header.mp4': (3840, 1646)}, '--poster', '00:00:05:30')
        self.assertEqual(code, 1)
        self.assertIn('runs 00 to 29', printed)

    def test_a_video_reporting_complete_is_still_processing(self):
        # Seen live: COMPLETE between the commit and PREPARE_FOR_SUBMISSION.
        answers = asset_answers([OPEN, LIVE])
        answers[('GET', '/v1/appAssetLibraryVideos/')] = {'data': {'id': 'VID1', 'attributes': {
            'state': 'COMPLETE', 'specId': None}}}
        ready = {'data': {'id': 'VID1', 'attributes': {'state': 'PREPARE_FOR_SUBMISSION', 'specId': 'HV'}}}
        states = iter([answers[('GET', '/v1/appAssetLibraryVideos/')], ready])
        answers[('GET', '/v1/appAssetLibraryVideos/')] = _Next(states)
        with mock.patch.object(asc.time, 'sleep'):
            code, sent, printed, _ = self.run_assets({'header.mp4': (3840, 1646)}, '--yes', answers=answers)
        self.assertEqual(code, 0, printed)
        self.assertIn('header.mp4: ready', printed)

    def test_a_reused_video_gets_its_opening_still_changed(self):
        with tempfile.TemporaryDirectory() as folder:
            (Path(folder) / 'header.mp4').write_bytes(b'0' * 64)
            size = (Path(folder) / 'header.mp4').stat().st_size
        answers = asset_answers([OPEN, LIVE], videos=[{'id': 'VID9', 'attributes': {
            'fileName': 'header.mp4', 'fileSize': size, 'state': 'PREPARE_FOR_SUBMISSION',
            'previewFrameTimeCode': '00:00:00:00'}}])
        code, sent, printed, _ = self.run_assets(
            {'header.mp4': (3840, 1646)}, '--poster', '00:00:05:00', '--yes', answers=answers)
        self.assertEqual(code, 0, printed)
        patches = [(u, k) for m, u, k in self.writes(sent) if m == 'PATCH']
        self.assertTrue(any(u.endswith('/v1/appAssetLibraryVideos/VID9')
                            and k['body']['data']['attributes'] == {'previewFrameTimeCode': '00:00:05:00'}
                            for u, k in patches), patches)
        self.assertFalse(any(u.endswith('/v1/appAssetLibraryVideos') for m, u, k in self.writes(sent)))


if __name__ == '__main__':
    unittest.main()
