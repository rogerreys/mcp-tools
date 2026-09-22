import pytest

from mysql_mcp_server.sql_guard import SqlNotAllowedError, validate_readonly_sql

ALLOWED = [
    "SELECT * FROM users",
    "select id, name from users where id = 1",
    "SHOW TABLES",
    "SHOW DATABASES",
    "DESCRIBE users",
    "DESC users",
    "EXPLAIN SELECT * FROM users",
    "EXPLAIN ANALYZE SELECT * FROM users",
    "WITH recent AS (SELECT * FROM orders) SELECT * FROM recent",
    "  SELECT 1;  ",  # trailing whitespace/semicolon is normalized away
]

FORBIDDEN = [
    "INSERT INTO users (name) VALUES ('x')",
    "UPDATE users SET name = 'x' WHERE id = 1",
    "DELETE FROM users WHERE id = 1",
    "REPLACE INTO users (id, name) VALUES (1, 'x')",
    "DROP TABLE users",
    "ALTER TABLE users ADD COLUMN x INT",
    "CREATE TABLE x (id INT)",
    "TRUNCATE TABLE users",
    "RENAME TABLE users TO people",
    "GRANT ALL ON *.* TO 'x'@'%'",
    "REVOKE ALL ON *.* FROM 'x'@'%'",
    "CALL some_procedure()",
    "SET GLOBAL max_connections = 1000",
    "LOCK TABLES users WRITE",
    "SELECT * FROM users INTO OUTFILE '/tmp/x.csv'",
    "SELECT * FROM users; DROP TABLE users",
    "UPDATE users SET name='x' WHERE id=1; SELECT 1",
]


@pytest.mark.parametrize("sql", ALLOWED)
def test_allowed_statements_pass(sql: str) -> None:
    result = validate_readonly_sql(sql)
    assert result  # non-empty normalized SQL
    assert not result.endswith(";")


@pytest.mark.parametrize("sql", FORBIDDEN)
def test_forbidden_statements_are_rejected(sql: str) -> None:
    with pytest.raises(SqlNotAllowedError):
        validate_readonly_sql(sql)


def test_empty_sql_is_rejected() -> None:
    with pytest.raises(SqlNotAllowedError):
        validate_readonly_sql("")
    with pytest.raises(SqlNotAllowedError):
        validate_readonly_sql("   ")


def test_multi_statement_is_rejected_even_if_both_are_selects() -> None:
    with pytest.raises(SqlNotAllowedError, match="una sentencia"):
        validate_readonly_sql("SELECT 1; SELECT 2")


def test_rejection_message_is_specific() -> None:
    with pytest.raises(SqlNotAllowedError, match="DROP"):
        validate_readonly_sql("DROP TABLE users")
