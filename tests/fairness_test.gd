extends Node3D
## Headless fairness test. Throws each die type thousands of times using the
## same DiceRoller and tables as the game, then reports how often each face
## came up and a chi-square test against a perfectly fair die.
##
## Run from the project folder:
##   Godot --headless --path . res://tests/fairness_test.tscn --fixed-fps 120 -- --throws=3000
## Options (all optional):
##   --throws=N     throws per die type (default 3000)
##   --arenas=N     tables per die type rolling in parallel (default 25)
##   --types=d6,d20 which types to test (default: all)
##   --seed=N       fixed random seed, to reproduce a run
##   --power=P      throw power 0–1 (default: random each throw, like real
##                  shakes of varying strength)

const ARENA_SPACING: float = 25.0

var _throws_per_type: int = 3000
var _arenas_per_type: int = 25
var _types: Array[String] = []
var _power: float = -1.0  # < 0 means random per throw

## type -> { "launched": int, "done": int, "counts": Dictionary (value -> int),
##           "tens": Dictionary, "units": Dictionary, "rollers": Array }
var _stats: Dictionary = {}
var _start_ms: int = 0
var _next_progress: float = 0.1


func _ready() -> void:
	_types = DiceFactory.TYPES.duplicate()
	for arg: String in OS.get_cmdline_user_args():
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

	print("Fairness test: %d throws each of %s, %d tables per type, power %s" \
			% [_throws_per_type, ", ".join(_types), _arenas_per_type,
			"random" if _power < 0.0 else str(_power)])
	_start_ms = Time.get_ticks_msec()

	for t_index: int in _types.size():
		var type: String = _types[t_index]
		_stats[type] = { "launched": 0, "done": 0, "counts": {}, "tens": {}, "units": {}, "rollers": [] }
		for a: int in _arenas_per_type:
			var offset: Vector3 = Vector3(a * ARENA_SPACING, 0.0, t_index * ARENA_SPACING)
			var table: Table = Table.new()
			table.position = offset
			add_child(table)
			var roller: DiceRoller = DiceRoller.new()
			roller.position = offset
			roller.log_events = false
			add_child(roller)
			roller.set_dice([{ "type": type }])
			roller.roll_finished.connect(_on_roll_finished.bind(type, roller))
			_stats[type]["rollers"].append(roller)
			_launch(type, roller)


func _launch(type: String, roller: DiceRoller) -> void:
	var s: Dictionary = _stats[type]
	if s["launched"] < _throws_per_type:
		s["launched"] += 1
		roller.roll(randf() if _power < 0.0 else _power)


func _on_roll_finished(results: Array[Dictionary], type: String, roller: DiceRoller) -> void:
	var s: Dictionary = _stats[type]
	var r: Dictionary = results[0]
	_bump(s["counts"], r["value"])
	if type == "d100":
		_bump(s["tens"], r["parts"][0])
		_bump(s["units"], r["parts"][1])
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


## Prints the report; returns true if no die looks biased.
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
		print("\n%s — %d throws, %d nudges, %d re-throws" % [type, s["done"], nudges, rethrows])
		if type == "d100":
			# 100 outcomes need far more throws to test directly, so test
			# each of the two d10s instead (that's what decides fairness).
			all_ok = _print_faces("tens die", s["tens"], _values(0, 90, 10), s["done"]) and all_ok
			all_ok = _print_faces("units die", s["units"], _values(0, 9, 1), s["done"]) and all_ok
		else:
			var sides: int = type.substr(1).to_int()
			all_ok = _print_faces(type, s["counts"], _values(1, sides, 1), s["done"]) and all_ok
	print("\nOverall: %s" % ("PASS — no die looks biased" if all_ok else "CHECK — at least one die looks biased (see above)"))
	print("(With 7 types, one borderline result now and then is normal chance; re-run with more throws to confirm.)")
	return all_ok


## Prints the frequency table and chi-square test for one die. Returns false
## if the result is suspicious (p < 0.01).
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
	print("  chi-square = %.2f, df = %d, p = %.3f  →  %s" % [chi, df, p, "OK" if ok else "SUSPICIOUS"])
	return ok


static func _bump(d: Dictionary, key: int) -> void:
	d[key] = d.get(key, 0) + 1


static func _values(from: int, to: int, step: int) -> Array[int]:
	var v: Array[int] = []
	for i: int in range(from, to + 1, step):
		v.append(i)
	return v


## Upper-tail p-value of the chi-square distribution, using the
## Wilson–Hilferty normal approximation (accurate enough for df >= 3).
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
