extends "res://tests/app_test.gd"
## App flows not covered elsewhere: Back closing things in order, the 1d6 and
## 1d20 quick rolls, history chips and the clear confirmation, the editor's
## rules, drag-scrolling every list, lifted dice fitting the screen, the debug
## overlay only showing while a debug landing is on, the low-power mode, and a
## damaged settings file.

var _main: Node


func _init() -> void:
	test_name = "APP FLOWS"


func run() -> void:
	_main = launch_main()
	await frames(2)
	await _quick_roll_checks()
	await _back_checks()
	await _history_checks()
	await _editor_checks()
	await _scroll_checks()
	await _layout_checks()
	await _drawer_checks()
	await _overlay_checks()
	await _power_checks()
	_settings_file_checks()


func _quick_roll_checks() -> void:
	var menu: StartMenu = _main.get_node("UI/Root/StartMenu")
	var roller: DiceRoller = _main.get_node("DiceRoller")
	var label: Label = _main.get("_result_label")
	menu.quick_roll.emit(["d6"] as Array[String])
	await frames(5)
	var one_d6: bool = roller.get_dice().size() == 1 and roller.get_dice()[0].die_type == "d6" and label.text.begins_with("1d6")
	_main.call("_show_menu")
	menu.quick_roll.emit(["d20"] as Array[String])
	await frames(5)
	check(one_d6 and roller.get_dice().size() == 1 and roller.get_dice()[0].die_type == "d20" and label.text.begins_with("1d20"),
			"the 1d6 and 1d20 quick rolls put that one die on the table")


func _back_checks() -> void:
	var store: DiceSetStore = _main.get("_store")
	var history_sheet: HistorySheet = _main.get_node("UI/Root/HistorySheet")
	var editor: SetEditor = _main.get_node("UI/Root/SetEditor")
	var drawer: SetDrawer = _main.get_node("UI/Root/SetDrawer")
	var menu: StartMenu = _main.get_node("UI/Root/StartMenu")
	_main.call("_on_set_chosen", store.sets[0]["id"])
	await frames(3)
	_main.call("_start_roll")
	await (_main.get_node("DiceRoller") as DiceRoller).roll_finished
	_main.call("_open_history")
	await frames(3)
	history_sheet.call("_ask_clear")
	await frames(2)
	press_back(_main)
	await frames(2)
	var confirm_first: bool = not history_sheet.is_confirming() and history_sheet.is_open()
	press_back(_main)
	await frames(10)
	check(confirm_first and not history_sheet.is_open(), "Back closes the clear-history question first, then the history")
	editor.open(store.sets[0])
	press_back(_main)
	await frames(2)
	_main.call("_open_drawer")
	await frames(3)
	var editor_closed: bool = not editor.is_open()
	press_back(_main)
	await frames(10)
	check(editor_closed and not drawer.is_open(), "Back cancels the editor, and closes the drawer")
	_main.call("_on_roll_button_pressed")  # arm
	await frames(3)
	var armed: bool = _main.get("_state") == 2
	press_back(_main)
	await frames(3)
	var disarmed: bool = _main.get("_state") == 0 and not menu.visible
	press_back(_main)
	await frames(3)
	check(armed and disarmed and menu.visible, "Back puts held dice down, then goes to the menu")
	menu.continue_pressed.emit()
	await frames(3)


func _history_checks() -> void:
	var history: RollHistory = _main.get("_history")
	var sheet: HistorySheet = _main.get_node("UI/Root/HistorySheet")
	history.add(RollHistory.make_entry("", "Mixed", [
		{ "type": "d20", "value": 17, "color": "#d23333", "label": "Attack", "parts": [17] },
		{ "type": "d100", "value": 48, "color": "#f2edd9", "label": "", "parts": [40, 8] },
	] as Array[Dictionary]))
	history.add(RollHistory.make_entry("", "Same", [
		{ "type": "d6", "value": 4, "color": "#1a1a1a", "label": "", "parts": [4] },
		{ "type": "d6", "value": 2, "color": "#1a1a1a", "label": "", "parts": [2] },
	] as Array[Dictionary]))
	_main.call("_open_history")
	await frames(3)
	var texts: Array[String] = []
	_collect_label_texts(sheet, texts)
	check(texts.has("4") and texts.has("2") and not texts.has("d6: 4"), "a roll of one type shows plain values on its chips")
	check(texts.has("Attack d20: 17") and texts.has("d100: 48 (40+8)"),
			"a mixed roll names each chip's type, with labels and d100 parts: %s" % [texts.filter(func(t: String) -> bool: return t.contains(":"))])
	# The black-die chips ("4", "2"): white text on the die's colour.
	var black_chips: int = 0
	var chip_colors_ok: bool = true
	var newest: Node = (sheet.get("_list") as VBoxContainer).get_child(0)  # the "Same" roll
	for n: Node in newest.find_children("*", "Label", true, false):
		var l: Label = n as Label
		if (l.text == "4" or l.text == "2") and l.has_theme_color_override("font_color"):
			black_chips += 1
			var box: StyleBoxFlat = (l.get_parent() as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
			chip_colors_ok = chip_colors_ok and l.get_theme_color("font_color") == Color.WHITE \
					and box.bg_color.is_equal_approx(DicePalette.from_hex("#1a1a1a"))
	chip_colors_ok = chip_colors_ok and black_chips == 2
	check(chip_colors_ok, "chips are the die's colour, with readable text (white on a black die)")
	sheet.call("_ask_clear")
	var dialog: ConfirmationDialog = sheet.get("_confirm")
	var n: int = history.entries.size()
	check(dialog.dialog_text == "Clear all %d rolls?\nThis can't be undone." % n, "clearing asks \"Clear all %d rolls? This can't be undone.\"" % n)
	dialog.confirmed.emit()
	await frames(3)
	check(history.entries.is_empty(), "confirming clears the history")
	sheet.cancel_confirm()
	sheet.close()
	await frames(10)


func _editor_checks() -> void:
	var editor: SetEditor = _main.get_node("UI/Root/SetEditor")
	var save: Button = editor.get("_save_button")
	editor.open({})
	var blank: bool = save.disabled
	(editor.get("_name_edit") as LineEdit).text = "Test"
	editor.call("_validate")
	var no_dice: bool = save.disabled
	editor.call("_add_die", "d6")
	var dice: Array = editor.get("_dice")
	dice[0]["color"] = "#2a8c3a"
	editor.call("_add_die", "d20")
	editor.call("_validate")
	check(blank and no_dice and not save.disabled, "Save stays off until the set has a name and a die")
	check(dice[1]["color"] == "#2a8c3a", "a new die takes the previous die's colour")
	check((editor.get("_name_edit") as LineEdit).max_length == 40, "set names stop at 40 characters")
	editor.cancel_editing()
	var store: DiceSetStore = _main.get("_store")
	editor.open(store.sets[0])
	editor.call("_ask_delete")
	var dialog: ConfirmationDialog = editor.get("_confirm_delete")
	check(dialog.visible and dialog.dialog_text == "Delete \"%s\"?\nThis can't be undone." % store.sets[0]["name"],
			"Delete asks first")
	dialog.hide()
	editor.cancel_editing()
	await frames(3)


## Every list scrolls when dragged from a button inside it.
func _scroll_checks() -> void:
	var store: DiceSetStore = _main.get("_store")
	for i: int in 10:
		store.upsert({ "name": "Extra %d" % i, "dice": [{ "type": "d6" }] })
	var history: RollHistory = _main.get("_history")
	for i: int in 12:
		history.add(RollHistory.make_entry("", "Roll %d" % i, [{ "type": "d6", "value": 3, "color": "#f2edd9", "label": "", "parts": [3] }] as Array[Dictionary]))
	var results: Array[String] = []
	_main.call("_open_drawer")
	await create_timer(0.5).timeout
	results.append("drawer %s" % await _drag_scrolls(_main.get_node("UI/Root/SetDrawer")))
	(_main.get_node("UI/Root/SetDrawer") as SetDrawer).close()
	await create_timer(0.5).timeout
	_main.call("_open_history")
	await create_timer(0.5).timeout
	results.append("history %s" % await _drag_scrolls(_main.get_node("UI/Root/HistorySheet")))
	(_main.get_node("UI/Root/HistorySheet") as HistorySheet).close()
	await create_timer(0.5).timeout
	var editor: SetEditor = _main.get_node("UI/Root/SetEditor")
	editor.open(store.sets[0])
	for i: int in 12:
		editor.call("_add_die", "d6")
	await frames(3)
	results.append("editor %s" % await _drag_scrolls(editor))
	editor.cancel_editing()
	await frames(3)
	check(results == ["drawer true", "history true", "editor true"], "the drawer, history and editor lists scroll when dragged from a button: %s" % [results])


func _drag_scrolls(sheet: Node) -> bool:
	var scroll: ScrollContainer = null
	for n: Node in sheet.find_children("*", "ScrollContainer", true, false):
		if (n as ScrollContainer).is_visible_in_tree():
			scroll = n
			break
	var target: Control = null
	for n: Node in scroll.find_children("*", "Button", true, false):
		var b: Button = n as Button
		var inner: Rect2 = scroll.get_global_rect().grow(-20.0)
		if b.is_visible_in_tree() and inner.has_point(b.get_global_rect().get_center()):
			target = b
			break
	if target == null:
		print("  no button fully inside the %s list" % sheet.name)
		return false
	var at: Vector2 = target.get_global_rect().get_center()
	_mouse(at, true)
	for i: int in 12:
		var m: InputEventMouseMotion = InputEventMouseMotion.new()
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		m.position = at - Vector2(0.0, 10.0 * i)
		m.global_position = m.position
		_main.get_viewport().push_input(m, true)
		await frames(1)
	_mouse(at - Vector2(0.0, 110.0), false)
	await frames(2)
	print("  %s: scrolled to %d of %d" % [sheet.name, scroll.scroll_vertical, scroll.get_v_scroll_bar().max_value - scroll.size.y])
	return scroll.scroll_vertical > 0


func _mouse(at: Vector2, down: bool) -> void:
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	e.position = at
	e.global_position = at
	_main.get_viewport().push_input(e, true)


## RPG set: 8 dice with a d100, so 4 per row; all between the result bar and the buttons.
func _layout_checks() -> void:
	var store: DiceSetStore = _main.get("_store")
	var roller: DiceRoller = _main.get_node("DiceRoller")
	var camera: Camera3D = _main.get_node("Camera3D")
	var label: Label = _main.get("_result_label")
	var button: Button = _main.get("_roll_button")
	_main.call("_on_set_chosen", store.sets[2]["id"])
	_main.set("_pick_mode", false)
	await frames(3)
	_main.call("_start_roll")
	await roller.roll_finished
	await create_timer(1.5).timeout
	var rows: Dictionary = {}
	var inside: bool = true
	var facing: bool = true
	for d: Die in roller.get_active_dice():
		var p: Vector2 = camera.unproject_position(d.global_position)
		inside = inside and p.y > label.get_global_rect().end.y and p.y < button.get_global_rect().position.y
		var row: int = roundi(p.y / 10.0)
		rows[row] = rows.get(row, 0) + 1
		var face: Vector3 = (d.global_basis * (d.result_entry()["show_normal"] as Vector3)).normalized()
		facing = facing and face.dot((camera.global_position - d.global_position).normalized()) > 0.95
	var max_row: int = 0
	for r: int in rows:
		max_row = maxi(max_row, rows[r])
	check(inside and max_row <= 4, "lifted dice sit between the result bar and the buttons, 4 per row with a d100 (%s)" % [rows.values()])
	check(facing, "each lifted die shows its result face to the player")


## The drawer: table and roller agree where it is; dice sitting out wait in it; thrown
## dice never land in it; the camera fits table and drawer on tall and 16:9 phones.
func _drawer_checks() -> void:
	var table: Table = _main.get_node("Table")
	var roller: DiceRoller = _main.get_node("DiceRoller")
	var store: DiceSetStore = _main.get("_store")
	check(is_equal_approx(table.drawer_front(), roller.drawer_z.x) and is_equal_approx(table.drawer_back(), roller.drawer_z.y)
			and is_equal_approx(table.drawer_floor(), roller.drawer_floor), "the table's drawer and the roller's agree")
	_main.call("_on_set_chosen", store.sets[1]["id"])  # Risk: 5 dice
	await frames(3)
	roller.set_active_groups([0, 1, 2])
	var parked_ok: bool = true
	for d: Die in roller.get_dice():
		if not roller.get_active_dice().has(d):
			var p: Vector3 = roller.to_local(d.global_position)
			parked_ok = parked_ok and p.z > roller.drawer_z.x and p.z < roller.drawer_z.y and d.freeze
	check(parked_ok, "dice sitting out wait in the drawer")
	var stayed_out: bool = true
	for i: int in 3:
		roller.rethrow_mode = RethrowMode.LIVE
		roller.roll(randf())
		await roller.roll_finished
		for d: Die in roller.in_play_dice():
			stayed_out = stayed_out and roller.to_local(d.global_position).z < table.size.y * 0.5
	check(stayed_out, "thrown dice never end up in the drawer")
	roller.activate_all()
	_main.call("_on_set_chosen", store.sets[0]["id"])  # back to Fireball (no picking) for the next checks
	await frames(3)

	var fits: Array[String] = []
	for size: Vector2i in [Vector2i(540, 1200), Vector2i(540, 960)]:
		root.size = size
		await frames(3)
		_main.call("_fit_camera")
		var camera: Camera3D = _main.get_node("Camera3D")
		var top: float = (_main.get("_result_label") as Label).get_global_rect().end.y
		var bottom: float = (_main.get("_roll_button") as Button).get_global_rect().position.y
		var far: Vector2 = camera.unproject_position(table.to_global(Vector3(0.0, 0.6, -table.size.y * 0.5 - table.rim_width)))
		var back: Vector2 = camera.unproject_position(table.to_global(Vector3(0.0, 0.6, table.drawer_back() + table.rim_width)))
		fits.append("%dx%d %s" % [size.x, size.y, far.y >= top and back.y <= bottom])
	check(fits == ["540x1200 true", "540x960 true"], "the table and drawer fit between the result bar and the buttons: %s" % [fits])


func _overlay_checks() -> void:
	var overlay: RethrowDebugOverlay = null
	for n: Node in _main.get_children():
		if n is RethrowDebugOverlay:
			overlay = n
	var roller: DiceRoller = _main.get_node("DiceRoller")
	var sheet: SettingsSheet = _main.get_node("UI/Root/SettingsSheet")
	var info: Dictionary = { "die": "D6-1", "rule": "cocked", "action": "nudging (1/3)", "tilt": 30.0,
			"threshold": 22.5, "lowest": 0.0, "touching": ["felt", "rim"] }
	var panel: Label = overlay.get("_panel")
	roller.debug_event.emit(roller.get_active_dice()[0], info)
	var hidden: bool = panel.text.is_empty()
	sheet.debug_force_changed.emit("lean")
	roller.debug_event.emit(roller.get_active_dice()[0], info)
	var shown: bool = panel.text.contains("D6-1 cocked") and roller.debug_force == "lean"
	sheet.debug_force_changed.emit("")
	check(overlay != null and hidden and shown and panel.text.is_empty() and roller.debug_force == "",
			"the debug overlay shows only while a debug landing is on, and clears when it's turned off")


func _power_checks() -> void:
	var power: PowerSaver = _main.get("_power")
	var roller: DiceRoller = _main.get_node("DiceRoller")
	var ticks: int = ProjectSettings.get_setting("physics/common/physics_ticks_per_second")
	power.idle_after = 0.5
	power.wake()
	await create_timer(1.0).timeout
	check(power.idle and Engine.max_fps == PowerSaver.IDLE_FPS and Engine.physics_ticks_per_second == PowerSaver.IDLE_PHYSICS_TICKS,
			"sitting idle drops to low power (%d fps, %d physics steps a second)" % [Engine.max_fps, Engine.physics_ticks_per_second])
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = Vector2(-50.0, -50.0)
	_main.get_viewport().push_input(e, true)
	check(not power.idle and Engine.max_fps == 0 and Engine.physics_ticks_per_second == ticks, "a touch wakes it straight away")
	await create_timer(1.0).timeout
	_main.call("_on_roll_button_pressed")  # hold the dice
	var woke: bool = not power.idle and Engine.physics_ticks_per_second == ticks
	await create_timer(1.0).timeout
	check(woke and not power.idle, "holding the dice (ready to shake) stays at full speed")
	_main.call("_on_roll_button_pressed")  # throw
	var full_while_rolling: bool = true
	var done: Array[bool] = [false]
	roller.roll_finished.connect(func(_r: Array[Dictionary]) -> void: done[0] = true, CONNECT_ONE_SHOT)
	while not done[0]:
		full_while_rolling = full_while_rolling and not power.idle
		await frames(1)
	check(full_while_rolling, "rolling stays at full speed")
	await create_timer(1.0).timeout
	check(power.idle, "once the result is showing and nothing moves, it goes low-power again")
	power.wake()
	power.idle_after = 3.0


func _settings_file_checks() -> void:
	var path: String = "user://test_flow_settings.json"
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	var s: AppSettings = AppSettings.new(path)
	s.load_settings()
	var kept: bool = FileAccess.file_exists(path.get_basename() + ".corrupt.json")
	check(s.sound and s.haptics and s.tap_to_roll and not s.fast_roll and s.rethrow_mode == RethrowMode.CLEAR and kept,
			"a damaged settings file means defaults, and is kept aside as .corrupt.json")
	for p: String in [path, path.get_basename() + ".corrupt.json"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _collect_label_texts(node: Node, out: Array[String]) -> void:
	for n: Node in node.find_children("*", "Label", true, false):
		out.append((n as Label).text)
