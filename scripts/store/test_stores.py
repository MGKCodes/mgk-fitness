"""Offline tests for the store scripts: signing, the apps they may touch, and
that nothing reaches a store without --yes.

    python -m unittest discover -s scripts/store -p "test_*.py"
"""

from __future__ import annotations

import base64
import contextlib
import io
import json
import sys
import tempfile
import unittest
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
                return answer
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


if __name__ == '__main__':
    unittest.main()
