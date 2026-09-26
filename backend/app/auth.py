"""Email + password accounts with stateless signed tokens (stdlib only)."""

import base64
import hashlib
import hmac
import os
import time

from .config import settings

TOKEN_TTL = 60 * 60 * 24 * 30  # 30 days
_ITER = 200_000


def hash_password(password: str) -> str:
    salt = os.urandom(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, _ITER)
    return f"pbkdf2${_ITER}${salt.hex()}${digest.hex()}"


def verify_password(password: str, stored: str) -> bool:
    try:
        _, iters, salt, digest = stored.split("$")
    except ValueError:
        return False
    calc = hashlib.pbkdf2_hmac("sha256", password.encode(), bytes.fromhex(salt), int(iters))
    return hmac.compare_digest(calc.hex(), digest)


def _sign(payload: str) -> str:
    mac = hmac.new(settings.secret_key.encode(), payload.encode(), hashlib.sha256).digest()
    return base64.urlsafe_b64encode(mac).decode().rstrip("=")


def make_token(user_id: str) -> str:
    payload = f"{user_id}.{int(time.time()) + TOKEN_TTL}"
    return f"{payload}.{_sign(payload)}"


def read_token(token: str) -> str | None:
    """Returns the user id, or None if the token is invalid or expired."""
    try:
        user_id, exp, sig = token.rsplit(".", 2)
    except ValueError:
        return None
    if not hmac.compare_digest(sig, _sign(f"{user_id}.{exp}")) or int(exp) < time.time():
        return None
    return user_id
