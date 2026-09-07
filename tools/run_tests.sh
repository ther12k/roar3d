#!/usr/bin/env bash
# Runs both headless suites against the pinned engine.
# Usage: tools/run_tests.sh [/path/to/godot]
set -euo pipefail

GODOT_BIN="${1:-${GODOT_BIN:-godot}}"
cd "$(dirname "$0")/.."

echo "== Engine version gate (must match ENGINE_VERSION) =="
ACTUAL_VERSION="$("$GODOT_BIN" --version | head -1)"
PINNED_VERSION="$(tr -d ' \t\n\r' < ENGINE_VERSION)"
# Normalize both to x.y.z.channel: 4.7.2.stable.official.xyz / 4.7.2-stable
ACTUAL_KEY="$(echo "$ACTUAL_VERSION" | cut -d. -f1-3).$(echo "$ACTUAL_VERSION" | cut -d. -f4)"
PINNED_KEY="${PINNED_VERSION//-/.}"
if [ "$ACTUAL_KEY" != "$PINNED_KEY" ]; then
  echo "ENGINE MISMATCH: binary '$ACTUAL_VERSION' != pinned '$PINNED_VERSION' — refusing to run."
  exit 1
fi
echo "OK: $ACTUAL_VERSION matches $PINNED_VERSION"

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

echo
echo "== Course-kit seam tests (real Jolt physics; takes ~2 min; isolated user://) =="
XDG_DATA_HOME="$(mktemp -d /tmp/roar3d-test-XXXX)" "$GODOT_BIN" --headless --path . res://tests/integration/run_course_kit_tests.tscn 2>&1 | grep -E "FAIL|TESTS:|SCRIPT ERROR" | head -20

echo
echo "== Level route tests (CC02/CC03 routes; takes ~2 min; isolated user://) =="
XDG_DATA_HOME="$(mktemp -d /tmp/roar3d-test-XXXX)" "$GODOT_BIN" --headless --path . res://tests/integration/run_level_route_tests.tscn 2>&1 | grep -E "FAIL|TESTS:|SCRIPT ERROR" | head -20
