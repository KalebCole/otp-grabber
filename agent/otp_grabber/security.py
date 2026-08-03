"""Security primitives for the local API."""

from __future__ import annotations

import hmac


def constant_time_token_match(expected: str, provided: str) -> bool:
    """Compare bearer tokens without leaking a matching prefix."""
    if not isinstance(expected, str) or not isinstance(provided, str):
        return False
    return hmac.compare_digest(expected.encode("utf-8"), provided.encode("utf-8"))


def extract_bearer_token(value: str | None) -> str | None:
    if not isinstance(value, str) or not value.startswith("Bearer "):
        return None
    token = value[7:]
    return token if token else None
