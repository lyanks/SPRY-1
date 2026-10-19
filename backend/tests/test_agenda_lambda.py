"""The agenda-parser handler: auth, limits, error mapping and the one log line."""

import base64
import json
import logging
import time

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa

from app import auth
from app.ai import agenda_lambda
from app.ai.agenda import AgendaParseError, ParsedAgenda, ParserConfig
from app.config import Settings

SETTINGS = Settings(
    cognito_region="eu-north-1",
    cognito_user_pool_id="eu-north-1_abc",
    cognito_client_id="client-1",
)
KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
CONFIG = ParserConfig(model="anthropic.claude-haiku-5-5", region="us-east-1", effort="low")


class _Jwks:
    def get_signing_key_from_jwt(self, token):
        class Key:
            key = KEY.public_key()

        return Key()


@pytest.fixture(autouse=True)
def _cognito(monkeypatch):
    monkeypatch.setattr(agenda_lambda, "get_settings", lambda: SETTINGS)
    monkeypatch.setattr(auth, "_jwks", lambda issuer: _Jwks())


def _token(**override):
    claims = {
        "sub": "user-ada",
        "iss": SETTINGS.cognito_issuer,
        "token_use": "access",
        "client_id": "client-1",
        "exp": int(time.time()) + 600,
        **override,
    }
    return jwt.encode(claims, KEY, algorithm="RS256")


def _event(body=None, *, token="ok", base64_body=False):
    raw = json.dumps(body) if not isinstance(body, str) else body
    if base64_body:
        raw = base64.b64encode(raw.encode()).decode()
    headers = {}
    if token:
        headers["authorization"] = f"Bearer {_token() if token == 'ok' else token}"
    return {"headers": headers, "body": raw, "isBase64Encoded": base64_body}


GOOD_BODY = {"text": "Mon 10:00 sync", "today": "2026-10-19", "tz": "Europe/Kyiv"}


def _parse_ok(text, today, tz, *, config):
    return ParsedAgenda(title="sync", items=[], language="en"), {
        "input_tokens": 2000,
        "output_tokens": 500,
    }


def _call(event, parse=_parse_ok):
    return agenda_lambda.handler(event, None, parse=parse, config=CONFIG)


def test_returns_the_agenda_and_logs_one_line(caplog):
    with caplog.at_level(logging.INFO):
        res = _call(_event(GOOD_BODY))
    assert res["statusCode"] == 200
    body = json.loads(res["body"])
    assert body["agenda"]["title"] == "sync"
    assert body["model"] == "anthropic.claude-haiku-5-5"
    assert body["prompt_version"] == "agenda-v1"
    lines = [json.loads(r.message) for r in caplog.records if r.message.startswith("{")]
    assert len(lines) == 1
    assert lines[0]["event"] == "agenda_parsed"
    assert lines[0]["user"] == "user-ada"
    assert lines[0]["input_tokens"] == 2000 and lines[0]["output_tokens"] == 500
    assert lines[0]["cost_usd"] == pytest.approx(0.00045)
    assert "latency_ms" in lines[0]


def test_base64_body():
    assert _call(_event(GOOD_BODY, base64_body=True))["statusCode"] == 200


@pytest.mark.parametrize(
    "token",
    [None, "garbage", _token(token_use="id"), _token(client_id="other"), _token(exp=1)],
)
def test_401_without_a_valid_access_token(token):
    called = []
    res = _call(_event(GOOD_BODY, token=token), parse=lambda *a, **k: called.append(1))
    assert res["statusCode"] == 401
    assert not called  # the model is never called for a stranger


def test_401_when_cognito_is_not_configured(monkeypatch):
    monkeypatch.setattr(agenda_lambda, "get_settings", lambda: Settings())
    assert _call(_event(GOOD_BODY))["statusCode"] == 401


def test_413_before_the_model_is_called():
    called = []
    big = {**GOOD_BODY, "text": "x" * 10_001}
    res = _call(_event(big), parse=lambda *a, **k: called.append(1))
    assert res["statusCode"] == 413 and not called
    assert _call(_event({**GOOD_BODY, "text": "x" * 10_000}))["statusCode"] == 200


@pytest.mark.parametrize(
    "body",
    [
        "not json",
        [],
        {**GOOD_BODY, "text": ""},
        {**GOOD_BODY, "text": "   "},
        {**GOOD_BODY, "text": 5},
        {**GOOD_BODY, "today": "Monday"},
        {**GOOD_BODY, "tz": "Mars/Base"},
        {"text": "x"},
    ],
)
def test_400_on_a_bad_body(body):
    assert _call(_event(body))["statusCode"] == 400


def test_422_when_no_agenda_is_found():
    def nope(*a, **k):
        raise AgendaParseError("no agenda returned (stop_reason=refusal)")

    res = _call(_event(GOOD_BODY), parse=nope)
    assert res["statusCode"] == 422
    assert "refusal" in json.loads(res["body"])["error"]


def test_429_when_bedrock_throttles():
    class RateLimitError(Exception):
        status_code = 429

    def throttled(*a, **k):
        raise RateLimitError("slow down")

    res = _call(_event(GOOD_BODY), parse=throttled)
    assert res["statusCode"] == 429
    assert "busy" in json.loads(res["body"])["error"]


@pytest.mark.parametrize("status", [503, 529])
def test_503_when_bedrock_is_overloaded_or_unavailable(status):
    class ServiceUnavailableError(Exception):
        status_code = 503

    err = ServiceUnavailableError("down")
    err.status_code = status

    def down(*a, **k):
        raise err

    res = _call(_event(GOOD_BODY), parse=down)
    assert res["statusCode"] == 503
    assert "busy" in json.loads(res["body"])["error"]


def test_502_on_anything_else():
    def boom(*a, **k):
        raise ConnectionError("nope")

    assert _call(_event(GOOD_BODY), parse=boom)["statusCode"] == 502
