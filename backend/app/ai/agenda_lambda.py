"""agenda-parser: the backend image with another handler, behind a function URL.

Outside the VPC (it needs the internet for Bedrock and Cognito's keys, and never
touches the database). It receives text and returns JSON; it writes nothing. The
person checks the pre-filled form and saves it through the normal API.

Every call costs money, so it is authenticated: a missing or invalid Cognito
access token is a 401, and text over 10,000 characters is a 413 before the model
is called. CORS is answered by the function URL itself (infra/ai.yml).
"""

from __future__ import annotations

import base64
import json
import logging
import time
from datetime import date
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import HTTPException

from app.ai.agenda import (
    MAX_TEXT_CHARS,
    PROMPT_VERSION,
    AgendaParseError,
    ParserConfig,
    cost_usd,
    parse_agenda,
)
from app.auth import User, verify_token
from app.config import get_settings

log = logging.getLogger()
log.setLevel(logging.INFO)


BUSY = "The AI service is busy, try again in a moment"


def _response(status: int, body: dict[str, Any]) -> dict[str, Any]:
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body),
    }


def _authenticate(event: dict[str, Any]) -> User | None:
    header = (event.get("headers") or {}).get("authorization", "")
    scheme, _, token = header.partition(" ")
    if scheme.lower() != "bearer" or not token:
        return None
    settings = get_settings()
    if not settings.auth_configured:  # fail closed: no Cognito, no parsing
        return None
    try:
        return verify_token(token, settings)
    except HTTPException:
        return None


def _body(event: dict[str, Any]) -> dict[str, Any] | None:
    raw = event.get("body") or ""
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw).decode("utf-8", errors="replace")
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return None
    return data if isinstance(data, dict) else None


def handler(event, context=None, *, parse=parse_agenda, config: ParserConfig | None = None):
    """`parse` and `config` are injection points for tests."""
    user = _authenticate(event)
    if user is None:
        return _response(401, {"error": "Sign in to parse an agenda"})

    data = _body(event)
    if data is None or not isinstance(data.get("text"), str) or not data["text"].strip():
        return _response(400, {"error": "Send JSON with a non-empty 'text'"})
    text: str = data["text"]
    if len(text) > MAX_TEXT_CHARS:
        return _response(413, {"error": f"Text is longer than {MAX_TEXT_CHARS} characters"})
    try:
        today = date.fromisoformat(str(data.get("today")))
        tz = str(data.get("tz"))
        ZoneInfo(tz)
    except (ValueError, ZoneInfoNotFoundError):
        return _response(400, {"error": "Send 'today' as YYYY-MM-DD and 'tz' as a time zone name"})

    config = config or ParserConfig.from_env()
    started = time.monotonic()
    try:
        agenda, usage = parse(text, today, tz, config=config)
    except AgendaParseError as exc:
        return _response(422, {"error": str(exc)})
    except Exception as exc:  # noqa: BLE001 - map the SDK's errors without importing it here
        status = getattr(exc, "status_code", None)
        if type(exc).__name__ == "RateLimitError" or status in (429, 503, 529):
            # Throttled, or Bedrock is overloaded / temporarily unavailable: try again later.
            log.warning("agenda_parse busy (status=%s): %s", status, exc)
            return _response(503 if status != 429 else 429, {"error": BUSY})
        log.exception("agenda_parse failed")
        return _response(502, {"error": "The AI service is unavailable"})

    log.info(
        json.dumps(
            {
                "event": "agenda_parsed",
                "user": user.id,
                "model": config.model,
                "prompt_version": PROMPT_VERSION,
                **usage,
                "latency_ms": int((time.monotonic() - started) * 1000),
                "cost_usd": cost_usd(config.model, usage),
            }
        )
    )
    return _response(
        200,
        {
            "agenda": agenda.model_dump(mode="json"),
            "model": config.model,
            "prompt_version": PROMPT_VERSION,
        },
    )
