#!/usr/bin/env bash
# Gate 1 multi-process network test (server + 4 headless clients). Pass extra args through,
# for example: tools/net_test.sh --lag 100 --jitter 30 --loss 0.05
cd "$(dirname "$0")/.."
python3 tests/net_test.py "$@"
