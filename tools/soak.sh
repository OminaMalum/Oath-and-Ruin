#!/usr/bin/env bash
# Runs N full bot-only matches headless (fixed 60 Hz steps, as fast as the CPU allows)
# and prints one summary line per match. Usage: tools/soak.sh [N] [godot]
cd "$(dirname "$0")/.."
N="${1:-3}"; GODOT="${2:-godot}"
for seed in $(seq 1 "$N"); do
  "$GODOT" --headless --path . --fixed-fps 60 -- --mode=match --spectate --seed="$seed" 2>&1 \
    | grep -E "MATCHLOG|SCRIPT ERROR" | python3 tools/summarize_match.py "$seed"
done
