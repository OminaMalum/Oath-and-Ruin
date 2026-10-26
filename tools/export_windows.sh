#!/usr/bin/env bash
# Build the Windows x86_64 release export. Needs Godot 4.7.2-stable and its
# export templates. Usage: tools/export_windows.sh [godot-binary]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${1:-godot}"
"$GODOT" --version | grep -q '^4\.7\.2\.stable' || { echo "Need Godot 4.7.2-stable (see ENGINE_VERSION)"; exit 1; }
mkdir -p build/windows
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --export-release "Windows Desktop" build/windows/OathAndRuin.exe
ls -la build/windows
