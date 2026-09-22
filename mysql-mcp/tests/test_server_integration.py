"""Integration tests against a real MySQL instance.

Requires `docker compose -f mysql/docker-compose.yml up -d` (see README.md).
The whole module is skipped automatically if that MySQL isn't reachable, so
`uv run pytest` still passes without Docker.

Each test opens its own in-memory Client rather than sharing one via an
async fixture - an async generator fixture's setup/teardown can end up
running in different asyncio tasks under pytest-asyncio, which anyio's
Client rejects (`Attempted to exit cancel scope in a different task than it
was entered in`). Opening the client inside the test's own coroutine avoids
that entirely.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any

import mysql.connector
import pytest

from mcp import Client
from mcp.server import MCPServer
from mcp.types import CallToolResult

pytestmark = pytest.mark.integration

MYSQL_HOST = os.environ.get("MYSQL_MCP_TEST_HOST", "127.0.0.1")
MYSQL_PORT = int(os.environ.get("MYSQL_MCP_TEST_PORT", "3306"))
MYSQL_USER = "readonly_user"
MYSQL_PASSWORD = "readonly_password"
MYSQL_DATABASE = "example_db"


def _mysql_available() -> bool:
    try:
        cnx = mysql.connector.connect(
            host=MYSQL_HOST,
            port=MYSQL_PORT,
            user=MYSQL_USER,
            password=MYSQL_PASSWORD,
            database=MYSQL_DATABASE,
            connection_timeout=3,
        )
        cnx.close()
        return True
    except mysql.connector.Error:
        return False


@pytest.fixture(scope="module")
def mcp_server() -> MCPServer:
    if not _mysql_available():
        pytest.skip(
            f"MySQL de prueba no disponible en {MYSQL_HOST}:{MYSQL_PORT}. "
            f"Levanta 'docker compose -f mysql/docker-compose.yml up -d' primero."
        )

    config_path = Path(__file__).parent / "_integration_config.json"
    config_path.write_text(
        json.dumps(
            {
                "host": MYSQL_HOST,
                "port": MYSQL_PORT,
                "user": MYSQL_USER,
                "password": MYSQL_PASSWORD,
                "database": MYSQL_DATABASE,
            }
        )
    )
    os.environ["MYSQL_MCP_CONFIG_PATH"] = str(config_path)

    # server.py validates the connection and registers tools at import time;
    # force a fresh import bound to this test's config even if some other
    # test already imported (and thus cached) the module.
    for mod_name in [m for m in sys.modules if m.startswith("mysql_mcp_server")]:
        del sys.modules[mod_name]

    from mysql_mcp_server import server as server_module

    try:
        yield server_module.mcp
    finally:
        config_path.unlink(missing_ok=True)


async def _call(mcp_server: MCPServer, name: str, arguments: dict[str, Any]) -> CallToolResult:
    async with Client(mcp_server) as client:
        return await client.call_tool(name, arguments)


async def test_list_databases_includes_example_db(mcp_server: MCPServer) -> None:
    result = await _call(mcp_server, "list_databases", {})
    assert not result.is_error
    assert MYSQL_DATABASE in result.structured_content["result"]


async def test_list_tables_returns_seeded_tables(mcp_server: MCPServer) -> None:
    result = await _call(mcp_server, "list_tables", {})
    assert not result.is_error
    names = {t["name"] for t in result.structured_content["result"]}
    assert {"customers", "orders", "order_items"} <= names


async def test_list_tables_unknown_database_is_a_tool_error(mcp_server: MCPServer) -> None:
    result = await _call(mcp_server, "list_tables", {"database": "does_not_exist_db"})
    assert result.is_error
    assert "no existe" in result.content[0].text


async def test_describe_table_reports_columns_and_primary_key(mcp_server: MCPServer) -> None:
    result = await _call(mcp_server, "describe_table", {"table": "customers"})
    assert not result.is_error
    schema = result.structured_content
    col_names = {c["name"] for c in schema["columns"]}
    assert {"id", "full_name", "email", "phone", "notes", "created_at"} <= col_names
    pk_columns = {c["name"] for c in schema["columns"] if c["is_primary_key"]}
    assert pk_columns == {"id"}


async def test_describe_table_reports_foreign_key(mcp_server: MCPServer) -> None:
    result = await _call(mcp_server, "describe_table", {"table": "orders"})
    assert not result.is_error
    fks = result.structured_content["foreign_keys"]
    assert any(
        fk["column"] == "customer_id" and fk["references_table"] == "customers" for fk in fks
    )


async def test_describe_table_unknown_table_is_a_tool_error(mcp_server: MCPServer) -> None:
    result = await _call(mcp_server, "describe_table", {"table": "nope_not_a_table"})
    assert result.is_error
    assert "no existe" in result.content[0].text


async def test_search_schema_finds_tables_by_partial_name(mcp_server: MCPServer) -> None:
    result = await _call(mcp_server, "search_schema", {"pattern": "order", "search_in": "tables"})
    assert not result.is_error
    matched_tables = {m["table"] for m in result.structured_content["result"]}
    assert {"orders", "order_items"} <= matched_tables


async def test_search_data_finds_value_in_specific_table(mcp_server: MCPServer) -> None:
    result = await _call(mcp_server, "search_data", {"pattern": "Ana Torres", "table": "customers"})
    assert not result.is_error
    matches = result.structured_content["result"]
    assert any(m["column"] == "full_name" and "Ana Torres" in m["row"]["full_name"] for m in matches)


async def test_search_data_without_table_scans_multiple_tables(mcp_server: MCPServer) -> None:
    result = await _call(mcp_server, "search_data", {"pattern": "Falsa"})
    assert not result.is_error
    matches = result.structured_content["result"]
    assert any(m["table"] == "orders" for m in matches)


async def test_run_query_select_returns_rows(mcp_server: MCPServer) -> None:
    result = await _call(mcp_server, "run_query", {"sql": "SELECT COUNT(*) AS n FROM customers"})
    assert not result.is_error
    rows = result.structured_content["rows"]
    assert rows[0]["n"] == 4


@pytest.mark.parametrize(
    "sql",
    [
        "INSERT INTO customers (full_name, email) VALUES ('Hacker', 'h@x.com')",
        "UPDATE customers SET full_name = 'x' WHERE id = 1",
        "DELETE FROM customers WHERE id = 1",
        "DROP TABLE customers",
        "CREATE TABLE evil (id INT)",
    ],
)
async def test_run_query_rejects_writes(mcp_server: MCPServer, sql: str) -> None:
    result = await _call(mcp_server, "run_query", {"sql": sql})
    assert result.is_error

    # The row must genuinely be untouched, not just the tool call rejected -
    # this is the real proof that the read-only transaction backstop holds.
    verify = await _call(mcp_server, "run_query", {"sql": "SELECT COUNT(*) AS n FROM customers"})
    assert verify.structured_content["rows"][0]["n"] == 4


async def test_run_query_rejects_multiple_statements(mcp_server: MCPServer) -> None:
    result = await _call(mcp_server, "run_query", {"sql": "SELECT 1; DROP TABLE customers"})
    assert result.is_error
