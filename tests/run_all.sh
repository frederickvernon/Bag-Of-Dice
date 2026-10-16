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
DATA=(--sets-file=user://test_sets.json --history-file=user://test_history.json --settings-file=user://test_settings.json
	--entitlements-file=user://test_entitlements.json --fake-store-file=user://test_fake_store.json)
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
	# Exit code 0 and the test's own "passed" line (a test that quits early has no such line).
	if [ $? -eq 0 ] && echo "$out" | grep -qE "CHECKS PASSED|Overall: PASS"; then
		echo "PASS  $(echo "$out" | grep -oE 'ALL [0-9]+ [A-Z ]*CHECKS PASSED|Overall: PASS' | tail -1)"
		passed=$((passed + 1))
	else
		echo "FAIL"
		echo "$out" | grep -E "FAIL|SCRIPT ERROR|ERROR:|timed out|biased" | head -20 | sed 's/^/    /'
		failed=$((failed + 1))
		failed_names+=("$name")
	fi
}

# Results file the tests also write (for phones); not needed on the Mac.
rm -f "$HOME/Library/Application Support/Godot/app_userdata/Bag Of Dice/test_results.log"

echo "Importing project…"
"$GODOT" --headless --path . --import >/dev/null 2>&1

run_test "Set storage"       -s res://tests/store_test.gd -- "${DATA[@]}"
run_test "Roll history"      -s res://tests/history_test.gd -- "${DATA[@]}"
run_test "Shake detector"    -s res://tests/shake_detector_test.gd -- "${DATA[@]}"
run_test "Re-throw timing"   -s res://tests/rethrow_timing_test.gd -- "${DATA[@]}"
run_test "Entitlements"      -s res://tests/entitlements_test.gd -- "${DATA[@]}"
run_test "Start menu"        -s res://tests/start_menu_test.gd -- "${DATA[@]}"
run_test "Set flow"          -s res://tests/set_flow_test.gd -- "${DATA[@]}"
run_test "d100 limit"        -s res://tests/d100_limit_test.gd -- "${DATA[@]}"
run_test "Pick dice"         -s res://tests/pick_dice_test.gd -- "${DATA[@]}"
run_test "Throw from hand"   -s res://tests/throw_from_hand_test.gd -- "${DATA[@]}"
run_test "Shake cup"         -s res://tests/shake_cup_test.gd -- "${DATA[@]}"
run_test "Re-roll"           -s res://tests/reroll_test.gd -- "${DATA[@]}"
run_test "Sound switch"      -s res://tests/sound_switch_test.gd -- "${DATA[@]}"
run_test "Settings & extras" -s res://tests/settings_extras_test.gd -- "${DATA[@]}"
run_test "Tap to roll"       -s res://tests/tap_to_roll_test.gd -- "${DATA[@]}"
run_test "Tutorial"          -s res://tests/tutorial_test.gd -- "${DATA[@]}"
if [ $QUICK -eq 0 ]; then
	run_test "Fairness"      res://tests/fairness_test.tscn --fixed-fps 120 -- --throws=2000 "${DATA[@]}"
fi

rm -f "$HOME/Library/Application Support/Godot/app_userdata/Bag Of Dice/test_results.log"
echo
echo "$passed passed, $failed failed"
if [ $failed -gt 0 ]; then
	printf '  failed: %s\n' "${failed_names[@]}"
	exit 1
fi
