#!/usr/bin/env python3
"""Minimal App Store Connect API client.

Usage: tools/asc.py GET /v1/apps?filter[bundleId]=com.zeyadamer.hotstash
       tools/asc.py PATCH /v1/appInfoLocalizations/<id> body.json

Needs env/AuthKey_<ASC_KEY_ID>.p8 (gitignored). Env overrides: ASC_KEY_ID, ASC_ISSUER_ID.
"""
import base64, json, os, subprocess, sys, tempfile, time, urllib.error, urllib.request

KEY_ID = os.environ.get("ASC_KEY_ID", "CM66SSALQR")
ISSUER = os.environ.get("ASC_ISSUER_ID", "a8b1c0c5-ff1d-4818-bade-241a4dc7dc7f")
KEY_PATH = os.path.join(os.path.dirname(__file__), "..", "env", f"AuthKey_{KEY_ID}.p8")


def b64url(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def token():
    now = int(time.time())
    header = b64url(json.dumps({"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}).encode())
    payload = b64url(json.dumps({"iss": ISSUER, "iat": now, "exp": now + 1140,
                                 "aud": "appstoreconnect-v1"}).encode())
    with tempfile.NamedTemporaryFile() as f:
        f.write(f"{header}.{payload}".encode())
        f.flush()
        der = subprocess.check_output(["openssl", "dgst", "-sha256", "-sign", KEY_PATH, f.name])
    # openssl emits a DER ECDSA signature; JWT wants raw r||s.
    i, raw = (2 if der[1] < 0x80 else 3), b""
    for _ in range(2):
        n = der[i + 1]
        raw += der[i + 2:i + 2 + n].lstrip(b"\0").rjust(32, b"\0")
        i += 2 + n
    return f"{header}.{payload}.{b64url(raw)}"


def api(method, path, body=None):
    req = urllib.request.Request(
        "https://api.appstoreconnect.apple.com" + path, method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            text = r.read().decode()
            return json.loads(text) if text else {}
    except urllib.error.HTTPError as e:
        sys.exit(f"{e.code} {e.read().decode()}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    body = json.load(open(sys.argv[3])) if len(sys.argv) > 3 else None
    print(json.dumps(api(sys.argv[1].upper(), sys.argv[2], body), indent=2))
