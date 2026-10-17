"""Who is calling: verify the Cognito access token the frontend sends.

The browser signs in with Cognito (password or Google) and gets an access
token. Every API call carries it as `Authorization: Bearer <token>`. Here the
signature is checked against Cognito's public keys, together with the issuer,
the expiry, the token type and the app client. The token's `sub` - a stable id
that never changes, even if the person changes their email - is the owner of
every meeting they create.
"""

import logging
from dataclasses import dataclass
from functools import lru_cache
from typing import Annotated

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt import PyJWKClient

from app.config import Settings, get_settings

log = logging.getLogger("spry.auth")

# Shown in `docker compose up` (no Cognito there), never in production.
DEV_USER = "dev-user"

_bearer = HTTPBearer(auto_error=False)


@dataclass(frozen=True)
class User:
    id: str


def _unauthorized(detail: str = "Sign in to continue") -> HTTPException:
    return HTTPException(
        status.HTTP_401_UNAUTHORIZED, detail, headers={"WWW-Authenticate": "Bearer"}
    )


@lru_cache
def _jwks(issuer: str) -> PyJWKClient:
    # Fetches Cognito's keys on first use and keeps them (PyJWKClient caches).
    return PyJWKClient(f"{issuer}/.well-known/jwks.json", cache_keys=True)


def verify_token(token: str, settings: Settings) -> User:
    """Return the user a valid access token belongs to, or raise 401."""
    try:
        key = _jwks(settings.cognito_issuer).get_signing_key_from_jwt(token)
        claims = jwt.decode(
            token,
            key.key,
            algorithms=["RS256"],
            issuer=settings.cognito_issuer,
            options={"require": ["exp", "iss", "sub"], "verify_aud": False},
        )
    except jwt.PyJWTError as exc:
        log.info("rejected token: %s", exc)
        raise _unauthorized("Invalid or expired token") from exc

    # An access token has no `aud`; Cognito puts the app client in `client_id`.
    # An ID token (token_use "id") must not open the API.
    if claims.get("token_use") != "access" or claims.get("client_id") != settings.cognito_client_id:
        raise _unauthorized("Invalid token")
    return User(id=claims["sub"])


def current_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> User:
    settings = get_settings()
    if not settings.auth_configured:
        if settings.is_development:
            return User(id=DEV_USER)
        # Fail closed: a deployment without Cognito must not serve anyone's data.
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "Sign-in is not configured")
    if credentials is None:
        raise _unauthorized()
    return verify_token(credentials.credentials, settings)


UserDep = Annotated[User, Depends(current_user)]
