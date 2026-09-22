"""MCP server entrypoint: registers the 6 read-only MySQL exploration tools.

Config is loaded and the connection is validated at import time (not inside
main()) because `mcp dev` / `mcp run` import this module directly and call
mcp.run() themselves - see config.py's module docstring.
"""

from __future__ import annotations

import sys
from typing import Any, Callable, Literal, TypeVar

import mysql.connector
from mcp.server import MCPServer
from mcp.server.mcpserver.exceptions import ToolError

from .config import ConfigError, load_config
from .db import Database, DatabaseError, NotFoundError
from .models import DataMatch, QueryResult, SchemaMatch, TableInfo, TableSchema

try:
    _cfg = load_config()
except ConfigError as exc:
    print(f"[mysql-mcp-server] {exc}", file=sys.stderr)
    sys.exit(1)

try:
    _db = Database(_cfg)
    _db.check_connection()
except DatabaseError as exc:
    print(f"[mysql-mcp-server] {exc}", file=sys.stderr)
    sys.exit(1)

mcp = MCPServer("MySQL Explorer")

_T = TypeVar("_T")


def _handle(fn: Callable[..., _T], *args: Any, **kwargs: Any) -> _T:
    """Run a Database method, turning known failure modes into ToolError so
    the model sees a specific, actionable message instead of a raw traceback.
    """
    try:
        return fn(*args, **kwargs)
    except (NotFoundError, DatabaseError) as exc:
        raise ToolError(str(exc)) from exc
    except mysql.connector.Error as exc:
        raise ToolError(f"Error de MySQL: {exc}") from exc


@mcp.tool()
def list_databases(include_system: bool = False) -> list[str]:
    """List the databases visible on the configured MySQL connection.

    By default excludes MySQL's own system databases (information_schema,
    mysql, performance_schema, sys); pass include_system=True to see them too.
    """
    return _handle(_db.list_databases, include_system=include_system)


@mcp.tool()
def list_tables(database: str | None = None) -> list[TableInfo]:
    """List the tables/views in a database: name, type, engine, estimated row
    count, and comment. Defaults to the database configured in config.json.
    """
    return _handle(_db.list_tables, database)


@mcp.tool()
def describe_table(table: str, database: str | None = None) -> TableSchema:
    """Describe a table's schema: columns (types, nullability, defaults,
    primary key), indexes, and foreign keys. Use this once you know a table's
    name (from list_tables or search_schema) and need its structure before
    writing a query against it.
    """
    return _handle(_db.describe_table, table, database)


@mcp.tool()
def search_schema(
    pattern: str,
    database: str | None = None,
    search_in: Literal["tables", "columns", "both"] = "both",
    limit: int = 50,
) -> list[SchemaMatch]:
    """Search for tables and/or columns whose name contains `pattern`
    (case-insensitive substring match). Use this when you don't know the
    exact table/column name and need to find where something might live.
    """
    return _handle(_db.search_schema, pattern, database, search_in, limit)


@mcp.tool()
def search_data(
    pattern: str,
    table: str | None = None,
    database: str | None = None,
    columns: list[str] | None = None,
    limit: int = 50,
    max_tables_scanned: int = 25,
) -> list[DataMatch]:
    """Search for a literal text value inside text columns (CHAR/VARCHAR/TEXT/
    ENUM/SET) of one table, or across up to `max_tables_scanned` tables
    (smallest first) if `table` is not given. Use this to find *which*
    table/row holds a specific piece of information when you don't already
    know where to look. Restrict to specific columns with `columns` to
    narrow/speed up the search.
    """
    return _handle(_db.search_data, pattern, table, database, columns, limit, max_tables_scanned)


@mcp.tool()
def run_query(sql: str, params: list[Any] | None = None, max_rows: int = 200) -> QueryResult:
    """Run a read-only SQL query (SELECT/SHOW/DESCRIBE/EXPLAIN, or WITH ...
    SELECT). Any write or DDL statement (INSERT/UPDATE/DELETE/DROP/ALTER/
    CREATE/...) is rejected, both by text validation and by MySQL itself (the
    query runs inside a read-only transaction). Only one statement per call.
    `max_rows` is capped by the server's configured hard limit regardless of
    what is requested.
    """
    return _handle(_db.run_readonly, sql, params, max_rows)


def run() -> None:
    mcp.run()


if __name__ == "__main__":
    run()
