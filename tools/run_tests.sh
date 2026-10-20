#!/usr/bin/env bash
# Headless gameplay tests. Exit code = number of failures.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${1:-godot}"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --fixed-fps 60 -s tests/run_tests.gd
