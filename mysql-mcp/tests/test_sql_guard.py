import pytest

from mysql_mcp_server.sql_guard import (
    SqlNotAllowedError,
    extract_assigned_variables,
    is_pure_variable_assignment,
    split_script_statements,
    strip_mysql_hash_comments,
    validate_readonly_sql,
)

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


def test_forbidden_keyword_inside_a_comment_is_not_a_false_positive() -> None:
    # A '--' comment mentioning a forbidden word must not trip the guard -
    # comments can't execute anything. Mirrors real text found in
    # src/scripts_error/reglas.sql.
    sql = "SELECT * FROM users\n-- se hace el UPDATE antes de esto\nWHERE id = 1"
    result = validate_readonly_sql(sql)
    assert "UPDATE" in result  # the comment itself is preserved in the executed SQL
    assert "-- se hace el UPDATE" in result


def test_forbidden_keyword_inside_hash_comment_is_not_a_false_positive() -> None:
    sql = "SELECT * FROM users WHERE id = 1  ##### DROP THIS ROW LATER"
    result = validate_readonly_sql(sql)
    assert "DROP" in result


class TestStripMysqlHashComments:
    def test_strips_full_line_comment(self) -> None:
        assert strip_mysql_hash_comments("# a comment\nSELECT 1") == "\nSELECT 1"

    def test_strips_inline_trailing_comment(self) -> None:
        assert strip_mysql_hash_comments("SELECT 1 # trailing\nSELECT 2") == "SELECT 1 \nSELECT 2"

    def test_preserves_hash_inside_single_quoted_string(self) -> None:
        assert strip_mysql_hash_comments("SELECT 'price #123'") == "SELECT 'price #123'"

    def test_preserves_hash_inside_backtick_identifier(self) -> None:
        assert strip_mysql_hash_comments("SELECT `col#name`") == "SELECT `col#name`"


class TestSplitScriptStatements:
    def test_splits_and_drops_comments_and_blank_statements(self) -> None:
        script = """
        # header comment
        SELECT @x:=1;

        SELECT * FROM users WHERE id = @x; -- trailing comment
        """
        statements = split_script_statements(script)
        assert statements == ["SELECT @x:=1", "SELECT * FROM users WHERE id = @x"]

    def test_trailing_comment_does_not_leave_a_stray_semicolon(self) -> None:
        # sqlparse.split() attaches a comment right after ';' to the
        # *preceding* chunk (e.g. "SELECT @x:='FECI'; -- note" is one chunk),
        # which would otherwise leave an embedded ';' once comments weren't
        # stripped first. Mirrors real text in transacc_historico&diaria.sql.
        script = "SELECT @x:='FECI'; -- 'CAP', 'INT'\n\nSELECT 1 FROM t;"
        assert split_script_statements(script) == ["SELECT @x:='FECI'", "SELECT 1 FROM t"]


class TestIsPureVariableAssignment:
    def test_single_assignment_with_no_from_is_pure(self) -> None:
        assert is_pure_variable_assignment("SELECT @w_operacionca:=147900") is True

    def test_multiple_assignments_with_no_from_is_pure(self) -> None:
        assert is_pure_variable_assignment("SELECT @a:=1, @b:=2, @c:=3") is True

    def test_assignment_with_from_clause_is_not_pure(self) -> None:
        stmt = "SELECT @w_banco := op_banco AS banco FROM ca_operacion WHERE op_operacion = @w_operacionca"
        assert is_pure_variable_assignment(stmt) is False

    def test_plain_select_with_no_assignment_is_not_pure(self) -> None:
        assert is_pure_variable_assignment("SELECT * FROM users") is False


def test_extract_assigned_variables_is_ordered_and_deduplicated() -> None:
    stmt = "SELECT @w_operacionca:=147900, @div_ini:=41, @div_hasta:=91, @w_operacionca:=1"
    assert extract_assigned_variables(stmt) == ["w_operacionca", "div_ini", "div_hasta"]
