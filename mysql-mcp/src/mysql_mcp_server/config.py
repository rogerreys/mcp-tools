"""Loading and validation of the connection config.json.

The path is resolved from the MYSQL_MCP_CONFIG_PATH environment variable,
falling back to ./config.json (relative to the current working directory).
This is deliberately env-var driven (not argparse) because `mcp dev` / `mcp
run` import server.py directly and call run() themselves, without going
through any CLI argument parsing of ours.
"""

from __future__ import annotations

import json
import os
from pathlib import Path

from pydantic import BaseModel, Field, ValidationError

DEFAULT_CONFIG_PATH = "config.json"
CONFIG_PATH_ENV_VAR = "MYSQL_MCP_CONFIG_PATH"


class ConfigError(Exception):
    """Raised when config.json is missing, malformed, or invalid."""


class AppConfig(BaseModel):
    host: str
    port: int = 3306
    user: str
    password: str
    database: str

    pool_size: int = Field(default=5, ge=1, le=32)
    connect_timeout_s: int = Field(default=10, ge=1)
    query_timeout_ms: int = Field(default=15_000, ge=100)
    max_rows: int = Field(default=200, ge=1)
    max_rows_hard_limit: int = Field(default=1000, ge=1)

    def model_post_init(self, __context: object) -> None:
        if self.max_rows > self.max_rows_hard_limit:
            # Keep the default sane relative to the hard cap rather than raising,
            # since a caller-supplied default shouldn't ever exceed the hard cap.
            object.__setattr__(self, "max_rows", self.max_rows_hard_limit)


def resolve_config_path() -> Path:
    raw = os.environ.get(CONFIG_PATH_ENV_VAR, DEFAULT_CONFIG_PATH)
    return Path(raw).expanduser().resolve()


def load_config(path: Path | None = None) -> AppConfig:
    """Load and validate config.json. Raises ConfigError with an actionable
    message on any problem. Never includes the password in an error message.
    """
    resolved = path or resolve_config_path()

    if not resolved.is_file():
        raise ConfigError(
            f"No se encontró el archivo de configuración en '{resolved}'. "
            f"Crea uno a partir de config.example.json, o define la variable de "
            f"entorno {CONFIG_PATH_ENV_VAR} apuntando a tu config.json."
        )

    try:
        raw_text = resolved.read_text(encoding="utf-8")
    except OSError as exc:
        raise ConfigError(f"No se pudo leer '{resolved}': {exc}") from exc

    try:
        data = json.loads(raw_text)
    except json.JSONDecodeError as exc:
        raise ConfigError(
            f"El archivo de configuración '{resolved}' no es JSON válido: {exc}"
        ) from exc

    if not isinstance(data, dict):
        raise ConfigError(
            f"El archivo de configuración '{resolved}' debe contener un objeto JSON "
            f"(host, port, user, password, database, ...), no un {type(data).__name__}."
        )

    try:
        return AppConfig.model_validate(data)
    except ValidationError as exc:
        missing_or_invalid = "; ".join(
            f"{'.'.join(str(p) for p in err['loc'])}: {err['msg']}" for err in exc.errors()
        )
        raise ConfigError(
            f"Configuración inválida en '{resolved}': {missing_or_invalid}. "
            f"Revisa config.example.json para ver los campos requeridos."
        ) from exc
