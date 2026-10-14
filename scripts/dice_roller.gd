class_name DiceRoller
extends Node3D
## Owns the dice on one table: throws them, waits until every die has
## settled, fixes cocked dice, then reports the results.
##
## Place this node at the table's centre (the table surface is at local y = 0).

## Emitted once every die is at rest with a clear top face. Each result is
## plain data: { "type": "d6", "value": 4, "color": "#f2edd9", "label": "",
## "parts": [4] }.
## For a d100, "parts" is [tens, units] and "value" is 1–100.
signal roll_finished(results: Array[Dictionary])
## A die hit something, for sound effects. `kind`: "felt" (the table top),
## "wood" (the rim), "click" (another die) or "cup" (the hand holding them).
signal die_impact(kind: String, speed: float)

## Keep in step with Table.size.
@export var table_size: Vector2 = Vector2(9.0, 15.0)
@export var throw_speed_min: float = 10.0
@export var throw_speed_max: float = 17.0
## How much throw power (0–1, e.g. from shake strength) scales the speed:
## power 0 multiplies it by x, power 1 by y. Power only changes how hard the
## dice are thrown; their starting orientation and spin stay fully random, so
## it can't favour any face.
@export var power_speed_scale: Vector2 = Vector2(0.8, 1.25)
@export var spin_min: float = 15.0
@export var spin_max: float = 30.0
## Upward speed range at launch, so dice arc through the air and land at an
## angle (which makes them tumble) instead of skimming flat.
@export var throw_lift: Vector2 = Vector2(3.0, 6.0)
## Extra forward-tumbling spin (rad/s) around the axis that makes a die roll
## in the direction it's thrown, like a die flicked off the fingers.
@export var forward_spin: Vector2 = Vector2(12.0, 22.0)
## A resting die whose lowest corner is more than this above the table is
## lying on another die, not on the table, and is re-thrown.
@export var on_table_tolerance: float = 0.15
## Times to nudge a cocked die before re-throwing it.
@export var max_nudges: int = 3
## Safety net: re-throw a die that has kept moving for this many seconds
## without a break. Timed per die, from its own last throw / nudge, so a die
## that was just re-thrown always gets the full time to land.
@export var roll_timeout: float = 10.0
## Print nudges / re-throws to the Output panel.
@export var log_events: bool = true

## Counters for the fairness test.
var nudge_count: int = 0
var rethrow_count: int = 0

var _specs: Array[Dictionary] = []
var _dice: Array[Die] = []
## Dice taking part in the next throw (all, unless some were set aside with
## set_active_groups). The rest sit out, frozen in a row at the near edge.
var _active: Array[Die] = []
var _rolling: bool = false
## Set by roll(); the dice are actually launched at the next physics step.
var _throw_pending: bool = false
var _power: float = 0.5
var _from_current: bool = false


## Replaces the dice on the table. Each spec: { "type": "d6", "style": "pips",
## "color": Color, "label": "Attacker" } (all but "type" optional).
func set_dice(specs: Array[Dictionary]) -> void:
	for d: Die in _dice:
		# Remove now (not just at the end of the frame) so the new dice can
		# reuse the names.
		remove_child(d)
		d.queue_free()
	_dice.clear()
	_active.clear()
	_rolling = false
	_throw_pending = false
	_specs = specs.duplicate()

	for i: int in _specs.size():
		var color: Color = _specs[i].get("color", DiceFactory.DEFAULT_COLOR)
		for die: Die in DiceFactory.create(_specs[i]["type"], color, _specs[i].get("style", "")):
			die.group_index = i
			# Number by position in the set, e.g. "D20-6", so log messages say
			# which die they mean even when a set has several of one type.
			die.name = "%s-%d" % [die.name, i + 1]
			die.impact.connect(_on_die_impact)
			add_child(die)
			_dice.append(die)
			_active.append(die)

	# Lay them out in a row so they're visible before the first throw.
	for i: int in _dice.size():
		var x: float = (i - (_dice.size() - 1) * 0.5) * 1.3
		_dice[i].position = Vector3(clampf(x, -table_size.x * 0.5 + 0.7, table_size.x * 0.5 - 0.7), 1.0, 0.0)
		_dice[i].rotate_y(randf() * TAU)


func get_dice() -> Array[Die]:
	return _dice


## The spec (type / color / label) of one entry of the set.
func get_spec(index: int) -> Dictionary:
	return _specs[index] if index >= 0 and index < _specs.size() else {}


func get_active_dice() -> Array[Die]:
	return _active


## Chooses which entries of the set (by index in the specs given to
## set_dice; a d100's two dice share one) take part in the next throws. The
## others are frozen, dimmed and set aside in a row along the near edge of
## the table.
func set_active_groups(groups: Array[int]) -> void:
	_active.clear()
	var aside: Array[Die] = []
	for d: Die in _dice:
		if groups.has(d.group_index):
			_active.append(d)
			d.set_dimmed(false)
		else:
			aside.append(d)
	var half: Vector2 = table_size * 0.5
	var spacing: float = 1.4
	var columns: int = int((table_size.x - 1.4) / spacing) + 1
	for i: int in aside.size():
		var d: Die = aside[i]
		var row: int = int(i / float(columns))
		var col: int = i % columns
		var basis: Basis = d.resting_basis(randf_range(-0.3, 0.3))
		d.freeze = true
		d.global_transform = Transform3D(global_basis * basis, to_global(Vector3(
				(col - (columns - 1) * 0.5) * spacing,
				d.rest_height(basis),
				half.y - 0.9 - row * spacing)))
		d.set_dimmed(true)


## Every entry of the set takes part (the normal case).
func activate_all() -> void:
	var all: Array[int] = []
	for i: int in _specs.size():
		all.append(i)
	set_active_groups(all)


## World positions to hold the dice at before a throw: a loose cluster
## raised above the near half of the table, not overlapping. Throwing with
## from_current_positions launches them from wherever they are, e.g. these.
func hand_positions() -> Array[Vector3]:
	var count: int = _active.size()
	var spacing: float = 1.35
	var columns: int = mini(count, 4)
	var rows: int = ceili(float(count) / columns)
	var centre: Vector3 = Vector3(0.0, 4.0, table_size.y * 0.5 - 3.5)
	var positions: Array[Vector3] = []
	for i: int in count:
		var row: int = int(i / float(columns))
		var in_row: int = mini(columns, count - row * columns)
		var col: int = i % columns
		var p: Vector3 = centre + Vector3(
				(col - (in_row - 1) * 0.5) * spacing,
				randf_range(-0.2, 0.2),
				(row - (rows - 1) * 0.5) * spacing)
		positions.append(to_global(p))
	return positions


func is_rolling() -> bool:
	return _rolling


## Starts a roll. The throw itself happens at the next physics step, so dice
## are never teleported in the middle of other work (such as being lifted to
## the screen). With from_current_positions the dice launch from where they
## are now (they must be inside the table, e.g. at hand_positions()).
func roll(power: float = 0.5, from_current_positions: bool = false) -> void:
	if _active.is_empty():
		return
	_power = clampf(power, 0.0, 1.0)
	_from_current = from_current_positions
	_throw_pending = true
	_rolling = true


func _physics_process(delta: float) -> void:
	if not _rolling:
		return

	if _throw_pending:
		_throw_pending = false
		var starts: Array[Vector3] = _start_positions(_active.size())
		if _from_current:
			for i: int in _active.size():
				starts[i] = to_local(_active[i].global_position)
		for i: int in _active.size():
			_active[i].nudges = 0
			_throw_die(_active[i], starts[i])
		return

	# Safety net: a die should never get past the walls, but if one does,
	# throw it again rather than waiting for it to fall forever.
	for d: Die in _active:
		if _is_off_table(d):
			_log("%s left the table — re-throwing it" % d.name)
			_rethrow(d)

	# Update every die each frame (no early exit) so rest timers stay accurate.
	var all_resting: bool = true
	for d: Die in _active:
		if not d.update_rest(delta):
			all_resting = false
	if not all_resting:
		for d: Die in _active:
			if d.get_moving_time() > roll_timeout:
				_log("%s still moving after %.0f s — re-throwing it" % [d.name, roll_timeout])
				_rethrow(d)
		return

	# Everything has stopped. Every die must be lying on the table with a clear
	# top face; fix any that aren't, then wait for things to settle again.
	var any_cocked: bool = false
	for d: Die in _active:
		if not _is_on_table(d):
			# Resting on other dice. Re-throw rather than nudge, since a nudge
			# would just as likely disturb the dice underneath.
			any_cocked = true
			_log("%s landed on top of another die — re-throwing it" % d.name)
			_rethrow(d)
			continue
		if d.get_top_face() != -1:
			continue
		any_cocked = true
		if d.nudges < max_nudges:
			d.nudges += 1
			nudge_count += 1
			_log("%s is cocked — nudging (%d/%d)" % [d.name, d.nudges, max_nudges])
			d.nudge()
		else:
			_log("%s still cocked — re-throwing it" % d.name)
			_rethrow(d)
	if any_cocked:
		return

	_rolling = false
	roll_finished.emit(_collect_results())


## Works out what a die hit, for the sound: another die, the wooden rim (a
## mostly sideways hit near a wall) or the felt.
func _on_die_impact(d: Die, other: Node, speed: float) -> void:
	if other is Die:
		die_impact.emit("click", speed)
		return
	if not other is Table:
		die_impact.emit("cup", speed)
		return
	var v: Vector3 = d.get_prev_velocity()
	var p: Vector3 = to_local(d.global_position)
	var near_wall: bool = absf(p.x) > table_size.x * 0.5 - 1.2 or absf(p.z) > table_size.y * 0.5 - 1.2
	var sideways: bool = Vector2(v.x, v.z).length() > absf(v.y)
	die_impact.emit("wood" if near_wall and sideways else "felt", speed)


func _is_on_table(d: Die) -> bool:
	return d.get_lowest_point() - global_position.y <= on_table_tolerance


func _is_off_table(d: Die) -> bool:
	var p: Vector3 = to_local(d.global_position)
	var margin: float = 0.5
	return absf(p.x) > table_size.x * 0.5 + margin \
			or absf(p.z) > table_size.y * 0.5 + margin \
			or p.y < -margin or p.y > 10.0


func _collect_results() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for i: int in _specs.size():
		var parts: Array[int] = []
		for d: Die in _active:
			if d.group_index == i:
				parts.append(d.get_top_face())
		if parts.is_empty():
			continue  # sat this throw out
		var type: String = _specs[i]["type"]
		var value: int = 0
		for p: int in parts:
			value += p
		if type == "d100" and value == 0:
			value = 100  # "00" + "0"
		var color: Color = _specs[i].get("color", DiceFactory.DEFAULT_COLOR)
		results.append({
			"type": type, "value": value, "color": DicePalette.to_hex(color),
			"label": str(_specs[i].get("label", "")), "parts": parts,
		})
	return results


func _rethrow(d: Die) -> void:
	d.nudges = 0
	rethrow_count += 1
	_throw_die(d, _start_positions(1)[0])


## Launch from `local_start` toward a random point around the middle of the
## table, with a uniformly random orientation and random spin.
func _throw_die(d: Die, local_start: Vector3) -> void:
	var half: Vector2 = table_size * 0.5
	var target: Vector3 = Vector3(
		randf_range(-half.x + 1.5, half.x - 1.5),
		0.0,
		randf_range(-half.y * 0.4, half.y * 0.2))
	var direction: Vector3 = Vector3(target.x - local_start.x, 0.0, target.z - local_start.z).normalized()
	var speed: float = randf_range(throw_speed_min, throw_speed_max) \
			* lerpf(power_speed_scale.x, power_speed_scale.y, _power)
	var lin_vel: Vector3 = direction * speed \
			+ Vector3.UP * randf_range(throw_lift.x, throw_lift.y)
	var roll_axis: Vector3 = Vector3.UP.cross(direction)
	var ang_vel: Vector3 = _random_unit_vector() * randf_range(spin_min, spin_max) \
			+ roll_axis * randf_range(forward_spin.x, forward_spin.y)
	if _from_current and not d.freeze:
		# Thrown out of the cup: keep some of the motion it had from shaking.
		lin_vel += d.linear_velocity.limit_length(8.0) * 0.5
	d.throw(to_global(local_start), global_basis * Basis(_random_rotation()),
			global_basis * lin_vel, global_basis * ang_vel)


## Non-overlapping launch points stacked in a box at the near end of the table.
func _start_positions(count: int) -> Array[Vector3]:
	var half: Vector2 = table_size * 0.5
	var spacing: float = 1.4
	var columns: int = int((table_size.x - 2.0) / spacing) + 1
	var slots: Array[Vector3] = []
	var y: float = 2.0
	while slots.size() < count:
		for row: int in 2:
			for col: int in columns:
				var x: float = (col - (columns - 1) * 0.5) * spacing
				slots.append(Vector3(x, y, half.y - 1.2 - row * spacing))
		y += spacing
	slots.shuffle()
	var picked: Array[Vector3] = []
	for i: int in count:
		picked.append(slots[i] + Vector3(randf_range(-0.15, 0.15), 0.0, randf_range(-0.15, 0.15)))
	return picked


func _log(message: String) -> void:
	if log_events:
		print(message)


## Uniformly random orientation (Shoemake's method), so no face starts favoured.
static func _random_rotation() -> Quaternion:
	var u1: float = randf()
	var u2: float = randf() * TAU
	var u3: float = randf() * TAU
	var a: float = sqrt(1.0 - u1)
	var b: float = sqrt(u1)
	return Quaternion(a * sin(u2), a * cos(u2), b * sin(u3), b * cos(u3))


static func _random_unit_vector() -> Vector3:
	return Vector3(randfn(0.0, 1.0), randfn(0.0, 1.0), randfn(0.0, 1.0)).normalized()
