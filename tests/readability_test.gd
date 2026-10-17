extends "res://tests/app_test.gd"
## Readability rule, ease-flat and the gentle hop:
## - every type reads a die tilted inside its limit and refuses one tilted past it;
## - a d6 leaning on the rim inside its limit is read with no hop and eases flat
##   without its result changing; past its limit it is hopped;
## - over many forced ambiguous landings, how often a hop frees the die, and how
##   often it lands on neither of the two faces it was leaning between.

const ARENA_SPACING: float = 25.0
## Forced landings per die type; --hop-samples=N to change (the phone runs fewer).
var hop_samples: int = 40
## Lean this far past each type's limit to force an ambiguous landing.
const LEAN_PAST_LIMIT: float = 8.0


func _init() -> void:
	test_name = "READABILITY"
	uses_app = false


func run() -> void:
	for arg: String in OS.get_cmdline_user_args() + Engine.get_meta("device_test_args", PackedStringArray()):
		if arg.begins_with("--hop-samples="):
			hop_samples = arg.get_slice("=", 1).to_int()
	_orientation_checks()
	await _rim_checks()
	await _hop_experiment()


## Pure orientation: tilt each die around a horizontal axis and read it.
func _orientation_checks() -> void:
	var all_ok: bool = true
	var limits: Array[String] = []
	for type: String in ["d4", "d6", "d8", "d10", "d12", "d20"]:
		var d: Die = DiceFactory.create(type)[0]
		d.freeze = true
		root.add_child(d)
		var limit: float = d.readable_limit_degrees()
		limits.append("%s %.1f°" % [type, limit])
		for i: int in 20:
			var flat: Basis = d.resting_basis(randf() * TAU)
			var value: int = d.faces[0]["value"]
			var axis: Vector3 = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
			d.global_basis = Basis(axis, deg_to_rad(limit * 0.9)) * flat
			var inside: int = d.get_top_face()
			d.global_basis = Basis(axis, deg_to_rad(limit * 1.1)) * flat
			var past: int = d.get_top_face()
			if inside != value or past != -1:
				all_ok = false
				print("  %s tilted %.1f°: read %d (want %d), past the limit read %d (want -1)" % [
						type, limit * 0.9, inside, value, past])
		d.queue_free()
	print("  readable limits: %s" % ", ".join(limits))
	check(all_ok, "every type reads a die tilted inside its limit, and refuses one tilted past it")
	var d4: Die = DiceFactory.create("d4")[0]
	check(absf(d4.readable_limit_degrees() - 27.37) < 0.1, "the d4 is read from its corners: limit about 27.4°")
	d4.free()


## A d6 leaned on the rim at 20° rests at about 18°: readable. At 30° it rests at about 28.5°: hopped.
func _rim_checks() -> void:
	var roller: DiceRoller = _arena(0, "d6")
	var d: Die = roller.get_dice()[0]
	roller.debug_force = "lean"
	roller.debug_lean_degrees = 20.0
	var finished: Array = []
	roller.roll_finished.connect(func(r: Array[Dictionary]) -> void: finished.append(r))
	roller.roll(0.3)
	var steps: int = 0
	while finished.is_empty() and steps < 120 * 20:
		await physics_frame
		steps += 1
	check(not finished.is_empty() and roller.nudge_count == 0 and roller.rethrow_count == 0,
			"a d6 leaning on the rim inside its limit is read with no hop (hops %d, re-throws %d)" % [
			roller.nudge_count, roller.rethrow_count])
	var result: int = (finished[0][0] as Dictionary)["value"] if not finished.is_empty() else -2
	var tilt: float = d.get_tilt_degrees()
	# Ease it flat as a waiting die would be, then hand it over as the roll end does.
	d.freeze = true
	d.ease_flat()
	await create_timer(Die.EASE_FLAT_SECONDS + 0.1).timeout
	var shown: Basis = d.global_basis * (d.get_node("Body") as Node3D).basis
	check(d.get_top_face() == result and absf(d.get_tilt_degrees() - tilt) < 0.01
			and (shown * (d.get_top_face_entry()["direction"] as Vector3)).angle_to(Vector3.UP) < deg_to_rad(1.0),
			"easing flat is visual: the die is shown flat on face %d and the physics body doesn't move" % result)
	d.bake_visual()
	check(d.get_top_face() == result and d.get_tilt_degrees() < 1.0,
			"handing it over keeps the result (%d) and the flat pose (tilt %.1f°, was %.1f°)" % [
			d.get_top_face(), d.get_tilt_degrees(), tilt])
	roller.queue_free()

	roller = _arena(1, "d6")
	roller.debug_force = "lean"
	roller.debug_lean_degrees = 30.0
	var rules: Array[String] = []
	roller.debug_event.connect(func(_d: Die, info: Dictionary) -> void: rules.append(info["rule"]))
	roller.roll(0.3)
	steps = 0
	while rules.is_empty() and steps < 120 * 20:
		await physics_frame
		steps += 1
	check(not rules.is_empty() and rules[0] == "cocked", "past its limit it is hopped (%s)" % [rules])
	roller.queue_free()


## Forces ambiguous landings for every type and follows the first hop of each.
func _hop_experiment() -> void:
	var types: Array[String] = ["d4", "d6", "d8", "d10", "d12", "d20"]
	## type -> { "forced", "hops", "freed", "between", "flipped" }
	var stats: Dictionary = {}
	var running: Array[int] = [0]
	for t: int in types.size():
		var type: String = types[t]
		stats[type] = { "forced": 0, "hops": 0, "freed": 0, "between": 0, "flipped": 0 }
		for i: int in hop_samples:
			var roller: DiceRoller = _arena(2 + t * hop_samples + i, type)
			var d: Die = roller.get_dice()[0]
			roller.debug_force = "lean"
			roller.debug_lean_degrees = d.readable_limit_degrees() + LEAN_PAST_LIMIT
			running[0] += 1
			_follow_first_hop(roller, d, stats[type], running)
			roller.roll(0.3)
	var steps: int = 0
	while running[0] > 0 and steps < 120 * 60:
		await physics_frame
		steps += 1
	var lines: Array[String] = []
	var flips: int = 0
	var hops: int = 0
	var freed: int = 0
	for type: String in types:
		var s: Dictionary = stats[type]
		lines.append("    %-4s %2d hops: %2d freed, %2d on one of its two faces, %2d flipped further" % [
				type, s["hops"], s["freed"], s["between"], s["flipped"]])
		flips += s["flipped"]
		hops += s["hops"]
		freed += s["freed"]
	print("  first hop of each forced ambiguous landing:\n" + "\n".join(lines))
	check(hops >= types.size() * hop_samples / 2, "enough ambiguous landings were forced (%d)" % hops)
	check(flips * 10 <= hops, "hops rarely land beyond the two faces the die leaned between (%d of %d)" % [flips, hops])
	check(freed * 10 >= hops * 7, "most hops free the die (%d of %d)" % [freed, hops])


## Watches one roller: records the two faces the die leans between at its first
## hop, then what it shows once it next settles.
func _follow_first_hop(roller: DiceRoller, d: Die, s: Dictionary, running: Array[int]) -> void:
	var leaning: Array[int] = []
	var done: Array[bool] = [false]
	var finish := func() -> void:
		if not done[0]:
			done[0] = true
			running[0] -= 1
			roller.set_physics_process(false)
			d.freeze = true
	roller.debug_event.connect(func(_d: Die, info: Dictionary) -> void:
		if done[0]:
			return
		if leaning.is_empty() and info["rule"] == "cocked":
			s["hops"] += 1
			leaning.append_array(_top_two(d))
		elif not leaning.is_empty():
			_score(d, leaning, s)
			finish.call())
	roller.roll_finished.connect(func(_r: Array[Dictionary]) -> void:
		if not leaning.is_empty() and not done[0]:
			_score(d, leaning, s)
		finish.call())


func _score(d: Die, leaning: Array[int], s: Dictionary) -> void:
	var now: int = _top_two(d)[0]
	if d.get_top_face() != -1:
		s["freed"] += 1
	if leaning.has(now):
		s["between"] += 1
	else:
		s["flipped"] += 1


## Indices of the two face directions pointing most nearly up.
func _top_two(d: Die) -> Array[int]:
	var order: Array[int] = []
	for i: int in d.faces.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return (d.global_basis * (d.faces[a]["direction"] as Vector3)).y > (d.global_basis * (d.faces[b]["direction"] as Vector3)).y)
	return [order[0], order[1]]


func _arena(index: int, type: String) -> DiceRoller:
	var offset: Vector3 = Vector3((index % 20) * ARENA_SPACING, 0.0, (index / 20) * ARENA_SPACING)
	var table: Table = Table.new()
	table.position = offset
	root.add_child(table)
	var roller: DiceRoller = DiceRoller.new()
	roller.position = offset
	roller.log_events = false
	root.add_child(roller)
	roller.set_dice([{ "type": type }])
	return roller
