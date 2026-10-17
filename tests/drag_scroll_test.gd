extends "res://tests/app_test.gd"
## Lists scroll when a drag starts on a switch, without flipping it; a plain tap still flips it.

func _init() -> void:
	test_name = "DRAG SCROLL"


func run() -> void:
	var main: Node = launch_main()
	await frames(2)
	var settings: AppSettings = main.get("_settings")
	var sheet: SettingsSheet = main.get_node("UI/Root/SettingsSheet")
	(main.get_node("UI/Root/StartMenu") as StartMenu).settings_pressed.emit()
	await create_timer(0.6).timeout
	var switches: Dictionary = sheet.get("_switches")
	var fast: CheckButton = switches["fast_roll"]
	var scroll: ScrollContainer = fast.get_parent().get_parent().get_parent()
	var before: bool = settings.fast_roll
	var at: Vector2 = fast.get_global_rect().get_center()

	_press(main, at, true)
	for i: int in 12:
		_move(main, at + Vector2(0.0, -10.0 * i))
		await frames(1)
	_press(main, at + Vector2(0.0, -110.0), false)
	await frames(3)
	check(scroll.scroll_vertical > 0 or scroll.get_v_scroll_bar().max_value <= scroll.size.y,
			"dragging up from a switch scrolls the list (now at %d)" % scroll.scroll_vertical)
	check(settings.fast_roll == before and fast.button_pressed == before, "the switch the drag started on didn't flip")

	at = fast.get_global_rect().get_center()
	_press(main, at, true)
	await frames(1)
	_press(main, at, false)
	await frames(3)
	check(settings.fast_roll != before, "a plain tap still flips it")
	sheet.changed.emit("fast_roll", before)


func _press(main: Node, at: Vector2, down: bool) -> void:
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	e.position = at
	e.global_position = at
	main.get_viewport().push_input(e, true)


func _move(main: Node, at: Vector2) -> void:
	var e: InputEventMouseMotion = InputEventMouseMotion.new()
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	e.position = at
	e.global_position = at
	main.get_viewport().push_input(e, true)
