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
    ('GET', '/appStoreVersionLocalizations'): {
        'data': [{'id': 'L1', 'attributes': {'locale': 'en-GB'}}]},
}


class AppleSubmit(unittest.TestCase):
    def run_submit(self, *flags):
        fake = FakeStore(APPLE)
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


if __name__ == '__main__':
    unittest.main()
