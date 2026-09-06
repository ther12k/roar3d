#!/usr/bin/env bash
# Runs both headless suites against the pinned engine.
# Usage: tools/run_tests.sh [/path/to/godot]
set -euo pipefail

GODOT_BIN="${1:-${GODOT_BIN:-godot}}"
cd "$(dirname "$0")/.."

echo "== Engine version (evidence for the test record) =="
"$GODOT_BIN" --version

echo
echo "== Clean import check =="
rm -rf .godot
"$GODOT_BIN" --headless --path . --import > /tmp/roar3d_import.log 2>&1 || {
  echo "IMPORT FAILED"; grep -E "ERROR|SCRIPT ERROR" /tmp/roar3d_import.log | head -20; exit 1;
}
IMPORT_ERRORS=$(grep -cE "SCRIPT ERROR|Parse Error" /tmp/roar3d_import.log || true)
echo "Import complete. Script/parse errors: $IMPORT_ERRORS"
[ "$IMPORT_ERRORS" = "0" ] || { grep -E "SCRIPT ERROR|Parse Error" /tmp/roar3d_import.log | head; exit 1; }

echo
echo "== Unit tests =="
XDG_DATA_HOME="$(mktemp -d /tmp/roar3d-test-XXXX)" "$GODOT_BIN" --headless --path . res://tests/unit/run_tests.tscn 2>&1 | grep -vE "Parse JSON|parse_string|backtrace|^\s+\[" | tail -20

echo
echo "== Integration tests (real Jolt physics; takes ~2 min; isolated user://) =="
XDG_DATA_HOME="$(mktemp -d /tmp/roar3d-test-XXXX)" "$GODOT_BIN" --headless --path . res://tests/integration/run_integration_tests.tscn 2>&1 | grep -E "FAIL|TESTS:|SCRIPT ERROR" | head -20
