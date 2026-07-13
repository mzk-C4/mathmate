import base64
import hashlib
import hmac
import json
import time

from auth import verify_token
from config import get_settings


def _encode(value: dict) -> str:
    return base64.urlsafe_b64encode(
        json.dumps(value, separators=(",", ":")).encode()
    ).decode().rstrip("=")


def _token(secret: bytes, payload: dict) -> str:
    header = _encode({"alg": "HS256", "typ": "JWT"})
    body = _encode(payload)
    signature = base64.urlsafe_b64encode(
        hmac.new(secret, f"{header}.{body}".encode(), hashlib.sha256).digest()
    ).decode().rstrip("=")
    return f"{header}.{body}.{signature}"


def test_verify_token_matches_auth_server_format(tmp_path, monkeypatch):
    secret_path = tmp_path / "secret.txt"
    secret_path.write_text("test-secret", encoding="utf-8")
    monkeypatch.setenv("AUTH_SECRET_PATH", str(secret_path))
    monkeypatch.setenv("AUTH_TOKEN_MAX_AGE_SECONDS", "3600")
    get_settings.cache_clear()
    now = int(time.time())

    user = verify_token(
        _token(
            b"test-secret",
            {
                "uid": "student-1",
                "role": "student",
                "iat": now,
                "exp": now + 600,
            },
        )
    )

    assert user is not None
    assert user.user_id == "student-1"
    assert user.role == "student"
    get_settings.cache_clear()


def test_verify_token_rejects_expired_token(tmp_path, monkeypatch):
    secret_path = tmp_path / "secret.txt"
    secret_path.write_text("test-secret", encoding="utf-8")
    monkeypatch.setenv("AUTH_SECRET_PATH", str(secret_path))
    get_settings.cache_clear()
    now = int(time.time())

    assert verify_token(
        _token(
            b"test-secret",
            {
                "uid": "student-1",
                "role": "student",
                "iat": now - 600,
                "exp": now - 1,
            },
        )
    ) is None
    get_settings.cache_clear()


def test_verify_token_rejects_bad_signature(tmp_path, monkeypatch):
    secret_path = tmp_path / "secret.txt"
    secret_path.write_text("test-secret", encoding="utf-8")
    monkeypatch.setenv("AUTH_SECRET_PATH", str(secret_path))
    get_settings.cache_clear()
    assert verify_token("bad.token.signature") is None
    get_settings.cache_clear()
