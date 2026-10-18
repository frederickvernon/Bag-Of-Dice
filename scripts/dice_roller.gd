class_name DiceRoller
extends Node3D
## Throws the dice on one table, waits for all to settle, fixes cocked dice and reports results.
## Place at the table's centre; the table surface is at local y = 0.

## Emitted once every die rests with a clear top face. Each result looks like
## { "type": "d6", "value": 4, "color": "#f2edd9", "label": "", "parts": [4] };
## a d100 has parts [tens, units] and value 1–100.
signal roll_finished(results: Array[Dictionary])
## A die hit something, for sound effects. `kind`: "felt" (the table top),
## "wood" (the rim), "click" (another die) or "cup" (the hand holding them).
signal die_impact(kind: String, speed: float)
## Debug builds only: a die is about to be hopped or re-thrown. `info` is diagnose()'s answer.
signal debug_event(die: Die, info: Dictionary)
## Clear the table: these dice (all set aside so far, in set order) were read and moved
## into the drawer before a re-throw. They're frozen and no longer collide.
signal dice_cleared(dice: Array[Die])
## `count` dice are being fully re-thrown (not hopped), for the "Re-rolling 1 die" note.
signal rethrow_started(count: int)
## A die was taken off the table into the bank, to wait for the next re-throw.
signal die_banked(die: Die)
## Re-roll by hand: the table has settled and these banked dice are ready for the player
## to throw (call throw_bank()). The mode's step (drawer, counting) has already happened.
signal bank_ready(dice: Array[Die])

## Re-throw tuning, in one place.
## Live table: re-throw rounds before the remaining problem dice are handled as in Clear the table.
const LIVE_ROUND_CAP: int = 3
## A die that lands on other dice this many times switches the roll to Clear the table.
const ESCALATE_AFTER_STACKS: int = 2
## Count where they land and Live table aim re-throws at open space: candidate landing
## points sampled, how many of the best to pick from at random, and throw directions tried.
const TARGET_SAMPLES: int = 32
const TARGET_PICK_FROM: int = 4
const TARGET_DIRECTIONS: int = 12
## Keep candidate points this far inside the walls; a wall counts as near as a die this far
## away (scaled), so dice aren't aimed into corners.
const TARGET_EDGE_MARGIN: float = 1.0
const TARGET_WALL_WEIGHT: float = 1.5
## How far before the target the die is launched, and its speeds (horizontal, upward).
const TARGET_RUN: float = 3.5
const TARGET_SPEED: Vector2 = Vector2(3.5, 5.5)
const TARGET_LIFT: Vector2 = Vector2(3.0, 5.0)

## Keep in step with Table.size.
@export var table_size: Vector2 = Vector2(9.0, 15.0)
## The drawer along the near edge, where dice wait out of play (keep in step with
## Table: drawer_front() to drawer_back(), felt at drawer_floor()).
@export var drawer_z: Vector2 = Vector2(7.72, 10.42)
@export var drawer_floor: float = -0.06
## Seconds a set-aside die takes to slide into the drawer.
@export var drawer_slide_time: float = 0.45
## Where banked dice are held (table-local): height above the felt, and distance in from the near edge.
@export var bank_height: float = 3.2
@export var bank_inset: float = 2.2
@export var throw_speed_min: float = 10.0
@export var throw_speed_max: float = 17.0
## Speed multiplier at throw power 0 (x) and 1 (y); power is 0–1, e.g. shake strength.
## Power never affects orientation or spin, so it can't favour a face.
@export var power_speed_scale: Vector2 = Vector2(0.8, 1.25)
@export var spin_min: float = 15.0
@export var spin_max: float = 30.0
## Upward launch speed range, so dice arc and land at an angle (and tumble) instead of skimming flat.
@export var throw_lift: Vector2 = Vector2(3.0, 6.0)
## Extra forward-tumbling spin (rad/s) in the throw direction, like a die flicked off the fingers.
@export var forward_spin: Vector2 = Vector2(12.0, 22.0)
## A resting die whose lowest corner is more than this above the table is
## lying on another die, not on the table, and is re-thrown.
@export var on_table_tolerance: float = 0.15
## Times to nudge a cocked die before re-throwing it.
@export var max_nudges: int = 3
## Re-throw a die still moving after this many seconds.
## Timed per die from its own last throw or nudge, so a re-thrown die gets the full time.
@export var roll_timeout: float = 10.0
## Print nudges / re-throws to the Output panel.
@export var log_events: bool = true

## What happens to the other dice when one is re-thrown (a RethrowMode id, already resolved).
var rethrow_mode: String = RethrowMode.CLEAR
## Re-roll by hand: banked dice wait for throw_bank() instead of being thrown automatically.
var manual_rethrow: bool = false

## Debug builds only: the next roll gets a problem landing once its dice settle,
## to try out hops and re-throws. "lean": a die leaning on the rim; "stack": a die set down on another die.
var debug_force: String = ""
## Tilt (degrees) of the "lean" debug landing.
var debug_lean_degrees: float = 30.0

## Counters for the fairness test.
var nudge_count: int = 0
var rethrow_count: int = 0

var _specs: Array[Dictionary] = []
var _dice: Array[Die] = []
## Dice in the next throw; the rest sit out, frozen in a row at the near edge.
var _active: Array[Die] = []
var _rolling: bool = false
## Set by roll(); the dice are actually launched at the next physics step.
var _throw_pending: bool = false
var _power: float = 0.5
var _from_current: bool = false
var _force_pending: bool = false
## This roll: dice read and lifted off the table (Clear the table), re-throw rounds
## (Live table cap), and whether the roll has switched to Clear the table.
var _cleared: Array[Die] = []
## The bank: dice that need a full re-throw, lifted off the table and held above its
## near end. Once every die on the table has settled, the whole bank is thrown together.
var _bank: Array[Die] = []
## Re-roll by hand: the bank is ready and waiting for the player's throw, in this mode.
var _bank_waiting: bool = false
var _bank_mode: String = RethrowMode.CLEAR
## Drawer slot positions (table-local) for this set, front-left first, and which die holds each.
var _slots: Array[Vector3] = []
var _slot_of: Dictionary = {}  # Die -> slot index
var _rounds: int = 0
var _escalated: bool = false


## Replaces the dice on the table. Each spec: { "type": "d6", "style": "pips",
## "color": Color, "label": "Attacker" } (all but "type" optional).
func set_dice(specs: Array[Dictionary]) -> void:
	for d: Die in _dice:
		# Remove now, not at end of frame, so the new dice can reuse the names.
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
			# Suffix the set position (e.g. "D20-6") so logs can tell same-type dice apart.
			die.name = "%s-%d" % [die.name, i + 1]
			die.impact.connect(_on_die_impact)
			add_child(die)
			_dice.append(die)
			_active.append(die)

	_slots = _drawer_slots(_dice.size())
	_slot_of.clear()

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


## Picks which set entries (indices into set_dice's specs; a d100's two dice share one) take part.
## The rest are frozen, greyed and put in the drawer, filling its slots from the back.
func set_active_groups(groups: Array[int]) -> void:
	_active.clear()
	_slot_of.clear()
	var aside: Array[Die] = []
	for d: Die in _dice:
		if groups.has(d.group_index):
			_active.append(d)
			d.set_dimmed(false)
		else:
			aside.append(d)
	for i: int in aside.size():
		var d: Die = aside[i]
		var slot: int = _slots.size() - aside.size() + i
		_slot_of[d] = slot
		d.freeze = true
		d.set_dimmed(true)
		d.global_transform = _slot_transform(d, slot, d.resting_basis(randf_range(-0.3, 0.3)))


func activate_all() -> void:
	var all: Array[int] = []
	for i: int in _specs.size():
		all.append(i)
	set_active_groups(all)


## Where to hold the dice before a throw: a loose, non-overlapping cluster above the near half.
## roll() with from_current_positions launches them from there.
## `count`: how many dice (default: every thrown die).
func hand_positions(count: int = -1) -> Array[Vector3]:
	if count < 0:
		count = _active.size()
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


## The throw is deferred to the next physics step so dice never teleport mid-work (e.g. while being lifted).
## With from_current_positions dice launch from where they are, which must be inside the table.
func roll(power: float = 0.5, from_current_positions: bool = false) -> void:
	if _active.is_empty():
		return
	_power = clampf(power, 0.0, 1.0)
	_from_current = from_current_positions
	_throw_pending = true
	_rolling = true
	_force_pending = OS.is_debug_build() and not debug_force.is_empty()


func _physics_process(delta: float) -> void:
	if not _rolling:
		return

	if _throw_pending:
		_throw_pending = false
		for d: Die in _cleared + _bank:
			_slot_of.erase(d)
			_stop_slide(d)
		_cleared.clear()
		_bank.clear()
		_bank_waiting = false
		_rounds = 0
		_escalated = false
		var starts: Array[Vector3] = _start_positions(_active.size())
		if _from_current:
			for i: int in _active.size():
				starts[i] = to_local(_active[i].global_position)
		for i: int in _active.size():
			var d: Die = _active[i]
			d.nudges = 0
			d.rethrows = 0
			d.stack_rethrows = 0
			d.locked_entry = {}
			d.set_counted(false)
			_throw_die(d, starts[i], _from_current)
		return

	if _bank_waiting:
		return  # the table is still; the player is holding the bank

	var in_play: Array[Die] = in_play_dice()
	# Safety net: a die that escapes the walls goes to the bank instead of falling forever.
	for d: Die in in_play:
		if _is_off_table(d):
			_report(d, "left the table", "banking it")
			_bank_die(d)
	in_play = in_play_dice()

	# Update every die each frame (no early exit) so rest timers stay accurate.
	var all_resting: bool = true
	for d: Die in in_play:
		if not d.update_rest(delta):
			all_resting = false
	if not all_resting:
		for d: Die in in_play:
			if d.get_moving_time() > roll_timeout:
				_report(d, "still moving after %.0f s" % roll_timeout, "banking it")
				_bank_die(d)
		return

	if _force_pending:
		_force_pending = false
		_apply_debug_force()
		return

	# Everything on the table has stopped. Hop dice that can't be read; bank dice lying
	# on other dice, or still unreadable after their hops. Counted dice keep their
	# result whatever happened.
	var hopping: bool = false
	var banked: bool = false
	for d: Die in in_play:
		if not d.locked_entry.is_empty():
			continue
		if not _is_on_table(d):
			# On other dice: bank it, since a hop could disturb the dice underneath.
			_report(d, "landed on top of another die", "banking it")
			d.stack_rethrows += 1
			_bank_die(d)
			banked = true
			continue
		if d.get_top_face() != -1:
			d.ease_flat()
			continue
		if d.nudges < max_nudges:
			d.nudges += 1
			nudge_count += 1
			_report(d, "cocked", "nudging (%d/%d)" % [d.nudges, max_nudges])
			d.nudge()
			hopping = true
		else:
			_report(d, "still cocked", "banking it")
			_bank_die(d)
			banked = true
	if hopping or banked:
		return  # wait until the table is still and every die on it is read

	if not _bank.is_empty():
		var throwing: Array[Die] = _bank.duplicate()
		if manual_rethrow:
			_bank_mode = _prepare_rethrow(throwing, true)
			_bank_waiting = true
			for d: Die in throwing:
				_stop_slide(d)
				d.set_solid(true)  # they'll be rattled in the hand
			bank_ready.emit(throwing)
			return
		_full_rethrow(throwing, true)
		return

	_rolling = false
	var results: Array[Dictionary] = _collect_results()
	for d: Die in _active:
		d.final_entry = d.result_entry()
	for d: Die in in_play:
		d.bake_visual()
		d.set_counted(false)
	roll_finished.emit(results)


## Takes a die off the table into the bank: frozen, no longer solid, gliding up to
## its place in a row held above the near end of the table.
func _bank_die(d: Die) -> void:
	if _bank.has(d):
		return
	d.bake_visual()
	d.freeze = true
	d.set_solid(false)
	_bank.append(d)
	die_banked.emit(d)
	_place_bank()


## Lines the bank up above the near end, re-spacing it as dice join.
func _place_bank() -> void:
	for i: int in _bank.size():
		var d: Die = _bank[i]
		var x: float = (i - (_bank.size() - 1) * 0.5) * 1.3
		var spot: Vector3 = Vector3(clampf(x, -table_size.x * 0.5 + 0.8, table_size.x * 0.5 - 0.8),
				bank_height, table_size.y * 0.5 - bank_inset)
		d.set_meta("bank_spot", spot)
		_glide(d, Transform3D(d.global_basis, to_global(spot)), 0.35, 0.0)


## Moves a frozen die to `to` over `seconds`, rising `arc` units in the middle.
func _glide(d: Die, to: Transform3D, seconds: float, arc: float) -> void:
	_stop_slide(d)
	var from: Transform3D = d.global_transform
	var tween: Tween = d.create_tween()
	d.set_meta("slide", tween)
	tween.tween_method(func(t: float) -> void:
		var tr: Transform3D = from.interpolate_with(to, t)
		tr.origin += global_basis.y * sin(t * PI) * arc
		d.global_transform = tr, 0.0, 1.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _stop_slide(d: Die) -> void:
	if d.has_meta("slide") and (d.get_meta("slide") as Tween).is_valid():
		(d.get_meta("slide") as Tween).kill()


## Dice waiting in the bank for the next re-throw.
func get_bank() -> Array[Die]:
	return _bank


## Re-roll by hand: the bank is waiting for the player to throw it.
func is_waiting_for_throw() -> bool:
	return _bank_waiting


## Re-roll by hand: throws the waiting bank from where the dice are now (in the hand),
## `power` 0–1 as for roll().
func throw_bank(power: float = 0.5) -> void:
	if not _bank_waiting:
		return
	_bank_waiting = false
	_power = clampf(power, 0.0, 1.0)
	_launch(_bank.duplicate(), _bank_mode, true)


## Thrown dice still on the table (not in the drawer or the bank).
func in_play_dice() -> Array[Die]:
	var dice: Array[Die] = []
	for d: Die in _active:
		if not _cleared.has(d) and not _bank.has(d):
			dice.append(d)
	return dice


## Dice lifted off the table so far this roll (Clear the table), in set order.
func get_cleared_dice() -> Array[Die]:
	var dice: Array[Die] = []
	for d: Die in _active:
		if _cleared.has(d):
			dice.append(d)
	return dice


## The mode this roll is using now: the chosen one, or Clear the table once it has escalated.
func current_mode() -> String:
	return RethrowMode.CLEAR if _escalated else RethrowMode.clean_global(rethrow_mode)


## Fully re-throws `dice` the way the roll's re-throw mode says. `settled`: found
## at a full stop (stacked or still cocked), not by a safety net mid-roll.
## A counted die only ever comes back here through a safety net; it's thrown
## back but keeps its result, and triggers nothing else.
func _full_rethrow(dice: Array[Die], settled: bool) -> void:
	_launch(dice, _prepare_rethrow(dice, settled), false)


## The mode's step before a re-throw of `dice`: escalation and the Live table cap,
## then counting (Count where they land) or moving settled dice into the drawer
## (Clear the table). Returns the mode the re-throw uses.
func _prepare_rethrow(dice: Array[Die], settled: bool) -> String:
	var problems: Array[Die] = []
	for d: Die in dice:
		if d.locked_entry.is_empty():
			problems.append(d)
	var mode: String = current_mode()
	if mode != RethrowMode.CLEAR:
		for d: Die in problems:
			if d.stack_rethrows >= ESCALATE_AFTER_STACKS:
				_escalated = true
				_log("%s landed on other dice %d times — clearing the table" % [d.name, d.stack_rethrows])
				break
	if mode == RethrowMode.LIVE and settled and not problems.is_empty() and not _escalated:
		_rounds += 1
		if _rounds > LIVE_ROUND_CAP:
			_escalated = true
			_log("Re-throw round %d — clearing the table" % _rounds)
	mode = current_mode()
	if problems.is_empty():
		return mode
	match mode:
		RethrowMode.COUNT:
			for d: Die in in_play_dice():
				if not dice.has(d) and d.locked_entry.is_empty() and _is_clean(d):
					d.locked_entry = d.get_top_face_entry()
					d.set_counted(true)
		RethrowMode.CLEAR:
			var lifted: bool = false
			for d: Die in in_play_dice():
				if not dice.has(d) and _is_clean(d):
					if d.locked_entry.is_empty():
						d.locked_entry = d.get_top_face_entry()
					d.bake_visual()
					d.set_counted(false)
					d.freeze = true
					d.set_solid(false)
					_cleared.append(d)
					_slide_into_drawer(d)
					lifted = true
			if lifted:
				dice_cleared.emit(get_cleared_dice())
	return mode


## Throws `dice` again: aimed at open space unless the table has been cleared.
## Banked dice launch from where they're held (or from the hand), others from the near end.
func _launch(dice: Array[Die], mode: String, from_hand: bool) -> void:
	var count: int = 0
	for d: Die in dice:
		if d.locked_entry.is_empty():
			count += 1
	if count > 0:
		rethrow_started.emit(count)
	var aim: bool = mode != RethrowMode.CLEAR
	for d: Die in dice:
		_bank.erase(d)
		_stop_slide(d)
		d.nudges = 0
		d.rethrows += 1
		rethrow_count += 1
		# From the hand, where the die is now; from the bank, its spot there (it may still be
		# gliding up, even from below the table); anything else from the near end.
		var start: Vector3 = _start_positions(1)[0]
		if from_hand:
			start = to_local(d.global_position)
		elif d.has_meta("bank_spot"):
			start = d.get_meta("bank_spot")
		d.remove_meta("bank_spot")
		if aim:
			_throw_into_space(d, dice, start)
		else:
			_throw_die(d, start, from_hand)


## Slides a set-aside die into the next free drawer slot from the front left, in a
## low arc, lying flat with its counted result on top.
func _slide_into_drawer(d: Die) -> void:
	var slot: int = 0
	while _slot_of.values().has(slot):
		slot += 1
	_slot_of[d] = slot
	var face: Vector3 = (d.locked_entry["direction"] as Vector3).normalized()
	var basis: Basis = Basis(Vector3.UP, randf_range(-0.3, 0.3)) * Basis(Quaternion(face, Vector3.UP))
	_glide(d, _slot_transform(d, slot, basis), drawer_slide_time, 1.2)


## Where a die lies in drawer slot `slot` with orientation `basis` (table-local).
func _slot_transform(d: Die, slot: int, basis: Basis) -> Transform3D:
	var p: Vector3 = _slots[clampi(slot, 0, _slots.size() - 1)]
	p.y = drawer_floor + d.rest_height(basis)
	return Transform3D(global_basis * basis, to_global(p))


## One slot per die of the set: up to 7 in a row, in 1–3 rows filling the drawer.
func _drawer_slots(count: int) -> Array[Vector3]:
	var slots: Array[Vector3] = []
	if count == 0:
		return slots
	var rows: int = 1 if count <= 7 else (2 if count <= 14 else 3)
	var cols: int = ceili(float(count) / rows)
	var x_gap: float = minf(1.25, (table_size.x - 0.9) / cols)
	var z_gap: float = (drawer_z.y - drawer_z.x) / rows
	for i: int in count:
		var row: int = int(i / float(cols))
		var col: int = i % cols
		slots.append(Vector3((col - (cols - 1) * 0.5) * x_gap, drawer_floor, drawer_z.x + z_gap * (row + 0.5)))
	return slots


## Resting flat on the felt with a readable top face.
func _is_clean(d: Die) -> bool:
	return d.is_resting() and _is_on_table(d) and d.get_top_face() != -1


## Classifies a hit for sound: the wooden rim is a mostly sideways hit near a wall, otherwise felt.
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


## Each result also says whether any of its dice had its result locked before a
## re-throw ("locked"; only Count where they land and Clear the table lock results)
## and how many full re-throws its dice needed ("rethrows").
func _collect_results() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for i: int in _specs.size():
		var parts: Array[int] = []
		var locked: bool = false
		var rethrows: int = 0
		for d: Die in _active:
			if d.group_index == i:
				parts.append(int(d.result_entry().get("value", -1)))
				locked = locked or not d.locked_entry.is_empty()
				rethrows += d.rethrows
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
			"locked": locked, "rethrows": rethrows,
		})
	return results


func _rethrow(d: Die) -> void:
	_full_rethrow([d], false)


## Aims at a random point near the middle with uniformly random orientation and spin.
## `from_hand`: keep some of the die's motion in the cup.
func _throw_die(d: Die, local_start: Vector3, from_hand: bool = true) -> void:
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
	if from_hand and not d.freeze:
		# Thrown from the cup: keep some of the shaking motion.
		lin_vel += d.linear_velocity.limit_length(8.0) * 0.5
	d.throw(to_global(local_start), global_basis * Basis(_random_rotation()),
			global_basis * lin_vel, global_basis * ang_vel)


## Re-throws a die into open space, away from the dice still on the table (including
## dice sitting out), along a path that doesn't cross them. Looks only at where dice
## lie, never at their values; orientation and spin are as random as a normal throw.
## `start` (table-local): launch from here, choosing a target with a clear path from it.
func _throw_into_space(d: Die, also_moving: Array[Die], start_at: Variant = null) -> void:
	var others: Array[Vector2] = []
	for o: Die in _dice:
		if o == d or also_moving.has(o) or _cleared.has(o) or not _active.has(o):
			continue
		var p: Vector3 = to_local(o.global_position)
		others.append(Vector2(p.x, p.z))
	var from: Variant = null if start_at == null else Vector2((start_at as Vector3).x, (start_at as Vector3).z)
	var target: Vector2 = pick_open_spot(others, from)
	var start: Vector2 = _clear_launch_point(target, others) if from == null else from
	var direction: Vector3 = Vector3(target.x - start.x, 0.0, target.y - start.y).normalized()
	var lin_vel: Vector3 = direction * randf_range(TARGET_SPEED.x, TARGET_SPEED.y) \
			+ Vector3.UP * randf_range(TARGET_LIFT.x, TARGET_LIFT.y)
	var ang_vel: Vector3 = _random_unit_vector() * randf_range(spin_min, spin_max) \
			+ Vector3.UP.cross(direction) * randf_range(forward_spin.x, forward_spin.y)
	var height: float = 2.0 if start_at == null else (start_at as Vector3).y
	d.throw(to_global(Vector3(start.x, height, start.y)), global_basis * Basis(_random_rotation()),
			global_basis * lin_vel, global_basis * ang_vel)


## A landing point (table-local x, z) well away from `others` and the walls: the
## best few of TARGET_SAMPLES random points, one of them picked at random. With `from`
## (a launch point), a point also scores by how clear the straight path to it is.
func pick_open_spot(others: Array[Vector2], from: Variant = null) -> Vector2:
	var half: Vector2 = table_size * 0.5 - Vector2.ONE * TARGET_EDGE_MARGIN
	var scored: Array[Array] = []
	for i: int in TARGET_SAMPLES:
		var p: Vector2 = Vector2(randf_range(-half.x, half.x), randf_range(-half.y, half.y))
		var wall: float = minf(half.x - absf(p.x), half.y - absf(p.y)) + TARGET_EDGE_MARGIN
		var score: float = wall * TARGET_WALL_WEIGHT
		for o: Vector2 in others:
			score = minf(score, p.distance_to(o))
			if from != null:
				score = minf(score, Geometry2D.get_closest_point_to_segment(o, from, p).distance_to(o) * 1.5)
		scored.append([score, p])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	return scored[randi() % mini(TARGET_PICK_FROM, scored.size())][1]


## Where to launch from so the path to `target` stays clearest of `others`
## (TARGET_DIRECTIONS tried), TARGET_RUN away and inside the walls.
func _clear_launch_point(target: Vector2, others: Array[Vector2]) -> Vector2:
	var half: Vector2 = table_size * 0.5 - Vector2.ONE * 0.8
	var best: Vector2 = target
	var best_score: float = -INF
	var offset: float = randf() * TAU
	for i: int in TARGET_DIRECTIONS:
		var angle: float = offset + TAU * i / TARGET_DIRECTIONS
		var start: Vector2 = target - Vector2(cos(angle), sin(angle)) * TARGET_RUN
		start = Vector2(clampf(start.x, -half.x, half.x), clampf(start.y, -half.y, half.y))
		var score: float = INF
		for o: Vector2 in others:
			score = minf(score, Geometry2D.get_closest_point_to_segment(o, start, target).distance_to(o))
		score = minf(score, start.distance_to(target))  # clamped right up to the target is a poor run-up
		if score > best_score:
			best_score = score
			best = start
	return best


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


## Why a die is being hopped or re-thrown, for the debug overlay and the log:
## { "die", "rule", "action", "tilt" and "threshold" (degrees), "lowest" (corner height
## above the felt), "touching" (e.g. ["felt", "rim", "D6-3"]) }.
func diagnose(d: Die, rule: String, action: String = "") -> Dictionary:
	return {
		"die": str(d.name), "rule": rule, "action": action,
		"tilt": d.get_tilt_degrees(), "threshold": d.readable_limit_degrees(),
		"lowest": d.get_lowest_point() - global_position.y, "touching": touching(d),
	}


## What the die is in contact with: "felt", "rim" (the table's sides), "cup", or other dice by name.
func touching(d: Die) -> Array[String]:
	var found: Array[String] = []
	var state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(d.get_rid())
	if state == null:
		return found
	for i: int in state.get_contact_count():
		var other: Object = state.get_contact_collider_object(i)
		var what: String = "cup"
		if other is Die:
			what = str((other as Die).name)
		elif other is Table:
			what = "felt" if to_local(state.get_contact_collider_position(i)).y < 0.05 else "rim"
		if not found.has(what):
			found.append(what)
	return found


func _report(d: Die, rule: String, action: String) -> void:
	if not (log_events or OS.is_debug_build()):
		return
	var info: Dictionary = diagnose(d, rule, action)
	var contacts: Array = info["touching"]
	_log("%s %s — %s (tilt %.1f°, limit %.1f°, lowest corner %.3f, touching %s)" % [
			d.name, rule, action, info["tilt"], info["threshold"], info["lowest"],
			"nothing" if contacts.is_empty() else ", ".join(contacts)])
	if OS.is_debug_build():
		debug_event.emit(d, info)


## Debug builds: makes one settled die land badly, then lets physics settle it again.
func _apply_debug_force() -> void:
	var d: Die = _active.pick_random()
	if debug_force == "stack" and _active.size() > 1:
		var under: Die = _active[0] if d != _active[0] else _active[1]
		# Set down flat on top with a random face up and a random turn, so forcing stacks
		# can't favour a face (always the same face up skewed results on the d4).
		var up_dir: Vector3 = (d.faces.pick_random()["direction"] as Vector3).normalized()
		var basis: Basis = Basis(Vector3.UP, randf() * TAU) * Basis(Quaternion(up_dir, Vector3.UP))
		var top: float = -INF
		for c: Vector3 in under.corners:
			top = maxf(top, to_local(under.global_transform * c).y)
		var p: Vector3 = to_local(under.global_position)
		p.y = top + d.rest_height(basis) + 0.02
		d.throw(to_global(p), global_basis * basis, Vector3.ZERO, Vector3.ZERO)
		_log("Debug: %s placed on top of %s" % [d.name, under.name])
		return
	# Lean against the right-hand rim: tilted about the table's long axis, raised side against the rim.
	var half: Vector2 = table_size * 0.5
	var basis: Basis = Basis(Vector3.BACK, deg_to_rad(debug_lean_degrees)) * d.resting_basis(0.0)
	var reach: float = 0.0
	for c: Vector3 in d.corners:
		reach = maxf(reach, (basis * c).x)
	var z: float = clampf(to_local(d.global_position).z, -half.y + 1.5, half.y - 2.5)
	d.throw(to_global(Vector3(half.x - reach - 0.01, d.rest_height(basis) + 0.01, z)),
			global_basis * basis, Vector3.ZERO, Vector3.ZERO)
	_log("Debug: %s leaned on the rim at %.0f°" % [d.name, debug_lean_degrees])


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
