"""Local agent configuration generation and loading."""

from __future__ import annotations

import json
import os
import secrets
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

DEFAULT_PORT = 8877
MIN_TOKEN_LENGTH = 32


def default_config_path() -> Path:
    return Path.home() / "Library" / "Application Support" / "OTP Grabber" / "agent.json"


@dataclass(frozen=True, slots=True)
class AgentConfig:
    port: int
    token: str
    allowed_origins: tuple[str, ...] = ()


def _validate_port(port: int) -> int:
    if isinstance(port, bool) or not isinstance(port, int) or not 1 <= port <= 65535:
        raise ValueError("port must be an integer between 1 and 65535")
    return port


def _validate_token(token: str) -> str:
    if not isinstance(token, str) or len(token) < MIN_TOKEN_LENGTH:
        raise ValueError("token must contain at least 32 characters")
    return token


def generate_config(
    path: Path | None = None,
    *,
    port: int = DEFAULT_PORT,
    token_factory: Callable[[], str] | None = None,
    allowed_origins: tuple[str, ...] = (),
) -> Path:
    """Create or replace a private minimal configuration file."""
    destination = Path(path) if path is not None else default_config_path()
    token = _validate_token((token_factory or (lambda: secrets.token_urlsafe(32)))())
    payload = {"port": _validate_port(port), "token": token, "allowed_origins": list(allowed_origins)}
    destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            json.dump(payload, output, separators=(",", ":"))
            output.write("\n")
    finally:
        os.chmod(destination, 0o600)
    return destination


def load_config(path: Path | None = None) -> AgentConfig:
    source = Path(path) if path is not None else default_config_path()
    with source.open(encoding="utf-8") as input_file:
        payload = json.load(input_file)
    if not isinstance(payload, dict):
        raise ValueError("config must be a JSON object")
    origins = payload.get("allowed_origins", [])
    if not isinstance(origins, list) or not all(isinstance(origin, str) for origin in origins):
        raise ValueError("allowed_origins must be a list of strings")
    return AgentConfig(_validate_port(payload.get("port")), _validate_token(payload.get("token")), tuple(origins))
