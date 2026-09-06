"""Local agent configuration generation and loading."""

from __future__ import annotations

import json
import os
import secrets
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, cast

DEFAULT_PORT = 8877
MIN_TOKEN_LENGTH = 32


def default_config_path() -> Path:
    return Path.home() / "Library" / "Application Support" / "OTP Grabber" / "agent.json"


@dataclass(frozen=True, slots=True)
class AgentConfig:
    port: int
    token: str
    allowed_origins: tuple[str, ...] = ()
    gmail_backend: str = "gws"
    gog_launcher: str | None = None
    gog_client: str | None = None
    gog_account: str | None = None


def _validate_port(port: int) -> int:
    if isinstance(port, bool) or not isinstance(port, int) or not 1 <= port <= 65535:
        raise ValueError("port must be an integer between 1 and 65535")
    return port


def _validate_token(token: str) -> str:
    if not isinstance(token, str) or len(token) < MIN_TOKEN_LENGTH:
        raise ValueError("token must contain at least 32 characters")
    return token


def _validate_gmail_backend(backend: object) -> str:
    if backend not in {"gws", "gog"}:
        raise ValueError("gmail_backend must be 'gws' or 'gog'")
    return cast(str, backend)


def _validate_gog_value(value: object, name: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{name} must be a non-empty string when gmail_backend is 'gog'")
    return value


def _validate_config(payload: object) -> AgentConfig:
    if not isinstance(payload, dict):
        raise ValueError("config must be a JSON object")
    origins = payload.get("allowed_origins", [])
    if not isinstance(origins, list) or not all(isinstance(origin, str) for origin in origins):
        raise ValueError("allowed_origins must be a list of strings")
    backend = _validate_gmail_backend(payload.get("gmail_backend", "gws"))
    gog_launcher: str | None = None
    gog_client: str | None = None
    gog_account: str | None = None
    if backend == "gog":
        gog_launcher = _validate_gog_value(payload.get("gog_launcher"), "gog_launcher")
        gog_client = _validate_gog_value(payload.get("gog_client"), "gog_client")
        gog_account = _validate_gog_value(payload.get("gog_account"), "gog_account")
    return AgentConfig(
        _validate_port(cast(int, payload.get("port"))),
        _validate_token(cast(str, payload.get("token"))),
        tuple(origins),
        backend,
        gog_launcher,
        gog_client,
        gog_account,
    )


def generate_config(
    path: Path | None = None,
    *,
    port: int = DEFAULT_PORT,
    token_factory: Callable[[], str] | None = None,
    allowed_origins: tuple[str, ...] = (),
    gmail_backend: str = "gws",
    gog_launcher: str | None = None,
    gog_client: str | None = None,
    gog_account: str | None = None,
) -> Path:
    """Create or replace a private minimal configuration file."""
    destination = Path(path) if path is not None else default_config_path()
    token = _validate_token((token_factory or (lambda: secrets.token_urlsafe(32)))())
    payload: dict[str, object] = {
        "port": _validate_port(port),
        "token": token,
        "allowed_origins": list(allowed_origins),
        "gmail_backend": _validate_gmail_backend(gmail_backend),
    }
    if gmail_backend == "gog":
        payload.update({
            "gog_launcher": gog_launcher,
            "gog_client": gog_client,
            "gog_account": gog_account,
        })
    _validate_config(payload)
    destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            json.dump(payload, output, separators=(",", ":"))
            output.write("\n")
    finally:
        os.chmod(destination, 0o600)
    return destination


def update_gmail_backend(
    path: Path,
    *,
    backend: str,
    gog_launcher: str | None = None,
    gog_client: str | None = None,
    gog_account: str | None = None,
) -> Path:
    """Atomically switch the configured Gmail backend, preserving core settings."""
    destination = Path(path)
    with destination.open(encoding="utf-8") as input_file:
        payload = json.load(input_file)
    if not isinstance(payload, dict):
        raise ValueError("config must be a JSON object")
    payload["gmail_backend"] = _validate_gmail_backend(backend)
    for key, value in (
        ("gog_launcher", gog_launcher),
        ("gog_client", gog_client),
        ("gog_account", gog_account),
    ):
        if backend == "gog":
            payload[key] = value
        else:
            payload.pop(key, None)
    _validate_config(payload)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{destination.name}.", dir=destination.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            json.dump(payload, output, separators=(",", ":"))
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, destination)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return destination


def load_config(path: Path | None = None) -> AgentConfig:
    source = Path(path) if path is not None else default_config_path()
    with source.open(encoding="utf-8") as input_file:
        payload = json.load(input_file)
    return _validate_config(payload)
