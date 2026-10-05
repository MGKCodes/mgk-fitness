"""What the store scripts share: the only two apps they may touch, where the
keys live, token signing, and one small HTTP helper.

Standard library and `cryptography` only, so nothing has to be installed to
use them (`cryptography` is already on the machine).
"""

from __future__ import annotations

import base64
import json
import os
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec, padding
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

# Hardcoded, like the Codemagic app id in scripts/codemagic-build.sh: the same
# App Store Connect key reaches every app on the MGKCodes team, Frunt's
# included, and nothing here should be able to change anything but these two.
APPS: dict[str, dict[str, str]] = {
    'run': {
        'name': 'MGKFitness: Run',
        'bundle': 'com.mgkcodes.fitness.run',
        'package': 'com.mgkcodes.fitness.run',
    },
    'lift': {
        'name': 'MGKFitness: Lift',
        'bundle': 'com.mgkcodes.liftio',
        'package': 'com.mgkcodes.liftio',
    },
}


class StoreError(Exception):
    """Something a store refused, or a key that is missing, said plainly."""


def keys_dir() -> Path:
    """Where the keys live: outside the repository, never committed."""
    return Path(os.environ.get('MGK_STORE_KEYS') or Path.home() / '.mgk-fitness')


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode('ascii')


def _segment(obj: dict) -> str:
    return b64url(json.dumps(obj, separators=(',', ':')).encode('utf-8'))


def es256_jwt(header: dict, claims: dict, key: ec.EllipticCurvePrivateKey) -> str:
    """A JWT signed ES256, as App Store Connect asks: the signature is r and s
    as two 32-byte integers, not the DER `cryptography` returns."""
    signing_input = f'{_segment(header)}.{_segment(claims)}'
    der = key.sign(signing_input.encode('ascii'), ec.ECDSA(hashes.SHA256()))
    r, s = decode_dss_signature(der)
    return f'{signing_input}.{b64url(r.to_bytes(32, "big") + s.to_bytes(32, "big"))}'


def rs256_jwt(claims: dict, key) -> str:
    """A JWT signed RS256, as Google's token endpoint asks."""
    signing_input = f'{_segment({"alg": "RS256", "typ": "JWT"})}.{_segment(claims)}'
    signature = key.sign(signing_input.encode('ascii'), padding.PKCS1v15(), hashes.SHA256())
    return f'{signing_input}.{b64url(signature)}'


def _redact(url: str) -> str:
    """The address without its query: upload URLs carry signatures."""
    parts = urllib.parse.urlsplit(url)
    return f'{parts.scheme}://{parts.netloc}{parts.path}'


def _summarise(detail: str) -> str:
    """The store's own words for what went wrong, without the noise."""
    try:
        body = json.loads(detail)
    except ValueError:
        return detail.strip()[:500]
    if isinstance(body.get('errors'), list):  # Apple
        return '; '.join(
            ' '.join(str(e.get(k)) for k in ('title', 'detail') if e.get(k))
            for e in body['errors']
        )
    if isinstance(body.get('error'), dict):  # Google
        return str(body['error'].get('message') or body['error'])
    if 'error_description' in body:  # Google's token endpoint
        return f"{body.get('error')}: {body['error_description']}"
    return detail.strip()[:500]


def call(
    method: str,
    url: str,
    *,
    token: str | None = None,
    body: dict | None = None,
    data: bytes | None = None,
    headers: dict[str, str] | None = None,
    expect_json: bool = True,
):
    """One request. A refusal raises StoreError with the store's own reason;
    no token or key ever appears in what is raised or printed."""
    sent = dict(headers or {})
    if token:
        sent['Authorization'] = f'Bearer {token}'
    payload = data
    if body is not None:
        payload = json.dumps(body).encode('utf-8')
        sent.setdefault('Content-Type', 'application/json')
    request = urllib.request.Request(url, data=payload, method=method, headers=sent)
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            raw = response.read()
    except urllib.error.HTTPError as e:
        reason = _summarise(e.read().decode('utf-8', 'replace'))
        raise StoreError(f'{method} {_redact(url)} refused ({e.code}): {reason}') from None
    except urllib.error.URLError as e:
        raise StoreError(f'{method} {_redact(url)} failed: {e.reason}') from None
    if not raw or not expect_json:
        return None
    return json.loads(raw)
