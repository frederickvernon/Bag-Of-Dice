extends "res://tests/app_test.gd"
## Picking dice on the Risk set (0–2 "Attack", 3–4 "Defend"): tap to pick or
## put back, long-press to lock; only picked dice are thrown and logged.

var _main: Node
var _roller: DiceRoller
var _camera: Camera3D


func _init() -> void:
	test_name = "PICK DICE"


func run() -> void:
	_main = launch_main()
	await frames(2)
	_roller = _main.get_node("DiceRoller")
	_camera = _main.get_node("Camera3D")
	var picker: DicePicker = _main.get_node("DicePicker")
	var button: Button = _main.get_node("UI/Root/BottomBar/RollButton")
	var history: RollHistory = _main.get("_history")

	_main.call("_on_set_chosen", (_main.get("_store") as DiceSetStore).sets[1]["id"])
	await frames(5)
	check(button.text == "Pick up", "a pick-dice set shows Pick up")
	_main.call("_on_roll_button_pressed")
	await frames(20)
	check(picker.is_active() and button.disabled, "picking starts with nothing picked and Roll disabled")

	_tap(0)
	_tap(1)
	await frames(15)
	check(picker.picked_groups() == [0, 1] and not button.disabled, "tapping two dice picks them")
	_tap(1)
	await frames(15)
	check(picker.picked_groups() == [0], "tapping a picked die puts it back")
	_click(_screen_pos(3), true)
	await create_timer(0.8).timeout  # hold for longer than the 0.5 s long press
	_click(_screen_pos(3), false)
	await frames(15)
	check(picker.locked_groups().has(3) and picker.picked_groups() == [0, 3], "a long press locks (and picks) a die")
	snap("picked")

	_main.call("_on_roll_button_pressed")  # Roll: arm
	await frames(40)
	check(_roller.get_active_dice().size() == 2, "only the 2 picked dice go into the hand")
	_main.call("_on_roll_button_pressed")  # Throw
	var results: Array = await _roller.roll_finished
	check(results.size() == 2 and results[0]["label"] == "Attack" and results[1]["label"] == "Defend",
			"results cover only the thrown dice")
	await frames(60)
	check(history.entries[0]["dice"].size() == 2, "history logs only the thrown dice")
	var aside_frozen: bool = true
	for d: Die in _roller.get_dice():
		if not _roller.get_active_dice().has(d) and not d.freeze:
			aside_frozen = false
	check(aside_frozen, "dice sitting out stay frozen at the side")

	_main.call("_on_roll_button_pressed")  # Pick up again
	await frames(20)
	check(picker.picked_groups() == [3], "next time, the locked die starts picked")
	press_back(_main)
	await frames(5)
	check(not picker.is_active() and button.text == "Pick up", "Back cancels picking")


func _screen_pos(group: int) -> Vector2:
	for d: Die in _roller.get_dice():
		if d.group_index == group:
			return _camera.unproject_position(d.global_position)
	return Vector2.ZERO


func _click(pos: Vector2, pressed: bool) -> void:
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	_main.call("_unhandled_input", e)


func _tap(group: int) -> void:
	var p: Vector2 = _screen_pos(group)
	_click(p, true)
	_click(p, false)
