extends "res://tests/app_test.gd"
## Tapping the table rolls (and throws when armed); flicking up throws held
## dice, harder for faster flicks; drags and long presses don't; the setting
## turns it all off.

var _main: Node


func _init() -> void:
	test_name = "TAP TO ROLL"


func run() -> void:
	_main = launch_main()
	await frames(2)
	var roller: DiceRoller = _main.get_node("DiceRoller")
	var store: DiceSetStore = _main.get("_store")
	var result_label: Label = _main.get_node("UI/Root/ResultLabel")
	_main.call("_on_set_chosen", store.sets[0]["id"])  # Fireball
	await frames(3)
	check(result_label.text.ends_with("Tap to roll"), "the hint says Tap to roll")

	_drag()
	await frames(3)
	check(_state() == "IDLE", "a drag across the table doesn't roll")
	await _tap(0.6)
	check(_state() == "IDLE", "a long press doesn't roll")
	await _tap()
	check(_state() == "ARMED", "a tap picks the dice up (same as Roll)")
	await frames(30)
	await _tap()
	check(_state() == "ROLLING", "a second tap throws them")
	await _tap()
	check(_state() == "ROLLING", "taps are ignored while the dice roll")
	await roller.roll_finished
	await frames(10)

	await _swipe(Vector2(270, 750), Vector2(270, 550), 0.15)
	check(_state() == "IDLE", "a flick up before picking up the dice doesn't throw")
	await _tap()  # pick up
	await frames(30)
	await _swipe(Vector2(270, 550), Vector2(270, 750), 0.15)
	check(_state() == "ARMED", "a flick down doesn't throw")
	await _swipe(Vector2(270, 750), Vector2(270, 450), 0.5)
	var slow_power: float = roller.get("_power")
	check(_state() == "ROLLING", "a flick up throws the held dice")
	await roller.roll_finished
	await frames(10)
	await _tap()
	await frames(30)
	await _swipe(Vector2(270, 800), Vector2(270, 350), 0.1)
	check(_state() == "ROLLING" and roller.get("_power") > slow_power,
			"a faster flick throws harder (power %.2f vs %.2f)" % [roller.get("_power"), slow_power])
	await roller.roll_finished
	await frames(10)

	_main.call("_on_set_chosen", store.sets[1]["id"])  # Risk: pick dice
	await frames(3)
	await _tap()
	check(_state() == "PICKING", "on a pick-dice set a tap starts Pick up")
	await _tap()
	check(_state() == "PICKING", "while picking, a tap on empty table doesn't roll")
	_main.call("_go_back")

	(_main.get_node("UI/Root/SettingsSheet") as SettingsSheet).changed.emit("tap_to_roll", false)
	_main.call("_on_set_chosen", store.sets[0]["id"])
	await frames(3)
	await _tap()
	var saved: AppSettings = AppSettings.new((_main.get("_settings") as AppSettings).path)
	saved.load_settings()
	check(_state() == "IDLE" and result_label.text.ends_with("Press Roll") and not saved.tap_to_roll,
			"with the setting off, taps do nothing, the hint says Press Roll, and it's saved")


func _state() -> String:
	return (_main.get("State") as Dictionary).find_key(_main.get("_state"))


## A press and release near the bottom of the table (clear of the dice).
func _tap(hold: float = 0.0) -> void:
	var pos: Vector2 = Vector2(270, 700)
	_mouse(pos, true)
	if hold > 0.0:
		await create_timer(hold).timeout
	else:
		await frames(1)
	_mouse(pos, false)
	await frames(2)


func _swipe(from: Vector2, to: Vector2, seconds: float) -> void:
	_mouse(from, true)
	await create_timer(seconds).timeout
	_mouse(to, false)
	await frames(2)


func _drag() -> void:
	_mouse(Vector2(150, 600), true)
	_mouse(Vector2(350, 650), false)


func _mouse(pos: Vector2, pressed: bool) -> void:
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	_main.call("_unhandled_input", e)
