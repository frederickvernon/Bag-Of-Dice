#!/bin/bash
# Runs every test in this folder and prints a summary.
#
#   tests/run_all.sh           all tests (the fairness test takes about a minute)
#   tests/run_all.sh --quick   everything except the fairness test
#
# App tests use throwaway data files (test_*.json in the app's user folder),
# never your real sets, history or settings. Set GODOT to use a different
# Godot binary.

cd "$(dirname "$0")/.." || exit 1
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
DATA=(--sets-file=user://test_sets.json --history-file=user://test_history.json --settings-file=user://test_settings.json)
QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1

passed=0
failed=0
failed_names=()

# run_test "Name" godot-args…   (each test is stopped after 5 minutes)
run_test() {
	local name="$1"
	shift
	printf "%-22s " "$name"
	local out
	out=$(perl -e 'alarm 300; exec @ARGV' "$GODOT" --headless --path . "$@" 2>&1)
	if [ $? -eq 0 ]; then
		echo "PASS  $(echo "$out" | grep -oE 'ALL [0-9]+ [A-Z ]*CHECKS PASSED|Overall: PASS' | tail -1)"
		passed=$((passed + 1))
	else
		echo "FAIL"
		echo "$out" | grep -E "FAIL|SCRIPT ERROR|ERROR:|timed out|biased" | head -20 | sed 's/^/    /'
		failed=$((failed + 1))
		failed_names+=("$name")
	fi
}

echo "Importing project…"
"$GODOT" --headless --path . --import >/dev/null 2>&1

run_test "Set storage"       -s res://tests/store_test.gd
run_test "Roll history"      -s res://tests/history_test.gd
run_test "Shake detector"    -s res://tests/shake_detector_test.gd
run_test "Re-throw timing"   -s res://tests/rethrow_timing_test.gd
run_test "Start menu"        -s res://tests/start_menu_test.gd -- "${DATA[@]}"
run_test "Set flow"          -s res://tests/set_flow_test.gd -- "${DATA[@]}"
run_test "d100 limit"        -s res://tests/d100_limit_test.gd -- "${DATA[@]}"
run_test "Pick dice"         -s res://tests/pick_dice_test.gd -- "${DATA[@]}"
run_test "Throw from hand"   -s res://tests/throw_from_hand_test.gd -- "${DATA[@]}"
run_test "Shake cup"         -s res://tests/shake_cup_test.gd -- "${DATA[@]}"
run_test "Re-roll"           -s res://tests/reroll_test.gd -- "${DATA[@]}"
run_test "Sound switch"      -s res://tests/sound_switch_test.gd -- "${DATA[@]}"
if [ $QUICK -eq 0 ]; then
	run_test "Fairness"      res://tests/fairness_test.tscn --fixed-fps 120 -- --throws=2000
fi

echo
echo "$passed passed, $failed failed"
if [ $failed -gt 0 ]; then
	printf '  failed: %s\n' "${failed_names[@]}"
	exit 1
fi
