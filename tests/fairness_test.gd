extends Node3D
## Throws each die type thousands of times with the game's DiceRoller and
## chi-square tests the face counts against a fair die.
##
## Run from the project folder:
##   Godot --headless --path . res://tests/fairness_test.tscn --fixed-fps 120 -- --throws=3000
## Options:
##   --throws=N     throws per die type (default 3000)
##   --arenas=N     parallel tables per die type (default 25)
##   --types=d6,d20 types to test (default: all)
##   --seed=N       fixed seed, to reproduce a run
##   --power=P      throw power 0–1 (default: random per throw)
##   --mode=M       re-throw mode: live, count or clear (default clear)
##   --dice=N       dice of the type on each table (default 1). With more than one,
##                  dice land on each other and get re-thrown, so the mode matters
##   --force-stack=P  chance (0–1) per roll of forcing one die onto another (debug builds),
##                  to make sure re-throws happen

const ARENA_SPACING: float = 25.0

var _throws_per_type: int = 3000
var _arenas_per_type: int = 25
var _types: Array[String] = []
var _power: float = -1.0  # < 0 means random per throw
var _mode: String = RethrowMode.CLEAR
var _dice_per_table: int = 1
var _force_stack: float = 0.0

## type -> { "launched": int, "done": int, "counts": Dictionary (value -> int),
##           "tens": Dictionary, "units": Dictionary, "rollers": Array }
var _stats: Dictionary = {}
var _start_ms: int = 0
var _next_progress: float = 0.1


func _ready() -> void:
	_types = DiceFactory.TYPES.duplicate()
	# On a phone, device_runner.gd passes the args through Engine metadata.
	for arg: String in OS.get_cmdline_user_args() + Engine.get_meta("device_test_args", PackedStringArray()):
		var value: String = arg.get_slice("=", 1)
		if arg.begins_with("--throws="):
			_throws_per_type = value.to_int()
		elif arg.begins_with("--arenas="):
			_arenas_per_type = value.to_int()
		elif arg.begins_with("--types="):
			_types.clear()
			for t: String in value.split(","):
				_types.append(t.strip_edges())
		elif arg.begins_with("--power="):
			_power = value.to_float()
		elif arg.begins_with("--seed="):
			seed(value.to_int())
		elif arg.begins_with("--mode="):
			_mode = RethrowMode.clean_global(value)
		elif arg.begins_with("--dice="):
			_dice_per_table = maxi(1, value.to_int())
		elif arg.begins_with("--force-stack="):
			_force_stack = value.to_float()

	print("Fairness test: %d throws each of %s, %d tables per type, power %s, mode %s, %d dice per table, forced stacks %.0f%%" \
			% [_throws_per_type, ", ".join(_types), _arenas_per_type,
			"random" if _power < 0.0 else str(_power), _mode, _dice_per_table, _force_stack * 100.0])
	_start_ms = Time.get_ticks_msec()

	for t_index: int in _types.size():
		var type: String = _types[t_index]
		_stats[type] = { "launched": 0, "done": 0, "results": 0, "locked": 0, "counts": {}, "tens": {}, "units": {},
				"rollers": [] }
		for a: int in _arenas_per_type:
			var offset: Vector3 = Vector3(a * ARENA_SPACING, 0.0, t_index * ARENA_SPACING)
			var table: Table = Table.new()
			table.position = offset
			add_child(table)
			var roller: DiceRoller = DiceRoller.new()
			roller.position = offset
			roller.log_events = false
			add_child(roller)
			roller.rethrow_mode = _mode
			var specs: Array[Dictionary] = []
			for i: int in _dice_per_table:
				specs.append({ "type": type })
			roller.set_dice(specs)
			roller.roll_finished.connect(_on_roll_finished.bind(type, roller))
			_stats[type]["rollers"].append(roller)
			_launch(type, roller)


func _launch(type: String, roller: DiceRoller) -> void:
	var s: Dictionary = _stats[type]
	if s["launched"] < _throws_per_type:
		s["launched"] += 1
		roller.debug_force = "stack" if randf() < _force_stack else ""
		roller.roll(randf() if _power < 0.0 else _power)


func _on_roll_finished(results: Array[Dictionary], type: String, roller: DiceRoller) -> void:
	var s: Dictionary = _stats[type]
	for r: Dictionary in results:
		_bump(s["counts"], r["value"])
		if type == "d100":
			_bump(s["tens"], r["parts"][0])
			_bump(s["units"], r["parts"][1])
		s["results"] += 1
		if r.get("locked", false):
			s["locked"] += 1
	s["done"] += 1
	_launch(type, roller)
	_report_progress()


func _report_progress() -> void:
	var total_done: int = 0
	for type: String in _types:
		total_done += _stats[type]["done"]
	var fraction: float = float(total_done) / float(_throws_per_type * _types.size())
	if fraction >= _next_progress:
		print("  %d%% (%.0f s)" % [roundi(fraction * 100.0), (Time.get_ticks_msec() - _start_ms) / 1000.0])
		_next_progress += 0.1
	if total_done >= _throws_per_type * _types.size():
		# Exit code 1 if any die looks biased, for run_all.sh.
		get_tree().quit(0 if _print_report() else 1)


## Returns true if no die looks biased.
func _print_report() -> bool:
	print("\n===== Fairness report (%.0f s) =====" % ((Time.get_ticks_msec() - _start_ms) / 1000.0))
	var all_ok: bool = true
	for type: String in _types:
		var s: Dictionary = _stats[type]
		var nudges: int = 0
		var rethrows: int = 0
		for roller: DiceRoller in s["rollers"]:
			nudges += roller.nudge_count
			rethrows += roller.rethrow_count
		preload("res://tests/test_log.gd").line("%s (%s) — %d throws, %d dice read, %d hops, %d re-throws, %d results locked before a re-throw" % [
				type, _mode, s["done"], s["results"], nudges, rethrows, s["locked"]])
		if type == "d100":
			# 100 outcomes need far more throws; test each d10 instead.
			all_ok = _print_faces("tens die", s["tens"], _values(0, 90, 10), s["results"]) and all_ok
			all_ok = _print_faces("units die", s["units"], _values(0, 9, 1), s["results"]) and all_ok
		else:
			var sides: int = type.substr(1).to_int()
			all_ok = _print_faces(type, s["counts"], _values(1, sides, 1), s["results"]) and all_ok
	preload("res://tests/test_log.gd").line("Overall: %s" % ("PASS — no die looks biased" if all_ok else "CHECK — at least one die looks biased (see above)"))
	print("(With 7 types, one borderline result now and then is normal chance; re-run with more throws to confirm.)")
	return all_ok


## Returns false if suspicious (p < 0.01).
func _print_faces(title: String, counts: Dictionary, faces: Array[int], n: int) -> bool:
	var expected: float = float(n) / faces.size()
	var chi: float = 0.0
	var lines: PackedStringArray = PackedStringArray()
	for f: int in faces:
		var c: int = counts.get(f, 0)
		chi += pow(c - expected, 2.0) / expected
		lines.append("    %3d: %5d  (%5.2f%%)" % [f, c, 100.0 * c / n])
	var df: int = faces.size() - 1
	var p: float = _chi_square_p(chi, df)
	var ok: bool = p >= 0.01
	print("  %s: expected %.1f per face (%.2f%%)" % [title, expected, 100.0 / faces.size()])
	print("\n".join(lines))
	preload("res://tests/test_log.gd").line("  %s: chi-square = %.2f, df = %d, p = %.3f  →  %s" % [title, chi, df, p, "OK" if ok else "SUSPICIOUS"])
	return ok


static func _bump(d: Dictionary, key: int) -> void:
	d[key] = d.get(key, 0) + 1


static func _values(from: int, to: int, step: int) -> Array[int]:
	var v: Array[int] = []
	for i: int in range(from, to + 1, step):
		v.append(i)
	return v


## Upper-tail p-value via Wilson–Hilferty (accurate enough for df >= 3).
static func _chi_square_p(chi: float, df: int) -> float:
	var k: float = float(df)
	var z: float = (pow(chi / k, 1.0 / 3.0) - (1.0 - 2.0 / (9.0 * k))) / sqrt(2.0 / (9.0 * k))
	return 1.0 - _normal_cdf(z)


static func _normal_cdf(z: float) -> float:
	# Abramowitz & Stegun 7.1.26 approximation of erf.
	var x: float = absf(z) / sqrt(2.0)
	var t: float = 1.0 / (1.0 + 0.3275911 * x)
	var erf: float = 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t \
			- 0.284496736) * t + 0.254829592) * t * exp(-x * x)
	return 0.5 * (1.0 + (erf if z >= 0.0 else -erf))
