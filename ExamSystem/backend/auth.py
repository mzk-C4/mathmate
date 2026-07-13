import base64
import hashlib
import hmac
import json
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Annotated, Any

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from config import get_settings


@dataclass(frozen=True)
class AuthUser:
    user_id: str
    role: str


bearer_scheme = HTTPBearer(auto_error=False)


def _decode_segment(segment: str) -> dict[str, Any]:
    padding = "=" * (-len(segment) % 4)
    return json.loads(base64.urlsafe_b64decode(segment + padding))


def verify_token(token: str) -> AuthUser | None:
    try:
        header_segment, payload_segment, signature_segment = token.split(".")
        header = _decode_segment(header_segment)
        payload = _decode_segment(payload_segment)
        if header.get("alg") != "HS256":
            return None

        settings = get_settings()
        secret = Path(settings.auth_secret_path).read_text(encoding="utf-8").strip()
        expected = hmac.new(
            secret.encode("utf-8"),
            f"{header_segment}.{payload_segment}".encode("ascii"),
            hashlib.sha256,
        ).digest()
        padding = "=" * (-len(signature_segment) % 4)
        provided = base64.urlsafe_b64decode(signature_segment + padding)
        if not hmac.compare_digest(expected, provided):
            return None

        issued_at = int(payload.get("iat", 0))
        expires_at = int(payload.get("exp", 0))
        now = int(time.time())
        if issued_at <= 0 or issued_at > now + 300:
            return None
        if expires_at <= now or expires_at < issued_at:
            return None
        if now - issued_at > settings.auth_token_max_age_seconds:
            return None

        user_id = str(payload.get("uid") or "").strip()
        role = str(payload.get("role") or "student").strip()
        return AuthUser(user_id=user_id, role=role) if user_id else None
    except (OSError, ValueError, TypeError, json.JSONDecodeError):
        return None


def require_user(
    credentials: Annotated[
        HTTPAuthorizationCredentials | None,
        Depends(bearer_scheme),
    ],
) -> AuthUser:
    user = verify_token(credentials.credentials) if credentials else None
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Valid Bearer token required",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user


def require_admin(user: Annotated[AuthUser, Depends(require_user)]) -> AuthUser:
    if user.role not in {"admin", "dev"}:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin role required",
        )
    return user


def ensure_owner(user: AuthUser, student_id: str | None) -> None:
    if user.role not in {"admin", "dev"} and str(student_id or "") != user.user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Exam access denied",
        )
