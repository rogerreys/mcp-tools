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


_VAR_ASSIGN_RE = re.compile(r"@([A-Za-z_]\w*)\s*:=")
_HAS_FROM_RE = re.compile(r"\bFROM\b", re.IGNORECASE)


def strip_mysql_hash_comments(sql: str) -> str:
    """Strip MySQL '#'-to-end-of-line comments, respecting quoted strings.

    sqlparse (used below for statement splitting and keyword scanning) only
    understands ANSI '--' comments, not MySQL's '#' comment syntax. Without
    this, a '#' anywhere in a .sql script file - inline or full-line - would
    be misread as SQL tokens instead of being ignored, as MySQL itself
    correctly ignores it at execution time regardless of position on the line.
    """
    out: list[str] = []
    quote: str | None = None
    i, n = 0, len(sql)
    while i < n:
        ch = sql[i]
        if quote:
            out.append(ch)
            if ch == "\\" and i + 1 < n:
                out.append(sql[i + 1])
                i += 2
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in ("'", '"', "`"):
            quote = ch
            out.append(ch)
            i += 1
            continue
        if ch == "#":
            nl = sql.find("\n", i)
            if nl == -1:
                break
            i = nl
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def split_script_statements(script: str) -> list[str]:
    """Split a multi-statement .sql script into individual statements.

    All comments ('#' and '--' style) are stripped before splitting on ';'.
    This isn't just cosmetic: sqlparse.split() attaches a comment trailing
    right after a ';' to the *preceding* chunk rather than treating it as
    its own fragment (e.g. "SELECT @x:=1; -- note" stays one chunk), which
    would otherwise leave a stray ';' embedded mid-statement once whitespace
    is trimmed. Stripping comments first means every chunk sqlparse.split()
    returns ends exactly at its ';', so trimming it is unambiguous.
    """
    cleaned = sqlparse.format(strip_mysql_hash_comments(script), strip_comments=True)
    statements: list[str] = []
    for raw in sqlparse.split(cleaned):
        stmt = raw.strip().rstrip(";").strip()
        if stmt:
            statements.append(stmt)
    return statements


def extract_assigned_variables(statement: str) -> list[str]:
    """Return the MySQL user-variable names (without '@') this statement
    assigns via `@name := ...`, in first-seen order, deduplicated.
    """
    seen: list[str] = []
    for name in _VAR_ASSIGN_RE.findall(statement):
        if name not in seen:
            seen.append(name)
    return seen


def is_pure_variable_assignment(statement: str) -> bool:
    """True if `statement` only assigns MySQL user variables and reads no
    table (e.g. `SELECT @w_operacionca:=147900;`), as opposed to a query
    that happens to also assign a variable from a fetched row (e.g.
    `SELECT @w_banco := op_banco ... FROM ca_operacion WHERE ...`).

    Used by Database.run_script() to tell a script's declared "entry
    parameters" (which the caller must supply) apart from its real,
    data-returning statements.
    """
    parsed = sqlparse.parse(statement)
    if not parsed:
        return False
    if _first_keyword(parsed[0]) != "SELECT":
        return False
    if _HAS_FROM_RE.search(statement):
        return False
    return bool(extract_assigned_variables(statement))


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

    # The forbidden-keyword/phrase scan below runs against a comment-free
    # copy of the SQL, not `normalized` itself, so a keyword mentioned only
    # inside a '#' or '--' comment (e.g. an explanatory note that happens to
    # say "UPDATE") never triggers a false rejection - comments can't
    # execute anything, so they're irrelevant to whether the statement is
    # actually read-only. The SQL actually returned (and later executed)
    # keeps its comments intact.
    scan_target = sqlparse.format(strip_mysql_hash_comments(normalized), strip_comments=True)

    # Note: EXPLAIN ANALYZE (MySQL 8, read-only) is allowed automatically since
    # "ANALYZE" is not in FORBIDDEN_KEYWORDS - only ANALYZE TABLE-style DDL uses
    # would be, and those don't start with an allowed first keyword anyway.
    for keyword in FORBIDDEN_KEYWORDS:
        pattern = rf"\b{re.escape(keyword)}\b"
        if re.search(pattern, scan_target, re.IGNORECASE):
            raise SqlNotAllowedError(
                f"La consulta contiene la palabra clave no permitida '{keyword}'. "
                f"Este servidor solo admite consultas de solo lectura."
            )

    for phrase in FORBIDDEN_PHRASES:
        if re.search(phrase, scan_target, re.IGNORECASE):
            raise SqlNotAllowedError(
                "La consulta intenta escribir un archivo en el servidor "
                "(INTO OUTFILE/DUMPFILE), lo cual no está permitido."
            )

    return normalized
