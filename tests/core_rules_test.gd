extends "res://tests/app_test.gd"
## The fixed rules underneath everything: project settings, dice numbering and
## styles, d100 reading, table and dice physics, throw ranges and shake strength,
## the at-rest rule, the safety nets, the hop limit and the result bar's wording.

const TICKS: int = 120


func _init() -> void:
	test_name = "CORE RULES"
	uses_app = false


func run() -> void:
	_project_checks()
	_dice_checks()
	_format_checks()
	await _physics_checks()


func _project_checks() -> void:
	check(ProjectSettings.get_setting("physics/common/physics_ticks_per_second") == 120
			and ProjectSettings.get_setting("physics/3d/physics_engine") == "Jolt Physics"
			and is_equal_approx(ProjectSettings.get_setting("physics/3d/default_gravity"), 20.0),
			"Jolt physics at 120 steps a second, gravity 20")
	check(ProjectSettings.get_setting("display/window/size/viewport_width") == 540
			and ProjectSettings.get_setting("display/window/size/viewport_height") == 960
			and ProjectSettings.get_setting("display/window/stretch/aspect") == "expand"
			and ProjectSettings.get_setting("display/window/handheld/orientation") == 1,
			"portrait, designed at 540×960, taller phones get more room")
	check(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile") == "mobile"
			or ProjectSettings.get_setting("rendering/renderer/rendering_method") == "mobile",
			"Mobile renderer")
	check(ProjectSettings.get_setting("application/boot_splash/minimum_display_time") == 1200,
			"the splash shows for at least 1.2 s")


func _dice_checks() -> void:
	# Every face present once, opposite faces adding up the standard way.
	var sums: Dictionary = { "d6": 7, "d8": 9, "d12": 13, "d20": 21 }
	var ok: bool = true
	for type: String in ["d4", "d6", "d8", "d10", "d12", "d20"]:
		var d: Die = DiceFactory.create(type)[0]
		var values: Array[int] = []
		for f: Dictionary in d.faces:
			values.append(f["value"])
		values.sort()
		var sides: int = type.substr(1).to_int()
		var expected: Array[int] = []
		for i: int in range(1, sides + 1):
			expected.append(i)
		if values != expected:
			ok = false
			print("  %s faces: %s" % [type, values])
		if sums.has(type):
			for f: Dictionary in d.faces:
				for g: Dictionary in d.faces:
					var opposite: bool = (f["direction"] as Vector3).dot(g["direction"]) < -0.99
					if opposite and f["value"] + g["value"] != sums[type]:
						ok = false
		d.free()
	check(ok, "each die has every face once; opposite faces add up (d6 7, d8 9, d12 13, d20 21)")

	var styles_ok: bool = true
	for style: String in ["zero", "ten"]:
		var d10: Die = DiceFactory.create("d10", DiceFactory.DEFAULT_COLOR, style)[0]
		var vals: Array[int] = []
		for f: Dictionary in d10.faces:
			vals.append(f["value"])
		vals.sort()
		styles_ok = styles_ok and vals == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
		d10.free()
	check(styles_ok, "both d10 styles count 1–10 (the 0–9 style's 0 counts as 10)")

	var pair: Array[Die] = DiceFactory.create("d100")
	var tens: Array[int] = []
	var units: Array[int] = []
	for f: Dictionary in pair[0].faces:
		tens.append(f["value"])
	for f: Dictionary in pair[1].faces:
		units.append(f["value"])
	tens.sort()
	units.sort()
	check(pair.size() == 2 and tens == [0, 10, 20, 30, 40, 50, 60, 70, 80, 90] and units == [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
			"a d100 is two d10s: tens 00–90 and units 0–9")
	for d: Die in pair:
		d.free()

	var light: Die = DiceFactory.create("d6", Color(0.95, 0.93, 0.85))[0]
	var dark: Die = DiceFactory.create("d6", Color(0.1, 0.1, 0.1))[0]
	var body: Mesh = (light.get_node("Body") as MeshInstance3D).mesh
	var dark_body: Mesh = (dark.get_node("Body") as MeshInstance3D).mesh
	var ink_light: Color = (body.surface_get_material(body.get_surface_count() - 1) as StandardMaterial3D).albedo_color
	var ink_dark: Color = (dark_body.surface_get_material(dark_body.get_surface_count() - 1) as StandardMaterial3D).albedo_color
	check(ink_light == Color.BLACK and ink_dark == Color.WHITE, "black ink on light dice, white on dark")
	check(light.continuous_cd and is_equal_approx(light.physics_material_override.friction, 0.9)
			and is_equal_approx(light.physics_material_override.bounce, 0.15) and is_equal_approx(light.mass, 1.0),
			"dice: continuous collision detection, friction 0.9, bounce 0.15")
	light.free()
	dark.free()


func _format_checks() -> void:
	var d6: Array[Dictionary] = [
		{ "type": "d6", "value": 5, "color": "#fff", "label": "", "parts": [5] },
		{ "type": "d6", "value": 6, "color": "#fff", "label": "", "parts": [6] },
		{ "type": "d6", "value": 3, "color": "#fff", "label": "", "parts": [3] },
	]
	check(RollHistory.format_dice(d6, false) == "d6: 5  6  3  (total 14)"
			and RollHistory.format_dice(d6, true).ends_with("\nTotal: 14"),
			"matching dice are grouped, with the total: %s" % RollHistory.format_dice(d6, false))
	var labelled: Array[Dictionary] = [{ "type": "d6", "value": 5, "color": "#fff", "label": "Attack", "parts": [5] }]
	check(RollHistory.format_dice(labelled, false) == "Attack (d6): 5", "labels show as Attack (d6): 5, no total for one die")
	var d100: Array[Dictionary] = [{ "type": "d100", "value": 48, "color": "#fff", "label": "", "parts": [40, 8] }]
	check(RollHistory.format_dice(d100, false) == "d100: 48 (40 + 8)", "a d100 shows its parts: %s" % RollHistory.format_dice(d100, false))


func _physics_checks() -> void:
	var table: Table = Table.new()
	root.add_child(table)
	var shapes: int = 0
	for c: Node in table.get_children():
		if c is CollisionShape3D:
			shapes += 1
	check(shapes == 6 and table.size == Vector2(9.0, 15.0) and is_equal_approx(table.physics_material_override.friction, 1.0),
			"the table is 9×15 with floor, four walls and a ceiling; felt friction 1.0")

	var roller: DiceRoller = DiceRoller.new()
	roller.log_events = false
	root.add_child(roller)
	roller.set_dice([{ "type": "d6" }])
	var d: Die = roller.get_dice()[0]

	# Throw ranges and shake strength (only speed changes with power).
	var ranges_ok: bool = true
	var slow_max: float = 0.0
	var fast_min: float = INF
	for i: int in 200:
		var power: float = 0.0 if i % 2 == 0 else 1.0
		roller.set("_power", power)
		roller.call("_throw_die", d, Vector3(0.0, 2.0, 6.0), false)
		var flat: float = Vector2(d.linear_velocity.x, d.linear_velocity.z).length()
		var lift: float = d.linear_velocity.y
		if lift < 3.0 - 0.01 or lift > 6.0 + 0.01:
			ranges_ok = false
		if power == 0.0:
			slow_max = maxf(slow_max, flat)
		else:
			fast_min = minf(fast_min, flat)
		ranges_ok = ranges_ok and flat >= 10.0 * 0.8 - 0.01 and flat <= 17.0 * 1.25 + 0.01
	check(ranges_ok and slow_max <= 17.0 * 0.8 + 0.01 and fast_min >= 10.0 * 1.25 - 0.01,
			"throws: speed 10–17 scaled 0.8× (gentle) to 1.25× (hard), lift 3–6 (gentle max %.1f, hard min %.1f)" % [slow_max, fast_min])

	# At rest: still for 0.4 s; any movement restarts the wait.
	d.freeze = true
	d.linear_velocity = Vector3.ZERO
	d.angular_velocity = Vector3.ZERO
	var rest_ok: bool = not d.update_rest(0.39) and d.update_rest(0.02)
	d.freeze = false
	d.linear_velocity = Vector3(0.2, 0.0, 0.0)
	rest_ok = rest_ok and not d.update_rest(0.5)
	check(rest_ok, "a die counts as settled after 0.4 s below 0.1 units/s, and moving restarts that")

	# Safety net: a die that leaves the table goes to the bank, then is re-thrown onto it.
	var banked: Array[Die] = []
	roller.die_banked.connect(func(b: Die) -> void: banked.append(b))
	roller.roll(0.5)
	await physics_frames(3)
	d.global_position = Vector3(0.0, -5.0, 0.0)
	d.linear_velocity = Vector3.ZERO
	await physics_frames(3)
	await _finish(roller)
	check(banked.has(d) and roller.rethrow_count >= 1 and roller.to_local(d.global_position).y > -0.1,
			"a die that leaves the table is banked, then re-thrown onto it")

	# Safety net: a die still moving after the time limit is re-thrown.
	roller.rethrow_count = 0
	roller.roll_timeout = 0.3
	roller.roll(1.0)
	await physics_frames(int(0.6 * TICKS))
	var timed_out: int = roller.rethrow_count
	roller.roll_timeout = 10.0
	check(timed_out >= 1, "a die still moving after the time limit is re-thrown (%d re-throws)" % timed_out)
	await _finish(roller)

	# Hop limit: with no hops allowed, a cocked die goes straight to a full re-throw.
	var rules: Array[String] = []
	roller.debug_event.connect(func(_d: Die, info: Dictionary) -> void: rules.append(info["rule"]))
	roller.max_nudges = 0
	roller.debug_force = "lean"
	roller.roll(0.3)
	var steps: int = 0
	while rules.is_empty() and steps < TICKS * 20:
		await physics_frame
		steps += 1
	check(not rules.is_empty() and rules[0] == "still cocked", "once its hops are used up, a cocked die is re-thrown (%s)" % [rules])
	roller.debug_force = ""
	roller.max_nudges = 3
	await _finish(roller)

	# 00 + 0 reads as 100.
	var d100_roller: DiceRoller = DiceRoller.new()
	d100_roller.position = Vector3(40.0, 0.0, 0.0)
	root.add_child(d100_roller)
	d100_roller.set_dice([{ "type": "d100" }])
	for die: Die in d100_roller.get_dice():
		for f: Dictionary in die.faces:
			if f["value"] == 0:
				die.locked_entry = f
	var results: Array[Dictionary] = d100_roller.call("_collect_results")
	check(results[0]["value"] == 100 and results[0]["parts"] == [0, 0], "a d100 showing 00 and 0 reads as 100")


func _finish(roller: DiceRoller) -> void:
	var steps: int = 0
	while roller.is_rolling() and steps < TICKS * 40:
		await physics_frame
		steps += 1
