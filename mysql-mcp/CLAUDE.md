# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A read-only MCP (Model Context Protocol) server, in Python, that lets a model explore an unfamiliar MySQL database: list databases/tables, describe a table's schema, search for tables/columns by partial name, search for a literal value across table data, and run arbitrary read-only SQL. Connection details (host, port, user, password, database) come from a `config.json`, never from arguments passed by the model. See [README.md](README.md) for the user-facing setup/usage docs — this file covers what a future Claude instance needs to safely modify the code.

## Commands

```bash
uv sync                                           # install deps (creates .venv)
uv run pytest                                     # all tests; integration tests auto-skip if MySQL isn't reachable
uv run pytest tests/test_sql_guard.py -v          # single file
uv run pytest tests/test_sql_guard.py::test_forbidden_statements_are_rejected -v  # single test (parametrized: add -k "DROP" to hit one case)

docker compose -f mysql/docker-compose.yml up -d  # start the disposable MySQL used by tests/test_server_integration.py
uv run pytest -v                                  # now the 16 integration tests run for real instead of skipping
docker compose -f mysql/docker-compose.yml down -v

uv run python -m mysql_mcp_server --config config.json   # run the server (stdio transport)
uv run mcp dev src/mysql_mcp_server/server.py             # MCP Inspector, interactive tool testing (needs npx)
```

There is no separate lint command configured; there's also no `config.json` committed (see Config below) — copy `config.example.json` before running anything that touches a real database.

## Architecture

**Read-only enforcement is the central design constraint, and it's deliberately two layers, not one:**

1. `sql_guard.py` — `validate_readonly_sql()` rejects obviously unsafe SQL *text* before any network call: only `SELECT/SHOW/DESCRIBE/EXPLAIN/WITH` as the first keyword, a blacklist of write/DDL keywords scanned across the whole statement (catches them inside a `WITH` or subquery too), no multi-statement input, no `INTO OUTFILE/DUMPFILE`.
2. `db.py` — every user-supplied query in `Database.run_readonly()` executes inside a real MySQL `START TRANSACTION READ ONLY` transaction, followed by an unconditional rollback. **This is the actual guarantee** — MySQL itself rejects any write attempt (error 1792) even if something slipped past the text guard, regardless of the configured MySQL user's real privileges. Multi-statement execution is never enabled on the connection either, so the driver itself rejects stacked queries.

When changing either layer, keep both — the text guard exists for fast, specific error messages; the transaction is what actually can't be bypassed. `tests/test_server_integration.py::test_run_query_rejects_writes` verifies the real guarantee end-to-end (it checks the row is genuinely unchanged after a rejected write, not just that the tool call failed) — that's the test to run after touching this logic.

**SQL-identifier injection**: `table`/`database`/`column` arguments from tool calls are never interpolated directly into SQL. `Database._resolve_database()` / `_resolve_table()` first check the name against `information_schema` with a parametrized query, and only the *value returned by that query* is used (backtick-quoted) in dynamic SQL — see `search_data()` for the pattern when building a query over caller-chosen columns.

**`information_schema` casing gotcha (MySQL 8.4)**: `information_schema` returns column metadata (`COLUMN_NAME`, `DATA_TYPE`, ...) in uppercase regardless of how the SELECT list is written, so `mysql.connector`'s dictionary cursor hands back uppercase dict keys unless every column is aliased. `db._lower_keys()` normalizes this once after every `information_schema` fetch — use it (don't add per-query aliases) when adding new `information_schema` queries.

**Module-import-time startup**: `server.py` loads config and validates the DB connection at *import* time (not inside a `main()`), because `mcp dev`/`mcp run` import `server.py` directly and call `mcp.run()` themselves — they never go through `__main__.py`'s argparse. `__main__.py` is only a convenience that sets `MYSQL_MCP_CONFIG_PATH` from `--config` before importing `server`. Any change to how config/connection is initialized must keep working when the module is imported directly, not just via the CLI entrypoint.

**Error surfacing**: tool functions in `server.py` call `Database` methods through the local `_handle()` wrapper, which converts `NotFoundError`/`DatabaseError`/`mysql.connector.Error` into `ToolError` (from `mcp.server.mcpserver.exceptions`) with the specific message — these reach the model as readable text. Anything else (a real bug) surfaces as `UnexpectedToolError` with a generic message instead of a stack trace; that's intentional, don't broaden the except clauses in `_handle()` to swallow unexpected exceptions silently.

**MCP SDK v2 API note**: this uses `mcp>=2.1` (`from mcp.server import MCPServer`, decorators unchanged from the old FastMCP naming). Structured tool output shape depends on the return type annotation: a single Pydantic model returns as the model dict directly; `list[Model]` / `list[str]` wraps as `{"result": [...]}`. Keep return-type annotations accurate — they drive both the JSON schema shown to the model and this wrapping behavior.

## Key files

- `src/mysql_mcp_server/server.py` — MCP server instance, the 6 `@mcp.tool()` definitions, error wrapping.
- `src/mysql_mcp_server/db.py` — connection pool, read-only transaction enforcement, all `information_schema` queries.
- `src/mysql_mcp_server/sql_guard.py` — text-level SQL validation (layer 1 above).
- `src/mysql_mcp_server/config.py` — `config.json` loading/validation (Pydantic `AppConfig`), env var `MYSQL_MCP_CONFIG_PATH`.
- `src/mysql_mcp_server/models.py` — Pydantic response models (drive the structured tool output).
- `mysql/docker-compose.yml` + `mysql/init/01-seed.sql` — disposable MySQL + seed schema used only by `tests/test_server_integration.py`; not part of the served application.

Code doesn't live under `mysql/` because `mysql-connector-python` occupies the `mysql` import namespace (`mysql.connector`) — a package named `mysql/` at the repo root would collide with it.
