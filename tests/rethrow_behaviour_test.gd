extends "res://tests/app_test.gd"
## Re-throw modes on the table (steps 4–7):
## - Clear the table: settled dice are read and lifted before the re-throw, the
##   problem die lands on an empty table and joins the result row.
## - Count where they land: counted dice stay dynamic but keep their result when
##   knocked, are never re-thrown for landing badly, and are marked while waiting.
## - Live table: a knocked die is read again; the cascade cap falls back to Clear
##   the table; every roll finishes.
## - Escalation: a die landing on other dice twice clears the table; locked results stay.
## - Targeting: re-throws aimed at open space hit a cluster of dice far less often.
## - Parked dice are never moved, read or counted in any mode.

const ARENA_SPACING: float = 25.0
const TICKS: int = 120

var _arena_count: int = 0


func _init() -> void:
	test_name = "RE-THROW BEHAVIOUR"
	uses_app = false
	time_limit = 400.0


## Targeting trials per kind of throw; --trials=N to change (the phone runs fewer).
var _trials: int = 60


func run() -> void:
	for arg: String in OS.get_cmdline_user_args() + Engine.get_meta("device_test_args", PackedStringArray()):
		if arg.begins_with("--trials="):
			_trials = arg.get_slice("=", 1).to_int()
	await _bank_checks()
	await _clear_checks()
	await _count_checks()
	await _live_checks()
	await _escalation_checks()
	await _parked_checks()
	await _targeting_checks()


# The bank

## A die needing a re-throw leaves the table at once; the bank is thrown only when
## every die on the table has stopped and been read; several banked dice go together.
func _bank_checks() -> void:
	# Arrays, so the callbacks below can update them.
	var off_at_once: Array[bool] = [true]
	var waited: Array[bool] = [true]
	var events: Array[int] = [0]
	for mode: String in RethrowMode.MODES:
		for run_index: int in 2:
			var roller: DiceRoller = _arena(mode, 5, "d6")
			roller.die_banked.connect(func(d: Die) -> void:
				events[0] += 1
				off_at_once[0] = off_at_once[0] and d.freeze and d.collision_layer == 0 and not roller.in_play_dice().has(d))
			roller.rethrow_started.connect(func(_count: int) -> void:
				for d: Die in roller.in_play_dice():
					var settled: bool = d.is_resting() and (not d.locked_entry.is_empty() or roller.call("_is_clean", d))
					waited[0] = waited[0] and settled)
			await _roll(roller, "stack")
	check(events[0] >= 4 and off_at_once[0], "a die that needs re-throwing goes straight into the bank, off the table (%d banked)" % events[0])
	check(waited[0], "the bank is thrown only once every die on the table has stopped and been read")

	var roller: DiceRoller = _arena(RethrowMode.LIVE, 5, "d6")
	await _roll(roller, "")
	roller.set("_rolling", true)
	var sizes: Array[int] = []
	roller.rethrow_started.connect(func(count: int) -> void: sizes.append(count))
	roller.call("_bank_die", roller.get_active_dice()[0])
	roller.call("_bank_die", roller.get_active_dice()[1])
	await physics_frames(2)
	var finished: bool = await _wait_finished(roller, 30.0)
	check(finished and not sizes.is_empty() and sizes[0] == 2, "two banked dice are re-rolled together in one throw (%s)" % [sizes])


# Clear the table

func _clear_checks() -> void:
	# Arrays where callbacks update them (a callback can't change a plain local).
	var lifted_ok: Array[bool] = [true]
	var empty_ok: Array[bool] = [true]
	var joined_ok: bool = true
	var events: int = 0
	for run_index: int in 6:
		var roller: DiceRoller = _arena(RethrowMode.CLEAR, 5, "d6")
		var seen: Array[Dictionary] = []
		roller.dice_cleared.connect(func(dice: Array[Die]) -> void:
			for d: Die in dice:
				if d.locked_entry.is_empty() or not d.freeze or d.collision_layer != 0:
					lifted_ok[0] = false
			seen.append({ "cleared": dice.size() }))
		roller.rethrow_started.connect(func(_count: int) -> void:
			for d: Die in roller.in_play_dice():
				if roller.call("_is_clean", d):
					empty_ok[0] = false)
		var results: Array = await _roll(roller, "stack")
		if seen.is_empty():
			continue
		events += 1
		for d: Die in roller.get_cleared_dice():
			var p: Vector3 = roller.to_local(d.global_position)
			if p.z < roller.drawer_z.x or p.z > roller.drawer_z.y:
				lifted_ok[0] = false
		var by_die: Dictionary = {}
		for d: Die in roller.get_active_dice():
			by_die[d] = d.result_entry().get("value", -1)
		joined_ok = joined_ok and results.size() == 5
		for d: Die in roller.get_cleared_dice():
			joined_ok = joined_ok and by_die[d] == d.locked_entry["value"]
		var rethrown: int = 0
		for r: Dictionary in results:
			rethrown += int(r["rethrows"])
		joined_ok = joined_ok and rethrown >= 1
	check(events >= 4, "Clear the table: forced stacks led to re-throws (%d of 6 rolls)" % events)
	check(lifted_ok[0], "settled dice are read, locked and moved into the drawer before the re-throw (frozen, no longer solid)")
	check(empty_ok[0], "the re-throw lands on a table with no settled dice left on it")
	check(joined_ok, "re-thrown dice join the result row: every die has a result, lifted ones keep theirs")


# Count where they land

func _count_checks() -> void:
	var dynamic_ok: Array[bool] = [true]
	var marked_ok: Array[bool] = [true]
	var kept_ok: bool = true
	var knocked: int = 0
	var counted_rethrown: int = 0
	var events: int = 0
	for run_index: int in 6:
		var roller: DiceRoller = _arena(RethrowMode.COUNT, 5, "d6")
		var counted: Array[Die] = []
		var locked_values: Dictionary = {}
		roller.rethrow_started.connect(func(_count: int) -> void:
			if not counted.is_empty():
				return
			for d: Die in roller.in_play_dice():
				if not d.locked_entry.is_empty():
					counted.append(d)
					locked_values[d] = d.locked_entry["value"]
					dynamic_ok[0] = dynamic_ok[0] and not d.freeze and d.collision_layer == 1
					marked_ok[0] = marked_ok[0] and d.is_counted_shown()
			if not counted.is_empty():
				# Knock one onto another face: tip it a quarter turn.
				var k: Die = counted[0]
				k.global_basis = Basis(Vector3.RIGHT, PI * 0.5) * k.global_basis
				k.global_position += Vector3.UP * 0.6
				k.sleeping = false)
		var results: Array = await _roll(roller, "stack")
		if counted.is_empty():
			continue
		events += 1
		for d: Die in counted:
			kept_ok = kept_ok and d.result_entry()["value"] == locked_values[d]
			if d.get_top_face() != locked_values[d]:
				knocked += 1
			counted_rethrown += d.rethrows
			marked_ok[0] = marked_ok[0] and not d.is_counted_shown()
		var total: int = 0
		for r: Dictionary in results:
			total += int(r["value"])
		var expect: int = 0
		for d: Die in roller.get_active_dice():
			expect += int(d.result_entry()["value"])
		kept_ok = kept_ok and total == expect
	check(events >= 4, "Count where they land: forced stacks led to re-throws (%d of 6 rolls)" % events)
	check(dynamic_ok[0], "counted dice stay on the table as normal physics objects")
	check(marked_ok[0], "counted dice are marked while the re-throw happens, and unmarked after")
	check(kept_ok and knocked >= 1, "a knocked counted die keeps its recorded result (%d knocked onto another face)" % knocked)
	check(counted_rethrown == 0, "counted dice are never re-thrown for landing badly")


# Live table

func _live_checks() -> void:
	var reread_ok: bool = true
	var events: int = 0
	for run_index: int in 4:
		var roller: DiceRoller = _arena(RethrowMode.LIVE, 5, "d6")
		var moved: Array[Die] = []
		roller.rethrow_started.connect(func(_count: int) -> void:
			if not moved.is_empty():
				return
			for d: Die in roller.in_play_dice():
				if roller.call("_is_clean", d):
					d.global_basis = Basis(Vector3.RIGHT, PI * 0.5) * d.global_basis
					d.global_position += Vector3.UP * 0.6
					d.sleeping = false
					moved.append(d)
					break)
		var results: Array = await _roll(roller, "stack")
		if moved.is_empty():
			continue
		events += 1
		for r: Dictionary in results:
			reread_ok = reread_ok and not r["locked"]
		reread_ok = reread_ok and moved[0].locked_entry.is_empty() and moved[0].get_top_face() != -1
	check(events >= 3 and reread_ok, "Live table: nothing is locked, and a knocked die is read again where it ends up")

	# Cascade cap: four re-throw rounds in a row; the fourth clears the table.
	var roller: DiceRoller = _arena(RethrowMode.LIVE, 5, "d6")
	await _roll(roller, "")
	roller.set("_rolling", true)
	var problem: Die = roller.get_active_dice()[0]
	problem.stack_rethrows = 0  # a natural stack in the warm-up roll mustn't trigger escalation instead
	roller.set("_rounds", 0)  # nor its re-throw rounds count towards the cap
	var cleared: Array[int] = []
	roller.dice_cleared.connect(func(dice: Array[Die]) -> void: cleared.append(dice.size()))
	var modes: Array[String] = []
	for i: int in DiceRoller.LIVE_ROUND_CAP + 1:
		roller.call("_full_rethrow", [problem] as Array[Die], true)
		modes.append(roller.current_mode())
	check(modes.slice(0, DiceRoller.LIVE_ROUND_CAP).count(RethrowMode.LIVE) == DiceRoller.LIVE_ROUND_CAP
			and modes[-1] == RethrowMode.CLEAR and not cleared.is_empty(),
			"after %d re-throw rounds the rest is handled as Clear the table (%s)" % [DiceRoller.LIVE_ROUND_CAP, modes])
	var finished: bool = await _wait_finished(roller, 30.0)
	check(finished, "and the roll still finishes")

	# Every roll finishes.
	var all_done: bool = true
	for i: int in 8:
		var r: DiceRoller = _arena(RethrowMode.LIVE, 8, "d6")
		r.debug_force = "stack"
		r.roll(randf())
	for r: DiceRoller in _rollers_since(8):
		all_done = all_done and await _wait_finished(r, 40.0)
	check(all_done, "8 Live table rolls of 8d6 with forced stacks all finish")


# Escalation

func _escalation_checks() -> void:
	var roller: DiceRoller = _arena(RethrowMode.COUNT, 5, "d6")
	await _roll(roller, "")
	roller.set("_rolling", true)
	var problem: Die = roller.get_active_dice()[0]
	roller.call("_full_rethrow", [problem] as Array[Die], true)
	var before: Dictionary = {}
	for d: Die in roller.get_active_dice():
		if not d.locked_entry.is_empty():
			before[d] = d.locked_entry["value"]
	var cleared: Array[Die] = []
	roller.dice_cleared.connect(func(dice: Array[Die]) -> void: cleared.append_array(dice))
	problem.stack_rethrows = DiceRoller.ESCALATE_AFTER_STACKS
	roller.call("_full_rethrow", [problem] as Array[Die], true)
	var kept: bool = not before.is_empty()
	for d: Die in before:
		kept = kept and d.locked_entry["value"] == before[d]
	check(roller.current_mode() == RethrowMode.CLEAR and not cleared.is_empty(),
			"a die landing on other dice a second time clears the table (%d dice lifted)" % cleared.size())
	check(kept, "results locked before that stay locked")
	check(await _wait_finished(roller, 30.0), "the roll finishes")

	# The real thing, many times: Count where they land with forced stacks always finishes.
	var all_done: bool = true
	for i: int in 8:
		var r: DiceRoller = _arena(RethrowMode.COUNT, 8, "d6")
		r.debug_force = "stack"
		r.roll(randf())
	for r: DiceRoller in _rollers_since(8):
		all_done = all_done and await _wait_finished(r, 40.0)
	check(all_done, "8 Count where they land rolls of 8d6 with forced stacks all finish")


# Parked dice

func _parked_checks() -> void:
	var ok: bool = true
	var details: Array[String] = []
	for mode: String in RethrowMode.MODES:
		for run_index: int in 2:
			var roller: DiceRoller = _arena(mode, 6, "d6")
			roller.set_active_groups([0, 1, 2])
			var parked: Array[Die] = []
			var start: Array[Transform3D] = []
			for d: Die in roller.get_dice():
				if not roller.get_active_dice().has(d):
					parked.append(d)
					start.append(d.global_transform)
			var results: Array = await _roll(roller, "stack")
			for i: int in parked.size():
				var p: Die = parked[i]
				if not p.global_transform.is_equal_approx(start[i]) or not p.locked_entry.is_empty() \
						or roller.get_cleared_dice().has(p) or roller.in_play_dice().has(p):
					ok = false
					details.append("%s %s" % [mode, p.name])
			ok = ok and results.size() == 3
	check(ok, "parked dice are never moved, read or counted, in every mode %s" % [details])


# Targeting

## 8 dice thrown normally and settled (they gather where throws usually land), then
## one more die re-thrown the normal way or aimed at open space. How often does it
## hit the group, or end up on another die?
func _targeting_checks() -> void:
	var trials: int = _trials
	var stats: Dictionary = { "normal": [0, 0, 0], "aimed": [0, 0, 0] }  # [trials, landed on a die, hit the cluster]
	var pending: Array[int] = [0]
	for kind: String in ["normal", "aimed"]:
		for i: int in trials:
			var roller: DiceRoller = _arena(RethrowMode.LIVE, 9, "d6")
			roller.set_active_groups([0, 1, 2, 3, 4, 5, 6, 7])
			var thrown: Die = roller.get_dice()[8]
			pending[0] += 1
			_targeting_trial(roller, thrown, kind, stats, pending)
	var steps: int = 0
	while pending[0] > 0 and steps < TICKS * 40:
		await physics_frame
		steps += 1
	var normal: Array = stats["normal"]
	var aimed: Array = stats["aimed"]
	TestLog.line("  re-throw at a cluster: normal throw landed on a die %d/%d, hit the cluster %d/%d; aimed at open space %d/%d, %d/%d" % [
			normal[1], normal[0], normal[2], normal[0], aimed[1], aimed[0], aimed[2], aimed[0]])
	check(normal[0] == trials and aimed[0] == trials, "every targeting trial finished")
	check(normal[2] >= trials / 12 and aimed[2] * 3 <= normal[2] and aimed[1] <= normal[1],
			"aimed re-throws hit the cluster far less often than normal ones")


func _targeting_trial(roller: DiceRoller, thrown: Die, kind: String, stats: Dictionary, pending: Array[int]) -> void:
	roller.roll(randf())
	var steps: int = 0
	while roller.is_rolling() and steps < TICKS * 30:
		await physics_frame
		steps += 1
	thrown.set_dimmed(false)
	var hit: Array[bool] = [false]
	thrown.body_entered.connect(func(other: Node) -> void:
		if other is Die:
			hit[0] = true)
	if kind == "aimed":
		roller.call("_throw_into_space", thrown, [thrown] as Array[Die])
	else:
		roller.call("_throw_die", thrown, roller.call("_start_positions", 1)[0], false)
	steps = 0
	await physics_frames(10)
	while steps < TICKS * 15:
		await physics_frame
		steps += 1
		if thrown.update_rest(1.0 / TICKS):
			break
	var s: Array = stats[kind]
	s[0] += 1
	if not roller.call("_is_on_table", thrown):
		s[1] += 1
	if hit[0]:
		s[2] += 1
	pending[0] -= 1


# Helpers

func _arena(mode: String, count: int, type: String) -> DiceRoller:
	var offset: Vector3 = Vector3((_arena_count % 15) * ARENA_SPACING, 0.0, (_arena_count / 15) * ARENA_SPACING)
	_arena_count += 1
	var table: Table = Table.new()
	table.position = offset
	root.add_child(table)
	var roller: DiceRoller = DiceRoller.new()
	roller.position = offset
	roller.log_events = false
	roller.rethrow_mode = mode
	root.add_child(roller)
	var specs: Array[Dictionary] = []
	for i: int in count:
		specs.append({ "type": type })
	roller.set_dice(specs)
	roller.set_meta("test_index", _arena_count)
	return roller


func _rollers_since(count: int) -> Array[DiceRoller]:
	var found: Array[DiceRoller] = []
	for n: Node in root.get_children():
		if n is DiceRoller and int(n.get_meta("test_index", 0)) > _arena_count - count:
			found.append(n)
	return found


## Rolls and returns the results (or [] after 40 s).
func _roll(roller: DiceRoller, force: String) -> Array:
	roller.debug_force = force
	var got: Array = []
	roller.roll_finished.connect(func(r: Array[Dictionary]) -> void: got.append(r), CONNECT_ONE_SHOT)
	roller.roll(randf())
	var steps: int = 0
	while got.is_empty() and steps < TICKS * 40:
		await physics_frame
		steps += 1
	return got[0] if not got.is_empty() else []


func _wait_finished(roller: DiceRoller, seconds: float) -> bool:
	var steps: int = 0
	while roller.is_rolling() and steps < int(TICKS * seconds):
		await physics_frame
		steps += 1
	return not roller.is_rolling()
