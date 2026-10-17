extends Node3D
## Diagnosis, not a pass/fail test: throws real sets many times and reports why
## dice get hopped or re-thrown (which rule fired, tilt, lowest corner, what
## the die touched), plus how flat accepted dice really lie. Then leans a d6
## on the rim at a range of angles to see which tilts can actually hold.
##
## Run from the project folder:
##   Godot --headless --path . res://tests/rethrow_diagnosis.tscn --fixed-fps 120 -- --rolls=200
## Options:
##   --rolls=N   rolls per set (default 200)
##   --seed=N    fixed seed, to reproduce a run

const ARENA_SPACING: float = 25.0
const ARENAS: int = 10
const SETS: Dictionary = {
	"8d6": ["d6", "d6", "d6", "d6", "d6", "d6", "d6", "d6"],
	"RPG": ["d4", "d6", "d8", "d10", "d12", "d20", "d100"],
}
const LEAN_ANGLES: Array[float] = [8.0, 12.0, 16.0, 20.0, 25.0, 30.0, 35.0, 40.0]

var _rolls: int = 200
var _events: Array[Dictionary] = []
## Every die accepted at the end of a roll: { "type", "tilt", "lowest" }.
var _accepted: Array[Dictionary] = []
var _launched: Dictionary = {}
var _finished: int = 0
var _expected: int = 0
var _lean_results: Array[String] = []
## Parked-dice check: hits from thrown dice on parked ones, and whether any parked die moved.
var _parked_hits: int = 0
var _parked_hit_rolls: Dictionary = {}
var _parked_moved: int = 0
var _parked_rolls: int = 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--rolls="):
			_rolls = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--seed="):
			seed(arg.get_slice("=", 1).to_int())
	print("Re-throw diagnosis: %d rolls of each of %s" % [_rolls, ", ".join(SETS.keys())])
	var row: int = 0
	for set_name: String in SETS:
		_launched[set_name] = 0
		_expected += _rolls
		for a: int in ARENAS:
			var roller: DiceRoller = _arena(Vector3(a * ARENA_SPACING, 0.0, row * ARENA_SPACING))
			var specs: Array[Dictionary] = []
			for t: String in SETS[set_name]:
				specs.append({ "type": t })
			roller.set_dice(specs)
			roller.debug_event.connect(func(d: Die, info: Dictionary) -> void:
				info["set"] = set_name
				info["type"] = d.die_type
				_events.append(info))
			roller.roll_finished.connect(_on_roll_finished.bind(set_name, roller))
			_launch(set_name, roller)
		row += 1
	_parked_check(row)


func _arena(offset: Vector3) -> DiceRoller:
	var table: Table = Table.new()
	table.position = offset
	add_child(table)
	var roller: DiceRoller = DiceRoller.new()
	roller.position = offset
	roller.log_events = false
	add_child(roller)
	return roller


## 8d6 with only 2 thrown and 6 parked along the near edge, like a Risk-style set.
func _parked_check(row: int) -> void:
	_expected += _rolls
	_launched["parked"] = 0
	for a: int in ARENAS:
		var roller: DiceRoller = _arena(Vector3(a * ARENA_SPACING, 0.0, row * ARENA_SPACING))
		var specs: Array[Dictionary] = []
		for i: int in 8:
			specs.append({ "type": "d6" })
		roller.set_dice(specs)
		roller.set_active_groups([0, 1])
		roller.debug_event.connect(func(d: Die, info: Dictionary) -> void:
			info["set"] = "parked"
			info["type"] = d.die_type
			_events.append(info))
		var parked: Array[Die] = []
		var start: Array[Transform3D] = []
		for d: Die in roller.get_dice():
			if not roller.get_active_dice().has(d):
				parked.append(d)
				start.append(d.global_transform)
		for d: Die in roller.get_active_dice():
			d.impact.connect(func(_d: Die, other: Node, _speed: float) -> void:
				if other is Die and parked.has(other as Die):
					_parked_hits += 1
					_parked_hit_rolls[roller.get_instance_id() * 1000 + int(_launched["parked"])] = true)
		roller.roll_finished.connect(func(_r: Array[Dictionary]) -> void:
			_parked_rolls += 1
			for i: int in parked.size():
				if not parked[i].global_transform.is_equal_approx(start[i]):
					_parked_moved += 1
			_on_roll_finished(_r, "parked", roller))
		_launch("parked", roller)


func _launch(set_name: String, roller: DiceRoller) -> void:
	if _launched[set_name] < _rolls:
		_launched[set_name] += 1
		roller.roll(randf())


func _on_roll_finished(_results: Array[Dictionary], set_name: String, roller: DiceRoller) -> void:
	for d: Die in roller.get_active_dice():
		_accepted.append({ "type": d.die_type, "tilt": d.get_tilt_degrees(),
				"lowest": d.get_lowest_point() - roller.global_position.y,
				"touching": roller.touching(d) })
	_finished += 1
	_launch(set_name, roller)
	if _finished == _expected:
		await _lean_experiment()
		_report()
		get_tree().quit()


## One d6 per arena, leaned on the rim at each angle; what does it settle to?
func _lean_experiment() -> void:
	for i: int in LEAN_ANGLES.size():
		var roller: DiceRoller = _arena(Vector3(i * ARENA_SPACING, 0.0, 5 * ARENA_SPACING))
		roller.set_dice([{ "type": "d6" }])
		var d: Die = roller.get_dice()[0]
		d.position = Vector3(0.0, d.rest_height(d.resting_basis()), 0.0)
		roller.debug_force = "lean"
		roller.debug_lean_degrees = LEAN_ANGLES[i]
		var first: Array[Dictionary] = []
		roller.debug_event.connect(func(_d: Die, info: Dictionary) -> void:
			if first.is_empty():
				first.append(info))
		roller.roll(0.0)
		# Wait for the throw to settle and the forced lean to happen, then until something fires or it ends.
		var waited: int = 0
		while roller.is_rolling() and first.is_empty() and waited < 120 * 20:
			await get_tree().physics_frame
			waited += 1
		var what: String
		if first.is_empty():
			what = "settled readable: tilt %.1f°, touching %s" % [d.get_tilt_degrees(), ", ".join(roller.touching(d))]
		else:
			var info: Dictionary = first[0]
			what = "%s: tilt %.1f°, lowest %.3f, touching %s" % [info["rule"], info["tilt"], info["lowest"],
					", ".join(info["touching"])]
		_lean_results.append("  leaned at %2.0f° → %s" % [LEAN_ANGLES[i], what])
		roller.set_physics_process(false)


func _report() -> void:
	print("\n== Hops and re-throws (%d events) ==" % _events.size())
	var by_rule: Dictionary = {}
	for e: Dictionary in _events:
		var key: String = "%s / %s" % [e["set"], e["rule"]]
		by_rule[key] = by_rule.get(key, 0) + 1
	for k: String in by_rule:
		print("  %-40s %d" % [k, by_rule[k]])

	print("\n== Cocked dice: what propped them up ==")
	var props: Dictionary = {}
	var tilt_buckets: Dictionary = {}
	var felt_only: Array[String] = []
	for e: Dictionary in _events:
		if not (e["rule"] as String).contains("cocked"):
			continue
		var cat: String = _prop_category(e["touching"])
		props[cat] = props.get(cat, 0) + 1
		var bucket: String = _tilt_bucket(e["tilt"])
		tilt_buckets[bucket] = tilt_buckets.get(bucket, 0) + 1
		if cat == "felt only" or cat == "nothing":
			felt_only.append("    %s tilt %.1f°, lowest %.3f" % [e["type"], e["tilt"], e["lowest"]])
	for k: String in props:
		print("  %-30s %d" % [k, props[k]])
	print("  tilt when cocked:")
	for k: String in ["10–15°", "15–22°", "22–30°", "30–45°", "45°+"]:
		print("    %-8s %d" % [k, tilt_buckets.get(k, 0)])
	if not felt_only.is_empty():
		print("  cocked with nothing but felt under it (should be impossible on a flat table):")
		for line: String in felt_only.slice(0, 15):
			print(line)

	print("\n== Stacked dice: lowest corner and contacts ==")
	var stacked: int = 0
	for e: Dictionary in _events:
		if (e["rule"] as String).contains("another die"):
			stacked += 1
			if stacked <= 8:
				print("  %s tilt %.1f°, lowest %.3f, touching %s" % [e["type"], e["tilt"], e["lowest"],
						", ".join(e["touching"])])

	print("\n== Accepted dice (%d): how flat they really lie ==" % _accepted.size())
	var per_type: Dictionary = {}
	for a: Dictionary in _accepted:
		var s: Dictionary = per_type.get(a["type"], { "n": 0, "tilt_max": 0.0, "low_min": INF, "low_max": -INF,
				"low_sum": 0.0, "propped": 0 })
		s["n"] += 1
		s["tilt_max"] = maxf(s["tilt_max"], a["tilt"])
		s["low_min"] = minf(s["low_min"], a["lowest"])
		s["low_max"] = maxf(s["low_max"], a["lowest"])
		s["low_sum"] += a["lowest"]
		if _prop_category(a["touching"]) != "felt only":
			s["propped"] += 1
		per_type[a["type"]] = s
	for t: String in per_type:
		var s: Dictionary = per_type[t]
		print("  %-4s n=%-5d max tilt %.2f°  lowest corner min %.4f / mean %.4f / max %.4f  touching more than felt: %d" % [
				t, s["n"], s["tilt_max"], s["low_min"], s["low_sum"] / s["n"], s["low_max"], s["propped"]])

	print("\n== Parked dice (2 thrown, 6 parked, %d rolls) ==" % _parked_rolls)
	print("  thrown dice hit a parked die %d times, in %d rolls; parked dice moved %d times" % [
			_parked_hits, _parked_hit_rolls.size(), _parked_moved])
	var parked_events: Dictionary = {}
	for e: Dictionary in _events:
		if e["set"] == "parked":
			parked_events[e["rule"]] = parked_events.get(e["rule"], 0) + 1
	print("  hops/re-throws in these rolls: %s" % parked_events)

	print("\n== d6 leaned on the rim ==")
	for line: String in _lean_results:
		print(line)


func _prop_category(touching: Array) -> String:
	if touching.is_empty():
		return "nothing"
	var rim: bool = touching.has("rim")
	var die: bool = false
	for t: String in touching:
		if t != "felt" and t != "rim" and t != "cup":
			die = true
	if rim and die:
		return "rim and another die"
	if rim:
		return "rim"
	if die:
		return "another die"
	return "felt only"


func _tilt_bucket(tilt: float) -> String:
	if tilt < 15.0:
		return "10–15°"
	if tilt < 22.0:
		return "15–22°"
	if tilt < 30.0:
		return "22–30°"
	if tilt < 45.0:
		return "30–45°"
	return "45°+"
