import time

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from httpx import AsyncClient

from app import auth
from app.config import Settings

SETTINGS = Settings(
    cognito_region="eu-north-1",
    cognito_user_pool_id="eu-north-1_abc",
    cognito_client_id="client-1",
)
KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)


class _Jwks:
    def get_signing_key_from_jwt(self, token: str):
        class Key:
            key = KEY.public_key()

        return Key()


@pytest.fixture(autouse=True)
def _cognito(monkeypatch):
    monkeypatch.setattr(auth, "get_settings", lambda: SETTINGS)
    monkeypatch.setattr(auth, "_jwks", lambda issuer: _Jwks())


def _token(**override) -> str:
    claims = {
        "sub": "user-ada",
        "iss": SETTINGS.cognito_issuer,
        "token_use": "access",
        "client_id": "client-1",
        "exp": int(time.time()) + 600,
        **override,
    }
    return jwt.encode(claims, KEY, algorithm="RS256")


def _bearer(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


@pytest.mark.parametrize(
    ("method", "path"),
    [
        ("GET", "/api/meetings"),
        ("POST", "/api/meetings"),
        ("GET", "/api/meetings/1"),
        ("PATCH", "/api/meetings/1"),
        ("DELETE", "/api/meetings/1"),
        ("GET", "/api/insights/week"),
        ("GET", "/api/agenda/readiness"),
        ("GET", "/api/deep-work/slots"),
        ("POST", "/api/deep-work/reserve"),
    ],
)
async def test_every_calendar_route_needs_a_token(anon_client: AsyncClient, method, path):
    res = await anon_client.request(method, path, json={})
    assert res.status_code == 401


async def test_health_stays_public(anon_client: AsyncClient):
    assert (await anon_client.get("/health")).status_code == 200


async def test_a_valid_access_token_opens_the_api(anon_client: AsyncClient):
    res = await anon_client.get("/api/meetings", headers=_bearer(_token()))
    assert res.status_code == 200


@pytest.mark.parametrize(
    "bad",
    [
        "not-a-jwt",
        _token(exp=int(time.time()) - 10),  # expired
        _token(iss="https://evil.example.com"),
        _token(client_id="someone-elses-app"),
        _token(token_use="id"),  # an ID token is not an access token
    ],
)
async def test_bad_tokens_are_rejected(anon_client: AsyncClient, bad):
    res = await anon_client.get("/api/meetings", headers=_bearer(bad))
    assert res.status_code == 401


async def test_token_signed_with_another_key_is_rejected(anon_client: AsyncClient):
    other = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    forged = jwt.encode(
        {
            "sub": "user-ada",
            "iss": SETTINGS.cognito_issuer,
            "token_use": "access",
            "client_id": "client-1",
            "exp": int(time.time()) + 600,
        },
        other,
        algorithm="RS256",
    )
    res = await anon_client.get("/api/meetings", headers=_bearer(forged))
    assert res.status_code == 401


async def test_unconfigured_production_fails_closed(anon_client: AsyncClient, monkeypatch):
    monkeypatch.setattr(auth, "get_settings", lambda: Settings(app_env="production"))
    res = await anon_client.get("/api/meetings")
    assert res.status_code == 503
