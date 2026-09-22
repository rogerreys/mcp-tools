import pytest


@pytest.fixture(autouse=True)
def _isolated_config_env(monkeypatch: pytest.MonkeyPatch) -> None:
    """Never let a stray MYSQL_MCP_CONFIG_PATH from the environment leak into
    tests; each test that needs config loading passes an explicit path.
    """
    monkeypatch.delenv("MYSQL_MCP_CONFIG_PATH", raising=False)
