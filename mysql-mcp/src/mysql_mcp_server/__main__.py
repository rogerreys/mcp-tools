"""CLI entrypoint: `python -m mysql_mcp_server [--config path/to/config.json]`.

This is a thin convenience wrapper. It just sets MYSQL_MCP_CONFIG_PATH (if
--config was given) and then imports server.py and calls run() - the same
thing `mcp run server.py` / `mcp dev server.py` do when driving the module
directly, so config loading always goes through the same env-var path
regardless of how the server is launched.
"""

from __future__ import annotations

import argparse
import os

from .config import CONFIG_PATH_ENV_VAR


def main() -> None:
    parser = argparse.ArgumentParser(prog="mysql-mcp-server")
    parser.add_argument(
        "--config",
        metavar="PATH",
        help=f"Path to config.json (overrides {CONFIG_PATH_ENV_VAR}; default: ./config.json)",
    )
    args = parser.parse_args()

    if args.config:
        os.environ[CONFIG_PATH_ENV_VAR] = args.config

    from .server import run  # imported after the env var is set

    run()


if __name__ == "__main__":
    main()
