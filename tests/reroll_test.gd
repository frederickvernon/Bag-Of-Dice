extends "res://tests/app_test.gd"
## Re-rolling while the last result shows (mid-lift and after) with the RPG
## set: every die must land back on the table (or, in Clear the table, be lifted
## off it after being read there).

var _main: Node
var _roller: DiceRoller


func _init() -> void:
	test_name = "RE-ROLL"


func run() -> void:
	_main = launch_main()
	await frames(2)
	_roller = _main.get_node("DiceRoller")
	_main.call("_on_set_chosen", (_main.get("_store") as DiceSetStore).sets[2]["id"])
	_main.call("_start_roll")
	await _roller.roll_finished
	for i: int in 10:
		# Alternate: re-roll mid-lift, or after the dice have lined up.
		await frames(10 if i % 2 == 0 else 80)
		_main.call("_start_roll")
		await _roller.roll_finished
		var off_table: Array[String] = []
		# Dice lifted mid-roll (Clear the table) were read on the table first.
		for d: Die in _roller.in_play_dice():
			var p: Vector3 = _roller.to_local(d.global_position)
			if absf(p.x) > _roller.table_size.x * 0.5 or absf(p.z) > _roller.table_size.y * 0.5 or p.y > 2.0 or p.y < -0.5:
				off_table.append(str(d.name))
		check(off_table.is_empty(), "re-roll %d (%s): all dice landed on the table%s" % [
				i + 1, "mid-lift" if i % 2 == 0 else "after lift",
				"" if off_table.is_empty() else "; off: " + ", ".join(off_table)])
