extends "res://tests/app_test.gd"
## A die re-thrown late must get the full time limit to land, not be pulled
## back moments later. Limit 1.5 s; the d20 re-throws at 1.4 s.

const TICKS: int = 120  # physics steps per second


func _init() -> void:
	test_name = "RE-THROW TIMING"
	uses_app = false


func run() -> void:
	var table: Table = Table.new()
	root.add_child(table)
	var roller: DiceRoller = DiceRoller.new()
	roller.roll_timeout = 1.5
	roller.log_events = false
	root.add_child(roller)
	roller.set_dice([{ "type": "d20" }, { "type": "d6" }])
	roller.roll()
	await physics_frames(int(1.4 * TICKS))
	check(roller.is_rolling(), "the roll is still in progress at 1.4 s")

	var d20: Die = roller.get_dice()[0]
	roller.call("_rethrow", d20)
	var last: Vector3 = d20.global_position
	var steps: int = 0
	while roller.is_rolling() and steps < 30 * TICKS:
		await physics_frame
		steps += 1
		if d20.global_position.distance_to(last) > 2.0:
			break  # teleported: re-thrown again
		last = d20.global_position
	var seconds: float = steps / float(TICKS)
	check(not roller.is_rolling() or seconds >= 1.5,
			"after a late re-throw the d20 got the full time (%.2f s before landing or the next re-throw)" % seconds)
