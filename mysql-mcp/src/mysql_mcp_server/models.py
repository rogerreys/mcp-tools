"""Pydantic models used as structured output for the MCP tools."""

from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel


class TableInfo(BaseModel):
    name: str
    type: str
    engine: str | None = None
    row_count_estimate: int | None = None
    comment: str | None = None


class ColumnInfo(BaseModel):
    name: str
    data_type: str
    column_type: str
    is_nullable: bool
    default: str | None = None
    is_primary_key: bool = False
    extra: str | None = None
    comment: str | None = None


class IndexInfo(BaseModel):
    name: str
    columns: list[str]
    is_unique: bool


class ForeignKeyInfo(BaseModel):
    column: str
    references_database: str
    references_table: str
    references_column: str


class TableSchema(BaseModel):
    database: str
    table: str
    columns: list[ColumnInfo]
    indexes: list[IndexInfo]
    foreign_keys: list[ForeignKeyInfo]


class QueryResult(BaseModel):
    columns: list[str]
    rows: list[dict[str, Any]]
    row_count: int
    truncated: bool


class SchemaMatch(BaseModel):
    database: str
    table: str
    column: str | None = None
    matched_on: Literal["table", "column"]


class DataMatch(BaseModel):
    database: str
    table: str
    column: str
    row: dict[str, Any]


class ScriptStatementResult(BaseModel):
    sql: str
    columns: list[str]
    rows: list[dict[str, Any]]
    row_count: int
    truncated: bool


class ScriptResult(BaseModel):
    script: str
    params: dict[str, Any]
    statements: list[ScriptStatementResult]
