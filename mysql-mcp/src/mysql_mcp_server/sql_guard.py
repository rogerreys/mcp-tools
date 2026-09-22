"""Text-level validation that a SQL statement is read-only.

This is the first, cheap line of defense: it rejects obviously unsafe SQL
before any network round-trip, with a specific and actionable error message.
It is deliberately NOT a full semantic SQL parser/validator - the real,
hard guarantee comes from db.py running every query inside a MySQL
`START TRANSACTION READ ONLY` transaction, which MySQL itself enforces at
the engine level (error 1792) even if a write attempt slips past this
text-based guard.
"""

from __future__ import annotations

import re

import sqlparse

ALLOWED_FIRST_KEYWORDS = {"SELECT", "SHOW", "DESCRIBE", "DESC", "EXPLAIN", "WITH"}

# Statement keywords that indicate a write, DDL, or other side-effecting
# operation. Matched case-insensitively with word boundaries against the
# full normalized text, so it also catches these hidden inside a WITH ...
# or subquery, not just as the first token.
FORBIDDEN_KEYWORDS = [
    "INSERT",
    "UPDATE",
    "DELETE",
    "REPLACE",
    "MERGE",
    "DROP",
    "ALTER",
    "CREATE",
    "TRUNCATE",
    "RENAME",
    "GRANT",
    "REVOKE",
    "LOCK",
    "UNLOCK",
    "CALL",
    "DO",
    "HANDLER",
    "LOAD",
    "FLUSH",
    "KILL",
    "SHUTDOWN",
    "INSTALL",
    "UNINSTALL",
    "PREPARE",
    "EXECUTE",
    "DEALLOCATE",
    "SET",
]

# Multi-word constructs, matched as literal (whitespace-flexible) phrases.
FORBIDDEN_PHRASES = [
    r"INTO\s+OUTFILE",
    r"INTO\s+DUMPFILE",
]


class SqlNotAllowedError(Exception):
    """Raised when a SQL statement fails the read-only guard."""


def _first_keyword(parsed: sqlparse.sql.Statement) -> str | None:
    token = parsed.token_first(skip_cm=True)
    if token is None:
        return None
    return token.value.upper()


def validate_readonly_sql(sql: str) -> str:
    """Validate that `sql` is a single, read-only statement.

    Returns the normalized SQL (stripped, trailing ';' removed) on success.
    Raises SqlNotAllowedError with a specific reason on failure.
    """
    if not sql or not sql.strip():
        raise SqlNotAllowedError("La consulta SQL está vacía.")

    statements = [s for s in sqlparse.split(sql) if s.strip()]
    if len(statements) == 0:
        raise SqlNotAllowedError("La consulta SQL está vacía.")
    if len(statements) > 1:
        raise SqlNotAllowedError(
            f"Solo se permite una sentencia SQL por llamada, se recibieron {len(statements)}."
        )

    normalized = statements[0].strip().rstrip(";").strip()
    parsed = sqlparse.parse(normalized)[0]

    first_kw = _first_keyword(parsed)
    if first_kw is None or first_kw not in ALLOWED_FIRST_KEYWORDS:
        raise SqlNotAllowedError(
            f"Solo se permiten SELECT/SHOW/DESCRIBE/EXPLAIN (o WITH ... SELECT). "
            f"Se recibió: '{first_kw or normalized[:40]}'."
        )

    # Note: EXPLAIN ANALYZE (MySQL 8, read-only) is allowed automatically since
    # "ANALYZE" is not in FORBIDDEN_KEYWORDS - only ANALYZE TABLE-style DDL uses
    # would be, and those don't start with an allowed first keyword anyway.
    for keyword in FORBIDDEN_KEYWORDS:
        pattern = rf"\b{re.escape(keyword)}\b"
        if re.search(pattern, normalized, re.IGNORECASE):
            raise SqlNotAllowedError(
                f"La consulta contiene la palabra clave no permitida '{keyword}'. "
                f"Este servidor solo admite consultas de solo lectura."
            )

    for phrase in FORBIDDEN_PHRASES:
        if re.search(phrase, normalized, re.IGNORECASE):
            raise SqlNotAllowedError(
                "La consulta intenta escribir un archivo en el servidor "
                "(INTO OUTFILE/DUMPFILE), lo cual no está permitido."
            )

    return normalized
