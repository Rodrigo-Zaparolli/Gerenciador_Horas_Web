"""Verify Firebase user tokens with public signing keys, without admin credentials."""
import cachecontrol
import requests
from google.auth.transport.requests import Request
from google.oauth2 import id_token

PROJECT_ID = "gerenciador-horas"
_request = Request(session=cachecontrol.CacheControl(requests.Session()))


def _fetch_certificates(url, method="GET", **kwargs):
    return _request(url, method=method, timeout=10, **kwargs)


def verify_token(token):
    claims = id_token.verify_firebase_token(token, _fetch_certificates, audience=PROJECT_ID)
    if claims.get("iss") != f"https://securetoken.google.com/{PROJECT_ID}":
        raise ValueError("Invalid issuer")
    subject = claims.get("sub")
    if not isinstance(subject, str) or not subject or len(subject) > 128:
        raise ValueError("Invalid subject")
    return claims
