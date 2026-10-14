extends "res://tests/app_test.gd"
## Throwing from the hand with the Throw button (no shake), both once the
## dice have settled in the hand and straight away while they're still
## being gathered. All dice must land on the table.

var _main: Node
var _roller: DiceRoller


func _init() -> void:
	test_name = "THROW FROM HAND"


func run() -> void:
	_main = launch_main()
	await frames(2)
	_roller = _main.get_node("DiceRoller")
	for case: Array in [["Fireball", 0, 90], ["Fireball", 0, 3], ["RPG set", 2, 90], ["RPG set", 2, 3]]:
		var set_data: Dictionary = (_main.get("_store") as DiceSetStore).sets[case[1]]
		_main.call("_on_set_chosen", set_data["id"])
		await frames(3)
		_main.set("_pick_mode", false)  # throw every die, even for pick-dice sets
		_main.call("_on_roll_button_pressed")  # Roll: into the hand
		await frames(case[2])
		_main.call("_on_roll_button_pressed")  # Throw
		var results: Array = await _roller.roll_finished
		var on_table: bool = true
		for d: Die in _roller.get_active_dice():
			var p: Vector3 = _roller.to_local(d.global_position)
			if absf(p.x) > 4.5 or absf(p.z) > 7.5 or p.y > 2.0:
				on_table = false
		check(on_table and results.size() == (set_data["dice"] as Array).size(),
				"%s thrown %s: all dice landed" % [case[0], "after settling in the hand" if case[2] > 10 else "straight away"])
