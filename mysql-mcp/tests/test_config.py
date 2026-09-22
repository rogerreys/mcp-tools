import json
from pathlib import Path

import pytest

from mysql_mcp_server.config import AppConfig, ConfigError, load_config

VALID = {
    "host": "127.0.0.1",
    "port": 3306,
    "user": "readonly_user",
    "password": "secret",
    "database": "example_db",
}


def write_config(tmp_path: Path, content: str | dict) -> Path:
    path = tmp_path / "config.json"
    if isinstance(content, dict):
        path.write_text(json.dumps(content))
    else:
        path.write_text(content)
    return path


def test_missing_file_raises_config_error(tmp_path: Path) -> None:
    missing = tmp_path / "does-not-exist.json"
    with pytest.raises(ConfigError, match="No se encontró"):
        load_config(missing)


def test_invalid_json_raises_config_error(tmp_path: Path) -> None:
    path = write_config(tmp_path, "{not valid json")
    with pytest.raises(ConfigError, match="JSON válido"):
        load_config(path)


def test_non_object_json_raises_config_error(tmp_path: Path) -> None:
    path = write_config(tmp_path, "[1, 2, 3]")
    with pytest.raises(ConfigError, match="objeto JSON"):
        load_config(path)


@pytest.mark.parametrize("missing_field", ["host", "user", "password", "database"])
def test_missing_required_field_raises_config_error(tmp_path: Path, missing_field: str) -> None:
    data = dict(VALID)
    del data[missing_field]
    path = write_config(tmp_path, data)
    with pytest.raises(ConfigError, match=missing_field):
        load_config(path)


def test_valid_config_loads_with_defaults(tmp_path: Path) -> None:
    path = write_config(tmp_path, VALID)
    cfg = load_config(path)
    assert isinstance(cfg, AppConfig)
    assert cfg.host == "127.0.0.1"
    assert cfg.port == 3306
    assert cfg.pool_size == 5
    assert cfg.max_rows == 200
    assert cfg.max_rows_hard_limit == 1000


def test_error_messages_never_include_password(tmp_path: Path) -> None:
    data = dict(VALID)
    del data["host"]
    data["password"] = "super-secret-value"
    path = write_config(tmp_path, data)
    with pytest.raises(ConfigError) as exc_info:
        load_config(path)
    assert "super-secret-value" not in str(exc_info.value)


def test_max_rows_default_is_capped_to_hard_limit(tmp_path: Path) -> None:
    data = dict(VALID)
    data["max_rows"] = 5000
    data["max_rows_hard_limit"] = 1000
    path = write_config(tmp_path, data)
    cfg = load_config(path)
    assert cfg.max_rows == 1000
