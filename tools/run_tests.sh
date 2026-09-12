#!/usr/bin/env bash
## Runs all headless suites against the pinned engine. Fails (non-zero) if any
## suite fails; a suite passes only when its exit code is 0 AND its report
## line shows "0 failed".
# Usage: tools/run_tests.sh [/path/to/godot]
set -uo pipefail

GODOT_BIN="${1:-${GODOT_BIN:-godot}}"
cd "$(dirname "$0")/.."

OVERALL=0
LOG_DIR="${ROAR3D_TEST_LOGS:-/tmp/roar3d-test-logs}"
mkdir -p "$LOG_DIR"

run_suite() {
	local name="$1" scene="$2"
	local log="$LOG_DIR/${name}.log"
	# Logs are RETAINED (never deleted) so a CI failure carries its full
	# output for inspection instead of a 20-line tail.
	XDG_DATA_HOME="$(mktemp -d /tmp/roar3d-test-XXXX)" "$GODOT_BIN" --headless --path . "$scene" >"$log" 2>&1
	local code=$?
	# Acceptance: exit 0 AND an exact "N passed, 0 failed" report with N >= 1
	# (the report line is anchored so "10 failed" can never match "0 failed"),
	# AND no unexplained engine/script errors. Deliberately-generated errors
	# (negative tests) print "Parse JSON" lines and are whitelisted below.
	local passed failed
	passed=$(grep -oE "[0-9]+ passed" "$log" | tail -1 | grep -oE "[0-9]+")
	failed=$(grep -oE "[0-9]+ failed" "$log" | tail -1 | grep -oE "[0-9]+")
	local report
	report=$(grep -E "TESTS:" "$log" | tail -1)
	printf '%-14s exit=%d %s\n' "$name" "$code" "$report"
	local ok=1
	if [ "$code" -ne 0 ]; then ok=0; fi
	if [ -z "$passed" ] || [ -z "$failed" ] || [ "$passed" -lt 1 ] || [ "$failed" -ne 0 ]; then ok=0; fi
	local errors
	errors=$(grep -cE "SCRIPT ERROR|Parse Error" "$log" || true)
	if [ "$errors" -ne 0 ]; then
		# Negative tests legitimately produce parse-json noise; SCRIPT ERROR /
		# Parse Error lines are never expected from a suite run.
		ok=0
	fi
	if [ "$ok" -ne 1 ]; then
		OVERALL=1
		echo "  -> REJECTED (exit=$code passed=$passed failed=$failed script_errors=$errors log=$log)"
		grep -E "FAIL|SCRIPT ERROR|Parse Error" "$log" | head -20
	fi
}

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
echo "== Suites (each runs with an isolated user:// profile) =="
run_suite "UNIT"          res://tests/unit/run_tests.tscn
run_suite "INTEGRATION"   res://tests/integration/run_integration_tests.tscn
run_suite "COURSE_KIT"    res://tests/integration/run_course_kit_tests.tscn
run_suite "LEVEL_ROUTE"   res://tests/integration/run_level_route_tests.tscn
run_suite "STABILITY"     res://tests/integration/run_stability_tests.tscn
run_suite "UI_SCREENS"    res://tests/integration/run_ui_screens_tests.tscn
run_suite "OBSTACLE"      res://tests/integration/run_obstacle_tests.tscn
run_suite "HOLE_ROUTE"    res://tests/integration/run_hole_route_tests.tscn

echo
if [ "$OVERALL" -eq 0 ]; then
	echo "ALL SUITES PASSED"
else
	echo "AT LEAST ONE SUITE FAILED"
fi
exit "$OVERALL"
