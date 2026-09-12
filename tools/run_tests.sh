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

# Acceptance for one suite: exit 0 AND exactly ONE correctly formatted
# summary line "<EXPECTED> TESTS: N passed, 0 failed" (N >= 1) with BOTH
# counts extracted from that single match, AND no unexplained engine/script
# errors. Anchored to the line start/end and pinned to the expected suite
# name, so diagnostics that merely CONTAIN "0 failed", duplicate summaries,
# wrong-suite summaries, or missing/malformed ones are all rejected.
run_suite() {
	local name="$1" scene="$2" expected="$3"
	local log="$LOG_DIR/${name}.log"
	# Logs are RETAINED (never deleted) so a CI failure carries its full
	# output for inspection instead of a 20-line tail.
	XDG_DATA_HOME="$(mktemp -d /tmp/roar3d-test-XXXX)" "$GODOT_BIN" --headless --path . "$scene" >"$log" 2>&1
	local code=$?
	local pattern="^${expected} TESTS: [0-9]+ passed, [0-9]+ failed$"
	local summary_count summary_line passed failed
	summary_count=$(grep -cE "$pattern" "$log")
	summary_line=$(grep -E "$pattern" "$log" | tail -1)
	passed=$(printf '%s' "$summary_line" | grep -oE "[0-9]+ passed" | grep -oE "[0-9]+")
	failed=$(printf '%s' "$summary_line" | grep -oE "[0-9]+ failed" | grep -oE "[0-9]+")
	printf '%-14s exit=%d %s\n' "$name" "$code" "$summary_line"
	local ok=1
	local reason=""
	if [ "$code" -ne 0 ]; then ok=0; reason="exit=$code"; fi
	if [ "$summary_count" -ne 1 ]; then
		ok=0
		reason="$reason summaries=$summary_count (need exactly 1 of: $pattern)"
	fi
	if [ -z "$passed" ] || [ -z "$failed" ] || [ "$passed" -lt 1 ] || [ "$failed" -ne 0 ]; then
		ok=0
		reason="$reason counts=(passed=${passed:-none} failed=${failed:-none})"
	fi
	local errors
	errors=$(grep -cE "SCRIPT ERROR|Parse Error" "$log" || true)
	if [ "$errors" -ne 0 ]; then
		# SCRIPT ERROR / Parse Error lines are never expected from a suite run
		# (deliberately-generated negative-test noise is "Parse JSON" only).
		ok=0
		reason="$reason script_errors=$errors"
	fi
	if [ "$ok" -ne 1 ]; then
		OVERALL=1
		echo "  -> REJECTED ($reason log=$log)"
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
"$GODOT_BIN" --headless --path . --import > "$LOG_DIR/import.log" 2>&1 || {
  echo "IMPORT FAILED"; grep -E "ERROR|SCRIPT ERROR" "$LOG_DIR/import.log" | head -20; exit 1;
}
IMPORT_ERRORS=$(grep -cE "SCRIPT ERROR|Parse Error" /tmp/roar3d_import.log || true)
echo "Import complete. Script/parse errors: $IMPORT_ERRORS"
[ "$IMPORT_ERRORS" = "0" ] || { grep -E "SCRIPT ERROR|Parse Error" /tmp/roar3d_import.log | head; exit 1; }

echo
echo "== Suites (each runs with an isolated user:// profile) =="
run_suite "UNIT"          res://tests/unit/run_tests.tscn "UNIT"
run_suite "INTEGRATION"   res://tests/integration/run_integration_tests.tscn "INTEGRATION"
run_suite "COURSE_KIT"    res://tests/integration/run_course_kit_tests.tscn "COURSE KIT"
run_suite "LEVEL_ROUTE"   res://tests/integration/run_level_route_tests.tscn "LEVEL ROUTE"
run_suite "STABILITY"     res://tests/integration/run_stability_tests.tscn "STABILITY"
run_suite "UI_SCREENS"    res://tests/integration/run_ui_screens_tests.tscn "UI SCREENS"
run_suite "OBSTACLE"      res://tests/integration/run_obstacle_tests.tscn "OBSTACLE"
run_suite "HOLE_ROUTE"    res://tests/integration/run_hole_route_tests.tscn "HOLE ROUTE"

echo
if [ "$OVERALL" -eq 0 ]; then
	echo "ALL SUITES PASSED"
else
	echo "AT LEAST ONE SUITE FAILED"
fi
exit "$OVERALL"
