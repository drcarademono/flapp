#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
for candidate in lua5.1 luajit lua5.4 lua5.3 lua; do
    if command -v "$candidate" >/dev/null 2>&1; then
        exec "$candidate" "$ROOT/tests/lua/run_game_tests.lua" "$ROOT"
    fi
done
echo "A Lua 5.1-compatible interpreter (lua5.1 or luajit) is required" >&2
exit 127
