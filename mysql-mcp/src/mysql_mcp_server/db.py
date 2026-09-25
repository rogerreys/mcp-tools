"""MySQL connection pooling and the real, engine-level read-only enforcement.

Enforcement has two layers:
  1. sql_guard.validate_readonly_sql() rejects obviously unsafe SQL text
     before touching the network.
  2. Every user-supplied query in run_readonly() executes inside a MySQL
     `START TRANSACTION READ ONLY` transaction, followed by an unconditional
     rollback. MySQL itself rejects any write attempt in that transaction
     (error 1792) even if something slipped past the text guard. Multi-
     statement execution is never enabled on the connection, so stacked
     queries (`SELECT 1; DROP TABLE x`) are rejected by the driver too.

Any table/database/column name that arrives as a tool argument is treated as
untrusted data, never interpolated directly as a SQL identifier: it is first
checked for existence against information_schema with a parametrized query,
and only the value *returned by that query* is used (quoted with backticks)
when building dynamic SQL. This means an attacker-controlled identifier can
never appear in a query unless it already matches a real object name.
"""

from __future__ import annotations

import re
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator, Literal

import mysql.connector
from mysql.connector import errorcode
from mysql.connector.pooling import MySQLConnectionPool

from .config import AppConfig
from .models import (
    ColumnInfo,
    DataMatch,
    ForeignKeyInfo,
    IndexInfo,
    QueryResult,
    SchemaMatch,
    ScriptResult,
    ScriptStatementResult,
    TableInfo,
    TableSchema,
)
from .sql_guard import (
    SqlNotAllowedError,
    extract_assigned_variables,
    is_pure_variable_assignment,
    split_script_statements,
    validate_readonly_sql,
)

SYSTEM_DATABASES = {"information_schema", "mysql", "performance_schema", "sys"}
_TEXT_DATA_TYPES = {"char", "varchar", "text", "tinytext", "mediumtext", "longtext", "enum", "set"}

# Plain filename only (no path separators/traversal), must end in .sql. '&' is
# allowed because it shows up in real script filenames in this project.
_SCRIPT_NAME_RE = re.compile(r"^[A-Za-z0-9_.&-]+\.sql$")
_VAR_NAME_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")

# MySQL error codes not exposed by name in mysql.connector.errorcode.
_CR_CONN_HOST_ERROR = 2003
_CR_CONNECTION_ERROR = 2002
_ER_CANT_EXECUTE_IN_READ_ONLY_TRANSACTION = 1792
_ER_QUERY_TIMEOUT = 3024


def _lower_keys(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Normalize dict-cursor row keys to lowercase.

    MySQL 8.4's information_schema returns column metadata (COLUMN_NAME,
    DATA_TYPE, ...) in uppercase regardless of how the SELECT list was
    written, so mysql.connector's dictionary cursor hands back uppercase
    keys unless every column is explicitly re-aliased. Normalizing here once
    is simpler than aliasing every information_schema column in every query.
    """
    return [{k.lower(): v for k, v in row.items()} for row in rows]


class DatabaseError(Exception):
    """Connection, configuration, or query-execution problem."""


class NotFoundError(Exception):
    """A requested database/table/column does not exist."""


def _friendly_connection_error(exc: mysql.connector.Error, cfg: AppConfig) -> DatabaseError:
    code = getattr(exc, "errno", None)
    if code == errorcode.ER_ACCESS_DENIED_ERROR:
        return DatabaseError(f"Usuario o contraseña inválidos para '{cfg.user}@{cfg.host}'.")
    if code == errorcode.ER_BAD_DB_ERROR:
        return DatabaseError(f"La base de datos '{cfg.database}' no existe en {cfg.host}:{cfg.port}.")
    if code in (_CR_CONN_HOST_ERROR, _CR_CONNECTION_ERROR):
        return DatabaseError(f"No se pudo conectar a MySQL en {cfg.host}:{cfg.port} ({exc}).")
    return DatabaseError(f"Error de conexión a MySQL: {exc}")


def _friendly_query_error(exc: mysql.connector.Error) -> DatabaseError:
    code = getattr(exc, "errno", None)
    if code == _ER_CANT_EXECUTE_IN_READ_ONLY_TRANSACTION:
        return DatabaseError(
            "La consulta intentó modificar datos; este servidor solo permite operaciones de lectura."
        )
    if code == _ER_QUERY_TIMEOUT:
        return DatabaseError(
            "La consulta superó el tiempo máximo permitido. Acótala con WHERE/LIMIT o simplifícala."
        )
    if code == errorcode.ER_PARSE_ERROR:
        return DatabaseError(f"Error de sintaxis SQL: {exc}")
    return DatabaseError(f"Error ejecutando la consulta: {exc}")


class Database:
    def __init__(self, cfg: AppConfig):
        self._cfg = cfg
        try:
            self._pool = MySQLConnectionPool(
                pool_name="mysql_mcp_pool",
                pool_size=cfg.pool_size,
                host=cfg.host,
                port=cfg.port,
                user=cfg.user,
                password=cfg.password,
                database=cfg.database,
                connection_timeout=cfg.connect_timeout_s,
                autocommit=False,
            )
        except mysql.connector.Error as exc:
            raise _friendly_connection_error(exc, cfg) from exc

    def check_connection(self) -> None:
        """Run a trivial query to validate connectivity/credentials at startup."""
        with self.connection() as cnx:
            cur = cnx.cursor()
            cur.execute("SELECT 1")
            cur.fetchall()
            cur.close()

    @contextmanager
    def connection(self) -> Iterator[Any]:
        try:
            cnx = self._pool.get_connection()
        except mysql.connector.Error as exc:
            raise _friendly_connection_error(exc, self._cfg) from exc
        try:
            yield cnx
        finally:
            try:
                cnx.close()  # returns the connection to the pool
            except Exception:
                pass

    # -- identifier resolution (defense against SQL-identifier injection) --

    def _resolve_database(self, database: str | None) -> str:
        db = database or self._cfg.database
        with self.connection() as cnx:
            cur = cnx.cursor()
            cur.execute("SELECT schema_name FROM information_schema.schemata WHERE schema_name = %s", (db,))
            row = cur.fetchone()
            cur.close()
        if row is None:
            available = self.list_databases(include_system=False)
            raise NotFoundError(
                f"La base de datos '{db}' no existe. BDs disponibles: {', '.join(available) or '(ninguna)'}."
            )
        return row[0]

    def _resolve_table(self, database: str, table: str) -> str:
        with self.connection() as cnx:
            cur = cnx.cursor()
            cur.execute(
                "SELECT table_name FROM information_schema.tables WHERE table_schema = %s AND table_name = %s",
                (database, table),
            )
            row = cur.fetchone()
            cur.close()
        if row is None:
            raise NotFoundError(
                f"La tabla '{table}' no existe en '{database}'. "
                f"Usa list_tables o search_schema para encontrar el nombre correcto."
            )
        return row[0]

    # -- exploration tools --

    def list_databases(self, include_system: bool = False) -> list[str]:
        with self.connection() as cnx:
            cur = cnx.cursor()
            cur.execute("SHOW DATABASES")
            names = [row[0] for row in cur.fetchall()]
            cur.close()
        if not include_system:
            names = [n for n in names if n not in SYSTEM_DATABASES]
        return names

    def list_tables(self, database: str | None = None) -> list[TableInfo]:
        db = self._resolve_database(database)
        with self.connection() as cnx:
            cur = cnx.cursor(dictionary=True)
            cur.execute(
                "SELECT table_name, table_type, engine, table_rows, table_comment "
                "FROM information_schema.tables WHERE table_schema = %s ORDER BY table_name",
                (db,),
            )
            rows = _lower_keys(cur.fetchall())
            cur.close()
        return [
            TableInfo(
                name=r["table_name"],
                type=r["table_type"],
                engine=r["engine"],
                row_count_estimate=r["table_rows"],
                comment=r["table_comment"] or None,
            )
            for r in rows
        ]

    def describe_table(self, table: str, database: str | None = None) -> TableSchema:
        db = self._resolve_database(database)
        tbl = self._resolve_table(db, table)

        with self.connection() as cnx:
            cur = cnx.cursor(dictionary=True)
            cur.execute(
                "SELECT column_name, data_type, column_type, is_nullable, column_default, "
                "column_key, extra, column_comment FROM information_schema.columns "
                "WHERE table_schema=%s AND table_name=%s ORDER BY ordinal_position",
                (db, tbl),
            )
            col_rows = _lower_keys(cur.fetchall())

            cur.execute(
                "SELECT index_name, column_name, non_unique FROM information_schema.statistics "
                "WHERE table_schema=%s AND table_name=%s ORDER BY index_name, seq_in_index",
                (db, tbl),
            )
            idx_rows = _lower_keys(cur.fetchall())

            cur.execute(
                "SELECT column_name, referenced_table_schema, referenced_table_name, referenced_column_name "
                "FROM information_schema.key_column_usage "
                "WHERE table_schema=%s AND table_name=%s AND referenced_table_name IS NOT NULL",
                (db, tbl),
            )
            fk_rows = _lower_keys(cur.fetchall())
            cur.close()

        columns = [
            ColumnInfo(
                name=r["column_name"],
                data_type=r["data_type"],
                column_type=r["column_type"],
                is_nullable=(r["is_nullable"] == "YES"),
                default=r["column_default"],
                is_primary_key=(r["column_key"] == "PRI"),
                extra=r["extra"] or None,
                comment=r["column_comment"] or None,
            )
            for r in col_rows
        ]

        indexes_map: dict[str, dict[str, Any]] = {}
        for r in idx_rows:
            entry = indexes_map.setdefault(r["index_name"], {"columns": [], "is_unique": r["non_unique"] == 0})
            entry["columns"].append(r["column_name"])
        indexes = [
            IndexInfo(name=name, columns=info["columns"], is_unique=info["is_unique"])
            for name, info in indexes_map.items()
        ]

        foreign_keys = [
            ForeignKeyInfo(
                column=r["column_name"],
                references_database=r["referenced_table_schema"],
                references_table=r["referenced_table_name"],
                references_column=r["referenced_column_name"],
            )
            for r in fk_rows
        ]

        return TableSchema(database=db, table=tbl, columns=columns, indexes=indexes, foreign_keys=foreign_keys)

    def search_schema(
        self,
        pattern: str,
        database: str | None = None,
        search_in: Literal["tables", "columns", "both"] = "both",
        limit: int = 50,
    ) -> list[SchemaMatch]:
        db = self._resolve_database(database)
        like = f"%{pattern}%"
        matches: list[SchemaMatch] = []

        with self.connection() as cnx:
            cur = cnx.cursor(dictionary=True)
            if search_in in ("tables", "both"):
                cur.execute(
                    "SELECT table_name FROM information_schema.tables "
                    "WHERE table_schema=%s AND table_name LIKE %s ORDER BY table_name LIMIT %s",
                    (db, like, limit),
                )
                matches.extend(
                    SchemaMatch(database=db, table=r["table_name"], column=None, matched_on="table")
                    for r in _lower_keys(cur.fetchall())
                )

            if search_in in ("columns", "both") and len(matches) < limit:
                remaining = limit - len(matches)
                cur.execute(
                    "SELECT table_name, column_name FROM information_schema.columns "
                    "WHERE table_schema=%s AND column_name LIKE %s ORDER BY table_name, column_name LIMIT %s",
                    (db, like, remaining),
                )
                matches.extend(
                    SchemaMatch(database=db, table=r["table_name"], column=r["column_name"], matched_on="column")
                    for r in _lower_keys(cur.fetchall())
                )
            cur.close()

        return matches[:limit]

    def search_data(
        self,
        pattern: str,
        table: str | None = None,
        database: str | None = None,
        columns: list[str] | None = None,
        limit: int = 50,
        max_tables_scanned: int = 25,
    ) -> list[DataMatch]:
        db = self._resolve_database(database)
        like = f"%{pattern}%"
        results: list[DataMatch] = []

        if table is not None:
            tables_to_scan = [self._resolve_table(db, table)]
        else:
            with self.connection() as cnx:
                cur = cnx.cursor()
                cur.execute(
                    "SELECT table_name FROM information_schema.tables "
                    "WHERE table_schema=%s AND table_type='BASE TABLE' ORDER BY table_rows ASC LIMIT %s",
                    (db, max_tables_scanned),
                )
                tables_to_scan = [r[0] for r in cur.fetchall()]
                cur.close()

        for tbl in tables_to_scan:
            if len(results) >= limit:
                break

            with self.connection() as cnx:
                cur = cnx.cursor(dictionary=True)
                cur.execute(
                    "SELECT column_name, data_type FROM information_schema.columns "
                    "WHERE table_schema=%s AND table_name=%s",
                    (db, tbl),
                )
                col_rows = _lower_keys(cur.fetchall())
                cur.close()

            text_columns = [r["column_name"] for r in col_rows if r["data_type"].lower() in _TEXT_DATA_TYPES]

            if columns is not None:
                valid_names = {r["column_name"] for r in col_rows}
                unknown = set(columns) - valid_names
                if unknown:
                    raise NotFoundError(f"Las columnas {sorted(unknown)} no existen en '{db}.{tbl}'.")
                text_columns = [c for c in text_columns if c in columns]

            if not text_columns:
                continue

            remaining = limit - len(results)
            select_cols = ", ".join(f"`{c}`" for c in text_columns)
            or_clauses = " OR ".join(f"`{c}` LIKE %s" for c in text_columns)
            sql = f"SELECT {select_cols} FROM `{db}`.`{tbl}` WHERE {or_clauses} LIMIT %s"
            params = [like] * len(text_columns) + [remaining]

            try:
                with self.connection() as cnx:
                    cur = cnx.cursor(dictionary=True)
                    cur.execute(f"SET SESSION MAX_EXECUTION_TIME={int(self._cfg.query_timeout_ms)}")
                    cnx.start_transaction(readonly=True)
                    try:
                        cur.execute(sql, params)
                        rows = cur.fetchall()
                    finally:
                        cnx.rollback()
                    cur.close()
            except mysql.connector.Error as exc:
                raise _friendly_query_error(exc) from exc

            for row in rows:
                for col in text_columns:
                    value = row.get(col)
                    if value is not None and pattern.lower() in str(value).lower():
                        results.append(DataMatch(database=db, table=tbl, column=col, row=row))
                        break

        return results[:limit]

    def run_readonly(self, sql: str, params: list[Any] | None, max_rows: int) -> QueryResult:
        try:
            normalized_sql = validate_readonly_sql(sql)
        except SqlNotAllowedError as exc:
            raise DatabaseError(str(exc)) from exc

        capped_max_rows = min(max_rows, self._cfg.max_rows_hard_limit)

        last_exc: mysql.connector.Error | None = None
        for _attempt in range(2):
            try:
                with self.connection() as cnx:
                    cur = cnx.cursor(dictionary=True)
                    cur.execute(f"SET SESSION MAX_EXECUTION_TIME={self._cfg.query_timeout_ms}")
                    cnx.start_transaction(readonly=True)
                    try:
                        cur.execute(normalized_sql, params or None)
                        rows = cur.fetchmany(capped_max_rows + 1)
                        truncated = len(rows) > capped_max_rows
                        rows = rows[:capped_max_rows]
                        column_names = list(cur.column_names)
                    finally:
                        cnx.rollback()
                    cur.close()
                return QueryResult(columns=column_names, rows=rows, row_count=len(rows), truncated=truncated)
            except mysql.connector.errors.OperationalError as exc:
                last_exc = exc
                continue  # connection may have gone stale; retry once with a fresh one from the pool
            except mysql.connector.Error as exc:
                raise _friendly_query_error(exc) from exc

        raise DatabaseError(f"Fallo de conexión con MySQL tras reintentar: {last_exc}")

    # -- parametrized multi-statement scripts (see sql_guard for the parsing rules) --

    def _scripts_dir(self) -> Path:
        return Path(self._cfg.scripts_dir)

    def list_scripts(self) -> list[str]:
        scripts_dir = self._scripts_dir()
        if not scripts_dir.is_dir():
            return []
        return sorted(p.name for p in scripts_dir.glob("*.sql"))

    def _resolve_script_path(self, script_name: str) -> Path:
        if not _SCRIPT_NAME_RE.match(script_name):
            raise DatabaseError(
                f"Nombre de script inválido: '{script_name}'. Debe ser solo un nombre de "
                f"archivo terminado en .sql, sin rutas (p.ej. 'reglas.sql')."
            )

        scripts_dir = self._scripts_dir()
        candidate = (scripts_dir / script_name).resolve()
        try:
            candidate.relative_to(scripts_dir.resolve())
        except ValueError as exc:
            raise DatabaseError(f"Nombre de script inválido: '{script_name}'.") from exc

        if not candidate.is_file():
            available = self.list_scripts()
            raise DatabaseError(
                f"El script '{script_name}' no existe en {scripts_dir}. "
                f"Scripts disponibles: {', '.join(available) or '(ninguno)'}."
            )
        return candidate

    def run_script(
        self,
        script_name: str,
        params: dict[str, Any] | None,
        max_rows: int,
    ) -> ScriptResult:
        """Run a curated, multi-statement .sql "script" from scripts_dir.

        These scripts (see src/scripts_error/*.sql) are parametrized MySQL
        diagnostic queries: a leading `SELECT @var:=value;` line declares an
        "entry parameter" (typically an operation id), and the rest of the
        script's SELECTs reference `@var` throughout. `params` supplies the
        real values for those declared variables - they're bound via `SET
        @var = %s` (never interpolated into SQL text), so the script's own
        hardcoded literal is only ever a placeholder/example.

        Every non-assignment statement is still validated as read-only and
        the whole script runs inside one read-only transaction with an
        unconditional rollback, same as run_query - a script is just several
        validated statements sharing one session so the @variables persist.
        """
        params = dict(params or {})
        script_path = self._resolve_script_path(script_name)

        try:
            script_text = script_path.read_text(encoding="utf-8")
        except OSError as exc:
            raise DatabaseError(f"No se pudo leer el script '{script_name}': {exc}") from exc

        statements = split_script_statements(script_text)

        required_vars: list[str] = []
        for stmt in statements:
            if is_pure_variable_assignment(stmt):
                for var in extract_assigned_variables(stmt):
                    if var not in required_vars:
                        required_vars.append(var)

        missing = [v for v in required_vars if v not in params]
        if missing:
            raise DatabaseError(
                f"Faltan parámetros requeridos por '{script_name}': {', '.join(missing)}. "
                f"Este script espera: {', '.join(required_vars) or '(ninguno)'}."
            )

        for name in params:
            if not _VAR_NAME_RE.match(name):
                raise DatabaseError(
                    f"Nombre de parámetro inválido: '{name}'. Debe ser un identificador "
                    f"simple (letras, dígitos, guion bajo, sin empezar por dígito)."
                )

        # Statements that only assign session variables are dropped here -
        # their caller-supplied values are set below via a parametrized SET,
        # so nothing from `params` is ever interpolated into SQL text.
        query_statements = [s for s in statements if not is_pure_variable_assignment(s)]
        if not query_statements:
            raise DatabaseError(f"El script '{script_name}' no contiene ninguna consulta ejecutable.")

        validated: list[str] = []
        for stmt in query_statements:
            try:
                validated.append(validate_readonly_sql(stmt))
            except SqlNotAllowedError as exc:
                raise DatabaseError(
                    f"El script '{script_name}' contiene una sentencia no permitida: {exc}"
                ) from exc

        capped_max_rows = min(max_rows, self._cfg.max_rows_hard_limit)

        try:
            with self.connection() as cnx:
                cur = cnx.cursor(dictionary=True)
                cur.execute(f"SET SESSION MAX_EXECUTION_TIME={self._cfg.query_timeout_ms}")
                for name, value in params.items():
                    cur.execute(f"SET @{name} = %s", (value,))

                results: list[ScriptStatementResult] = []
                cnx.start_transaction(readonly=True)
                try:
                    for stmt in validated:
                        cur.execute(stmt)
                        rows = cur.fetchmany(capped_max_rows + 1)
                        truncated = len(rows) > capped_max_rows
                        rows = rows[:capped_max_rows]
                        results.append(
                            ScriptStatementResult(
                                sql=stmt,
                                columns=list(cur.column_names),
                                rows=rows,
                                row_count=len(rows),
                                truncated=truncated,
                            )
                        )
                finally:
                    cnx.rollback()
                cur.close()
        except mysql.connector.Error as exc:
            raise _friendly_query_error(exc) from exc

        return ScriptResult(script=script_name, params=params, statements=results)
