# mysql-mcp-server

Servidor MCP (Model Context Protocol) de **solo lectura** para explorar el
esquema de una base de datos MySQL y encontrar información en ella, sin
necesidad de conocer de antemano qué tablas o columnas existen.

## Herramientas expuestas

- `list_databases` — lista las bases de datos visibles en la conexión.
- `list_tables` — lista las tablas de una BD (tipo, engine, filas estimadas).
- `describe_table` — columnas, claves primarias, índices y foreign keys de una tabla.
- `search_schema` — busca tablas/columnas por nombre parcial, cuando no se conoce el nombre exacto.
- `search_data` — busca un valor de texto dentro de una tabla, o en varias si no se especifica cuál.
- `run_query` — ejecuta SQL de solo lectura (`SELECT`/`SHOW`/`DESCRIBE`/`EXPLAIN`).

Cualquier intento de escritura o DDL (`INSERT`/`UPDATE`/`DELETE`/`DROP`/`ALTER`/
`CREATE`/...) se rechaza en dos capas: validación del texto SQL antes de tocar
la red, y ejecución dentro de una transacción `READ ONLY` de MySQL, que el
propio motor rechaza a nivel de protocolo aunque el usuario de MySQL
configurado tuviera permisos de escritura.

## Configuración

Copia `config.example.json` a `config.json` y completa tus credenciales:

```json
{
  "host": "127.0.0.1",
  "port": 3306,
  "user": "readonly_user",
  "password": "CHANGE_ME",
  "database": "example_db",
  "pool_size": 5,
  "connect_timeout_s": 10,
  "query_timeout_ms": 15000,
  "max_rows": 200,
  "max_rows_hard_limit": 1000
}
```

`config.json` está en `.gitignore` — nunca se commitea. La ruta al archivo se
puede cambiar con la variable de entorno `MYSQL_MCP_CONFIG_PATH` (por defecto
busca `./config.json` en el directorio desde donde se lanza el proceso).

Se recomienda usar un usuario de MySQL con privilegios de solo `SELECT` sobre
la(s) BD(s) a explorar, aunque el servidor ya impone solo-lectura por su cuenta.

## Instalación

```bash
uv sync
```

## Correr los tests

```bash
uv run pytest                                    # todos los tests
uv run pytest tests/test_sql_guard.py -v          # solo el validador de SQL
uv run pytest -m integration                      # requiere MySQL real, ver abajo
```

### Tests de integración (con MySQL real vía Docker)

```bash
docker compose -f mysql/docker-compose.yml up -d
uv run pytest -m integration -v
docker compose -f mysql/docker-compose.yml down -v
```

## Correr el servidor

```bash
uv run python -m mysql_mcp_server --config /ruta/a/config.json
```

Para probarlo interactivamente con el MCP Inspector (requiere `npx`):

```bash
uv run mcp dev src/mysql_mcp_server/server.py
```

## Registrar en Claude Code

```bash
claude mcp add mysql-explorer \
  --env MYSQL_MCP_CONFIG_PATH=/ruta/absoluta/config.json \
  -- uv run --with "mcp[cli]" mcp run /ruta/absoluta/src/mysql_mcp_server/server.py
```

Verifica el registro con `/mcp` dentro de una sesión de Claude Code.
