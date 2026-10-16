#!/bin/bash
# Runs the test suite on a connected Android phone, in a separate test copy of
# the app ("Bag Of Dice Tests", package com.btgog.bagofdice.tests), so the real
# app and its data are never touched. Needs USB debugging and the Android SDK.
#
#   tests/run_on_device.sh            every test (the fairness test is shortened)
#   tests/run_on_device.sh --quick    everything except the fairness test

cd "$(dirname "$0")/.." || exit 1
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
ADB="${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}"
PKG=com.btgog.bagofdice.tests
APK="${TMPDIR:-/tmp}/bag_of_dice_tests.apk"
QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1

echo "Building and installing the test copy…"
"$GODOT" --headless --path . --export-debug "Bag Of Dice Tests" "$APK" >/dev/null 2>&1 || { echo "Export failed"; exit 1; }
"$ADB" start-server >/dev/null 2>&1
"$ADB" install -r "$APK" >/dev/null 2>&1 || "$ADB" install -r "$APK" >/dev/null || { echo "Install failed"; exit 1; }

passed=0
failed=0
failed_names=()

# run_test "Name" "res://tests/x.gd [args]" [minutes]
run_test() {
	local name="$1" spec="$2" limit=$(( ${3:-4} * 60 ))
	printf "%-22s " "$name"
	"$ADB" shell am force-stop $PKG
	"$ADB" shell "echo '$spec' | run-as $PKG sh -c 'cat > files/next_test.txt; rm -f files/test_results.log'"
	"$ADB" shell am start -n $PKG/com.godot.game.GodotAppLauncher >/dev/null 2>&1
	sleep 3
	local waited=0
	while [ -n "$("$ADB" shell pidof $PKG)" ] && [ $waited -lt $limit ]; do
		sleep 2
		waited=$((waited + 2))
	done
	local out
	out=$("$ADB" shell run-as $PKG cat files/test_results.log 2>/dev/null)
	if [ $waited -ge $limit ]; then
		"$ADB" shell am force-stop $PKG
		out="$out
  FAIL timed out"
	fi
	if echo "$out" | grep -qE "FAIL|SUSPICIOUS|at least one die looks biased" || ! echo "$out" | grep -qE "CHECKS PASSED|Overall: PASS"; then
		echo "FAIL"
		echo "${out:-  (no results — the test did not run)}" | grep -vE "^$" | sed 's/^/    /' | head -20
		failed=$((failed + 1))
		failed_names+=("$name")
	else
		echo "PASS  $(echo "$out" | grep -oE 'ALL [0-9]+ [A-Z ]*CHECKS PASSED|Overall: PASS' | tail -1)"
		passed=$((passed + 1))
	fi
}

run_test "Set storage"       "res://tests/store_test.gd"
run_test "Roll history"      "res://tests/history_test.gd"
run_test "Shake detector"    "res://tests/shake_detector_test.gd"
run_test "Re-throw timing"   "res://tests/rethrow_timing_test.gd"
run_test "Entitlements"      "res://tests/entitlements_test.gd"
run_test "Start menu"        "res://tests/start_menu_test.gd"
run_test "Set flow"          "res://tests/set_flow_test.gd"
run_test "d100 limit"        "res://tests/d100_limit_test.gd"
run_test "Pick dice"         "res://tests/pick_dice_test.gd"
run_test "Throw from hand"   "res://tests/throw_from_hand_test.gd"
run_test "Shake cup"         "res://tests/shake_cup_test.gd"
run_test "Re-roll"           "res://tests/reroll_test.gd" 6
run_test "Sound switch"      "res://tests/sound_switch_test.gd"
run_test "Settings & extras" "res://tests/settings_extras_test.gd"
run_test "Tap to roll"       "res://tests/tap_to_roll_test.gd"
run_test "Tutorial"          "res://tests/tutorial_test.gd"
if [ $QUICK -eq 0 ]; then
	run_test "Fairness"      "res://tests/fairness_test.tscn --throws=600" 15
fi

echo
echo "$passed passed, $failed failed (on $("$ADB" shell getprop ro.product.model))"
if [ $failed -gt 0 ]; then
	printf '  failed: %s\n' "${failed_names[@]}"
	exit 1
fi
